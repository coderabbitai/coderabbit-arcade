extends SceneTree
## Host-only: nine boss views plus an effects plate in the dark a5 rig, then (art review r1) the
## in-corridor gameplay-camera strips: the real runner scene (starship corridor, Hoppy, chase
## camera), paused, with every signature attack replayed into its BossArena, one 4-frame strip
## (telegraph, mid-telegraph, commit, impact) per signature -> a5-corridor-<boss>-<signature>.png,
## and every review-r1 numeric target measured and printed (capture_corridor()).
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
const ProjectileArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
## Contract 2.4 signature views: [boss slot, signature, telegraph fraction shown, shot age shown
## (seconds since fire of an identical attack already in flight; < 0 for none), commit].
const SIGNATURE_VIEWS := [
	[0, &"flaky", 0.2, 0.25, false], [0, &"flaky", 0.85, -1.0, true], [0, &"scatter", 0.5, 0.42, false],
	[1, &"branching", 0.6, 0.3, false], [1, &"sweep", 0.55, 0.45, false], [1, &"force_push", 0.5, 0.35, false],
	[2, &"legacy_wall", 0.4, 0.22, false], [2, &"quake", 0.6, 0.3, false], [2, &"debris", 0.7, 0.5, false],
]
const CLOSE_CAMERA := Vector3(3.1, 4.4, -9.6)
var previous_png := PackedByteArray()
var previous_view := ""
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A5 CAPTURE: requires a graphical host")
		call_deferred("finish_capture", 1)
		return
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	# The corridor pass runs a real run: keep it silent for whoever sits at the machine.
	AudioServer.set_bus_mute(0, true)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Art.Materials.environment()
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -25, 0)
	key.light_color = Palette.MATRIX
	key.light_energy = 0.35
	world.add_child(key)
	var near_light := OmniLight3D.new()
	near_light.position = Vector3(0, 3, 1)
	near_light.light_color = Palette.CREAM
	near_light.light_energy = 1.6
	near_light.omni_range = 9.0
	near_light.shadow_enabled = false
	world.add_child(near_light)
	Art.box(world, Vector3(0, -0.2, -15), Vector3(8, 0.35, 55), Palette.NAVY_2)
	for side in [-1, 1]:
		Art.box(world, Vector3(side * 4.2, 3, -18), Vector3(0.3, 6, 50), Palette.NAVY_BG)
	for lane in [-1, 0, 1]:
		Art.box(world, Vector3(lane * 2, 0, -18), Vector3(0.025, 0.015, 45), Palette.SLATE)
	camera = Camera3D.new()
	camera.fov = 60
	world.add_child(camera)
	camera.current = true
	var folder := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(folder)
	for kind in ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]:
		var mount := Node3D.new()
		mount.position = Vector3(0, 2.6, -14)
		world.add_child(mount)
		var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kind).instantiate()
		mount.add_child(visual)
		visual.hover_z = -14.0
		visual.kind = StringName(kind)
		visual.max_hp = 100
		visual.show_name_plate = false
		visual.on_spawned()
		visual.set_process(false)
		for view in ["gameplay", "close", "phase2"]:
			visual.on_spawned()
			if view == "phase2":
				visual.set_phase(2)
				visual.set_health(40, 100)
			visual._process(1.4)
			camera.position = Vector3(0, 4, 8) if view == "gameplay" else CLOSE_CAMERA
			camera.look_at(Vector3(0, 1, -8) if view == "gameplay" else Vector3(0, 2.9, -14))
			if not await save_view(folder, kind + "-" + view): return
		mount.free()
	if not await capture_signatures(folder): return
	var fx: Node3D = load("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	world.add_child(fx)
	fx.telegraphs[0].start(0, &"orb", 1.0)
	fx.telegraphs[0]._process(0.5)
	fx.numbers[0].start(Vector3(0, 2.6, -6), 15, Palette.ORANGE, 0)
	fx.numbers[0]._process(0.2)
	fx.tracers[0].fire(Vector3(2, 1, 0), Vector3(0, 3, -14), &"lint_rule", 12)
	fx.tracers[0]._process(0.07)
	for node in fx.telegraphs + fx.numbers + fx.tracers: node.set_process(false)
	camera.position = Vector3(0, 4, 8)
	camera.look_at(Vector3(0, 1, -8))
	if not await save_view(folder, "effects"): return
	world.free()
	if not await capture_corridor(folder): return
	print("ASSET A5 CAPTURE: PASS")
	await finish_capture(0)

## Each boss's signature attacks: the telegraph mode on the floor, the boss reacting, and the
## projectile look in flight, from the real boss_attacks.gd attacks and motion.
func capture_signatures(folder: String) -> bool:
	var fx: Node3D = load("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	world.add_child(fx)
	var kinds := ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]
	var scene := load("res://scenes/runner/hazards/visuals/projectile_visual.tscn") as PackedScene
	for view: Array in SIGNATURE_VIEWS:
		var slot: int = view[0]
		var signature: StringName = view[1]
		var option := signature_option(slot, signature)
		var mount := Node3D.new()
		mount.position = Vector3(0, 2.6, -14)
		world.add_child(mount)
		var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kinds[slot]).instantiate()
		mount.add_child(visual)
		visual.hover_z = -14.0
		visual.kind = StringName(kinds[slot])
		visual.max_hp = 100
		visual.show_name_plate = false
		visual.on_spawned()
		visual.set_process(false)
		visual.set_phase(option[0])
		visual._process(1.0)
		fx.clear()
		var shown: float = view[2]
		var shots: Array[Node3D] = []
		for attack: Dictionary in option[1]:
			fx._planned(attack)
			fx._telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
			visual.play_telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
			var age: float = view[3]
			if age < 0.0: continue
			for shot: Dictionary in attack.shots:
				shots.append(spawn_shot(scene, shot, age, kinds[slot], signature))
		var lead: Dictionary = option[1][0]
		var step := float(lead.telegraph) * shown
		if view[4]:
			var commit := float(lead.commit_at)
			fx._process(commit)
			for node in fx.telegraphs: node._process(commit)
			visual._process(commit)
			fx._committed(int(lead.mask), lead.variant, float(lead.telegraph) - commit)
			visual.play_commit(int(lead.mask), lead.variant, float(lead.telegraph) - commit)
			step -= commit
		fx._process(step)
		for node in fx.telegraphs: node._process(step)
		visual._process(step)
		fx.set_process(false)
		for node in fx.telegraphs: node.set_process(false)
		camera.position = Vector3(0, 4.6, 8.5)
		camera.look_at(Vector3(0, 0.6, -7))
		var title := "%s-%s%s" % [kinds[slot].get_slice("_", kinds[slot].get_slice_count("_") - 1), String(signature).replace("_", "-"), "-commit" if view[4] else ""]
		if not await save_view(folder, title): return false
		fx.set_process(true)
		for node in fx.telegraphs: node.set_process(true)
		for node in shots: node.free()
		mount.free()
	fx.free()
	return true

