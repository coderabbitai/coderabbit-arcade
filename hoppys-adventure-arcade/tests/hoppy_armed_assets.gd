extends SceneTree
## Strict pack contract for every armed Hoppy sheet.
## All 11 sheets (6 Code City, 5 Heroes vs. Villains) are required. A missing
## sheet, SpriteFrames resource, manifest entry, source master, carry icon,
## PROMPTS.md, preview.png, sources/ directory, or carry/ directory fails.

const ArmedMeasure = preload("res://tests/support/armed_measure.gd")

const ROOT := "res://Assets/hoppy-armed/"
const CLIPS := {
	"hold_idle": {"frames": 1, "loop": true},
	"run": {"frames": 4, "loop": true},
	"step1": {"frames": 3, "loop": false},
	"step2": {"frames": 3, "loop": false},
	"step3": {"frames": 3, "loop": false},
	"equip": {"frames": 1, "loop": false},
	"hurt": {"frames": 1, "loop": false},
}

const EXPECTED := {
	"code_city": {
		"cell": Vector2i(192, 128),
		"pivot": Vector2i(72, 118),
		"run_fps": 12,
		"grid": Vector2i(4, 8),
		"populated": 30,
		"clips": {
			"hold_idle": {"frames": 1, "loop": true},
			"run": {"frames": 6, "loop": true},
			"step1": {"frames": 3, "loop": false},
			"step2": {"frames": 3, "loop": false},
			"step3": {"frames": 3, "loop": false},
			"equip": {"frames": 1, "loop": false},
			"hurt": {"frames": 1, "loop": false},
			"walk_up": {"frames": 4, "loop": true},
			"walk_down": {"frames": 4, "loop": true},
		},
		"run_registration": "foot",
		"unused_cells": [1, 2, 3, 4],
		"run_first_frame": 16,
		"walk_first_frame": 22,
		"pilot": "debug_stick",
		"weapons": ["debug_stick", "linter_staff", "api_key_whip", "git_branch", "refactor_hammer", "firewall_shield"],
	},
	"heroes": {
		"cell": Vector2i(256, 160),
		"pivot": Vector2i(96, 147),
		"run_fps": 7,
		"grid": Vector2i(4, 4),
		"populated": 16,
		"clips": CLIPS,
		"run_registration": "body",
		"unused_cells": [],
		"pilot": "review_stamp",
		"weapons": ["review_stamp", "triage_hammer", "change_stack_baton", "security_scanner", "pr_merger"],
	},
}
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, context: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", context)


func run() -> void:
	var required := 0
	for mode: String in EXPECTED:
		var expected: Dictionary = EXPECTED[mode]
		required += expected.weapons.size()
	check(required == 11, "armed pack lists 11 sheets")
	for mode: String in EXPECTED:
		validate_mode(mode, EXPECTED[mode])
	if failures == 0:
		print("PASS: all 11 armed Hoppy sheets satisfy the pack contract.")
	else:
		printerr(failures, " armed asset checks failed")
	quit(0 if failures == 0 else 1)


func validate_mode(mode: String, expected: Dictionary) -> void:
	var folder := ROOT + mode + "/"
	var manifest_path := folder + "manifest.json"
	var manifest: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		check(parsed is Dictionary, mode + ": manifest.json must contain an object")
		if parsed is Dictionary:
			manifest = parsed
	else:
		check(false, mode + ": manifest.json missing")

	for weapon: String in expected.weapons:
		var png_path := folder + weapon + ".png"
		var tres_path := folder + weapon + ".tres"
		var has_png := FileAccess.file_exists(png_path)
		var has_tres := FileAccess.file_exists(tres_path)
		check(has_png, mode + "/" + weapon + ": PNG sheet missing")
		check(has_tres, mode + "/" + weapon + ": SpriteFrames resource missing")
		var entry := manifest_entry(manifest, weapon)
		if not entry.is_empty():
			validate_manifest_entry(mode, weapon, entry, expected)
		else:
			check(false, mode + "/" + weapon + ": absent from manifest")
		if has_png:
			validate_sheet(png_path, mode + "/" + weapon, expected, entry)
		check(FileAccess.file_exists(folder + "sources/" + weapon + ".png"), mode + "/" + weapon + ": untouched source master missing")
		check(FileAccess.file_exists(folder + "carry/" + weapon + ".png"), mode + "/" + weapon + ": carry icon missing")
		if has_tres:
			validate_frames(tres_path, mode + "/" + weapon, expected, entry)

	validate_pack_file(folder + "PROMPTS.md", mode + ": PROMPTS.md")
	validate_pack_file(folder + "preview.png", mode + ": preview.png")
	validate_pack_file(folder + "sources/", mode + ": sources/")
	validate_carry(folder, mode, expected, manifest)


