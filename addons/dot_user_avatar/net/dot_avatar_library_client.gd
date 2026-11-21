class_name GSAvatarLibraryClient
extends RefCounted

## The member-side avatar library calls of the site's app API: what a player may equip in one game, and equipping it.
## `GET` / `PUT /api/app/v1/avatar/actions` and `/api/app/v1/avatar/wearables`. Every call carries the game's
## [member app_id]: a player token is answered for that app's rules and its per-app loadout, and a game credential is
## always answered for its own app (the site ignores an id it sends, so passing it is harmless).
## [param base_url] is the site origin. [param headers] carries the bearer token; this class never stores one.

const CHANNEL := "avatar.library"

const ACTIONS_PATH := "/api/app/v1/avatar/actions"
const WEARABLES_PATH := "/api/app/v1/avatar/wearables"

var http: GSHttp = null
var base_url := ""
## The app whose rules and loadout every call is for. 0 is refused: a call without an app would read the built-in
## figure's loadout and none of this game's switches.
var app_id: int = 0
var headers: Dictionary = {}


static func make(http_: GSHttp, base_url_: String, app_id_: int, headers_: Dictionary = {}) -> GSAvatarLibraryClient:
	var c := GSAvatarLibraryClient.new()
	c.http = http_
	c.base_url = base_url_.trim_suffix("/")
	c.app_id = app_id_
	c.headers = headers_
	return c


## The query string of a read: the app id and, when given, one kind or slot. Pure, so tests can pin it.
func read_query(extra: Dictionary = {}) -> String:
	var parts := PackedStringArray(["appId=%d" % app_id])
	for key: String in extra:
		parts.append("%s=%s" % [key.uri_encode(), str(extra[key]).uri_encode()])
	return "&".join(parts)


## The actions the member may equip here. Success value:
## [code]{ max: int (0 = unlimited), actions: Array, by_kind: { emote: [..], pose: [..], gesture: [..] } }[/code],
## every row kept as the site sent it. [param kind] is [code]EMOTE[/code], [code]POSE[/code], [code]GESTURE[/code] or "" for all.
func list_actions(kind: String = "") -> GSResult:
	var ready := _ready()
	if not ready.ok:
		return ready
	var extra := {}
	if kind != "":
		extra["kind"] = kind
	var res: GSResult = await http.get_json("%s%s?%s" % [base_url, ACTIONS_PATH, read_query(extra)], headers)
	if not res.ok:
		return res.wrap("Could not read the avatar actions this game offers.")
	return read_actions_list(res.value)


## Parses a list answer; separate from the request so the shape is testable offline.
static func read_actions_list(body: Variant) -> GSResult:
	if not body is Dictionary or not (body as Dictionary).get("actions") is Array:
		return GSResult.fail(GSError.CODE_PARSE, "the actions list is not an object with an actions array")
	var max_equipped: Variant = (body as Dictionary).get("max", 0)
	if not max_equipped is int and not max_equipped is float:
		return GSResult.fail(GSError.CODE_PARSE, "the actions list has a non-numeric max")
	if int(max_equipped) < 0:
		return GSResult.fail(GSError.CODE_PARSE, "the actions list has a negative max", str(max_equipped))
	var by_kind := {"emote": [], "pose": [], "gesture": []}
	for row: Variant in (body as Dictionary)["actions"]:
		if not row is Dictionary:
			return GSResult.fail(GSError.CODE_PARSE, "an action row is not an object")
		var kind := String(row.get("kind", "")).to_lower()
		if not by_kind.has(kind):
			return GSResult.fail(GSError.CODE_PARSE, "an action row has an unknown kind", kind)
		by_kind[kind].append(row)
	return GSResult.success({"max": int(max_equipped), "actions": (body as Dictionary)["actions"], "by_kind": by_kind})


## Replaces one kind's equipped list, in order. [param max_equipped] is the [code]max[/code] of the last list read
## (0 = unlimited): a list over it is refused here with [code]quota[/code], before any request, rather than trimmed.
## The site refuses a kind the app switched off and says which setting; that failure is passed on as it came.
func equip_actions(kind: String, action_ids: Array, max_equipped: int = 0) -> GSResult:
	var ready := _ready()
	if not ready.ok:
		return ready
	var over := check_equip_count(action_ids.size(), max_equipped, kind)
	if not over.ok:
		return over
	var res: GSResult = await http.put_json(base_url + ACTIONS_PATH, equip_body(kind, action_ids), headers)
	if not res.ok:
		return res.wrap("Could not equip %s." % kind.to_lower())
	return GSResult.success(true)


## The body of an equip: the kind, the ids and this game's app id.
func equip_body(kind: String, action_ids: Array) -> Dictionary:
	return {"kind": kind, "actionIds": action_ids, "appId": app_id}


## Whether [param count] equips fit [param max_equipped] (0 = unlimited).
static func check_equip_count(count: int, max_equipped: int, kind: String = "") -> GSResult:
	if max_equipped < 0:
		return GSResult.fail(GSError.CODE_INVALID, "max_equipped is negative", str(max_equipped))
	if max_equipped > 0 and count > max_equipped:
		return GSResult.fail(
			GSError.CODE_QUOTA,
			"%d %s equips, the site allows %d (play.avatar.maxActionsEquipped)" % [count, kind.to_lower(), max_equipped],
			kind
		)
	return GSResult.success(true)


## The wearables the member may wear here (the site's rows: id, name, slot, bone, offset, url, equipped, locked).
func list_wearables(slot: String = "") -> GSResult:
	var ready := _ready()
	if not ready.ok:
		return ready
	var extra := {}
	if slot != "":
		extra["slot"] = slot
	var res: GSResult = await http.get_json("%s%s?%s" % [base_url, WEARABLES_PATH, read_query(extra)], headers)
	if not res.ok:
		return res.wrap("Could not read the wearables this game offers.")
	if not res.value is Dictionary or not (res.value as Dictionary).get("wearables") is Array:
		return GSResult.fail(GSError.CODE_PARSE, "the wearables list is not an object with a wearables array")
	return GSResult.success((res.value as Dictionary)["wearables"])


## Wears (or takes off) one wearable on the avatar the member wears in this app.
func set_wearable(wearable_id: int, equipped: bool) -> GSResult:
	var ready := _ready()
	if not ready.ok:
		return ready
	var res: GSResult = await http.put_json(
		base_url + WEARABLES_PATH, {"wearableId": wearable_id, "equipped": equipped, "appId": app_id}, headers
	)
	if not res.ok:
		return res.wrap("Could not change the wearable.")
	return GSResult.success(true)


func _ready() -> GSResult:
	if http == null:
		return GSResult.fail(GSError.CODE_STATE, "No HTTP client.")
	if app_id <= 0:
		return GSResult.fail(GSError.CODE_INVALID, "No app id: the avatar library is read per app.")
	if base_url == "":
		return GSResult.fail(GSError.CODE_INVALID, "No site url.")
	return GSResult.success(true)
