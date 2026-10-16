extends Node
## Soak test and frame-rate probe for long unattended runs: `<game> -- --soak=<minutes>`. The game
## visits every AppRouter route in turn and stays `--soak-dwell=<seconds>` (default 30) on each with
## nobody playing, for the given minutes of wall-clock time. Every SAMPLE_SECONDS it appends a CSV
## row: the route, the frame rate and frame times, and the engine's memory and object counts. At
## the end it prints a frame-rate table per route and a leak check, writes both next to the CSV in
## `--soak-log=<folder>` (default user://soak), and quits: 0 when the counts held steady, 1 when
## they kept growing, 2 when a route failed to open or the results couldn't be written.
## `--soak-routes=hub,heroes_vs_villains` limits the soak to those routes (the hub is always one),
## and `--soak-cycles=<n>` ends it after n full passes if that comes before the minutes run out.
## Run it rendered and fullscreen on the booth machine for frame rates at the booth resolution;
## headless runs measure only the leak check. tools/booth/soak.py wraps a run and adds the
## process's resident memory, which release builds can't report from inside; it reads the
## "SOAK hub <n>" lines to measure it at the same point of each pass.
const MINUTES_PREFIX := "--soak="
const DWELL_PREFIX := "--soak-dwell="
const FOLDER_PREFIX := "--soak-log="
const ROUTES_PREFIX := "--soak-routes="
const CYCLES_PREFIX := "--soak-cycles="
const DEFAULT_DWELL := 30.0
const MIN_DWELL := 0.2
const DEFAULT_FOLDER := "user://soak"
const SAMPLE_SECONDS := 5.0
## Frames this soon after a route opens are loading, not play: they count as load hitches. Short
## dwells settle for half the dwell instead.
const SETTLE_SECONDS := 1.0
## Frame-time histogram: BUCKET_MS wide buckets up to BUCKETS * BUCKET_MS, then one overflow bucket.
const BUCKET_MS := 0.5
const BUCKETS := 200
## Frame times the summary reports the share of frames above (60 and 30 fps).
const SLOW_MS: Array[float] = [16.7, 33.3]
## The leak check needs this many settled hub visits: the first warms caches and is not compared.
const MIN_CYCLES := 3
## Growth from the second hub visit to the last that counts as a leak: [absolute, fraction].
const LIMITS := {"objects": [500, 0.05], "nodes": [100, 0.0], "orphan_nodes": [20, 0.0],
	"resources": [50, 0.1], "static_mb": [32.0, 0.1]}
const COLUMNS := ["elapsed_s", "cycle", "route", "frames", "fps", "frame_p50_ms", "frame_p99_ms",
	"frame_max_ms", "static_mb", "video_mb", "objects", "nodes", "orphan_nodes", "resources"]

var minutes := 0.0
var dwell := DEFAULT_DWELL
var settle := SETTLE_SECONDS
var folder := DEFAULT_FOLDER
## The routes named by --soak-routes, or empty for all of them.
var only: PackedStringArray = []
## Full passes after which the soak ends (--soak-cycles), or 0 for no limit.
var max_cycles := 0
var csv_path := ""
var summary_path := ""
var router: Node
var routes: Array[String] = []
var index := -1
var cycle := 0
## Wall-clock seconds since the soak began, on the route since it opened, and since the last row.
var elapsed := 0.0
var on_route := 0.0
var since_sample := 0.0
var last_usec := 0
## True while a route change is under way; nothing counts towards the dwell then.
var changing := false
var window: PackedFloat32Array = []
## Per route: {"histogram": PackedInt32Array, "frames": int, "ms": total, "max": float,
## "slow": [frames over each SLOW_MS]}.
var stats := {}
var load_hitch := {"ms": 0.0, "route": ""}
## Engine counts at the end of each settled hub visit, for the leak check.
var hub_snapshots: Array[Dictionary] = []
## Whether this visit to the hub has been counted already.
var hub_counted := false
## Why the soak can't be trusted, if anything went wrong: a route that didn't open, or results
## that couldn't be written. Either makes the exit status 2.
var failure := ""
var finished := false