static func signature_option(slot: int, signature: StringName) -> Array:
	var def: Dictionary = BossDefs.SLOTS[slot]
	for phase in [1, 2, 3]:
		for beat: Dictionary in def.patterns[phase - 1]:
			if StringName(beat.get("signature", &"")) == signature:
				var options := BossAttacks.beat_options(beat, def, phase, null)
				# A two-lane draw where there is one reads better in a still.
				var pick: Array = options[0]
				for option: Array in options:
					if option.size() == 1 and bin_count(int(option[0].mask)) == 2 and signature == &"debris": pick = option
				return [phase, pick]
	return [1, []]

static func bin_count(mask: int) -> int:
	return (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1)

func spawn_shot(scene: PackedScene, shot: Dictionary, age: float, boss_kind: String, signature: StringName, parent: Node3D = null) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(BossAttacks.x_at(shot, age), BossAttacks.y_offset_at(shot, age), BossAttacks.z_at(shot, age))
	(parent if parent != null else world).add_child(holder)
	var def := HazardDefs.get_def(&"projectile", StringName(shot.variant))
	var visual: Node3D = scene.instantiate()
	visual.variant = StringName(shot.variant)
	visual.projectile_variant = StringName(shot.variant)
	visual.boss_kind = StringName(boss_kind)
	visual.signature = signature
	visual.motion = shot
	visual.hitbox_size = def.size
	visual.hitbox_offset = Vector3(0, float(def.y_min) + def.size.y * 0.5, 0)
	visual.closing_speed = float(shot.speed)
	holder.add_child(visual)
	visual.on_spawned()
	visual._process(age)
	visual.set_process(false)
	return holder