func manifest_entry(manifest: Dictionary, weapon: String) -> Dictionary:
	if manifest.has("weapons") and manifest.weapons is Dictionary and manifest.weapons.get(weapon) is Dictionary:
		return manifest.weapons[weapon]
	if manifest.get("weapon", "") == weapon:
		return manifest
	return {}


func validate_manifest_entry(mode: String, weapon: String, entry: Dictionary, expected: Dictionary) -> void:
	var label := mode + "/" + weapon + " manifest"
	check(entry.get("weapon", weapon) == weapon, label + ": weapon id")
	var cell: Variant = entry.get("cell", [])
	check(cell is Array and cell.size() == 2 and int(cell[0]) == expected.cell.x and int(cell[1]) == expected.cell.y, label + ": cell dimensions")
	var pivot: Variant = entry.get("pivot", [])
	check(pivot is Array and pivot.size() == 2 and int(pivot[0]) == expected.pivot.x and int(pivot[1]) == expected.pivot.y, label + ": foot pivot")
	check(entry.get("facing", "") == "right", label + ": facing must be right")
	check(entry.get("run_registration") == expected.run_registration, label + ": run_registration must be %s (got %s)" % [expected.run_registration, str(entry.get("run_registration"))])
	var clips: Variant = entry.get("clips", {})
	check(clips is Dictionary, label + ": clips object")
	if clips is Dictionary:
		for clip_name: String in expected.clips:
			check(clips.has(clip_name), label + ": missing clip " + clip_name)
		check(clips.size() == expected.clips.size(), label + ": clip set has exactly the contract clips")
		validate_clip_layout(label, mode, clips, expected)
	var grid: Variant = entry.get("grid", [])
	check(grid is Array and grid.size() == 2 and int(grid[0]) == expected.grid.x and int(grid[1]) == expected.grid.y, label + ": grid %s" % str(expected.grid))
	var anchors: Variant = entry.get("anchors", {})
	check(anchors is Dictionary, label + ": anchors object")
	if anchors is Dictionary:
		for step_name: String in ["step1", "step2", "step3"]:
			check(has_contact_tip(anchors, step_name), label + ": missing tip anchor for " + step_name + " contact frame")


## Code City appends locomotion cells after the 16 original attack and idle cells, so
## every pre-existing frame index (and the contact tip keys 6, 9 and 12) stays valid.
## JSON numbers load as floats, so cell lists are normalised before comparing with ints.
func int_list(values: Array) -> Array:
	var out := []
	for value in values:
		out.append(int(value))
	return out


