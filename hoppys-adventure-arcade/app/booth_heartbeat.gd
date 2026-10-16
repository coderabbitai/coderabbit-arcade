extends Node
## Booth watchdog support. While the game's main loop runs, this rewrites a file with the current
## Unix time every INTERVAL seconds. tools/booth/watchdog.sh restarts the game when the file goes
## stale, which catches a hang that leaves the process alive. AppRouter adds it only when the game
## is launched with `--heartbeat=<path>`.
const INTERVAL := 2.0
var path := ""
var elapsed := 0.0
## Set after the first failed write, so the warning prints once. Every beat still tries again: a
## heartbeat that stays stale makes the watchdog restart the game.
var warned := false

func _init(file_path: String) -> void:
	path = file_path
	name = "BoothHeartbeat"
	# Keep beating while a game has the tree paused: a paused game is not a hung one.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	beat()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= INTERVAL:
		elapsed = 0.0
		beat()

## Write to a temporary file and rename it over the heartbeat, so the watchdog never reads a
## half-written number. A leftover temporary file is removed first, so a link planted in its place
## is replaced rather than written through. The watchdog keeps the heartbeat in a private folder.
func beat() -> void:
	var temporary := path + ".tmp"
	var folder := DirAccess.open(path.get_base_dir())
	var leftover := temporary.get_file()
	if folder != null and (folder.file_exists(leftover) or folder.is_link(leftover)):
		folder.remove(leftover)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_fail(error_string(FileAccess.get_open_error()))
		return
	var written := file.store_line(str(int(Time.get_unix_time_from_system())))
	file.close()
	if not written:
		_fail("write failed")
		return
	var error := DirAccess.rename_absolute(temporary, path)
	if error != OK:
		_fail(error_string(error))

func _fail(reason: String) -> void:
	if warned:
		return
	warned = true
	var problem := "Booth heartbeat: cannot write %s (%s)." % [path, reason]
	push_warning(problem + " If it stays stale, the watchdog restarts the game.")