func save_view(folder: String, view: String) -> bool:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var png := root.get_texture().get_image().save_png_to_buffer()
	if not distinct_view(png, previous_png):
		printerr("ASSET A5 CAPTURE: FAIL identical views " + previous_view + " / " + view)
		await finish_capture(1)
		return false
	previous_png = png
	previous_view = view
	var result := root.get_texture().get_image().save_png(folder.path_join("a5-" + view + ".png"))
	if result != OK:
		printerr("ASSET A5 CAPTURE: FAIL saving " + view)
		await finish_capture(1)
		return false
	print("ASSET A5 CAPTURE DRAW CALLS: %s = %d (whole fixture)" % [view, draws])
	return true

static func distinct_view(current: PackedByteArray, previous: PackedByteArray) -> bool:
	return not current.is_empty() and current != previous

func finish_capture(code: int) -> void:
	if is_instance_valid(world): world.free()
	paused = false
	# The game first: its CanvasLayers still point at the offscreen viewport.
	if is_instance_valid(game): game.free()
	for port: SubViewport in iso.values():
		if is_instance_valid(port): port.free()
	iso.clear()
	Art.Forge.clear_cache()
	ProjectileArt.release_caches()
	# Stop the autoload MP3 playback before the audio thread exits.
	root.get_node("AudioService").shutdown()
	await create_timer(0.25).timeout
	quit(code)

# --- art review r1: in-corridor gameplay-camera strips and measured targets ---

## [boss slot, signature]: every contract 2.4 signature once.
const CORRIDOR_SIGNATURES := [[0, &"flaky"], [0, &"scatter"], [1, &"branching"], [1, &"sweep"],
	[1, &"force_push"], [2, &"legacy_wall"], [2, &"quake"], [2, &"debris"]]
## Render layers the isolation viewports see (added on top of layer 1, so the corridor frame is
## untouched): the shots, the whole boss, one Hydra head, the signature marks.
const LAYER_SHOT := 1 << 19
const LAYER_BOSS := 1 << 18
const LAYER_HEAD := 1 << 17
const LAYER_MARKS := 1 << 16
const STEP := 1.0 / 60.0
const STRIP_FRAME := Vector2i(640, 360)
## Pixel classes of classify().
enum Tone { UNLIT, DANGER, ORANGE, GREEN, LILAC, NEUTRAL, OTHER }
var game: Node
var iso := {}
var missed := 0

