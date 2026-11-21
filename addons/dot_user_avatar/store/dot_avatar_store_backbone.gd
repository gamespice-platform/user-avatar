class_name GSAvatarStoreBackbone
extends GSAvatarStore

## Avatars over the open HTTP protocol, so they follow a player between servers.
## GET, PUT, DELETE on [code]/user/{key}/avatar[/code], no opinion about storage; spec in [code]docs/api/avatar-protocol.md[/code] on the backbone.
## The server token is scoped to connected players' avatars and works nowhere else, as in [GSUserStoreBackbone]. Wire is [method GSAvatar.to_dict] JSON, since [GSAvatarSync.write] indices need both ends to share a schema.

const BACKBONE_CHANNEL := "avatar.store.backbone"

## Where the backbone lives. Required.
var base_url: String = ""

## Token identifying this server to the backbone. Not a player credential.
## Never logged or sent to a client, and refused from environment and argv by [method GSAvatarConfig.sensitive_keys].
var server_token: String = ""

## HTTP client. One is built if none is supplied.
## A parameter so a host can share one client, retry policy and pool across backbone calls.
var http: GSHttp = null

## Whether writes are permitted. A read-only mirror is a legitimate deployment.
## The default matches [member GSAvatarConfig.read_only], not stricter: a store stricter than its configuration is a setting that does nothing.
var read_only: bool = false

## Seconds a request may take before it is abandoned.
## Short, because this is on the join path: admit with a default avatar rather than hold the player.
var timeout_sec: float = 8.0

## Whether [member http] was built (and parented to the root) by this store, so
## [method _close] frees it.
var _owns_http: bool = false


static func at(url: String, token: String) -> GSAvatarStoreBackbone:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var s := new()
	s.base_url = url
	s.server_token = token
	return s


func _store_name() -> String:
	return "GSAvatarStoreBackbone"


func _writable() -> bool:
	return not read_only


func _open() -> GSResult:
	if base_url.strip_edges() == "":
		return GSResult.fail(
			GSError.CODE_INVALID,
			"The backbone avatar store needs a base URL.",
			"e.g. https://moddingcommunity.com/api/integration/v1"
		)

	if not (base_url.begins_with("https://") or base_url.begins_with("http://")):
		return GSResult.fail(
			GSError.CODE_INVALID, "The backbone URL needs a scheme.", base_url
		)

		# Plain HTTP sends the server token in the clear and it can read every connected player's avatar.
		# Refusing would break loopback development, so warn, loudly, because the failure is silent and total.
	if base_url.begins_with("http://") and not _is_loopback(base_url):
		GSLog.warn(
			BACKBONE_CHANNEL,
			"the backbone URL is plain HTTP; the server token travels in the clear",
			{"url": base_url}
		)

	if server_token.strip_edges() == "":
		return GSResult.fail(
			GSError.CODE_AUTH, "The backbone avatar store needs a server token."
		)

	if http == null:
		http = GSHttp.new()
		http.name = "GSAvatarStoreBackboneHttp"
		_owns_http = true

	http.base_url = base_url
	http.timeout_sec = timeout_sec

		# GSHttp is a Node and sends through HTTPRequest children, which only work in the tree; an orphan
		# client fails every request with engine error 3. Parent to the root, deferred (open() may run inside
		# _ready), then await a frame. Same fix as GameSpice User's GSUserStoreBackbone.
	if not http.is_inside_tree():
		var tree := Engine.get_main_loop() as SceneTree

		if tree == null:
			return GSResult.fail(
				GSError.CODE_STATE,
				"The backbone avatar store needs a running scene tree for its HTTP client."
			)

		if http.get_parent() == null:
			tree.root.add_child.call_deferred(http)

		await tree.process_frame

	GSLog.debug(
		BACKBONE_CHANNEL,
		"avatar store open",
		{"url": base_url, "read_only": read_only}
	)

	return GSResult.success(true)


func _close() -> void:
	# Only a client this store built: one a caller supplied is the caller's to free.
	if _owns_http and is_instance_valid(http):
		http.queue_free()
		http = null
		_owns_http = false


static func _is_loopback(url: String) -> bool:
	return (
		url.begins_with("http://127.0.0.1")
		or url.begins_with("http://localhost")
		or url.begins_with("http://[::1]")
	)


func _headers() -> Dictionary:
	return {
		"Authorization": "Bearer %s" % server_token,
		"Accept": "application/json",
	}


## Reads a player's avatar.
## Delegates to [method GSAvatarSync.fetch] so the 404-means-no-avatar rule lives in one place.
func _fetch(user_key: String) -> GSResult:
	return await GSAvatarSync.fetch(http, user_key, _headers())


func _store(user_key: String, avatar: GSAvatar) -> GSResult:
		# Replay fields: without a `ts` a backbone cannot bound how long a captured publish stays useful.
		# Unix SECONDS, as milliseconds are refused by the window check.
	var res: GSResult = await GSAvatarSync.publish(
		http,
		user_key,
		avatar,
		_headers(),
		{
			"ts": int(Time.get_unix_time_from_system()),
			"nonce": GSHash.random_hex(16),
		}
	)

	if not res.ok:
		return res

		# The backbone's digest: a mismatch means the sides canonicalise differently, so every client would
		# re-fetch every avatar on every join with no error. Warn, not fail: the write DID happen.
	var mine := avatar.digest()

	if res.value is String and res.value != "" and res.value != mine:
		GSLog.warn(
			BACKBONE_CHANNEL,
			"the backbone computed a different digest for this avatar",
			{"ours": mine, "theirs": res.value}
		)

	return GSResult.success(true)


func _remove(user_key: String) -> GSResult:
	var res: GSResult = await http.request(
		HTTPClient.METHOD_DELETE,
		"/user/%s/avatar" % user_key.uri_encode(),
		PackedByteArray(),
		_headers()
	)

	if not res.ok:
		# Already gone is the outcome the caller asked for.
		if res.error != null and res.error.http_status == 404:
			return GSResult.success(true)

		return res.wrap("Could not erase the avatar.")

	return GSResult.success(true)


func describe() -> Dictionary:
	var out := super.describe()
	out["base_url"] = base_url
	out["read_only"] = read_only
	# Deliberately reports presence, never the value.
	out["has_token"] = server_token != ""
	return out
