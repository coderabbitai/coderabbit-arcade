extends SceneTree
## Soak test (app/booth_soak.gd): --soak parsing, the frame-time math and the leak check on fixed
## numbers, then short real soaks in child processes: one over every route must write CSV samples
## and a summary with a frame-rate row per route and exit 0; one over the hub and the platformer
## menu must judge its hub visits steady; the same next to a script that leaks nodes must judge them
## growing and exit 1.
## Run headless with --script res://tests/booth_soak.gd.
const BoothSoak := preload("res://app/booth_soak.gd")
const ChildGame := preload("res://tests/support/child_game.gd")
const FOLDER := "user://test_soak"
const SHORT_FOLDER := "user://test_soak_short"
const LEAK_FOLDER := "user://test_soak_leak"
## Every route at least once, even on a slow CI runner.
const FULL := ["--soak=0.4", "--soak-dwell=0.6"]
## Two light routes: three settled hub visits in seconds.
const SHORT := ["--soak=0.2", "--soak-dwell=0.6", "--soak-routes=hub,platformer"]
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func counts(nodes: int, static_mb := 0.0) -> Dictionary:
	return {"objects": 3000, "nodes": nodes, "orphan_nodes": 0, "resources": 600,
		"static_mb": static_mb, "video_mb": 0.0}

func clean() -> void:
	for folder in [FOLDER, SHORT_FOLDER, LEAK_FOLDER]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			dir.remove(file_name)
		DirAccess.remove_absolute(folder)

## The files a soak wrote in `folder`: {"csv": text, "summary": text}.
func results(folder: String) -> Dictionary:
	var found := {"csv": "", "summary": ""}
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for file_name in dir.get_files():
		var text := FileAccess.get_file_as_string(folder.path_join(file_name))
		found["summary" if file_name.ends_with("-summary.txt") else "csv"] = text
	return found

func run() -> void:
	clean()
	check(BoothSoak.minutes_from(PackedStringArray()) == 0.0, "No --soak, no soak")
	check(is_equal_approx(BoothSoak.minutes_from(PackedStringArray(["--soak=480"])), 480.0),
		"--soak sets the minutes")
	check(BoothSoak.minutes_from(PackedStringArray(["--soak=0"])) == 0.0
		and BoothSoak.minutes_from(PackedStringArray(["--soak=long"])) == 0.0
		and BoothSoak.minutes_from(PackedStringArray(["--soak=1e999"])) == 0.0,
		"A zero, non-numeric or infinite --soak runs no soak")
	var endless := BoothSoak.new(10.0, PackedStringArray(["--soak-dwell=1e999"]))
	check(endless.dwell == BoothSoak.DEFAULT_DWELL, "An infinite --soak-dwell keeps the default")
	var short := BoothSoak.new(10.0, PackedStringArray(["--soak-dwell=0.6"]))
	check(is_equal_approx(short.settle, 0.3), "A short dwell settles for half of it")

	var histogram := PackedInt32Array()
	histogram.resize(BoothSoak.BUCKETS + 1)
	histogram[33] = 90 # 16.5-17 ms
	histogram[80] = 10 # 40-40.5 ms
	check(is_equal_approx(BoothSoak.percentile(histogram, 100, 0.5), 17.0)
		and is_equal_approx(BoothSoak.percentile(histogram, 100, 0.95), 40.5),
		"Percentiles come from the frame-time histogram")
	histogram[BoothSoak.BUCKETS] = 900 # over 100 ms
	check(BoothSoak.percentile(histogram, 1000, 0.99) == INF,
		"A percentile in the overflow bucket has no upper edge (the caller caps it at the worst)")
	short._count(16.6)
	short._count(16.8)
	short._count(40.0)
	check(short.stats[""].slow == [2, 1], "Slow frames are counted exactly against 16.7 and 33.3 ms")
	endless.free()
	short.free()

	var steady: Array[Dictionary] = [counts(400), counts(69), counts(70), counts(69)]
	check(BoothSoak.growth(steady) == "", "Counts that hold steady pass (the first visit is ignored)")
	var leaking: Array[Dictionary] = [counts(69), counts(69), counts(400), counts(900)]
	check(BoothSoak.growth(leaking).begins_with("nodes 69 -> 900"), "Nodes that keep growing fail")
	var memory: Array[Dictionary] = [counts(69, 300.0), counts(69, 300.0), counts(69, 420.0)]
	check(BoothSoak.growth(memory).begins_with("static_mb 300.0 -> 420.0"),
		"Static memory that keeps growing fails when the build reports it")
	var single: Array[Dictionary] = [counts(69)]
	check(BoothSoak.growth(single) == "", "One snapshot is too few to compare")

	var args: Array[String] = ["--"]
	args.append_array(FULL)
	args.append("--soak-log=" + ProjectSettings.globalize_path(FOLDER))
	var clean_run: Dictionary = await ChildGame.run(self, args, 300.0)
	check(clean_run.code == 0, "A soak over every route exits 0 (exit %d)" % clean_run.code)
	var missing := []
	for route: String in root.get_node("AppRouter").ROUTES.keys():
		if not RegEx.create_from_string("(?m)^SOAK %s +\\d+" % route).search(clean_run.log):
			missing.append(route)
	check(missing.is_empty(),
		"The frame-rate table has a row for every route (missing %s)" % [missing])
	var written := results(FOLDER)
	var rows: PackedStringArray = String(written.csv).strip_edges().split("\n")
	check(rows.size() > 3 and rows[0] == ",".join(BoothSoak.COLUMNS),
		"The CSV has the documented columns and a row per sample")
	check(String(written.summary).contains("SOAK verdict: ")
		and String(written.summary).contains("SOAK worst load hitch"),
		"The summary file holds the table and the verdict")

	var short_args: Array[String] = ["--"]
	short_args.append_array(SHORT)
	short_args.append("--soak-log=" + ProjectSettings.globalize_path(SHORT_FOLDER))
	var short_run: Dictionary = await ChildGame.run(self, short_args, 300.0)
	check(short_run.code == 0 and short_run.log.contains("SOAK hub 3 at")
		and short_run.log.contains("SOAK verdict: steady")
		and not RegEx.create_from_string("(?m)^SOAK runner_game +\\d+").search(short_run.log),
		"--soak-routes keeps to its routes, announces hub visits and judges them steady")

	var leak_args: Array[String] = ["--script", "res://tests/support/soak_leak.gd", "--"]
	leak_args.append_array(SHORT)
	leak_args.append("--soak-log=" + ProjectSettings.globalize_path(LEAK_FOLDER))
	var leaky: Dictionary = await ChildGame.run(self, leak_args, 300.0)
	check(leaky.code == 1 and leaky.log.contains("SOAK verdict: GROWING: ")
		and leaky.log.contains("orphan_nodes"),
		"A soak next to a node leak judges it growing and exits 1 (exit %d)" % leaky.code)

	clean()
	await root.get_node("AudioService").settle()
	print("Booth soak failures: ", failures)
	quit(1 if failures else 0)