func capture_corridor(folder: String) -> bool:
	game = (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("a5_corridor_capture_leaderboard.cfg")
	root.add_child(game)
	game.start_run(4242)
	var chunks := game.get_node("World/Chunks") as Node3D
	# Hoppy runs down an empty corridor so the boss attacks are the only hazards in frame.
	chunks.visible = false
	for frame in 50: await process_frame
	chunks.visible = false
	game.pause()
	route_panels()
	var arena := game.get_node("World/TurnRig/BossArena") as Node3D
	var fx: Node3D = null
	for child in arena.get_children():
		if child.has_method("draw_record"): fx = child
	if fx == null:
		printerr("ASSET A5 CAPTURE: FAIL no BossFX in the arena")
		await finish_capture(1)
		return false
	fx.marks.layers |= LAYER_MARKS
	var view_camera := root.get_camera_3d()
	make_iso(view_camera)
	var player := game.get("player") as Node3D
	var hoppy := view_camera.unproject_position(player.global_position + Vector3(0, 0.6, 0))
	target("Hoppy in frame (chase camera, px)", hoppy.x > 0 and hoppy.x < 1280 and hoppy.y > 0 and hoppy.y < 720, "%.0f, %.0f" % [hoppy.x, hoppy.y])
	var kinds := ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]
	var scene := load("res://scenes/runner/hazards/visuals/projectile_visual.tscn") as PackedScene
	for entry: Array in CORRIDOR_SIGNATURES:
		var slot: int = entry[0]
		var signature: StringName = entry[1]
		var option := signature_option(slot, signature)
		var attacks: Array = option[1]
		var lead: Dictionary = attacks[0]
		var total := float(lead.telegraph)
		var commit_at := float(lead.get("commit_at", -1.0))
		var lead_shot: Dictionary = lead.shots[0]
		var impact_age := 0.0
		while impact_age < 8.0 and BossAttacks.z_at(lead_shot, impact_age) < -2.4: impact_age += 0.01
		var mid := total * 0.55 if commit_at < 0.0 else minf(total * 0.55, commit_at - 0.05)
		# The flaky commit frame is shown once the tiles have snapped (0.12 s) into the column.
		var times := [total * 0.15, mid, commit_at + 0.14 if commit_at >= 0.0 else total + 0.03, total + impact_age]
		var title := "%s-%s" % [kinds[slot].get_slice("_", kinds[slot].get_slice_count("_") - 1), String(signature).replace("_", "-")]
		var strip := Image.create(STRIP_FRAME.x * 4, STRIP_FRAME.y, false, Image.FORMAT_RGBA8)
		var shot_counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
		for f in 4:
			var staged := stage(arena, fx, scene, kinds[slot], option[0], attacks, float(times[f]), signature)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var frame_image := root.get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGBA8)
			var draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var visual: Node3D = staged[0].get_child(0)
			var shots: Array = staged.slice(1)
			if f >= 2 and not shots.is_empty():
				var counts: PackedInt32Array = census(iso_image("shot"), Rect2i(0, 0, 1280, 720)).counts
				for i in counts.size(): shot_counts[i] += counts[i]
			measure_frame(title, f, signature, visual, shots, lead, fx, view_camera, frame_image)
			print("A5 CORRIDOR FRAME: %s %s t=%.2f s, %d shots, %d draws (whole corridor frame)" % [title, ["telegraph", "mid-telegraph", "commit", "impact"][f], times[f], shots.size(), draws])
			var small := frame_image.duplicate() as Image
			small.resize(STRIP_FRAME.x, STRIP_FRAME.y, Image.INTERPOLATE_BILINEAR)
			strip.blit_rect(small, Rect2i(Vector2i.ZERO, STRIP_FRAME), Vector2i(STRIP_FRAME.x * f, 0))
			for node: Node in staged: node.free()
		# Every projectile is DANGER: >= 50 % of lit projectile pixels over the commit + impact frames.
		var lit := 0
		for i in range(1, shot_counts.size()): lit += shot_counts[i]
		var danger := float(shot_counts[Tone.DANGER]) / maxi(lit, 1)
		var accent := float(shot_counts[Tone.GREEN] + shot_counts[Tone.LILAC] + shot_counts[Tone.ORANGE]) / maxi(lit, 1)
		target("%s projectile DANGER share of lit pixels (>= 50 %%)" % title, lit > 0 and danger >= 0.5, "%.0f %% of %d px" % [danger * 100.0, lit])
		target("%s projectile MATRIX/LILAC/ORANGE share (<= 25 %%)" % title, accent <= 0.25, "%.0f %% (MATRIX %.0f, LILAC %.0f, ORANGE %.0f, neutral %.0f)" % [accent * 100.0,
			100.0 * shot_counts[Tone.GREEN] / maxi(lit, 1), 100.0 * shot_counts[Tone.LILAC] / maxi(lit, 1), 100.0 * shot_counts[Tone.ORANGE] / maxi(lit, 1), 100.0 * shot_counts[Tone.NEUTRAL] / maxi(lit, 1)])
		var path := folder.path_join("a5-corridor-" + title + ".png")
		if strip.save_png(path) != OK:
			printerr("ASSET A5 CAPTURE: FAIL saving " + path)
			await finish_capture(1)
			return false
		print("A5 CORRIDOR STRIP: " + path)
	print("ASSET A5 CORRIDOR TARGETS: %s (%d missed)" % ["PASS" if missed == 0 else "FAIL", missed])
	return true

