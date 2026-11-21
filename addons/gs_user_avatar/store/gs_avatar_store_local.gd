class_name GSAvatarStoreLocal
extends GSAvatarStore

## Avatars as JSON files under a directory. The default, and it works unconfigured.
## One file per player, so an interrupted write loses one record, not all.

const LOCAL_CHANNEL := "avatar.store.local"

var directory: String = "user://avatars"

## Write through a temporary file and rename over the target.
## Passed to [GSSaveStoreFile], which does the temporary file, rename and browser IndexedDB flush.
var atomic_writes: bool = true

var _files: GSSaveStoreFile


static func at(path: String) -> GSAvatarStoreLocal:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var s := new()
	s.directory = path
	return s


func _store_name() -> String:
	return "GSAvatarStoreLocal"


func _open() -> GSResult:
	var made := GSPaths.ensure_dir(directory)

	if not made.ok:
		return made.wrap("Could not open the avatar directory.")

	GSLog.debug(LOCAL_CHANNEL, "avatar store open", {"directory": directory})
	return GSResult.success(true)


## The file store under this one, with the folder and write mode as they stand now.
func files() -> GSSaveStoreFile:
	if _files == null:
		_files = GSSaveStoreFile.new()
		_files.suffix = ".json"
		_files.key_check = func(key: String) -> bool: return GSPaths.safe_relative(key + ".json").ok
	_files.directory = directory
	_files.atomic = atomic_writes
	return _files


func _path_for(user_key: String) -> GSResult:
	var relative := GSPaths.safe_relative("%s.json" % user_key)

	if not relative.ok:
		return relative.wrap("That key is not a usable filename.")

	return GSResult.success(files().path_for(user_key))


func _fetch(user_key: String) -> GSResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	if not FileAccess.file_exists(path.value):
		return GSResult.success(null)

	var read := GSPaths.read_json(path.value)

	if not read.ok:
		# A file that exists and will not parse is a failure, never an absence.
		# Reporting it as "no avatar" would make the manager write a default over
		# whatever could still have been recovered by hand.
		return read.wrap("A stored avatar could not be read.")

	if not (read.value is Dictionary):
		return GSResult.fail(
			GSError.CODE_PARSE, "A stored avatar is not an object.", path.value
		)

	return GSAvatar.from_dict(read.value as Dictionary)


func _store(user_key: String, avatar: GSAvatar) -> GSResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	var written := files().write(user_key, JSON.stringify(avatar.to_dict(), "\t"))

	if not written.ok:
		return written.wrap("Could not write the avatar.")

	return GSResult.success(true)


func _remove(user_key: String) -> GSResult:
	var path := _path_for(user_key)

	if not path.ok:
		return path

	if not FileAccess.file_exists(path.value):
		return GSResult.success(true)

	var removed := files().remove(user_key)

	if not removed.ok:
		return removed.wrap("Removing the avatar")

	return GSResult.success(true)


func describe() -> Dictionary:
	var out := super.describe()
	out["directory"] = directory
	return out