func validate_clip_layout(label: String, mode: String, clips: Dictionary, expected: Dictionary) -> void:
	var used := {}
	for clip_name: String in expected.clips:
		var clip: Variant = clips.get(clip_name)
		if not clip is Dictionary or not clip.get("frames") is Array:
			continue
		var listed: Array = clip.frames
		check(listed.size() == expected.clips[clip_name].frames, label + ": manifest frame list " + clip_name)
		check(bool(clip.get("loop", not expected.clips[clip_name].loop)) == expected.clips[clip_name].loop, label + ": manifest loop flag " + clip_name)
		for frame_value in listed:
			var frame := int(frame_value)
			check(frame >= 0 and frame < expected.populated, label + ": %s frame %d outside the populated cells" % [clip_name, frame])
			check(not used.has(frame), label + ": %s reuses cell %d already owned by %s" % [clip_name, frame, used.get(frame, "")])
			used[frame] = clip_name
	# Code City keeps the obsolete 4 frame run cells 1 to 4 populated but unused; nothing else may be orphaned.
	var orphans := []
	for cell_index in int(expected.populated):
		if not used.has(cell_index):
			orphans.append(cell_index)
	check(orphans == expected.unused_cells, label + ": only cells %s may be unused (unused: %s)" % [str(expected.unused_cells), str(orphans)])
	if mode != "code_city":
		return
	var run: Variant = clips.get("run", {})
	if run is Dictionary and run.get("frames") is Array:
		check(int_list(run.frames) == range(expected.run_first_frame, expected.run_first_frame + 6), label + ": run uses appended cells 16 to 21")
		check(int(run.get("fps", 0)) >= 12 and int(run.get("fps", 0)) <= 15, label + ": run fps %s must sit in 12 to 15 for about 240 px/s" % str(run.get("fps")))
	var walk_first: int = expected.walk_first_frame
	for clip_name in ["walk_up", "walk_down"]:
		var walk: Variant = clips.get(clip_name, {})
		if walk is Dictionary and walk.get("frames") is Array:
			var start := walk_first if clip_name == "walk_up" else walk_first + 4
			check(int_list(walk.frames) == range(start, start + 4), label + ": %s uses cells %d to %d" % [clip_name, start, start + 3])
			check(int(walk.get("fps", 0)) >= 8 and int(walk.get("fps", 0)) <= 10, label + ": %s fps %s must sit in 8 to 10" % [clip_name, str(walk.get("fps"))])
	for clip_name in ["hold_idle", "step1", "step2", "step3", "equip", "hurt"]:
		var original: Variant = clips.get(clip_name, {})
		if original is Dictionary and original.get("frames") is Array:
			for frame_value in original.frames:
				check(int(frame_value) < 16, label + ": %s must keep its original cell (got %d)" % [clip_name, int(frame_value)])


func validate_sheet(path: String, label: String, expected: Dictionary, entry: Dictionary) -> void:
	var cell: Vector2i = expected.cell
	var image := Image.new()
	var error := image.load(path)
	check(error == OK, label + ": PNG readable")
	if error != OK:
		return
	var sheet_size: Vector2i = Vector2i(cell.x * expected.grid.x, cell.y * expected.grid.y)
	check(image.get_size() == sheet_size, label + ": sheet must be a %dx%d grid of contract-sized cells" % [expected.grid.x, expected.grid.y])
	check(image.detect_alpha() != Image.ALPHA_NONE, label + ": sheet must have alpha")
	if image.get_size() != sheet_size:
		return
	var pivot_data: Variant = entry.get("pivot", [])
	var pivot := Vector2i(int(pivot_data[0]), int(pivot_data[1])) if pivot_data is Array and pivot_data.size() == 2 else Vector2i.ZERO
	for frame in int(expected.populated):
		var region := image.get_region(Rect2i((frame % 4) * cell.x, int(frame / 4) * cell.y, cell.x, cell.y))
		check(region.get_used_rect().has_area(), label + ": empty cell " + str(frame + 1))
		check(region.detect_alpha() != Image.ALPHA_NONE, label + ": cell has no alpha channel " + str(frame + 1))
		var anchors: Variant = entry.get("anchors", {})
		var hands: Variant = anchors.get("hand", {}) if anchors is Dictionary else {}
		var hand: Variant = hands.get(str(frame), []) if hands is Dictionary else []
		check(anchor_near_alpha(image, cell, frame, hand), label + ": hand anchor is missing or farther than 2 pixels from alpha in frame " + str(frame))
		if frame == 6 or frame == 9 or frame == 12:
			var tips: Variant = anchors.get("tip", {}) if anchors is Dictionary else {}
			var tip: Variant = tips.get(str(frame), []) if tips is Dictionary else []
			check(anchor_near_alpha(image, cell, frame, tip), label + ": contact tip anchor is missing or farther than 2 pixels from alpha in frame " + str(frame))
		var feet := find_grounded_foot_row(image, cell, frame, pivot)
		check(feet.has("row"), label + ": no grounded opaque foot row near pivot in frame " + str(frame))
		if frame == 0 and feet.has("row"):
			var foot_center := (float(feet.min_x) + float(feet.max_x)) / 2.0
			check(absf(foot_center - float(pivot.x)) <= 2.0, label + ": hold_idle foot centre differs from pivot.x by more than 2 pixels")
	if not entry.is_empty():
		if expected.run_registration == "body":
			validate_run_body(label, image, cell, entry, expected.clips.run.frames)
		else:
			validate_run_stride(label, image, cell, entry, expected.clips.run.frames)


