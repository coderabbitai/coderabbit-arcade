extends RefCounted
## Local top-10 persistence for the Endless Runner (systems spec §7). Static only: the runner menu
## reads the board without a game instance.

const DEFAULT_PATH := "user://leaderboard.cfg"
const SCHEMA_VERSION := 1
const MAX_ENTRIES := 10
const MAX_NAME := 16
const FALLBACK_NAME := "Hoppy"

## strip_edges, drop control code points (C0 < 32, DEL 127 and C1 0x80-0x9F), truncate to 16,
## strip_edges again (the cut can leave a trailing space), blank becomes "Hoppy". Every stored name
## passes through here: submit/_validate and rename.
static func sanitize_name(raw: String) -> String:
	var trimmed := raw.strip_edges()
	var filtered := ""
	for i in trimmed.length():
		var code := trimmed.unicode_at(i)
		if code < 32 or code == 127 or (code >= 128 and code <= 159):
			continue
		filtered += String.chr(code)
	filtered = filtered.substr(0, MAX_NAME).strip_edges()
	if filtered.is_empty():
		return FALLBACK_NAME
	return filtered

## Score desc, then duration desc, then insertion order asc. sort_custom is not stable, so every
## entry carries an explicit `order`.
static func sort_entries(entries: Array) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for i in entries.size():
		var entry: Dictionary = (entries[i] as Dictionary).duplicate()
		if not entry.has("order"):
			entry["order"] = i
		ordered.append(entry)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if not is_equal_approx(float(a["duration"]), float(b["duration"])):
			return float(a["duration"]) > float(b["duration"])
		return int(a["order"]) < int(b["order"]))
	return ordered

## The board on disk plus the schema it declares: `{entries: Array[Dictionary], version: int,
## error: Error}`. `entries` is empty unless `error` is OK, so a caller that only wants rows can
## ignore the rest; the writers use `version`/`error` to tell "nothing readable here, go ahead and
## write" apart from "a newer build owns this file, do not touch it".
static func read_board(path := DEFAULT_PATH) -> Dictionary:
	var empty: Array[Dictionary] = []
	var source := path
	# A crash between save_entries' two renames leaves only the backup; it is the last good board.
	if not FileAccess.file_exists(source) and FileAccess.file_exists(path + ".bak"):
		source = path + ".bak"
	if not FileAccess.file_exists(source):
		return {"entries": empty, "version": 0, "error": ERR_FILE_NOT_FOUND}
	var config := ConfigFile.new()
	if config.load(source) != OK:
		return {"entries": empty, "version": 0, "error": ERR_FILE_CORRUPT}
	var version := int(config.get_value("meta", "version", 0))
	if version != SCHEMA_VERSION:
		return {"entries": empty, "version": version, "error": ERR_FILE_UNRECOGNIZED}
	var raw: Variant = config.get_value("leaderboard", "entries", [])
	if not (raw is Array):
		return {"entries": empty, "version": version, "error": ERR_FILE_CORRUPT}
	var valid: Array[Dictionary] = []
	for item in (raw as Array):
		var entry := _validate(item)
		if not entry.is_empty():
			valid.append(entry)
	return {"entries": sort_entries(valid), "version": version, "error": OK}

static func load_entries(path := DEFAULT_PATH) -> Array[Dictionary]:
	var entries: Array[Dictionary] = read_board(path)["entries"]
	return entries

## True when the file was written by a build with a newer schema. Its rows cannot be parsed, so the
## writers must leave it alone: overwriting would silently replace a real board with one run. An
## older or unrecognised-but-not-newer version keeps the old behaviour (read empty, overwrite).
static func _is_newer_schema(board: Dictionary, path: String) -> bool:
	var version := int(board["version"])
	if int(board["error"]) != ERR_FILE_UNRECOGNIZED or version <= SCHEMA_VERSION:
		return false
	push_warning("Runner leaderboard: %s declares schema version %d, newer than the supported %d; leaving it untouched" % [path, version, SCHEMA_VERSION])
	return true

