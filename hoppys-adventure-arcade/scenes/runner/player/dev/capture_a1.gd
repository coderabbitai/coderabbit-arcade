extends SceneTree
## Coordinator-only graphical fixture. Never renders in headless mode.
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Guard = preload("res://scenes/runner/player/hifi/palette_guard.gd")
const MaskShader = preload("res://scenes/runner/player/hifi/palette_mask.gdshader")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const CHASE_EYE := Vector3(0, 4, 8)
const CHASE_TARGET := Vector3(0, 1, -8)
const CHASE_SIZE := Vector2(1280, 720)
## Base contract FOV and the in-play worst case (speed_fov_boost 5 at normalized speed 1.2).
const CHASE_FOV := 60.0
const CHASE_FOV_WIDEST := 66.0
## Review r1 numeric targets (1280x720).
const DASH_HEAD_PX := 8.0
const VICTORY_PAWS_PX := 6.0
const FACE_LUMA := Vector2(0.65, 0.85)
const FACE_SATURATION := 0.20
const FLOOR_LUMA_CAP := 0.9
## Studio views whose fur the reviewer read as tan; their fur stats are printed for reference.
const FUR_REPORT_VIEWS := ["dash", "react", "face-focused", "face-wide", "face-wince", "face-grin"]

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	root.get_node("AudioService").music.stop()
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A1 CAPTURE: graphical renderer required")
		await finish(null, 1)
		return
	capture()