## Foot registration. The builder plants a foot at stance_x on pivot row y for each run cell, and
## the world speed must carry the planted foot back by exactly the ground the body covers per
## frame: run_speed / fps + delta_x * body_scale stays within 1 px across 0>1>2 and 3>4>5.
const RUN_SPEED := 240.0
const STANCE_X := [84, 72, 60, 84, 72, 60]
const STANCE_PAIRS := [[0, 1], [1, 2], [3, 4], [4, 5]]

func validate_run_stride(label: String, sheet: Image, cell: Vector2i, entry: Dictionary, run_count: int) -> void:
	var pivot_data: Variant = entry.get("pivot", [])
	var clips: Variant = entry.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var frames: Variant = run.get("frames", []) if run is Dictionary else []
	var locomotion: Variant = entry.get("locomotion", {})
	check(locomotion is Dictionary and not locomotion.is_empty(), label + ": locomotion record missing")
	var ready: bool = pivot_data is Array and pivot_data.size() == 2 and frames is Array and frames.size() == run_count and run_count == STANCE_X.size() and locomotion is Dictionary and not locomotion.is_empty()
	check(ready, label + ": foot run needs pivot, %d run frames and a locomotion record" % run_count)
	if not ready:
		return
	var stance_x: Variant = locomotion.get("stance_x", [])
	check(stance_x is Array and stance_x.size() == STANCE_X.size(), label + ": locomotion stance_x lists 6 planted foot x values")
	if not stance_x is Array or stance_x.size() != STANCE_X.size():
		return
	var fps := float(run.get("fps", 0))
	var scale := float(locomotion.get("body_scale", 0.0))
	check(is_equal_approx(fps, 13.0), label + ": run fps %s must be 13" % str(run.get("fps")))
	check(int(locomotion.get("stance_step_px", 0)) == 12, label + ": stance_step_px must be 12")
	check(absf(scale - 1.55) < 0.001, label + ": body_scale must be 1.55")
	check(absf(float(locomotion.get("matched_world_speed", 0.0)) - 241.8) <= 0.5, label + ": matched_world_speed must be about 241.8")
	for i in STANCE_X.size():
		check(int(stance_x[i]) == STANCE_X[i], label + ": stance_x[%d] must be %d" % [i, STANCE_X[i]])
		var cell_frame := int(frames[i])
		check(cell_frame == int(entry.clips.run.frames[0]) + i, label + ": run frame %d must sit in cell %d" % [i, int(entry.clips.run.frames[0]) + i])
		check(anchor_near_alpha(sheet, cell, cell_frame, [int(stance_x[i]), int(pivot_data[1])]), label + ": no opaque sole at stance x %d, y %d in run cell %d" % [int(stance_x[i]), int(pivot_data[1]), cell_frame])
	for pair in STANCE_PAIRS:
		var delta := float(int(stance_x[pair[1]]) - int(stance_x[pair[0]]))
		var drift := RUN_SPEED / fps + delta * scale
		check(absf(drift) <= 1.0, label + ": planted foot slides %.2f px per frame across stance %d to %d (limit 1.0)" % [drift, pair[0], pair[1]])
	var walk_fps_ok := true
	for clip_name in ["walk_up", "walk_down"]:
		var walk: Variant = clips.get(clip_name, {})
		walk_fps_ok = walk_fps_ok and walk is Dictionary and is_equal_approx(float(walk.get("fps", 0)), 9.0)
	check(walk_fps_ok, label + ": walk_up and walk_down run at 9 fps")