## One frame of a signature, rebuilt from scratch: the boss visual mounted where the encounter
## mounts it, the attacks telegraphed through boss_fx and the visual hooks, the clock stepped to
## `t` seconds after the telegraph (commits and fires on their own ticks), then the shots already
## fired spawned at their real motion. Returns [boss mount, shot holders...].
func stage(arena: Node3D, fx: Node3D, scene: PackedScene, boss_kind: String, phase: int, attacks: Array, t: float, signature: StringName) -> Array:
	var mount := Node3D.new()
	mount.position = Vector3(0, 2.6, -14)
	arena.add_child(mount)
	var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % boss_kind).instantiate()
	visual.hover_z = -14.0
	visual.kind = StringName(boss_kind)
	visual.max_hp = 100
	visual.show_name_plate = false
	mount.add_child(visual)
	visual.on_spawned()
	visual.set_phase(phase)
	visual._process(1.0)
	fx.clear()
	var committed: Array[bool] = []
	var fired: Array[bool] = []
	for attack: Dictionary in attacks:
		fx._planned(attack)
		fx._telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
		visual.play_telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
		committed.append(float(attack.get("commit_at", -1.0)) < 0.0)
		fired.append(false)
	var clock := 0.0
	while clock < t - 0.0001:
		var dt := minf(STEP, t - clock)
		clock += dt
		fx._process(dt)
		for node in fx.telegraphs: node._process(dt)
		visual._process(dt)
		for i in attacks.size():
			var attack: Dictionary = attacks[i]
			if not committed[i] and clock >= float(attack.commit_at):
				committed[i] = true
				fx._committed(int(attack.mask), attack.variant, float(attack.telegraph) - float(attack.commit_at))
				visual.play_commit(int(attack.mask), attack.variant, float(attack.telegraph) - float(attack.commit_at))
			if not fired[i] and clock >= float(attack.telegraph):
				fired[i] = true
				visual.play_attack(attack.variant)
	for node: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false): node.layers |= LAYER_BOSS
	var art: Node3D = visual._art
	if art.heads.size() > 1:
		for node: GeometryInstance3D in art.heads[1].find_children("*", "GeometryInstance3D", true, false): node.layers |= LAYER_HEAD
	var result: Array = [mount]
	for i in attacks.size():
		var attack: Dictionary = attacks[i]
		var age := t - float(attack.telegraph)
		if age < 0.0: continue
		for shot: Dictionary in attack.shots:
			var holder := spawn_shot(scene, shot, age, boss_kind, signature, arena)
			holder.set_meta("shot", shot)
			holder.set_meta("age", age)
			for node: GeometryInstance3D in holder.find_children("*", "GeometryInstance3D", true, false): node.layers |= LAYER_SHOT
			result.append(holder)
	return result

