extends Node
## Soak test and frame-rate probe for long unattended runs: `<game> -- --soak=<minutes>`. The game
## visits every AppRouter route in turn and stays `--soak-dwell=<seconds>` (default 30) on each with
## nobody playing, for the given minutes. Every SAMPLE_SECONDS it appends a CSV row: the route, the
## frame rate and frame times, and the engine's memory and object counts. At the end it prints a
## frame-rate table per route and a leak check, writes both next to the CSV in `--soak-log=<folder>`
## (default user://soak), and quits: 0 when the counts held steady, 1 when they kept growing.
## Run it rendered and fullscreen on the booth machine for frame rates at the booth resolution;
## headless runs measure only the leak check. tools/booth/soak.py wraps a run and adds the
## process's resident memory, which release builds can't report from inside.
const MINUTES_PREFIX := "--soak="
const DWELL_PREFIX := "--soak-dwell="
const FOLDER_PREFIX := "--soak-log="
const DEFAULT_DWELL := 30.0
const DEFAULT_FOLDER := "user://soak"
const SAMPLE_SECONDS := 5.0
## Frames this soon after a route opens are loading, not play: they count as load hitches.
const SETTLE_SECONDS := 1.0
## Frame-time histogram: BUCKET_MS wide buckets up to BUCKETS * BUCKET_MS, then one overflow bucket.
const BUCKET_MS := 0.5
const BUCKETS := 200
## The leak check needs this many visits to the hub: the first warms caches and is not compared.
const MIN_CYCLES := 3
## Growth from the second hub visit to the last that counts as a leak: [absolute, fraction].
const LIMITS := {"objects": [500, 0.05], "nodes": [100, 0.0], "orphan_nodes": [20, 0.0],
	"resources": [50, 0.1], "static_mb": [32.0, 0.1]}
const COLUMNS := ["elapsed_s", "cycle", "route", "frames", "fps", "frame_p50_ms", "frame_p99_ms",
	"frame_max_ms", "static_mb", "video_mb", "objects", "nodes", "orphan_nodes", "resources"]

var minutes := 0.0
var dwell := DEFAULT_DWELL
var folder := DEFAULT_FOLDER
var csv_path := ""
var summary_path := ""
var router: Node
var routes: Array[String] = []
var index := -1
var cycle := 0
var elapsed := 0.0
var on_route := 0.0
var since_sample := 0.0
var last_usec := 0
var window: PackedFloat32Array = []
## Per route: {"histogram": PackedInt32Array, "frames": int, "ms": total frame time, "max": float}.
var stats := {}
var load_hitch := {"ms": 0.0, "route": ""}
## Engine counts at the end of each hub visit, for the leak check.
var hub_snapshots: Array[Dictionary] = []
var finished := false

## The soak length from `--soak=<minutes>`, or 0.0 when absent or not a positive number.
static func minutes_from(args: PackedStringArray) -> float:
	for arg in args:
		if arg.begins_with(MINUTES_PREFIX):
			var value := arg.trim_prefix(MINUTES_PREFIX)
			if value.is_valid_float() and value.to_float() > 0.0:
				return value.to_float()
			push_warning("--soak needs a positive number of minutes, not %s; no soak" % value)
	return 0.0

func _init(soak_minutes: float, args: PackedStringArray) -> void:
	name = "BoothSoak"
	process_mode = Node.PROCESS_MODE_ALWAYS
	minutes = soak_minutes
	for arg in args:
		if arg.begins_with(DWELL_PREFIX) and arg.trim_prefix(DWELL_PREFIX).is_valid_float():
			dwell = maxf(0.2, arg.trim_prefix(DWELL_PREFIX).to_float())
		elif arg.begins_with(FOLDER_PREFIX) and arg.length() > FOLDER_PREFIX.length():
			folder = arg.trim_prefix(FOLDER_PREFIX)

