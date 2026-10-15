extends RefCounted
## Run this project in a child Godot process with a wall-clock limit, collecting its output.
## OS.execute() blocks with no limit, so a child that never quits would hang a suite run directly
## (outside tools/tests/run_tests.py's timeout). This kills the child at the deadline instead.
const DEFAULT_SECONDS := 120.0

## Start `godot --headless --path <project> <args>` and wait for it. Returns {"code": its exit code,
## or -1 when it was killed at the deadline, "log": what it printed}.
static func run(tree: SceneTree, args: Array[String], seconds := DEFAULT_SECONDS) -> Dictionary:
	var full := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://")])
	full.append_array(args)
	var info := OS.execute_with_pipe(OS.get_executable_path(), full, false)
	if info.is_empty():
		return {"code": -1, "log": "child_game: could not start Godot"}
	var pid: int = info.pid
	var text := ""
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while OS.is_process_running(pid):
		text += _drain(info.stdio) + _drain(info.stderr)
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			return {"code": -1, "log": text + "\nchild_game: killed after %d s" % seconds}
		await tree.create_timer(0.05, true).timeout
	text += _drain(info.stdio) + _drain(info.stderr)
	return {"code": OS.get_process_exit_code(pid), "log": text}

static func _drain(pipe: FileAccess) -> String:
	return pipe.get_buffer(1 << 20).get_string_from_utf8()