func validate_run_body(label: String, sheet: Image, cell: Vector2i, entry: Dictionary, run_count: int) -> void:
	var pivot_data: Variant = entry.get("pivot", [])
	var height := int(entry.get("unarmed_idle_height", -1))
	var clips: Variant = entry.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var frames: Variant = run.get("frames", []) if run is Dictionary else []
	var anchors: Variant = entry.get("anchors", {})
	var hands: Variant = anchors.get("hand", {}) if anchors is Dictionary else {}
	var ready: bool = pivot_data is Array and pivot_data.size() == 2 and height >= 0 and frames is Array and frames.size() == run_count and hands is Dictionary
	check(ready, label + ": run body registration needs pivot, unarmed_idle_height, %d run frames and hand anchors" % run_count)
	if not ready:
		return
	var foot_y := int(pivot_data[1])
	var refs := PackedFloat32Array()
	var names := PackedInt32Array()
	for frame_value in frames:
		var frame := int(frame_value)
		var hand: Variant = hands.get(str(frame), [])
		var hand_ok: bool = hand is Array and hand.size() >= 2
		check(hand_ok, label + ": run frame %d is missing a hand anchor" % frame)
		if not hand_ok:
			return
		var region := sheet.get_region(Rect2i((frame % 4) * cell.x, int(frame / 4.0) * cell.y, cell.x, cell.y))
		var measured := ArmedMeasure.body_reference_x(region, foot_y, int(hand[0]), height)
		check(not is_nan(measured), label + ": run frame %d has no body pixels behind the paw" % frame)
		if is_nan(measured):
			return
		refs.append(measured)
		names.append(frame)
	var worst := 0.0
	var worst_from := int(names[0])
	var worst_to := int(names[0])
	var listed := ""
	for i in refs.size():
		listed += (", " if i > 0 else "") + "%.2f" % refs[i]
		var nxt := (i + 1) % refs.size()
		var step := absf(refs[nxt] - refs[i])
		if step > worst:
			worst = step
			worst_from = int(names[i])
			worst_to = int(names[nxt])
	check(worst <= 3.0, label + ": run body moves %.2f px between frames %d and %d (limit 3.0; body x %s)" % [worst, worst_from, worst_to, listed])


func anchor_near_alpha(sheet: Image, cell: Vector2i, frame: int, point: Variant) -> bool:
	if not point is Array or point.size() != 2:
		return false
	var x := int(point[0])
	var y := int(point[1])
	if x < 0 or y < 0 or x >= cell.x or y >= cell.y:
		return false
	var origin := Vector2i((frame % 4) * cell.x, int(frame / 4) * cell.y)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy > 4:
				continue
			var pixel := Vector2i(x + dx, y + dy)
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= cell.x or pixel.y >= cell.y:
				continue
			if sheet.get_pixel(origin.x + pixel.x, origin.y + pixel.y).a >= 128.0 / 255.0:
				return true
	return false


func find_grounded_foot_row(sheet: Image, cell: Vector2i, frame: int, pivot: Vector2i) -> Dictionary:
	# Feet are sought in the bottom 45% of the cell and close to the foot pivot,
	# keeping a raised weapon or hand from being mistaken for ground contact.
	var lower_body_top := int(ceil(float(cell.y) * 0.55))
	var first_row := maxi(lower_body_top, pivot.y - 1)
	var last_row := mini(cell.y - 1, pivot.y + 1)
	var x_radius := int(round(float(cell.x) * 0.10))
	var first_x := maxi(0, pivot.x - x_radius)
	var last_x := mini(cell.x - 1, pivot.x + x_radius)
	var best := {}
	var best_run := 2
	for y in range(first_row, last_row + 1):
		var min_x := cell.x
		var max_x := -1
		var run := 0
		var longest_run := 0
		for x in range(first_x, last_x + 1):
			var opaque := sheet.get_pixel((frame % 4) * cell.x + x, int(frame / 4) * cell.y + y).a >= 128.0 / 255.0
			if opaque:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				run += 1
				longest_run = maxi(longest_run, run)
			else:
				run = 0
		if longest_run > best_run:
			best_run = longest_run
			best = {"row": y, "min_x": min_x, "max_x": max_x}
	return best