## The soak length from `--soak=<minutes>`, or 0.0 when absent or not a positive, finite number.
static func minutes_from(args: PackedStringArray) -> float:
	for arg in args:
		if arg.begins_with(MINUTES_PREFIX):
			var value := arg.trim_prefix(MINUTES_PREFIX)
			var parsed := value.to_float()
			if value.is_valid_float() and is_finite(parsed) and parsed > 0.0:
				return parsed
			push_warning("--soak needs a positive number of minutes, not %s; no soak" % value)
	return 0.0

func _init(soak_minutes: float, args: PackedStringArray) -> void:
	name = "BoothSoak"
	process_mode = Node.PROCESS_MODE_ALWAYS
	minutes = soak_minutes
	for arg in args:
		if arg.begins_with(DWELL_PREFIX):
			var value := arg.trim_prefix(DWELL_PREFIX)
			var parsed := value.to_float()
			if value.is_valid_float() and is_finite(parsed):
				dwell = maxf(MIN_DWELL, parsed)
			else:
				push_warning("--soak-dwell needs a number of seconds, not %s; using %s" \
					% [value, dwell])
		elif arg.begins_with(FOLDER_PREFIX) and arg.length() > FOLDER_PREFIX.length():
			folder = arg.trim_prefix(FOLDER_PREFIX)
		elif arg.begins_with(ROUTES_PREFIX):
			only = arg.trim_prefix(ROUTES_PREFIX).split(",", false)
		elif arg.begins_with(CYCLES_PREFIX):
			var value := arg.trim_prefix(CYCLES_PREFIX)
			if value.is_valid_int() and value.to_int() > 0:
				max_cycles = value.to_int()
			else:
				push_warning("--soak-cycles needs a whole number above 0, not %s; no limit" % value)
	settle = minf(SETTLE_SECONDS, dwell * 0.5)

func _ready() -> void:
	router = get_parent()
	for route: String in router.ROUTES:
		if only.is_empty() or route in only or route == "hub":
			routes.append(route)
	for route in only:
		if not router.ROUTES.has(route):
			push_warning("--soak-routes: unknown route %s, skipped" % route)
	if not DirAccess.dir_exists_absolute(folder) \
			and DirAccess.make_dir_recursive_absolute(folder) != OK:
		failure = "cannot create %s" % ProjectSettings.globalize_path(folder)
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

func _process(_delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	var span := (now - last_usec) / 1000.0
	last_usec = now
	var seconds := span / 1000.0
	elapsed += seconds
	since_sample += seconds
	if changing or router.busy:
		_hitch(span)
	else:
		on_route += seconds
		if on_route < settle:
			_hitch(span)
		else:
			_count(span)
	if since_sample >= SAMPLE_SECONDS:
		_sample()
	if elapsed >= minutes * 60.0:
		_finish()
	elif not changing and not router.busy and on_route >= dwell:
		if _route() == "hub":
			_snapshot_hub()
		_next_route()

func _route() -> String:
	return routes[index] if index >= 0 else ""

## Open the next route and wait for it. The dwell starts once the scene is there; a route that
## doesn't open ends the soak, since its samples would carry the wrong label.
func _next_route() -> void:
	if index == routes.size() - 1 and max_cycles > 0 and cycle >= max_cycles:
		_finish()
		return
	index = (index + 1) % routes.size()
	if index == 0:
		cycle += 1
		print("SOAK cycle %d at %.1f s" % [cycle, elapsed])
	var route := routes[index]
	on_route = 0.0
	hub_counted = false
	window.clear()
	changing = true
	var opened: bool = await router.go(route)
	changing = false
	var scene := get_tree().current_scene
	# Record a failed route before anything else: _finish() may already be waiting on this change.
	var failed: bool = not opened or scene == null or scene.scene_file_path != router.ROUTES[route]
	if failed and failure == "":
		failure = "route %s did not open" % route
	if failed and not finished:
		_finish()

func _hitch(span: float) -> void:
	if span > load_hitch.ms:
		load_hitch = {"ms": span, "route": _route()}

func _count(span: float) -> void:
	window.append(span)
	var route := _route()
	if not stats.has(route):
		var histogram := PackedInt32Array()
		histogram.resize(BUCKETS + 1)
		stats[route] = {"histogram": histogram, "frames": 0, "ms": 0.0, "max": 0.0, "slow": [0, 0]}
	var entry: Dictionary = stats[route]
	entry.histogram[mini(int(span / BUCKET_MS), BUCKETS)] += 1
	entry.frames += 1
	entry.ms += span
	entry.max = maxf(entry.max, span)
	for i in SLOW_MS.size():
		if span > SLOW_MS[i]:
			entry.slow[i] += 1

func _snapshot_hub() -> void:
	if hub_counted:
		return
	hub_counted = true
	hub_snapshots.append(_counts())
	# tools/booth/soak.py samples resident memory when it reads this line.
	print("SOAK hub %d at %.1f s" % [hub_snapshots.size(), elapsed])

func _counts() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}

