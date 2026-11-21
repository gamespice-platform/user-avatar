class_name DotAvatarStoreLocal
extends DotAvatarStore

## Avatars as JSON files under a directory. The default, and it works unconfigured.
## One file per player, so an interrupted write loses one record, not all.

const LOCAL_CHANNEL := "avatar.store.local"

var directory: String = "user://avatars"

## Write through a temporary file and rename over the target.
## Passed to [DotSaveStoreFile], which does the temporary file, rename and browser IndexedDB flush.
var atomic_writes: bool = true

var _files: DotSaveStoreFile


static func at(path: String) -> DotAvatarStoreLocal:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var s := new()
	s.directory = path
	return s


func _store_name() -> String:
	return "DotAvatarStoreLocal"


func _open() -> DotResult:
	var made := DotPaths.ensure_dir(directory)

	if not made.ok:
		return made.wrap("Could not open the avatar directory.")

	DotLog.debug(LOCAL_CHANNEL, "avatar store open", {"directory": directory})
	return DotResult.success(true)


## The file store under this one, with the folder and write mode as they stand now.
func files() -> DotSaveStoreFile:
	if _files == null:
		_files = DotSaveStoreFile.new()
		_files.suffix = ".json"
		_files.key_check = func(key: String) -> bool: return DotPaths.safe_relative(key + ".json").ok
	_files.directory = directory
	_files.atomic = atomic_writes
	return _files


func _path_for(user_key: String) -> DotResult:
	var relative := DotPaths.safe_relative("%s.json" % user_key)

	if not relative.ok:
		return relative.wrap("That key is not a usable filename.")

	return DotResult.success(files().path_for(user_key))


func _fetch(user_key: String) -> DotResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	if not FileAccess.file_exists(path.value):
		return DotResult.success(null)

	var read := DotPaths.read_json(path.value)

	if not read.ok:
		# A file that exists and will not parse is a failure, never an absence.
		# Reporting it as "no avatar" would make the manager write a default over
		# whatever could still have been recovered by hand.
		return read.wrap("A stored avatar could not be read.")

	if not (read.value is Dictionary):
		return DotResult.fail(
			DotError.CODE_PARSE, "A stored avatar is not an object.", path.value
		)

	return DotAvatar.from_dict(read.value as Dictionary)


func _store(user_key: String, avatar: DotAvatar) -> DotResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	var written := files().write(user_key, JSON.stringify(avatar.to_dict(), "\t"))

	if not written.ok:
		return written.wrap("Could not write the avatar.")

	return DotResult.success(true)


func _remove(user_key: String) -> DotResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	if not FileAccess.file_exists(path.value):
		return DotResult.success(true)

	var removed := files().remove(user_key)

	if not removed.ok:
		return removed.wrap("Removing the avatar")

	return DotResult.success(true)


func describe() -> Dictionary:
	var out := super.describe()
	out["directory"] = directory
	return out