func validate_frames(path: String, label: String, expected: Dictionary, entry: Dictionary) -> void:
	var cell: Vector2i = expected.cell
	var run_fps: int = expected.run_fps
	var clip_contract: Dictionary = expected.clips
	var frames := load(path) as SpriteFrames
	check(frames != null, label + ": SpriteFrames resource loads")
	if frames == null:
		return
	check(frames.get_animation_names().size() == clip_contract.size(), label + ": animation set")
	for clip_name: String in clip_contract:
		var contract: Dictionary = clip_contract[clip_name]
		check(frames.has_animation(clip_name), label + ": missing animation " + clip_name)
		if not frames.has_animation(clip_name):
			continue
		check(frames.get_frame_count(clip_name) == contract.frames, label + "/" + clip_name + ": frame count")
		check(frames.get_animation_loop(clip_name) == contract.loop, label + "/" + clip_name + ": loop flag")
		var manifest_clip: Variant = entry.get("clips", {}).get(clip_name) if entry.get("clips") is Dictionary else null
		if clip_name == "run" and expected.has("grid") and expected.grid.y > 4:
			# Code City calibrates run fps to the 240 px/s ground speed; the manifest is the source.
			var listed_fps := float(manifest_clip.get("fps", 0)) if manifest_clip is Dictionary else 0.0
			check(listed_fps > 0.0 and is_equal_approx(frames.get_animation_speed(clip_name), listed_fps), label + "/run: frame rate matches manifest")
		elif clip_name == "run":
			check(is_equal_approx(frames.get_animation_speed(clip_name), float(run_fps)), label + "/run: frame rate")
		elif manifest_clip is Dictionary and manifest_clip.has("fps"):
			check(is_equal_approx(frames.get_animation_speed(clip_name), float(manifest_clip.fps)), label + "/" + clip_name + ": frame rate matches manifest")
		for index in frames.get_frame_count(clip_name):
			var texture := frames.get_frame_texture(clip_name, index)
			check(texture != null, label + "/" + clip_name + ": missing texture")
			if texture == null:
				continue
			check(Vector2i(texture.get_size()) == cell, label + "/" + clip_name + ": texture cell size")
			if texture is AtlasTexture:
				check(texture.atlas != null and Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), label + "/" + clip_name + ": atlas region bounds")
			var frame_image := texture.get_image()
			check(frame_image != null and frame_image.get_used_rect().has_area(), label + "/" + clip_name + ": nonempty frame")
			if frame_image != null:
				check(frame_image.detect_alpha() != Image.ALPHA_NONE, label + "/" + clip_name + ": frame alpha")
	if not entry.is_empty() and entry.has("clips") and entry.clips is Dictionary:
		for clip_name: String in clip_contract:
			var clip: Variant = entry.clips.get(clip_name)
			if clip is Dictionary:
				var listed: Variant = clip.get("frames")
				check(listed is Array and listed.size() == clip_contract[clip_name].frames, label + ": manifest frame list " + clip_name)


func has_contact_tip(anchors: Dictionary, step_name: String) -> bool:
	var contact_index: int = {"step1": 6, "step2": 9, "step3": 12}[step_name]
	if anchors.has("tip") and anchors.tip is Dictionary:
		if anchors.tip.has(str(contact_index)) or anchors.tip.has(str(contact_index + 1)):
			return true
	if anchors.has(str(contact_index)) and anchors[str(contact_index)] is Dictionary and anchors[str(contact_index)].has("tip"):
		return true
	if anchors.has(str(contact_index + 1)) and anchors[str(contact_index + 1)] is Dictionary and anchors[str(contact_index + 1)].has("tip"):
		return true
	if anchors.has(step_name) and anchors[step_name] is Dictionary:
		var step: Dictionary = anchors[step_name]
		if step.has("tip"):
			return true
		if step.has("contact") and step.contact is Dictionary and step.contact.has("tip"):
			return true
	return false