## One CSV row for the frames since the last one, which all belong to the current route.
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

## The frame time (ms) below which `share` of a route's frames fall, to the bucket's upper edge;
## INF when it lands in the overflow bucket, whose frames have no upper bound (callers cap it at the
## route's worst frame).
static func percentile(histogram: PackedInt32Array, frames: int, share: float) -> float:
	var target := ceili(frames * share)
	var seen := 0
	for i in histogram.size():
		seen += histogram[i]
		if seen >= target:
			return INF if i >= BUCKETS else (i + 1) * BUCKET_MS
	return INF

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

## The summary lines and exit status: 0 steady (or too short to judge), 1 growing, 2 failed.
func verdict() -> Dictionary:
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
			100.0 * entry.slow[0] / maxf(1.0, frames), 100.0 * entry.slow[1] / maxf(1.0, frames)])
	lines.append("SOAK worst load hitch: %.0f ms (%s)" % [load_hitch.ms, load_hitch.route])
	var text := "too short to judge: %d hub visits, needs %d" % [hub_snapshots.size(), MIN_CYCLES]
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
		text = "steady" if grew == "" else "GROWING: " + grew
		code = 0 if grew == "" else 1
	if failure != "":
		text = "FAILED: " + failure
		code = 2
	lines.append("SOAK verdict: " + text)
	return {"lines": lines, "code": code}

func _finish() -> void:
	if finished:
		return
	finished = true
	# A route change under way decides whether the soak failed; let it land first.
	while changing or router.busy:
		await get_tree().process_frame
	if not window.is_empty():
		_sample()
	if _route() == "hub" and not changing and not router.busy and on_route >= dwell:
		_snapshot_hub()
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null and failure == "":
		failure = "cannot write %s" % ProjectSettings.globalize_path(summary_path)
	var result := verdict()
	var text := "\n".join(result.lines)
	if file != null:
		file.store_string(text + "\n")
		file.close()
	print(text)
	print("SOAK summary at %s" % ProjectSettings.globalize_path(summary_path))
	router.go("hub")
	await get_tree().create_timer(1.0, true).timeout
	get_tree().unload_current_scene()
	# By path: suites preload this script before autoloads exist.
	get_node(^"/root/AudioService").shutdown()
	await get_tree().create_timer(0.4, true).timeout
	get_tree().quit(result.code)

## Append one line to the CSV; a failure marks the soak failed rather than stopping it.
func _append(line: String) -> void:
	var file := FileAccess.open(csv_path, FileAccess.READ_WRITE if FileAccess.file_exists(csv_path)
		else FileAccess.WRITE)
	if file == null:
		if failure == "":
			failure = "cannot write %s (%s)" % [ProjectSettings.globalize_path(csv_path),
				error_string(FileAccess.get_open_error())]
		return
	file.seek_end()
	var written := file.store_line(line)
	file.close()
	if not written and failure == "":
		failure = "cannot write %s" % ProjectSettings.globalize_path(csv_path)