func _ready() -> void:
	router = get_parent()
	routes.assign(router.ROUTES.keys())
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	# The process id keeps two soaks started in the same second apart.
	var stamp := "%s-%d" % [Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id()]
	csv_path = folder.path_join("soak-%s.csv" % stamp)
	summary_path = folder.path_join("soak-%s-summary.txt" % stamp)
	_append(",".join(COLUMNS))
	print("SOAK %s min, %s s per route, %d routes; samples to %s" % [minutes, dwell, routes.size(),
		ProjectSettings.globalize_path(csv_path)])
	last_usec = Time.get_ticks_usec()
	_next_route()

func _process(delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	var span := (now - last_usec) / 1000.0
	last_usec = now
	elapsed += delta
	if router.busy or on_route < SETTLE_SECONDS:
		if span > load_hitch.ms:
			load_hitch = {"ms": span, "route": _route()}
	else:
		_count(span)
	on_route += delta
	since_sample += delta
	if since_sample >= SAMPLE_SECONDS:
		_sample()
	if elapsed >= minutes * 60.0:
		_finish()
	elif on_route >= dwell and not router.busy:
		if _route() == "hub":
			hub_snapshots.append(_counts())
		_next_route()

func _route() -> String:
	return routes[index] if index >= 0 else ""

func _next_route() -> void:
	index = (index + 1) % routes.size()
	if index == 0:
		cycle += 1
		# tools/booth/soak.py times its memory check from these lines.
		print("SOAK cycle %d at %.1f s" % [cycle, elapsed])
	on_route = 0.0
	router.go(routes[index])

func _count(span: float) -> void:
	window.append(span)
	var route := _route()
	if not stats.has(route):
		var histogram := PackedInt32Array()
		histogram.resize(BUCKETS + 1)
		stats[route] = {"histogram": histogram, "frames": 0, "ms": 0.0, "max": 0.0}
	var entry: Dictionary = stats[route]
	entry.histogram[mini(int(span / BUCKET_MS), BUCKETS)] += 1
	entry.frames += 1
	entry.ms += span
	entry.max = maxf(entry.max, span)

func _counts() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}

func _sample() -> void:
	var sorted := window.duplicate()
	sorted.sort()
	var frames := sorted.size()
	var total_ms := 0.0
	for span in sorted:
		total_ms += span
	var counts := _counts()
	_append(",".join(PackedStringArray([
		"%.1f" % elapsed, str(cycle), _route(), str(frames),
		"%.1f" % (1000.0 * frames / total_ms if total_ms > 0.0 else 0.0),
		"%.2f" % (sorted[int(frames * 0.5)] if frames else 0.0),
		"%.2f" % (sorted[mini(frames - 1, int(frames * 0.99))] if frames else 0.0),
		"%.2f" % (sorted[frames - 1] if frames else 0.0),
		"%.1f" % counts.static_mb, "%.1f" % counts.video_mb, str(counts.objects), str(counts.nodes),
		str(counts.orphan_nodes), str(counts.resources)])))
	window.clear()
	since_sample = 0.0

## The frame time (ms) below which `share` of a route's frames fall, to the bucket's upper edge.
static func percentile(histogram: PackedInt32Array, frames: int, share: float) -> float:
	var target := ceili(frames * share)
	var seen := 0
	for i in histogram.size():
		seen += histogram[i]
		if seen >= target:
			return (i + 1) * BUCKET_MS
	return BUCKETS * BUCKET_MS

## Frames slower than `ms`, as a share of all of the route's frames.
static func slower_than(histogram: PackedInt32Array, frames: int, ms: float) -> float:
	var slow := 0
	for i in range(int(ms / BUCKET_MS), histogram.size()):
		slow += histogram[i]
	return float(slow) / maxf(1.0, frames)

