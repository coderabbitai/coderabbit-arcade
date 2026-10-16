extends SceneTree
## Every platformer level plays its own original music: each level and boss constant points at the
## expected file, and each import loops sample-accurately from the loop point recorded in that
## folder's PROMPTS.md. Checked from the scripts' constants, without building a level.
## Run headless with --script res://tests/platformer_music.gd.
const ROOT := "res://Assets/Audio/Platformer/"
## [script, constant, file, loop_offset in seconds, bpm]
const EXPECTED := [
	["res://scenes/platformer/bay_area_blitz.gd", "LEVEL_MUSIC", "Bay Area Blitz/bay_area_blitz_level.ogg", 16.532608, 132.174],
	["res://scenes/platformer/bay_area_blitz.gd", "MUSIC", "Bay Area Blitz/bay_area_blitz_boss.ogg", 10.669569, 160.941],
	["res://scenes/platformer/orbital_ops.gd", "ORBITAL_LEVEL_MUSIC", "Obital Ops/orbital_ops_level.ogg", 59.617234, 145.1],
	["res://scenes/platformer/orbital_ops.gd", "ORBITAL_BOSS_MUSIC", "Obital Ops/orbital_ops_boss.ogg", 8.022494, 149.995],
	["res://scenes/platformer/enchanted_repo.gd", "FOREST_MUSIC", "The Enchanted Repo/enchanted_repo_level.ogg", 38.545125, 94.63],
	["res://scenes/platformer/enchanted_repo.gd", "BOSS_MUSIC", "The Enchanted Repo/enchanted_repo_boss.ogg", 6.640907, 176.014],
]
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func run() -> void:
	var seen := {}
	for row in EXPECTED:
		var constants: Dictionary = (load(row[0]) as Script).get_script_constant_map()
		var stream := constants.get(row[1]) as AudioStreamOggVorbis
		var label := "%s.%s" % [row[0].get_file().get_basename(), row[1]]
		check(stream != null and stream.resource_path == ROOT + row[2], "%s plays %s" % [label, row[2]])
		if stream == null:
			continue
		check(stream.loop and absf(stream.loop_offset - row[3]) < 0.001 and stream.loop_offset < stream.get_length(),
			"%s loops from %.3f s, after its intro" % [label, row[3]])
		check(is_equal_approx(stream.bpm, row[4]) and stream.bar_beats == 4 and stream.beat_count == 0,
			"%s carries its tempo and bar and loops at the file end" % label)
		check(not seen.has(stream.resource_path), "%s is not shared with another level or fight" % label)
		seen[stream.resource_path] = true
	print("PLATFORMER MUSIC: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	await root.get_node("AudioService").settle()
	quit(1 if failures else 0)
