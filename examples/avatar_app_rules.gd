extends Node

## Per-app avatar rules, offline: the emote / pose / gesture switches, per-wearable rules, the equip cap read from
## the site (0 = unlimited, over it is refused, never trimmed), and every library call carrying the app id.
## godot --headless --path . res://examples/avatar_app_rules.tscn

const SECTIONS := 6
const CHECKS := 53

var _entered := 0
var _completed := 0
var _passed := 0
var _failed := 0


## Records each request and answers from canned bodies.
class FakeHttp extends DotHttp:
	var got: Array[String] = []
	var puts: Array = []
	var body: Variant = {}
	var fail_put := false

	func get_json(path: String, _headers: Dictionary = {}) -> DotResult:
		got.append(path)
		return DotResult.success(body)

	func put_json(path: String, b: Variant, _headers: Dictionary = {}) -> DotResult:
		puts.append([path, b])
		if fail_put:
			return DotResult.fail(DotError.CODE_INVALID, "This game has emotes switched off (app setting emotesEnabled).")
		return DotResult.success({"ok": true})


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	print("dot-user-avatar app rules self-test")
	_test_rules_read()
	_test_actions_follow_switches()
	_test_equip_cap()
	_test_wearables_follow_rules()
	await _test_client_reads()
	await _test_client_writes()
	_check(_completed == _entered and _entered == SECTIONS, "every section ran (%d of %d)" % [_completed, SECTIONS])
	_check(_passed + _failed + 1 == CHECKS, "every check ran (%d of %d)" % [_passed + _failed + 1, CHECKS])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL %s %s" % [what, detail])


func _test_rules_read() -> void:
	_section("the switches read like the site's")
	var r := DotAvatarAppRules.from_dict(null)
	_check(r.ok and r.value.allows_kind(&"emote") and r.value.allows_wearables(), "no document is everything on")
	r = DotAvatarAppRules.from_dict({"emotesEnabled": false, "wearablesEnabled": true}, 7)
	_check(r.ok and not r.value.allows_kind(&"emote") and r.value.allows_kind(&"pose") and r.value.allows_kind(&"gesture"),
		"emotes off leaves poses and gestures on")
	_check(r.value.app_id == 7, "the app id is kept")
	r = DotAvatarAppRules.from_dict({"actionsEnabled": false, "posesEnabled": true})
	_check(r.ok and not r.value.allows_kind(&"pose") and not r.value.allows_kind(&"emote"), "the master switch beats a kind switch")
	r = DotAvatarAppRules.from_dict({"posesEnabled": false, "gesturesEnabled": false})
	_check(r.ok and r.value.allows_kind(&"emote") and not r.value.allows_kind(&"pose") and not r.value.allows_kind(&"gesture"),
		"poses and gestures switch separately")
	_check(not DotAvatarAppRules.from_dict("x").ok, "a non-object is refused")
	var bad := DotAvatarAppRules.from_dict({"gesturesEnabled": "no"})
	_check(not bad.ok and bad.error.code == DotError.CODE_PARSE, "a non-boolean switch fails loudly, not as on")
	_check(not DotAvatarAppRules.from_dict({"rules": "x"}).ok, "a non-array rules list is refused")
	_check(not DotAvatarAppRules.from_dict({"rules": [{"targetKind": "WEARABLE", "targetId": "3"}]}).ok, "a wearable rule without enabled is refused")
	_completed += 1


func _test_actions_follow_switches() -> void:
	_section("actions follow the switches")
	var rules: DotAvatarAppRules = DotAvatarAppRules.from_dict({"emotesEnabled": false}).value
	var payload := {
		"EMOTE": [{"builtin": "dance"}],
		"POSE": [{"builtin": "sit"}],
		"GESTURE": [],
	}
	var res := DotAvatarActions.from_backbone(payload, 0, rules)
	_check(res.ok, "reads with rules")
	var a: DotAvatarActions = res.value
	_check(a.equipped(&"emote").is_empty(), "a switched-off kind is empty even if the site sent rows")
	_check(a.equipped(&"pose").size() == 1, "a kind left on keeps its rows")
	_check(a.equipped(&"gesture").is_empty(), "an empty kind stays empty: the site's answer is taken as given")
	_check(a.next(&"emote").is_empty() and a.find(&"emote", "dance").is_empty(), "an off kind plays nothing, built-ins included")
	_check(not a.find(&"pose", "sit").is_empty(), "an on kind still finds by id")
	var input := DotAvatarActionInput.new()
	input.actions = a
	_check(input.request(&"emote").is_empty() and not input.request(&"pose").is_empty(), "the keys follow the switches")
	input.free()
	var starter := DotAvatarActions.from_backbone(null, 0, rules)
	_check(starter.ok and starter.value.equipped(&"emote").is_empty() and starter.value.equipped(&"pose").size() == 4,
		"the starter set honours the switches")
	var all_off: DotAvatarActions = DotAvatarActions.from_backbone(payload, 0, DotAvatarAppRules.from_dict({"actionsEnabled": false}).value).value
	_check(all_off.equipped(&"pose").is_empty() and all_off.equipped(&"emote").is_empty(), "actionsEnabled off empties every kind")
	_completed += 1


