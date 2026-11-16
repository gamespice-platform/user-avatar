class_name DotAvatarAppRules
extends RefCounted

## What one app (game) allows of avatar actions and wearables: the site's per-app switches and per-item rules.
## Data only; the site is the authority and already filters what it sends, so this is the client's second check.
## Keys follow the site's [code]AppOffersActionKind[/code] / [code]ItemVisibleToApp[/code]:
## [code]actionsEnabled[/code] is the master switch for emotes, poses and gestures, and
## [code]emotesEnabled[/code], [code]posesEnabled[/code], [code]gesturesEnabled[/code] switch one kind each under it.
## [code]wearablesEnabled[/code] switches every wearable. A missing key means on, as on the site.

const EMOTE := &"emote"
const POSE := &"pose"
const GESTURE := &"gesture"

## Settings field per action kind, as the site's ACTION_KIND_SETTING names them.
const KIND_SETTING := {
	EMOTE: "emotesEnabled",
	POSE: "posesEnabled",
	GESTURE: "gesturesEnabled",
}

## The app these rules are for; 0 when unknown (a game credential is always answered for its own app).
var app_id: int = 0
var actions_enabled := true
var wearables_enabled := true
var _kind_enabled := {EMOTE: true, POSE: true, GESTURE: true}
## Per-wearable rules from the app's rule rows: wearable id (String) -> enabled.
var _wearable_rules := {}


## Reads the site's settings document (the app avatar settings, or the avatar-rules read). Unknown keys are
## ignored; a key of the wrong type is [code]parse[/code] (fail loudly rather than guess "on").
static func from_dict(d: Variant, app_id_: int = 0) -> DotResult:
	if d == null:
		var plain := DotAvatarAppRules.new()
		plain.app_id = app_id_
		return DotResult.success(plain)
	if not d is Dictionary:
		return DotResult.fail(DotError.CODE_PARSE, "avatar rules are not an object")
	var out := DotAvatarAppRules.new()
	out.app_id = app_id_
	var src: Dictionary = d
	for key: String in ["actionsEnabled", "wearablesEnabled"]:
		if src.has(key):
			if not src[key] is bool:
				return DotResult.fail(DotError.CODE_PARSE, "avatar rule %s is not a boolean" % key)
			if key == "actionsEnabled":
				out.actions_enabled = src[key]
			else:
				out.wearables_enabled = src[key]
	for kind: StringName in KIND_SETTING:
		var key: String = KIND_SETTING[kind]
		if src.has(key):
			if not src[key] is bool:
				return DotResult.fail(DotError.CODE_PARSE, "avatar rule %s is not a boolean" % key)
			out._kind_enabled[kind] = src[key]
	var rules: Variant = src.get("rules", [])
	if not rules is Array:
		return DotResult.fail(DotError.CODE_PARSE, "avatar rules list is not an array")
	for row: Variant in rules:
		if not row is Dictionary:
			return DotResult.fail(DotError.CODE_PARSE, "an avatar rule row is not an object")
		if String(row.get("targetKind", "")) != "WEARABLE":
			continue
		if not row.get("enabled") is bool:
			return DotResult.fail(DotError.CODE_PARSE, "a wearable rule has no boolean enabled")
		out._wearable_rules[str(row.get("targetId", ""))] = row["enabled"]
	return DotResult.success(out)


## Whether the app offers this action kind: the master switch on and the kind's own switch on.
func allows_kind(kind: StringName) -> bool:
	return actions_enabled and _kind_enabled.get(kind, true)


## Whether the app offers wearables at all.
func allows_wearables() -> bool:
	return wearables_enabled


## Whether one wearable (by its site id) may be worn here: wearables on and no rule switching it off.
func allows_wearable(id: Variant) -> bool:
	return wearables_enabled and _wearable_rules.get(str(id), true)


func set_kind_enabled(kind: StringName, on: bool) -> void:
	_kind_enabled[kind] = on


## The wire rows of [param rows] whose wearable this app allows. A row with no id has nothing to match and is kept.
func filter_wearables(rows: Array) -> Array:
	var out := []
	if not wearables_enabled:
		return out
	for row: Variant in rows:
		if row is Dictionary and (row as Dictionary).has("id") and not allows_wearable(row["id"]):
			continue
		out.append(row)
	return out


func describe() -> Dictionary:
	return {
		"app_id": app_id, "actions": actions_enabled, "wearables": wearables_enabled,
		"kinds": _kind_enabled.duplicate(), "wearable_rules": _wearable_rules.size(),
	}
