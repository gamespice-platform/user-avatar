class_name GSAvatarStore
extends RefCounted

## Where avatar documents live, keyed by the player's scoped id.
## Same shape and rules as GameSpice User's profile store: loads may be slow, join-path lookups may not, and a failed read keeps what is in force.
## Keyed by the scoped id, never an account id, so two operators cannot correlate players by directory listing.

const CHANNEL := "avatar.store"

var _opened: bool = false

## Emitted when an attempt [method open] started finishes, for callers that arrived
## while it was in flight.
signal _open_finished(res: GSResult)

var _opening: bool = false

var fetch_count: int = 0
var store_count: int = 0
var failure_count: int = 0


## Reads one avatar. A successful null means "this player has not made one".
func _fetch(_user_key: String) -> GSResult:
	return GSResult.fail(
		GSError.CODE_INTERNAL, "%s does not implement _fetch()." % _store_name()
	)


func _store(_user_key: String, _avatar: GSAvatar) -> GSResult:
	return GSResult.fail(
		GSError.CODE_INTERNAL, "%s does not implement _store()." % _store_name()
	)


func _remove(_user_key: String) -> GSResult:
	return GSResult.fail(
		GSError.CODE_INTERNAL, "%s does not implement _remove()." % _store_name()
	)


func _open() -> GSResult:
	return GSResult.success(true)


func _close() -> void:
	pass


func _writable() -> bool:
	return true


func _store_name() -> String:
	return "GSAvatarStore"


func open() -> GSResult:
	if _opened:
		return GSResult.success(true)

		# One attempt at a time; a second caller waits. _open can suspend and both a manager's _ready and
		# setup() open the store; overlapping attempts queued the same client onto the root twice.
	if _opening:
		var shared: GSResult = await _open_finished
		return shared

	_opening = true
	var res := await _open()
	_opening = false

	if res.ok:
		_opened = true
	else:
		failure_count += 1

	_open_finished.emit(res)
	return res


func close() -> void:
	if _opened:
		_close()
		_opened = false


func is_open() -> bool:
	return _opened


func is_writable() -> bool:
	return _writable()


## Reads an avatar, or null when the player has not made one.
## The key is checked before any implementation sees it, so a malformed one never reaches a path or URL.
func fetch(user_key: String) -> GSResult:
	if not GSAvatarKey.is_usable(user_key):
		return GSResult.fail(
			GSError.CODE_INVALID,
			"That is not a usable player key.",
			user_key.substr(0, 64)
		)

	if not _opened:
		var opened := await open()
		if not opened.ok:
			return opened.wrap("The avatar store is not available.")

	fetch_count += 1

	var res: GSResult = await _fetch(user_key)

	if not res.ok:
		failure_count += 1

	return res


## Writes an avatar, validating its structure first.
## Structure only: entitlements need the schema, which the store lacks; [GSAvatarManager.publish] checks both, and a store pretending to would be a trusted false checkpoint.
func store(user_key: String, avatar: GSAvatar) -> GSResult:
	if avatar == null:
		return GSResult.fail(GSError.CODE_INVALID, "No avatar to store.")

	if not GSAvatarKey.is_usable(user_key):
		return GSResult.fail(
			GSError.CODE_INVALID, "That is not a usable player key."
		)

	if not _writable():
		return GSResult.fail(
			GSError.CODE_FORBIDDEN, "This avatar store is read-only.", _store_name()
		)

	var valid := avatar.validate()

	if not valid.ok:
		return valid.wrap("Refusing to store an invalid avatar.")

	if not _opened:
		var opened := await open()
		if not opened.ok:
			return opened

	var res: GSResult = await _store(user_key, avatar)

	if res.ok:
		store_count += 1
	else:
		failure_count += 1
		_report_write_failure("an avatar was not saved", user_key, res)

	return res


func remove(user_key: String) -> GSResult:
	if not GSAvatarKey.is_usable(user_key):
		return GSResult.fail(
			GSError.CODE_INVALID, "That is not a usable player key."
		)

	if not _writable():
		return GSResult.fail(
			GSError.CODE_FORBIDDEN, "This avatar store is read-only."
		)

	if not _opened:
		var opened := await open()
		if not opened.ok:
			return opened

	var res: GSResult = await _remove(user_key)

	if not res.ok:
		failure_count += 1
		_report_write_failure("an avatar was not removed", user_key, res)

	return res


## Logged in the base because every backend's write passes through it, so none can forget it.
## ERROR because the avatar had passed validation: this is a player's avatar not persisting. Only write paths; the manager logs failed opens and fetches.
func _report_write_failure(what: String, user_key: String, res: GSResult) -> void:
	GSLog.error(CHANNEL, what, {
		"store": _store_name(),
		"key": user_key,
		"code": res.code(),
		"error": res.error.message if res.error != null else "",
	})


func describe() -> Dictionary:
	return {
		"store": _store_name(),
		"open": _opened,
		"writable": _writable(),
		"fetches": fetch_count,
		"stores": store_count,
		"failures": failure_count,
	}


func _to_string() -> String:
	return "%s(%s)" % [_store_name(), "open" if _opened else "closed"]