## The review-r1 numeric targets that belong to this frame, printed with their measured values.
func measure_frame(title: String, f: int, signature: StringName, visual: Node3D, shots: Array, lead: Dictionary, fx: Node3D, view_camera: Camera3D, frame_image: Image) -> void:
	var art: Node3D = visual._art
	if f == 1:
		# Attack-state accents: the saturated boss pixels mid-telegraph are DANGER.
		var boss: PackedInt32Array = census(iso_image("boss"), Rect2i(0, 0, 1280, 720)).counts
		var saturated := boss[Tone.DANGER] + boss[Tone.ORANGE] + boss[Tone.GREEN] + boss[Tone.LILAC] + boss[Tone.OTHER]
		var share := float(boss[Tone.DANGER]) / maxi(saturated, 1)
		target("%s boss attack-state accents DANGER (share of saturated boss pixels >= 50 %%)" % title, share >= 0.5, "%.0f %% of %d px" % [share * 100.0, saturated])
	if f == 0 and signature == &"branching":
		# Unlit plating reflects the black isolation backdrop, so any non-black pixel is the head.
		var head: Rect2i = census(iso_image("head"), Rect2i(0, 0, 1280, 720), 0.004).box
		target("hydra head width at fight distance (>= 40 px)", head.size.x >= 40, "%d px wide, %d px tall" % [head.size.x, head.size.y])
	if f == 0 and signature == &"legacy_wall":
		# The MINT gap lines at their far (boss) end: the longest MINT run across the row at z -12.
		var marks := iso_image("marks")
		var widest := 0
		for side in [-1.0, 1.0]:
			var point := view_camera.unproject_position(Vector3(fx.lane_x(int(lead.gap_from)) + side * 0.9, 0.036, -12.0))
			var run := 0
			for x in range(maxi(int(point.x) - 30, 0), mini(int(point.x) + 30, 1280)):
				var tone := classify(marks.get_pixel(x, clampi(int(point.y), 0, 719)))
				run = run + 1 if tone == Tone.GREEN else 0
				widest = maxi(widest, run)
		target("legacy wall MINT gap line width at z -12 (>= 4 px)", widest >= 4, "%d px" % widest)
	if f == 2 and signature == &"flaky":
		# The committed column: a DANGER fill (alpha >= 0.5), in the marks alone and in the frame.
		var won := 1
		for lane in 3:
			if int(lead.mask) & (1 << lane): won = lane
		var marks := iso_image("marks")
		var fill := 0
		var in_frame := 0
		var samples := 0
		# Sample the seven committed tiles (boss_fx._flaky: z = from_z + 1.5 + k * 1.75), 3 x 3 each.
		for k in 7:
			for dz in [-0.5, 0.0, 0.5]:
				var z: float = float(lead.get("from_z", -14.0)) + 1.5 + k * 1.75 + dz
				for dx in [-0.45, 0.0, 0.45]:
					var p := view_camera.unproject_position(Vector3(fx.lane_x(won) + dx, 0.036, z))
					var px := Vector2i(clampi(int(p.x), 0, 1279), clampi(int(p.y), 0, 719))
					samples += 1
					if classify(marks.get_pixelv(px)) == Tone.DANGER: fill += 1
					if classify(frame_image.get_pixelv(px)) == Tone.DANGER: in_frame += 1
		target("flaky committed column DANGER fill alpha (>= 0.5)", fx.COMMIT_FILL_ALPHA >= 0.5, "%.2f" % fx.COMMIT_FILL_ALPHA)
		target("flaky committed column DANGER samples, marks layer (>= 80 %)", fill >= samples * 0.8, "%d / %d" % [fill, samples])
		target("flaky committed column reads DANGER in the corridor frame (>= 80 %)", in_frame >= samples * 0.8, "%d / %d" % [in_frame, samples])
	if f == 2 and signature in [&"branching", &"sweep", &"legacy_wall"] and not shots.is_empty():
		var holder: Node3D = shots[0]
		var window := shot_window(holder, view_camera)
		var box: Rect2i = census(iso_image("shot"), window).box
		var distance := view_camera.global_position.distance_to(holder.global_position)
		if signature == &"legacy_wall":
			target("legacy wall slab height when the wall fires (>= 60 px)", box.size.y >= 60, "%d px tall at %.1f m" % [box.size.y, distance])
		else:
			var at_30 := box.size.x * distance / 30.0
			target("%s width at 30 m (>= 16 px)" % ("hydra bolt" if signature == &"branching" else "rebase serpent"), at_30 >= 16.0, "%.1f px (%d px at %.1f m)" % [at_30, box.size.x, distance])

