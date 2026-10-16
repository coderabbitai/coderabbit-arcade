extends SceneTree
## Booth heartbeat (app/booth_heartbeat.gd): with --heartbeat=<path> the game keeps that file
## updated with the current Unix time, including while a game has paused the tree; without the flag
## there is no heartbeat; a link planted where the temporary file goes is replaced, not written
## through; a heartbeat it can't write warns instead of failing. The flag is checked by launching
## the game as a child process, so _ready()'s argument handling is covered. Every run starts from an
## empty folder of its own. Run headless with --script res://tests/booth_heartbeat.gd.
const BoothHeartbeat := preload("res://app/booth_heartbeat.gd")
const FOLDER := "user://test_heartbeat"
const BEAT := FOLDER + "/beat"
const CHILD_BEAT := FOLDER + "/child_beat"
## Wall-clock limit for the child launch, for runs outside tools/tests/run_tests.py's timeout.
const CHILD_SECONDS := 60.0
var failures := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

## Launch the game headless with user args for two simulated seconds and return its exit code,
## or -1 if it outlives CHILD_SECONDS and had to be killed.
func launch(user_args: Array[String]) -> int:
	var args: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--quit-after", "120", "--"]
	args.append_array(user_args)
	var pid := OS.create_process(OS.get_executable_path(), args)
	var deadline := Time.get_ticks_msec() + int(CHILD_SECONDS * 1000.0)
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			return -1
		await wait(0.1)
	return OS.get_process_exit_code(pid)

func read(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges()

## True when the file holds a Unix time within a minute of now.
func fresh(path: String) -> bool:
	var text := read(path)
	return text.is_valid_int() and absi(text.to_int() - int(Time.get_unix_time_from_system())) < 60

func clean() -> void:
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(FOLDER)

func run() -> void:
	router = root.get_node("AppRouter")
	clean()
	DirAccess.make_dir_recursive_absolute(FOLDER)
	await wait(0.3)
	check(router.heartbeat == null, "No heartbeat without --heartbeat")
	check(router.heartbeat_path(PackedStringArray(["--booth"])) == "",
		"--booth alone has no heartbeat")
	check(router.heartbeat_path(PackedStringArray(["--heartbeat=user://beat"])) == "user://beat",
		"--heartbeat names the file")
	check(router.heartbeat_path(PackedStringArray(["--heartbeat="])) == "",
		"An empty --heartbeat is ignored")

	var code := await launch(["--booth", "--heartbeat=" + ProjectSettings.globalize_path(CHILD_BEAT)])
	check(code == 0, "A launch with --heartbeat exits cleanly (exit %d)" % code)
	check(fresh(CHILD_BEAT), "--heartbeat makes the game write the current Unix time")
	check(not FileAccess.file_exists(CHILD_BEAT + ".tmp"), "The heartbeat leaves no temporary file")

	# A link where the temporary file goes: the heartbeat replaces it instead of writing through it.
	var decoy := FOLDER + "/decoy"
	var keep := FileAccess.open(decoy, FileAccess.WRITE)
	keep.store_line("keep me")
	keep.close()
	var linked := DirAccess.open(FOLDER).create_link(ProjectSettings.globalize_path(decoy),
		ProjectSettings.globalize_path(BEAT + ".tmp")) == OK
	var beat := BoothHeartbeat.new(BEAT)
	root.add_child(beat)
	check(fresh(BEAT), "The heartbeat writes as soon as it starts")
	if linked:
		check(read(decoy) == "keep me", "A link planted at the temporary path is not written through")
	var marker := FileAccess.open(BEAT, FileAccess.WRITE)
	marker.store_line("0")
	marker.close()
	paused = true
	await wait(beat.INTERVAL + 0.6)
	check(fresh(BEAT), "The heartbeat keeps writing while a game has the tree paused")
	paused = false

	# The heartbeat file itself where a folder should be: warn, keep running, never an error.
	var broken := BoothHeartbeat.new(BEAT + "/nested")
	root.add_child(broken)
	check(broken.warned, "A heartbeat it can't write warns")
	broken.beat()
	check(broken.is_inside_tree(), "A failed heartbeat leaves the game running")

	beat.queue_free()
	broken.queue_free()
	await process_frame
	clean()
	await root.get_node("AudioService").settle()
	print("Booth heartbeat failures: ", failures)
	quit(1 if failures else 0)