## Write through a .tmp and a .bak (systems spec §7): save the new board beside the destination,
## move the destination aside, move the new board into place, then drop the backup. Any failure
## puts the backup back and keeps the .tmp, so a board is never lost to a half-finished write.
static func save_entries(entries: Array, path := DEFAULT_PATH) -> Error:
	var base_dir := path.get_base_dir()
	if base_dir != "":
		# OK when the directory already exists, so the common case is unaffected; a real failure
		# (a file standing where the directory belongs) is reported here instead of surfacing later
		# as a confusing ConfigFile.save() error. Nothing has been written yet.
		var dir_error := DirAccess.make_dir_recursive_absolute(base_dir)
		if dir_error != OK:
			push_warning("Runner leaderboard: cannot create %s (error %d); %s was not written" % [base_dir, dir_error, path])
			return dir_error
	var config := ConfigFile.new()
	config.set_value("meta", "version", SCHEMA_VERSION)
	config.set_value("leaderboard", "entries", entries)
	var tmp := path + ".tmp"
	var backup := path + ".bak"
	var error := config.save(tmp)
	if error != OK:
		# Nothing moved yet; the destination still holds the previous board.
		return error
	var backed_up := false
	if FileAccess.file_exists(path):
		error = DirAccess.rename_absolute(path, backup)
		if error != OK:
			push_warning("Runner leaderboard: cannot move %s aside (error %d); the new board is at %s" % [path, error, tmp])
			return error
		backed_up = true
	error = DirAccess.rename_absolute(tmp, path)
	if error != OK:
		if backed_up:
			# Only this save's own backup is ever put back. A `.bak` left by an earlier crash is
			# never restored over the destination: `backed_up` is true only when the rename above
			# is what created this one.
			var restore_error := DirAccess.rename_absolute(backup, path)
			if restore_error != OK:
				push_warning("Runner leaderboard: cannot restore %s from %s (error %d); load_entries() still reads the backup" % [path, backup, restore_error])
		push_warning("Runner leaderboard: cannot write %s (error %d); the new board is at %s" % [path, error, tmp])
		return error
	if backed_up:
		DirAccess.remove_absolute(backup)
	return OK

## Insert or replace by run_id and keep the top 10. Returns {rank, entries, error};
## rank is 1-10, or 0 when the run did not place.
static func submit(entry: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	var board := read_board(path)
	var entries: Array[Dictionary] = board["entries"]
	var candidate := _validate(entry)
	if candidate.is_empty():
		return {"rank": 0, "entries": entries, "error": ERR_INVALID_DATA}
	if _is_newer_schema(board, path):
		# Contract §4.3: a non-OK error keeps rank 0 / qualifies false and emits no leaderboard_saved.
		return {"rank": 0, "entries": entries, "error": ERR_FILE_UNRECOGNIZED}
	var order := 0
	var kept: Array[Dictionary] = []
	for existing in entries:
		order = maxi(order, int(existing["order"]) + 1)
		if String(existing["run_id"]) != String(candidate["run_id"]):
			kept.append(existing)
	candidate["order"] = order
	kept.append(candidate)
	var sorted := sort_entries(kept)
	if sorted.size() > MAX_ENTRIES:
		sorted.resize(MAX_ENTRIES)
	var error := save_entries(sorted, path)
	var rank := 0
	for i in sorted.size():
		if String(sorted[i]["run_id"]) == String(candidate["run_id"]):
			rank = i + 1
			break
	return {"rank": rank, "entries": sorted, "error": error}

## Rename an existing run without adding a second entry.
static func rename(run_id: String, name: String, path := DEFAULT_PATH) -> Error:
	var board := read_board(path)
	# Same rule as submit(): a newer board is reported, never rewritten. Without this the rename
	# would find no run in the empty read, and the ERR_DOES_NOT_EXIST would hide the real reason.
	if _is_newer_schema(board, path):
		return ERR_FILE_UNRECOGNIZED
	var entries: Array[Dictionary] = board["entries"]
	var clean := sanitize_name(name)
	var found := false
	for entry in entries:
		if String(entry["run_id"]) == run_id:
			entry["name"] = clean
			found = true
	if not found:
		return ERR_DOES_NOT_EXIST
	return save_entries(entries, path)

static func clear(path := DEFAULT_PATH) -> Error:
	return save_entries([], path)

static func _validate(item: Variant) -> Dictionary:
	if not (item is Dictionary):
		return {}
	var source: Dictionary = item
	for key in ["run_id", "name", "score", "duration", "seed", "submitted_at"]:
		if not source.has(key):
			return {}
	if not (source["run_id"] is String) or String(source["run_id"]).is_empty():
		return {}
	if not (source["name"] is String):
		return {}
	var score := _number(source["score"])
	var duration := _number(source["duration"])
	var run_seed := _number(source["seed"])
	var submitted_at := _number(source["submitted_at"])
	if is_nan(score) or is_nan(duration) or is_nan(run_seed) or is_nan(submitted_at):
		return {}
	if score < 0.0 or duration < 0.0:
		return {}
	var entry := {
		"run_id": String(source["run_id"]),
		"name": sanitize_name(String(source["name"])),
		"score": int(score),
		"duration": duration,
		"seed": int(run_seed),
		"submitted_at": int(submitted_at)
	}
	if source.has("order") and (source["order"] is int or source["order"] is float):
		entry["order"] = int(source["order"])
	return entry

## Finite numeric value, or NAN when the field is not a usable number.
static func _number(value: Variant) -> float:
	if not (value is int or value is float):
		return NAN
	var number := float(value)
	if not is_finite(number):
		return NAN
	return number