## The screen rectangle of a shot's hitbox (110 %), for per-shot measurements.
func shot_window(holder: Node3D, view_camera: Camera3D) -> Rect2i:
	var shot: Dictionary = holder.get_meta("shot")
	var def := HazardDefs.get_def(&"projectile", StringName(shot.variant))
	var size: Vector3 = def.size * 1.1
	var centre := holder.global_position + Vector3(0, float(def.y_min) + def.size.y * 0.5, 0)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in 8:
		var offset := Vector3(size.x if corner & 1 else -size.x, size.y if corner & 2 else -size.y, size.z if corner & 4 else -size.z) * 0.5
		var p := view_camera.unproject_position(centre + offset)
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var rect := Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE)
	return rect.intersection(Rect2i(0, 0, 1280, 720))

func target(name: String, ok: bool, value: String) -> void:
	if not ok: missed += 1
	print("A5 R1 TARGET: %s = %s -> %s" % [name, value, "PASS" if ok else "MISS"])

## Isolation viewports sharing the corridor's World3D, each seeing one render layer over black,
## with the corridor's own tonemap so hues match the frame.
func make_iso(source: Camera3D) -> void:
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.3, 0.36, 0.45)
	settings.ambient_light_energy = 0.6
	var corridor_environment := source.get_world_3d().environment if source.get_world_3d() != null else null
	for node in game.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null: corridor_environment = (node as WorldEnvironment).environment
	if corridor_environment != null:
		settings.tonemap_mode = corridor_environment.tonemap_mode
		settings.tonemap_exposure = corridor_environment.tonemap_exposure
		settings.tonemap_white = corridor_environment.tonemap_white
	for key: String in ["shot", "boss", "head", "marks"]:
		var port := SubViewport.new()
		port.size = Vector2i(1280, 720)
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# The very World3D the corridor renders from (same scenario, same lights).
		port.world_3d = root.find_world_3d()
		root.add_child(port)
		var eye := Camera3D.new()
		eye.environment = settings
		eye.cull_mask = {"shot": LAYER_SHOT, "boss": LAYER_BOSS, "head": LAYER_HEAD, "marks": LAYER_MARKS}[key]
		eye.fov = source.fov
		eye.near = source.near
		eye.far = source.far
		port.add_child(eye)
		eye.global_transform = source.global_transform
		eye.current = true
		iso[key] = port

func iso_image(key: String) -> Image:
	var image := (iso[key] as SubViewport).get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

static func classify(c: Color, floor_value := 0.12) -> int:
	if maxf(c.r, maxf(c.g, c.b)) < floor_value: return Tone.UNLIT
	if c.s < 0.25: return Tone.NEUTRAL
	var h := c.h
	if h <= 0.04 or h >= 0.94: return Tone.DANGER
	if h <= 0.11: return Tone.ORANGE
	if h >= 0.33 and h <= 0.5: return Tone.GREEN
	if h >= 0.62 and h <= 0.8: return Tone.LILAC
	return Tone.OTHER

## Pixel counts per Tone inside `rect`, and the bounding box of its lit pixels.
static func census(image: Image, rect: Rect2i, floor_value := 0.12) -> Dictionary:
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var low := Vector2i(100000, 100000)
	var high := Vector2i(-1, -1)
	var data := image.get_data()
	var width := image.get_width()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := (y * width + x) * 4
			var tone := classify(Color8(data[i], data[i + 1], data[i + 2]), floor_value)
			counts[tone] += 1
			if tone != Tone.UNLIT:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	var box := Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i()
	return {"counts": counts, "box": box}

## HUD panels and overlays render offscreen (as the menu captures do); the post-FX pass stays, so
## the frame looks as it does in play.
func route_panels() -> void:
	var offscreen := SubViewport.new()
	offscreen.size = Vector2i(8, 8)
	offscreen.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(offscreen)
	iso["offscreen"] = offscreen
	for layer: CanvasLayer in game.find_children("*", "CanvasLayer", true, false):
		if layer.name != "PostFX": layer.custom_viewport = offscreen