func capture() -> void:
	var started := Time.get_ticks_msec()
	var corridor_ms := 0
	var guard_ms := 0
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(stage)
	var studio := Node3D.new()
	stage.add_child(studio)
	configure_lighting(studio)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 60)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Palette.NAVY_2
	# Art review r1: the old glossy metal deck (roughness 0.35, metallic 0.7) blew out a white
	# specular hotspot; a satin deck keeps the fixture floor at luma <= FLOOR_LUMA_CAP.
	floor_mat.roughness = 0.75
	floor_mat.metallic = 0.25
	floor_mesh.material_override = floor_mat
	floor_mesh.position.z = -20
	studio.add_child(floor_mesh)
	var hoppy := Hoppy.instantiate()
	stage.add_child(hoppy)
	hoppy.set_process(false)
	hoppy.animation_player.set_process(false)
	hoppy.animation_player.playback_default_blend_time = 0.0
	var camera := Camera3D.new()
	camera.fov = 60
	stage.add_child(camera)
	camera.current = true
	var directory := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(directory)
	hoppy.animation_player.stop()
	hoppy.skeleton.reset_bone_poses()
	var standing_leg := limb_bounds(hoppy, ["leg_R", "shin_R", "foot_R"])
	var views := [
		["close", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"idle", false],
		["run", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"run", false],
		["run-side", Vector3(2.5, 0.65, 0), Vector3(0, 0.65, 0), &"run", false],
		["jump", Vector3(2.2, 1.0, -1.1), Vector3(0, 0.85, 0), &"jump", false],
		["gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"run", false],
		["shield", Vector3(-2.4, 1.7, -3.3), Vector3(0, 0.9, 0), &"run", true],
		["roll", Vector3(1.2, 1.0, -1.9), Vector3(0, 0.45, 0), &"roll", false],
		["trail", Vector3(1.4, 1.8, 2.8), Vector3(0, 1.0, 0.4), &"run", false],
		["rear", Vector3(1.3, 1.55, 2.3), Vector3(0, 0.95, 0), &"idle", false],
		["roll-gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"roll", false],
		["roll-shield", Vector3(1.6, 1.25, -2.7), Vector3(0, 0.45, 0), &"roll", true],
		# Round 7: movement one-shots, face expressions and the power-up LED strip.
		["dash", Vector3(0, 1.3, -3.3), Vector3(0, 0.9, 0), &"lane_dash_right", false, 4.0 / 30.0],
		["land", Vector3(2.2, 1.0, -1.4), Vector3(0, 0.75, 0), &"land", false, 0.0],
		["brace", Vector3(1.6, 1.4, -2.6), Vector3(0, 0.9, 0), &"shield_brace", true, 0.18],
		["react", Vector3(1.5, 1.4, -2.5), Vector3(0, 1.0, 0), &"powerup_react", false, 0.25],
		["victory", Vector3(0.9, 1.3, -3.0), Vector3(0, 1.0, 0), &"victory", false, 0.6],
		["face-focused", Vector3(0.35, 1.32, -1.05), Vector3(0, 1.27, 0), &"run", false, 0.24],
		["face-wide", Vector3(0.35, 1.32, -1.05), Vector3(0, 1.27, 0), &"jump", false, 0.24],
		["face-wince", Vector3(0.35, 1.32, -1.05), Vector3(0, 1.27, 0), &"hurt", false, 0.3],
		["face-grin", Vector3(0.35, 1.32, -1.05), Vector3(0, 1.27, 0), &"victory", false, 0.6],
		["leds", Vector3(0.8, 1.3, 1.6), Vector3(0, 0.9, 0.2), &"run", false, 0.24, "nitro"],
		["detail-shoes", Vector3(0.7, 0.45, -0.9), Vector3(0, 0.12, -0.05), &"idle", false, 0.0],
		["detail-back", Vector3(0.9, 1.25, 1.3), Vector3(0, 1.05, 0.15), &"idle", false, 0.0],
		["corridor", Vector3(0, 4, 8), Vector3(0, 1, -8), &"run", false],
		["corridor-close", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"idle", false]]
	var palette_ok := true
	var floor_peak := 0.0
	for view: Array in views:
		if view[0] == "corridor":
			studio.free()
			var corridor_started := Time.get_ticks_msec()
			stage.add_child(Corridor.instantiate())
			corridor_ms = Time.get_ticks_msec() - corridor_started
			print("A1 CAPTURE TIMING corridor=%d ms" % corridor_ms)
		camera.position = view[1]
		camera.look_at(view[2])
		var pose_time := 0.0 if view[3] == &"roll" else 0.24
		if view[0] == "run-side":pose_time = 16.5 / 30.0
		if view[0] == "jump":pose_time = 7.5 / 30.0
		if view.size() > 5:pose_time = view[5]
		hoppy.on_power_up_end(&"nitro")
		if view.size() > 6:
			hoppy.on_power_up(StringName(view[6]), 6.0)
			hoppy._process(0.6)
		if not pose_for_view(hoppy, view[3], pose_time):
			printerr("ASSET A1 CAPTURE: incorrect animation for " + str(view[0]))
			await finish(stage, 1)
			return
		if view[0] in ["run-side", "jump"]:
			var bent := limb_bounds(hoppy, ["leg_R", "shin_R", "foot_R"])
			var extent_delta := bent.size.z - standing_leg.size.z
			print("A1 KNEE SILHOUETTE %s: standing=%.4f posed=%.4f delta=%.4f m" % [view[0], standing_leg.size.z, bent.size.z, extent_delta])
			if view[0] == "jump":
				var tuck := jump_tuck_metrics(hoppy)
				print("A1 JUMP TUCK: ", tuck)
				if not tuck["pass"]:palette_ok = false
			if extent_delta < 0.05:
				printerr("ASSET A1 CAPTURE: knee silhouette does not extend beyond standing")
				palette_ok = false
		hoppy.show_shield(view[4])
		hoppy.show_aura(&"lgtm", view[4])
		hoppy.set_run_speed(1)
		hoppy._process(0.1)
		# Settle the face on this state's expression; a capture never lands mid-blink.
		hoppy._expression = hoppy.EXPRESSIONS[view[3]]
		hoppy._process(0.0)
		hoppy._face.blink = 0.0
		if view[0] == "trail":
			assert(hoppy._trail.visible and hoppy._speed == 1.0, "Trail capture must run at speed")
		for frame in 2:
			await process_frame
		if hoppy._flash_remaining > 0.0:
			# The hurt clip's flash method keys fire deferred; clear them so face views keep colour.
			hoppy._process(hoppy._flash_remaining + 0.001)
			hoppy._face.blink = 0.0
			await process_frame
		assert(hoppy.animation_player.current_animation == view[3], "Capture animation mismatch")
		await RenderingServer.frame_post_draw
		var calls := RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var error := root.get_texture().get_image().save_png(directory.path_join("a1-%s.png" % view[0]))
		if error != OK:
			printerr("ASSET A1 CAPTURE: failed to save " + str(view[0]))
			await finish(stage, 1)
			return
		if is_instance_valid(studio):
			var floor_luma := await measure_floor(hoppy)
			floor_peak = maxf(floor_peak, floor_luma)
			print("A1 FLOOR %s: peak luma %.4f (cap %.2f)" % [view[0], floor_luma, FLOOR_LUMA_CAP])
			if floor_luma > FLOOR_LUMA_CAP:
				printerr("ASSET A1 CAPTURE: fixture floor hotspot above cap in " + str(view[0]))
				palette_ok = false
			if view[0] in FUR_REPORT_VIEWS:
				var fur := fur_stats(Image.load_from_file(directory.path_join("a1-%s.png" % view[0])), await capture_mask(hoppy, camera, stage))
				print("A1 STUDIO FUR %s: luma %.4f saturation %.4f (%d px)" % [view[0], fur.luma, fur.saturation, fur.pixels])
		if view[0] == "close":
			var studio_image := Image.load_from_file(directory.path_join("a1-close.png"))
			var lens := measure_goggle_band(studio_image)
			print("A1 GOGGLE BAND: ", lens)
			if not lens["pass"]:
				printerr("ASSET A1 CAPTURE: opaque-looking goggle band")
				palette_ok = false
		if str(view[0]).begins_with("corridor"):
			var saved := Image.load_from_file(directory.path_join("a1-%s.png" % view[0]))
			var mask := await capture_mask(hoppy, camera, stage)
			var guard_started := Time.get_ticks_msec()
			var result := Guard.measure(saved, mask)
			var measured_ms := Time.get_ticks_msec() - guard_started
			guard_ms += measured_ms
			print("A1 CAPTURE TIMING guard=%d ms view=%s" % [measured_ms, view[0]])
			print("A1 HUE %s: %s" % [view[0], result])
			if not result["pass"]:
				printerr("ASSET A1 CAPTURE: corridor palette guard failed")
				palette_ok = false
		print("A1 CAPTURE %s: %d measured viewport draws (includes floor)" % [view[0], calls])
	print("A1 FLOOR PEAK: %.4f over every studio view (cap %.2f)" % [floor_peak, FLOOR_LUMA_CAP])
	if not await capture_chase(hoppy, camera, stage, directory):
		palette_ok = false
	print("A1 CAPTURE TIMING corridor=%d guard=%d total=%d" % [corridor_ms, guard_ms, Time.get_ticks_msec() - started])
	print("ASSET A1 CAPTURE: " + ("PASS" if palette_ok else "FAIL"))
	await finish(stage, 0 if palette_ok else 1)

static func configure_lighting(stage: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Palette.NAVY_BG
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Palette.CREAM
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	# Match the corridor's rear-side player key, lighting gameplay/rear views.
	var key := OmniLight3D.new()
	key.name = "CorridorKey"
	key.position = Vector3(0, 1.8, 1)
	key.light_color = Palette.MINT
	key.light_energy = 0.65
	key.omni_range = 3.2
	key.shadow_enabled = false
	stage.add_child(key)

## Art review r1: in-corridor evidence from the contract rear chase camera (0,4,8 -> 0,1,-8,
## 1280x720). Every new clip is written at its peak frame (a1-chase-<clip>.png) with the palette
## guard, dash and land also as 4-frame strips, and the face fur is measured in the corridor.
func capture_chase(hoppy: Node3D, camera: Camera3D, stage: Node3D, directory: String) -> bool:
	var ok := true
	var player: AnimationPlayer = hoppy.animation_player
	camera.fov = CHASE_FOV
	var clips := [["dash-left", &"lane_dash_left", -1.0, false], ["dash-right", &"lane_dash_right", 1.0, false],
		["land", &"land", 0.0, false], ["brace", &"shield_brace", 0.0, true], ["react", &"powerup_react", 0.0, false],
		["victory", &"victory", 0.0, false]]
	for clip: Array in clips:
		var state: StringName = clip[1]
		var length := player.get_animation(state).length
		# Peak: widest head swing for dashes (runtime lane lean on, as in play), highest paws for
		# victory, first frame for land (full squash), the held guard / pump for brace and react.
		var peak := 0.0
		if state == &"land":peak = 0.0
		elif state == &"shield_brace":peak = 0.18
		elif state == &"powerup_react":peak = 0.25
		else:
			var best := -INF
			for sample in 37:
				var time := length * sample / 36.0
				pose_for_view(hoppy, state, time)
				hoppy.set_lane_lean(clip[2])
				var metrics := chase_metrics(hoppy, CHASE_FOV)
				var score: float = absf(metrics.head_lateral_px) if clip[2] != 0.0 else metrics.paws_above_ears_px
				if score > best:
					best = score
					peak = time
		var image := await chase_shot(hoppy, camera, state, peak, clip[2], clip[3])
		var metrics := chase_metrics(hoppy, CHASE_FOV)
		var widest := chase_metrics(hoppy, CHASE_FOV_WIDEST)
		var head := limb_bounds(hoppy, ["head"]).get_center()
		var projection_error := camera.unproject_position(head).distance_to(chase_screen(head, CHASE_FOV))
		var name := "a1-chase-%s.png" % clip[0]
		if image.save_png(directory.path_join(name)) != OK:
			printerr("ASSET A1 CAPTURE: failed to save " + name)
			return false
		print("A1 CHASE %s: t=%.3f s head_lateral=%.2f px paws_above_ears=%.2f px height=%.1f px (fov %.0f); at fov %.0f head %.2f paws %.2f; cpu projection error %.2f px" % [clip[0], peak, metrics.head_lateral_px, metrics.paws_above_ears_px, metrics.height_px, CHASE_FOV, CHASE_FOV_WIDEST, widest.head_lateral_px, widest.paws_above_ears_px, projection_error])
		if projection_error > 1.5:
			printerr("ASSET A1 CAPTURE: CPU chase projection disagrees with the camera")
			ok = false
		if clip[2] != 0.0 and (signf(metrics.head_lateral_px) != clip[2] or absf(metrics.head_lateral_px) < DASH_HEAD_PX):
			printerr("ASSET A1 CAPTURE: dash head displacement below %.0f px" % DASH_HEAD_PX)
			ok = false
		if state == &"victory" and metrics.paws_above_ears_px < VICTORY_PAWS_PX:
			printerr("ASSET A1 CAPTURE: victory paws below the ear tips")
			ok = false
		var result := Guard.measure(image, await capture_mask(hoppy, camera, stage))
		# The brace plays under the mint shield bubble, which tints the fur on purpose; like the
		# studio shield views it is reported, not gated.
		print("A1 HUE chase-%s%s: %s" % [clip[0], " (under shield, informational)" if clip[3] else "", result])
		if not result["pass"] and not clip[3]:
			printerr("ASSET A1 CAPTURE: chase palette guard failed " + str(clip[0]))
			ok = false
	# Face fur in the corridor: the chase camera only sees the back, so a front camera in the
	# same corridor lighting measures the fur the reviewer read as tan.
	var face_eye := Vector3(0.35, 1.32, -1.05)
	var face_target := Vector3(0, 1.27, 0)
	var sweep := OS.get_cmdline_user_args().has("--front-fill-sweep")
	for fill: float in ([0.0, 0.12, 0.22, 0.32, hoppy.FRONT_FILL] if sweep else [hoppy.FRONT_FILL]):
		set_front_fill(hoppy, fill)
		var image := await chase_shot(hoppy, camera, &"run", 0.24, 0.0, false, face_eye, face_target)
		var fur := fur_stats(image, await capture_mask(hoppy, camera, stage))
		print("A1 CORRIDOR FACE FUR front_fill=%.2f: luma %.4f saturation %.4f (%d px)" % [fill, fur.luma, fur.saturation, fur.pixels])
		if sweep:
			var close := await chase_shot(hoppy, camera, &"idle", 0.24, 0.0, false, Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0))
			print("A1 SWEEP corridor-close front_fill=%.2f: %s" % [fill, Guard.measure(close, await capture_mask(hoppy, camera, stage))])
			var rear := await chase_shot(hoppy, camera, &"run", 0.24, 0.0, false)
			print("A1 SWEEP chase-run front_fill=%.2f: %s" % [fill, Guard.measure(rear, await capture_mask(hoppy, camera, stage))])
		if is_equal_approx(fill, hoppy.FRONT_FILL):
			image.save_png(directory.path_join("a1-chase-face.png"))
			var in_band: bool = fur.luma >= FACE_LUMA.x and fur.luma <= FACE_LUMA.y and fur.saturation <= FACE_SATURATION and fur.pixels >= 1000
			if not in_band:
				printerr("ASSET A1 CAPTURE: corridor face fur outside luma %s / saturation <= %.2f" % [FACE_LUMA, FACE_SATURATION])
				ok = false
	for strip: Array in [["dash-left", &"lane_dash_left", -1.0], ["dash-right", &"lane_dash_right", 1.0], ["land", &"land", 0.0]]:
		var length := player.get_animation(strip[1]).length
		# Land's last cell sits one 120 Hz key before the end (the clip has returned by then).
		var times := [0.0, length / 3.0, length * 2.0 / 3.0, length - 1.0 / 120.0] if strip[1] == &"land" else [0.0, length * 0.25, length * 0.5, length * 0.75]
		var top := int(chase_screen(Vector3(0, 2.05, 0), CHASE_FOV).y)
		var bottom := int(chase_screen(Vector3(0, -0.05, 0.3), CHASE_FOV).y)
		var cell := Rect2i(640 - 110, top, 220, bottom - top)
		var sheet := Image.create(cell.size.x * 4, cell.size.y, false, Image.FORMAT_RGBA8)
		var heads := []
		for index in 4:
			var frame := await chase_shot(hoppy, camera, strip[1], times[index], strip[2], false)
			frame.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame, cell, Vector2i(cell.size.x * index, 0))
			var metrics := chase_metrics(hoppy, CHASE_FOV)
			heads.append("t=%.3f head %.2f px height %.1f px" % [times[index], metrics.head_lateral_px, metrics.height_px])
		var name := "a1-chase-%s-strip.png" % strip[0]
		if sheet.save_png(directory.path_join(name)) != OK:
			printerr("ASSET A1 CAPTURE: failed to save " + name)
			return false
		print("A1 CHASE STRIP %s: %s" % [strip[0], ", ".join(heads)])
	set_front_fill(hoppy, hoppy.FRONT_FILL)
	hoppy.set_lane_lean(0.0)
	return ok

func chase_shot(hoppy: Node3D, camera: Camera3D, state: StringName, time: float, lean: float, shield: bool,
		eye := CHASE_EYE, target := CHASE_TARGET) -> Image:
	camera.position = eye
	camera.look_at(target)
	hoppy.on_power_up_end(&"nitro")
	pose_for_view(hoppy, state, time)
	hoppy.set_lane_lean(lean)
	hoppy.show_shield(shield)
	hoppy.show_aura(&"lgtm", shield)
	hoppy.set_run_speed(1)
	hoppy._process(0.1)
	hoppy._expression = hoppy.EXPRESSIONS[state]
	hoppy._process(0.0)
	hoppy._face.blink = 0.0
	for frame in 2:
		await process_frame
	if hoppy._flash_remaining > 0.0:
		hoppy._process(hoppy._flash_remaining + 0.001)
		hoppy._face.blink = 0.0
		await process_frame
	assert(hoppy.animation_player.current_animation == state, "Chase capture animation mismatch")
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

static func set_front_fill(hoppy: Node3D, fill: float) -> void:
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			(mesh.get_active_material(surface) as ShaderMaterial).set_shader_parameter("front_fill", fill)

## Peak Rec.709 luma of the frame with Hoppy hidden: in the studio that is the deck (the
## background is flat navy), so it caps the fixture floor hotspot.
func measure_floor(hoppy: Node3D) -> float:
	hoppy.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	hoppy.visible = true
	return peak_luma(image)

static func peak_luma(image: Image) -> float:
	var pixels := image.duplicate() as Image
	pixels.convert(Image.FORMAT_RGB8)
	var rgb := pixels.get_data()
	var peak := 0.0
	for offset in range(0, rgb.size(), 3):
		peak = maxf(peak, (0.2126 * rgb[offset] + 0.7152 * rgb[offset + 1] + 0.0722 * rgb[offset + 2]) / 255.0)
	return peak

## Mean Rec.709 luma and mean-colour HSV saturation of the fur (mask green) class, on saved bytes.
static func fur_stats(image: Image, mask: Image) -> Dictionary:
	var pixels := image.duplicate() as Image
	var classes := mask.duplicate() as Image
	pixels.convert(Image.FORMAT_RGB8)
	classes.convert(Image.FORMAT_RGB8)
	var rgb := pixels.get_data()
	var masks := classes.get_data()
	var sum := Vector3.ZERO
	var luma := 0.0
	var count := 0
	for offset in range(0, mini(rgb.size(), masks.size()), 3):
		if not (masks[offset + 1] > 204 and masks[offset] < 51):
			continue
		var c := Vector3(rgb[offset], rgb[offset + 1], rgb[offset + 2]) / 255.0
		sum += c
		luma += 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
		count += 1
	var mean := sum / maxi(count, 1)
	return {"luma": luma / maxi(count, 1), "saturation": Color(mean.x, mean.y, mean.z).s, "pixels": count}

static func pose_for_view(hoppy: Node3D, state: StringName, time: float) -> bool:
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	hoppy.set_anim_state(state)
	if hoppy.anim_state != state:
		# A gait one-shot defers its own return state; fixtures always sample the requested clip.
		hoppy._play(state)
	# Runtime uses an explicit cross-fade; setting the default alone cannot cancel it.
	player.play(state, 0.0)
	player.advance(0.0)
	player.seek(time, true)
	player.advance(0.0)
	return player.assigned_animation == state

func finish(stage: Node3D, code: int) -> void:
	root.get_node("AudioService").shutdown()
	if is_instance_valid(stage):
		stage.free()
	await process_frame
	quit(code)

func capture_mask(hoppy: Node3D, camera: Camera3D, stage: Node3D) -> Image:
	var original: Array = []
	var layers: Array = []
	for mesh: MeshInstance3D in hoppy._meshes:
		layers.append(mesh.layers)
		mesh.layers = 1 << 19
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			original.append(material)
			var mask := ShaderMaterial.new()
			mask.shader = MaskShader
			mask.set_shader_parameter("albedo_map", material.get_shader_parameter("albedo_map"))
			mask.set_shader_parameter("albedo_color", material.get_shader_parameter("albedo_color"))
			mesh.set_surface_override_material(surface, mask)
	var world := stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	var environment := world.environment
	var blank := Environment.new()
	blank.background_mode = Environment.BG_COLOR
	blank.background_color = Color.BLACK
	world.environment = blank
	var cull := camera.cull_mask
	camera.cull_mask = 1 << 19
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	camera.cull_mask = cull
	world.environment = environment
	var index := 0
	for mesh_index in hoppy._meshes.size():
		var mesh: MeshInstance3D = hoppy._meshes[mesh_index]
		mesh.layers = layers[mesh_index]
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, original[index])
			index += 1
	original.clear()
	layers.clear()
	environment = null
	blank = null
	return image

