extends SceneTree
## Host-only: nine boss views plus an effects plate. No gameplay dependency.
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

func spawn_shot(scene: PackedScene, shot: Dictionary, age: float, boss_kind: String, signature: StringName) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(BossAttacks.x_at(shot, age), BossAttacks.y_offset_at(shot, age), BossAttacks.z_at(shot, age))
	world.add_child(holder)
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
	Art.Forge.clear_cache()
	ProjectileArt.release_caches()
	# Stop the autoload MP3 playback before the audio thread exits.
	root.get_node("AudioService").shutdown()
	await create_timer(0.25).timeout
	quit(code)