func validate_pack_file(path: String, label: String) -> void:
	if path.ends_with("/"):
		var absolute := ProjectSettings.globalize_path(path)
		check(DirAccess.dir_exists_absolute(absolute), label + " missing")
		if DirAccess.dir_exists_absolute(absolute):
			check(not DirAccess.get_files_at(path).is_empty(), label + " must not be empty")
		return
	check(FileAccess.file_exists(path), label + " missing")
	if FileAccess.file_exists(path) and path.ends_with(".png"):
		var image := Image.new()
		check(image.load(path) == OK and image.get_used_rect().has_area(), label + " must be a readable nonempty PNG")


func validate_carry(folder: String, mode: String, expected: Dictionary, manifest: Dictionary) -> void:
	var carry_folder := folder + "carry/"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(carry_folder)):
		check(false, mode + ": carry/ missing")
	var calibration: Variant = manifest.get("carry_calibration", {})
	check(calibration is Dictionary, mode + ": carry_calibration object missing")
	if not calibration is Dictionary:
		return
	var rule := str(calibration.get("rule", "")).to_lower()
	check(rule.contains("pilot") and rule.contains("body") and rule.contains("ratio"), mode + ": calibration rule must document the pilot weapon-to-body ratio basis")
	var carry_scale := float(calibration.get("carry_scale", 0.0))
	var body_height := int(calibration.get("body_height", 0))
	check(carry_scale > 0.0, mode + ": calibration carry_scale must be positive")
	check(body_height > 0, mode + ": calibration body_height must be positive")
	var pilot: Variant = calibration.get("pilot", {})
	check(pilot is Dictionary, mode + ": pilot calibration object missing")
	var pilot_baked_length := 0
	if pilot is Dictionary:
		check(pilot.get("weapon", "") == expected.pilot, mode + ": calibration pilot weapon id")
		pilot_baked_length = int(pilot.get("baked_length", 0))
		check(pilot_baked_length > 0, mode + ": pilot baked_length must be positive")
		validate_pilot_bounds(folder, mode, expected.cell, pilot)
	var calibrated_weapons: Variant = calibration.get("weapons", {})
	check(calibrated_weapons is Dictionary, mode + ": calibration weapons object missing")
	if not calibrated_weapons is Dictionary:
		calibrated_weapons = {}
	for weapon: String in expected.weapons:
		var weapon_calibration: Variant = calibrated_weapons.get(weapon, {})
		check(weapon_calibration is Dictionary, mode + "/carry/" + weapon + ": calibration record missing")
		if not weapon_calibration is Dictionary:
			weapon_calibration = {}
		var target_length := int(weapon_calibration.get("target_length", 0))
		check(target_length > 0, mode + "/carry/" + weapon + ": target_length must be positive")
		if weapon == expected.pilot:
			check(within_ten_percent(target_length, pilot_baked_length), mode + "/carry/" + weapon + ": calibration target differs from baked hold_idle by more than 10%")
		else:
			var bounds: Variant = weapon_calibration.get("source_visible_bounds", [])
			var source_length := int(weapon_calibration.get("source_length", 0))
			check(valid_source_bounds(bounds), mode + "/carry/" + weapon + ": source_visible_bounds invalid")
			if valid_source_bounds(bounds):
				var source_visible_length := maxi(int(bounds[2]) - int(bounds[0]), int(bounds[3]) - int(bounds[1]))
				check(source_length == source_visible_length, mode + "/carry/" + weapon + ": source_length does not match visible bounds")
			check(source_length > 0, mode + "/carry/" + weapon + ": source_length must be positive")
			var rule_for_weapon := str(weapon_calibration.get("rule", "")).to_lower()
			if rule_for_weapon.contains("baked"):
				var baked_bounds: Variant = weapon_calibration.get("hold_idle_bounds", [])
				var baked_length := int(weapon_calibration.get("baked_length", 0))
				check(valid_bounds(baked_bounds), mode + "/carry/" + weapon + ": baked hold_idle_bounds invalid")
				if valid_bounds(baked_bounds):
					check(baked_length == maxi(int(baked_bounds[2]), int(baked_bounds[3])), mode + "/carry/" + weapon + ": baked_length does not match hold_idle_bounds")
					validate_weapon_bounds(folder, mode, expected.cell, weapon, baked_bounds)
				check(within_ten_percent(target_length, baked_length), mode + "/carry/" + weapon + ": calibration target differs from baked hold_idle by more than 10%")
			elif source_length > 0 and carry_scale > 0.0:
				check(absi(target_length - roundi(source_length * carry_scale)) <= 1, mode + "/carry/" + weapon + ": target_length does not follow documented carry_scale")
		var path := carry_folder + weapon + ".png"
		if not FileAccess.file_exists(path):
			continue
		var image := Image.new()
		var error := image.load(path)
		check(error == OK, mode + "/carry/" + weapon + ": PNG readable")
		if error == OK:
			var used := image.get_used_rect()
			check(used.has_area(), mode + "/carry/" + weapon + ": nonempty")
			check(image.detect_alpha() != Image.ALPHA_NONE, mode + "/carry/" + weapon + ": alpha")
			if not used.has_area():
				continue
			var measured_length := maxi(used.size.x, used.size.y)
			check(within_ten_percent(measured_length, target_length), mode + "/carry/" + weapon + ": measured length differs from calibration target by more than 10%")
			if weapon == expected.pilot:
				check(within_ten_percent(measured_length, pilot_baked_length), mode + "/carry/" + weapon + ": length differs from baked hold_idle by more than 10%")