static func measure_goggle_band(image: Image) -> Dictionary:
	# Fixed studio camera, 1280x720; inclusive reviewer coordinates.
	var mean := Color(0, 0, 0, 0)
	for y in range(230, 249):
		for x in range(624, 701):
			mean += image.get_pixel(x, y)
	mean /= 77.0 * 19.0
	# Authored veil a9b48d has saturation 0.217; opaque r11 62a48c has 0.402.
	return {"pass": mean.s < 0.30, "mean_color": mean.to_html(false), "saturation": mean.s}

static func limb_bounds(hoppy: Node3D, names: Array) -> AABB:
	# CPU skin bounds for one leg/sole, valid with the dummy headless renderer too.
	var points := skinned_points(hoppy, names)
	assert(not points.is_empty(), "No vertices for requested limb")
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

## World-space CPU-skinned vertices mostly weighted to `names` (headless-safe).
static func skinned_points(hoppy: Node3D, names: Array) -> PackedVector3Array:
	var skeleton: Skeleton3D = hoppy.skeleton
	skeleton.force_update_all_bone_transforms()
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in hoppy._meshes:
		var skin := mesh.skin
		var transforms: Array[Transform3D] = []
		var selected: Array[bool] = []
		for bind in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone < 0:bone = skeleton.find_bone(skin.get_bind_name(bind))
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
			selected.append(str(skeleton.get_bone_name(bone)) in names)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var membership := 0.0
				for joint in stride:
					var index := vertex * stride + joint
					var bind := bones[index]
					var weight := weights[index]
					if weight <= 0.0:continue
					point += transforms[bind] * vertices[vertex] * weight
					if selected[bind]:membership += weight
				if membership < 0.5:continue
				points.append(point)
	return points