## The leak check's findings: "" when steady or too few to compare, else what kept growing.
static func growth(snapshots: Array[Dictionary]) -> String:
	if snapshots.size() < 2:
		return ""
	var first := snapshots[1]
	var last := snapshots[snapshots.size() - 1]
	var grew := PackedStringArray()
	for key: String in LIMITS:
		var before := float(first[key])
		var change := float(last[key]) - before
		if key == "static_mb" and before <= 0.0:
			continue # Release builds don't report static memory.
		if change > maxf(LIMITS[key][0], before * LIMITS[key][1]):
			var shape := "%s %.1f -> %.1f" if key == "static_mb" else "%s %d -> %d"
			grew.append(shape % [key, first[key], last[key]])
	return ", ".join(grew)

func _finish() -> void:
	finished = true
	if since_sample > 0.0:
		_sample()
	if _route() == "hub":
		hub_snapshots.append(_counts())
	var size := DisplayServer.window_get_size()
	var lines := PackedStringArray()
	lines.append("SOAK %.1f min, %d cycles, window %dx%d, vsync %s, %s" % [elapsed / 60.0, cycle,
		size.x, size.y, "off" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
		else "on", DisplayServer.get_name()])
	lines.append("SOAK %-20s %7s %6s %7s %7s %7s %7s %8s %8s" % ["route", "frames", "fps", "p50 ms",
		"p95 ms", "p99 ms", "max ms", ">16.7ms", ">33.3ms"])
	for route in routes:
		if not stats.has(route):
			continue
		var entry: Dictionary = stats[route]
		var frames: int = entry.frames
		var top: float = entry.max
		lines.append("SOAK %-20s %7d %6.1f %7.1f %7.1f %7.1f %7.1f %7.1f%% %7.1f%%" % [route, frames,
			1000.0 * frames / maxf(entry.ms, 0.001),
			minf(top, percentile(entry.histogram, frames, 0.5)),
			minf(top, percentile(entry.histogram, frames, 0.95)),
			minf(top, percentile(entry.histogram, frames, 0.99)), top,
			100.0 * slower_than(entry.histogram, frames, 16.7),
			100.0 * slower_than(entry.histogram, frames, 33.3)])
	lines.append("SOAK worst load hitch: %.0f ms (%s)" % [load_hitch.ms, load_hitch.route])
	var verdict := "too short to judge: %d hub visits, needs %d" % [hub_snapshots.size(), MIN_CYCLES]
	var code := 0
	if hub_snapshots.size() >= MIN_CYCLES:
		var first := hub_snapshots[1]
		var last := hub_snapshots[hub_snapshots.size() - 1]
		for key in ["objects", "nodes", "orphan_nodes", "resources"]:
			lines.append("SOAK %-13s %8d -> %8d (hub, visit 2 -> %d)" % [key, first[key], last[key],
				hub_snapshots.size()])
		lines.append("SOAK static memory %s" % ("%.1f MB -> %.1f MB" % [first.static_mb,
			last.static_mb] if first.static_mb > 0.0 else "not reported by release builds"))
		var grew := growth(hub_snapshots)
		verdict = "steady" if grew == "" else "GROWING: " + grew
		code = 0 if grew == "" else 1
	lines.append("SOAK verdict: " + verdict)
	var text := "\n".join(lines)
	print(text)
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file:
		file.store_string(text + "\n")
		file.close()
	print("SOAK summary at %s" % ProjectSettings.globalize_path(summary_path))
	router.go("hub")
	await get_tree().create_timer(1.0, true).timeout
	get_tree().unload_current_scene()
	# By path: suites preload this script before autoloads exist.
	get_node(^"/root/AudioService").shutdown()
	await get_tree().create_timer(0.4, true).timeout
	get_tree().quit(code)

func _append(line: String) -> void:
	var file := FileAccess.open(csv_path, FileAccess.READ_WRITE if FileAccess.file_exists(csv_path)
		else FileAccess.WRITE)
	if file == null:
		push_warning("Soak: cannot write %s (%s)" % [csv_path,
			error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	file.store_line(line)
	file.close()