func _test_equip_cap() -> void:
	_section("the equip cap is the site's, 0 = unlimited")
	var many := []
	for i in 20:
		many.append({"builtin": "dance"})
	var unlimited := DotAvatarActions.from_backbone({"EMOTE": many})
	_check(unlimited.ok and unlimited.value.equipped(&"emote").size() == 20, "no cap given keeps all 20")
	var zero := DotAvatarActions.from_backbone({"EMOTE": many}, 0)
	_check(zero.ok and zero.value.equipped(&"emote").size() == 20, "max 0 is unlimited")
	var over := DotAvatarActions.from_backbone({"EMOTE": many}, 8)
	_check(not over.ok and over.error.code == DotError.CODE_QUOTA, "over the site's max is refused, not trimmed")
	_check(over.error.message.contains("maxActionsEquipped"), "and names the setting", over.error.message)
	var exact := DotAvatarActions.from_backbone({"EMOTE": many.slice(0, 8)}, 8)
	_check(exact.ok and exact.value.equipped(&"emote").size() == 8, "exactly the max is fine")
	_check(not DotAvatarActions.from_backbone({}, -1).ok, "a negative max is refused")
	_check(DotAvatarLibraryClient.check_equip_count(9, 8, "EMOTE").error.code == DotError.CODE_QUOTA, "equip over max is quota")
	_check(DotAvatarLibraryClient.check_equip_count(500, 0, "EMOTE").ok, "equip with max 0 is unlimited")
	_check(DotAvatarLibraryClient.check_equip_count(8, 8).ok, "equip at max is fine")
	_completed += 1


func _skeleton() -> Skeleton3D:
	var s := Skeleton3D.new()
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightHand", "LeftHand"]:
		var i := s.add_bone(n)
		if i > 0:
			s.set_bone_parent(i, 0)
	add_child(s)
	return s


func _test_wearables_follow_rules() -> void:
	_section("wearables follow the rules")
	var parsed := DotAvatarAppRules.from_dict({
		"rules": [
			{"targetKind": "WEARABLE", "targetId": "2", "enabled": false},
			{"targetKind": "AVATAR", "targetId": "9", "enabled": false},
			{"targetKind": "WEARABLE", "targetId": "3", "enabled": true},
		],
	})
	var rules: DotAvatarAppRules = parsed.value
	_check(not rules.allows_wearable(2) and rules.allows_wearable(3) and rules.allows_wearable(99), "a rule switches one wearable; unlisted ones follow the default")
	_check(rules.allows_wearable("3"), "ids match as strings too")
	var rows := [
		{"id": 1, "slot": "hat", "bone": "Head", "contentId": "wearable/1/1"},
		{"id": 2, "slot": "back", "bone": "Spine", "contentId": "wearable/2/1"},
	]
	_check(rules.filter_wearables(rows).size() == 1 and rules.filter_wearables(rows)[0]["id"] == 1, "filter drops the switched-off wearable")
	var sk := _skeleton()
	var w := DotAvatarWearables.new()
	w.rules = rules
	w.scene_fn = func(_row: Dictionary) -> DotResult:
		return DotResult.success(MeshInstance3D.new())
	var hung := w.apply(sk, rows)
	_check(hung.ok and hung.value == 1 and w.mount_for("hat") != null and w.mount_for("back") == null, "only the allowed wearable is hung")
	w.rules = DotAvatarAppRules.from_dict({"wearablesEnabled": false}).value
	hung = w.apply(sk, rows)
	_check(hung.ok and hung.value == 0 and w.mount_for("hat") == null, "wearablesEnabled off hangs nothing and clears the old ones")
	_check(not DotAvatarAppRules.from_dict({"wearablesEnabled": false}).value.allows_wearable(1), "no wearable is allowed with the switch off")
	w.rules = null
	_check(w.apply(sk, rows).value == 2, "no rules hangs everything the site sent")
	w.clear()
	sk.queue_free()
	_completed += 1