## The contract chase camera (runner_game CameraRig at rest), projected on the CPU so the
## gameplay-view targets are checkable headless; `fov` is vertical, as Camera3D keeps height.
static func chase_screen(point: Vector3, fov: float) -> Vector2:
	var eye := Transform3D(Basis.IDENTITY, CHASE_EYE).looking_at(CHASE_TARGET, Vector3.UP)
	var local := eye.affine_inverse() * point
	var focal := 1.0 / tan(deg_to_rad(fov) * 0.5) * CHASE_SIZE.y * 0.5
	return CHASE_SIZE * 0.5 + Vector2(local.x, -local.y) * focal / -local.z

## Review targets read from the rear chase camera: dash head displacement from the corridor
## centreline and how far the lower paw tip rises above the higher ear tip (screen px, 1280x720).
static func chase_metrics(hoppy: Node3D, fov: float) -> Dictionary:
	var head := limb_bounds(hoppy, ["head"]).get_center()
	var head_px := chase_screen(head, fov).x - chase_screen(Vector3(0.0, head.y, head.z), fov).x
	var ear_top := INF
	for point in skinned_points(hoppy, ["ear_L", "ear_tip_L", "ear_R", "ear_tip_R"]):
		ear_top = minf(ear_top, chase_screen(point, fov).y)
	var paw_tops := []
	for side in ["hand_L", "hand_R"]:
		var top := INF
		for point in skinned_points(hoppy, [side]):
			top = minf(top, chase_screen(point, fov).y)
		paw_tops.append(top)
	var feet := limb_bounds(hoppy, ["foot_L", "foot_R"])
	var height_px := chase_screen(Vector3(0.0, feet.position.y, feet.get_center().z), fov).y - ear_top
	return {"head_lateral_px": head_px, "paws_above_ears_px": ear_top - maxf(paw_tops[0], paw_tops[1]),
		"height_px": height_px}

static func jump_tuck_metrics(hoppy: Node3D) -> Dictionary:
	var skeleton: Skeleton3D = hoppy.skeleton
	skeleton.force_update_all_bone_transforms()
	var knee := skeleton.get_bone_global_pose(skeleton.find_bone("shin_R")).origin
	var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("foot_R")).origin
	var hip := skeleton.get_bone_global_pose(skeleton.find_bone("leg_R")).origin
	# +Z is toward the tail; measure real joint positions along the bend plane.
	return {"pass": ankle.z - knee.z >= 0.16 and ankle.y - knee.y >= -0.07 and hip.y - ankle.y <= 0.30,
		"heel_back": ankle.z - knee.z, "heel_vs_knee_y": ankle.y - knee.y, "hip_to_heel_drop": hip.y - ankle.y}
