extends SceneTree
## Soak test (app/booth_soak.gd): --soak parsing, the frame-time math and the leak check on fixed
## numbers, then a short real soak in a child process at a fixed 60 fps. It must visit every route,
## write CSV samples and a summary with a frame-rate row per route, judge three hub visits as
## steady, and exit 0. Run headless with --script res://tests/booth_soak.gd.
const BoothSoak := preload("res://app/booth_soak.gd")
const ChildGame := preload("res://tests/support/child_game.gd")
const FOLDER := "user://test_soak"
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
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(FOLDER)

func run() -> void:
	clean()
	check(BoothSoak.minutes_from(PackedStringArray()) == 0.0, "No --soak, no soak")
	check(is_equal_approx(BoothSoak.minutes_from(PackedStringArray(["--soak=480"])), 480.0),
		"--soak sets the minutes")
	check(BoothSoak.minutes_from(PackedStringArray(["--soak=0"])) == 0.0
		and BoothSoak.minutes_from(PackedStringArray(["--soak=long"])) == 0.0,
		"A zero or non-numeric --soak runs no soak")

	var histogram := PackedInt32Array()
	histogram.resize(BoothSoak.BUCKETS + 1)
	histogram[33] = 90 # 16.5-17 ms
	histogram[80] = 10 # 40-40.5 ms
	check(is_equal_approx(BoothSoak.percentile(histogram, 100, 0.5), 17.0)
		and is_equal_approx(BoothSoak.percentile(histogram, 100, 0.95), 40.5),
		"Percentiles come from the frame-time histogram")
	check(is_equal_approx(BoothSoak.slower_than(histogram, 100, 33.3), 0.1),
		"The share of frames slower than 33.3 ms is counted")

	var steady: Array[Dictionary] = [counts(400), counts(69), counts(70), counts(69)]
	check(BoothSoak.growth(steady) == "", "Counts that hold steady pass (the first visit is ignored)")
	var leaking: Array[Dictionary] = [counts(69), counts(69), counts(400), counts(900)]
	check(BoothSoak.growth(leaking).begins_with("nodes 69 -> 900"), "Nodes that keep growing fail")
	var memory: Array[Dictionary] = [counts(69, 300.0), counts(69, 300.0), counts(69, 420.0)]
	check(BoothSoak.growth(memory).begins_with("static_mb 300.0 -> 420.0"),
		"Static memory that keeps growing fails when the build reports it")

	var child: Dictionary = await ChildGame.run(self, ["--fixed-fps", "60", "--", "--soak=0.8",
		"--soak-dwell=1.5", "--soak-log=" + ProjectSettings.globalize_path(FOLDER)], 300.0)
	var text_out: String = child.log
	check(child.code == 0, "A short soak exits 0 (exit %d)" % child.code)
	var routes: Array = root.get_node("AppRouter").ROUTES.keys()
	var missing := []
	for route: String in routes:
		if not RegEx.create_from_string("(?m)^SOAK %s +\\d+" % route).search(text_out):
			missing.append(route)
	check(missing.is_empty(),
		"The frame-rate table has a row for every route (missing %s)" % [missing])
	check(text_out.contains("SOAK verdict: steady"), "Three or more hub visits are judged steady")
	var csv := ""
	var summary := ""
	var dir := DirAccess.open(FOLDER)
	if dir != null:
		for file_name in dir.get_files():
			var text := FileAccess.get_file_as_string(FOLDER.path_join(file_name))
			if file_name.ends_with("-summary.txt"):
				summary = text
			elif file_name.ends_with(".csv"):
				csv = text
	var rows := csv.strip_edges().split("\n")
	check(rows.size() > 3 and rows[0] == ",".join(BoothSoak.COLUMNS),
		"The CSV has the documented columns and a row per sample")
	check(summary.contains("SOAK verdict: steady") and summary.contains("SOAK worst load hitch"),
		"The summary file holds the table and the verdict")

	clean()
	await root.get_node("AudioService").settle()
	print("Booth soak failures: ", failures)
	quit(1 if failures else 0)