func valid_bounds(bounds: Variant) -> bool:
	return bounds is Array and bounds.size() == 4 and int(bounds[0]) >= 0 and int(bounds[1]) >= 0 and int(bounds[2]) > 0 and int(bounds[3]) > 0


func valid_source_bounds(bounds: Variant) -> bool:
	return bounds is Array and bounds.size() == 4 and int(bounds[0]) >= 0 and int(bounds[1]) >= 0 and int(bounds[2]) > int(bounds[0]) and int(bounds[3]) > int(bounds[1])


func within_ten_percent(actual: int, target: int) -> bool:
	return target > 0 and absf(float(actual - target)) <= float(target) * 0.1


func validate_pilot_bounds(folder: String, mode: String, cell: Vector2i, pilot: Dictionary) -> void:
	var bounds: Variant = pilot.get("hold_idle_bounds", [])
	check(valid_bounds(bounds), mode + ": pilot hold_idle_bounds invalid")
	if not valid_bounds(bounds):
		return
	var rect := Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3]))
	var in_bounds := Rect2i(Vector2i.ZERO, cell).encloses(rect)
	check(in_bounds, mode + ": pilot hold_idle_bounds outside cell")
	check(int(pilot.get("baked_length", 0)) == maxi(rect.size.x, rect.size.y), mode + ": pilot baked_length does not match hold_idle_bounds")
	if not in_bounds:
		return
	var pilot_image := Image.new()
	var pilot_path := folder + str(pilot.get("weapon", "")) + ".png"
	if pilot_image.load(pilot_path) != OK or pilot_image.get_size().x != cell.x * 4:
		check(false, mode + ": cannot inspect pilot hold_idle bounds")
		return
	var hold_idle := pilot_image.get_region(Rect2i(0, 0, cell.x, cell.y))
	check(hold_idle.get_region(rect).get_used_rect().has_area(), mode + ": pilot hold_idle_bounds contain no opaque pixels")


func validate_weapon_bounds(folder: String, mode: String, cell: Vector2i, weapon: String, bounds: Variant) -> void:
	if not valid_bounds(bounds):
		return
	var rect := Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3]))
	check(Rect2i(Vector2i.ZERO, cell).encloses(rect), mode + "/carry/" + weapon + ": baked hold_idle_bounds outside cell")
	var image := Image.new()
	var path := folder + weapon + ".png"
	if image.load(path) != OK or image.get_size().x != cell.x * 4:
		check(false, mode + "/carry/" + weapon + ": cannot inspect baked hold_idle bounds")
		return
	var hold_idle := image.get_region(Rect2i(0, 0, cell.x, cell.y))
	check(hold_idle.get_region(rect).get_used_rect().has_area(), mode + "/carry/" + weapon + ": baked hold_idle_bounds contain no opaque pixels")