func _test_client_reads() -> void:
	_section("reads carry the app id")
	var http := FakeHttp.new()
	add_child(http)
	var c := DotAvatarLibraryClient.make(http, "https://site.test/", 42, {})
	http.body = {"max": 0, "actions": [
		{"id": 1, "kind": "EMOTE", "name": "Dance", "builtin": true},
		{"id": 2, "kind": "POSE", "name": "Sit", "builtin": true},
	]}
	var res: DotResult = await c.list_actions()
	_check(res.ok and http.got[0] == "https://site.test/api/app/v1/avatar/actions?appId=42", "actions GET names the app", str(http.got))
	_check(res.value["max"] == 0 and res.value["by_kind"]["emote"].size() == 1 and res.value["by_kind"]["gesture"].is_empty(),
		"max 0 is read as unlimited and rows are grouped by kind")
	res = await c.list_actions("EMOTE")
	_check(http.got[1] == "https://site.test/api/app/v1/avatar/actions?appId=42&kind=EMOTE", "a kind narrows the read", http.got[1])
	http.body = {"slots": [], "wearables": [{"id": 5, "slot": "hat"}]}
	res = await c.list_wearables("hat")
	_check(res.ok and res.value.size() == 1 and http.got[2] == "https://site.test/api/app/v1/avatar/wearables?appId=42&slot=hat",
		"wearables GET names the app", http.got[2])
	http.body = {"max": -1, "actions": []}
	_check(not (await c.list_actions()).ok, "a negative max from the site fails loudly")
	http.body = {"actions": [{"kind": "DANCE"}]}
	_check(not (await c.list_actions()).ok, "an unknown kind fails loudly")
	http.body = "nope"
	_check(not (await c.list_wearables()).ok, "a malformed wearables list fails loudly")
	_check(not (await DotAvatarLibraryClient.make(http, "https://site.test", 0).list_actions()).ok, "no app id is refused before any request")
	_check(http.got.size() == 6, "and sent nothing", str(http.got.size()))
	_check(not (await DotAvatarLibraryClient.make(null, "https://site.test", 1).list_actions()).ok, "no http client is refused")
	http.queue_free()
	_completed += 1


func _test_client_writes() -> void:
	_section("writes carry the app id and the site's cap")
	var http := FakeHttp.new()
	add_child(http)
	var c := DotAvatarLibraryClient.make(http, "https://site.test", 42, {})
	var res: DotResult = await c.equip_actions("POSE", [3, 4], 0)
	_check(res.ok and http.puts[0][0] == "https://site.test/api/app/v1/avatar/actions", "equip PUTs the actions route")
	_check(http.puts[0][1] == {"kind": "POSE", "actionIds": [3, 4], "appId": 42}, "and names the app", str(http.puts[0][1]))
	res = await c.equip_actions("POSE", [1, 2, 3], 2)
	_check(not res.ok and res.error.code == DotError.CODE_QUOTA and http.puts.size() == 1, "over the max is refused locally, nothing sent")
	res = await c.equip_actions("POSE", range(300), 0)
	_check(res.ok and http.puts.size() == 2, "max 0 sends any count")
	http.fail_put = true
	res = await c.equip_actions("EMOTE", [1], 0)
	_check(not res.ok and res.error.detail.contains("emotesEnabled"), "a switched-off kind's refusal is passed on with its setting name")
	http.fail_put = false
	res = await c.set_wearable(9, true)
	_check(res.ok and http.puts[-1][0] == "https://site.test/api/app/v1/avatar/wearables"
		and http.puts[-1][1] == {"wearableId": 9, "equipped": true, "appId": 42}, "wearable PUT names the app", str(http.puts[-1]))
	_check(not (await DotAvatarLibraryClient.make(http, "", 42).set_wearable(1, true)).ok, "no site url is refused")
	http.queue_free()
	_completed += 1
