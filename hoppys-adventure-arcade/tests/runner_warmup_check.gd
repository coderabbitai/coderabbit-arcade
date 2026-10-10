extends SceneTree
## W3 warm-up check (headless). A directly launched runner_game.tscn must finish every prewarm job
## inside its own _ready (bind), so no package is finalized during play and every cue, including
## the pickup SFX, is cached before the first pickup can spawn. The GPU warm-up stage must mount
## every runtime visual batch cleanly and leave nothing behind. Headless cannot compile shaders, so
## the forced draws themselves are measured by tests/runner_pickup_hitch.gd (rendered).
## Coverage census: every draw state (geometry type + shader or BaseMaterial3D feature set, label
## setup, canvas shader) the warm-up stage and the scene it warms show, against every draw state a
## scripted run shows: an autopiloted stage into the stage-1 fight, then all three bosses through
## all phases on the live BossEncounter. Anything a run draws that the warm-up never drew would
## compile on a gameplay frame. Lit variants (Hoppy / 9 m / 55 m) need the rendered check.
## Run with --path <project> --script res://tests/runner_warmup_check.gd.
## Scripts are loaded at run time: under --script this is compiled before the autoloads exist.
const GAME_PATH := "res://scenes/runner/runner_game.tscn"
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const HAZARD_DIR := "res://scenes/runner/hazards/visuals/"
## Scripted run: runner_smoke's speed-up (360 ticks at time_scale 6 keeps a real 1/60 s tick).
const TIME_SCALE := 6.0
const PHYSICS_TICKS := 360
const STAGE_DISTANCE := 120.0
const RUN_WALL_TIMEOUT := 30.0
## Game seconds each boss phase is fought on the live encounter.
const PHASE_SECONDS := 5.0
var checks := 0
var failures := 0
var _fingerprints := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RUNNER WARMUP: " + message)

func run() -> void:
	await process_frame
	var Prewarm: Script = load("res://scenes/runner/environment/hifi/prewarm.gd")
	var Synth: Script = load("res://scenes/runner/audio/sfx_synth.gd")
	var GpuWarmup: Script = load("res://scenes/runner/warmup/gpu_warmup.gd")
	check(Prewarm.get("runs") == 0, "fresh process starts cold")
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	game.autostart = false
	# The shortened stage runner_smoke uses (never the shared .tres), so the scripted run reaches a
	# boss inside the wall clock.
	var config: Resource = (load(CONFIG_PATH) as Resource).duplicate()
	config.set(&"stage_base_distance", STAGE_DISTANCE)
	config.set(&"boss_hp_scale", 0.4)
	game.config = config
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_warmup_check_leaderboard.cfg")
	var started := Time.get_ticks_usec()
	root.add_child(game)
	print("RUNNER WARMUP: direct scene ready %.0f ms (finish %.0f ms)" % [(Time.get_ticks_usec() - started) / 1000.0, Prewarm.get("finish_ms")])
	check(Prewarm.call("is_complete"), "prewarm complete after bind, before the first frame")
	check(not process_frame.is_connected(Callable(Prewarm, "poll")), "poll disconnected once complete")
	check(Prewarm.get("generated_on_workers"), "audio and images generated on workers")
	check(Prewarm.get("finalized_on_main"), "finalized on main")
	var cache: Dictionary = Synth.get("_cache")
	for kind: StringName in Synth.get("RECIPES"):
		check(cache.has(kind), "cue cached before play: " + kind)
	for kind in [&"powerup", &"nitro", &"lgtm", &"auto_fix", &"tool_pickup", &"shield_block"]:
		check(cache.has(kind), "pickup cue cached before play: " + kind)
	for kind in [&"projectile_whoosh", &"turn_whoosh"]:
		for mask in 8:
			check(cache.has(StringName("%s_pan_%d" % [kind, mask])), "panned %s %d cached" % [kind, mask])
	for surface in 3:
		for strike in 2:
			check(cache.has(StringName("footstep_surface_%d_variant_%d" % [surface, strike])), "footstep variant cached")
	# Identity: a later on-demand call returns the stream prewarm installed.
	check(Synth.call("sound", &"lgtm") == cache[&"lgtm"], "installed stream identity kept")
	# Headless: the guard is spent once and the forced draws are skipped.
	check(GpuWarmup.get("done"), "GPU warm-up guard set by the first bind")
	check(not GpuWarmup.call("run", game), "GPU warm-up runs once per process")
	check(game.get_node_or_null("GpuWarmup") == null, "no stage left in the game")
	var warmed := await warm_census(game, GpuWarmup)
	game.start_run(4242)
	var before: int = game.get_child_count()
	# Mount every batch the rendered warm-up draws, tick it, then clear it.
	var camera := Camera3D.new()
	root.add_child(camera)
	var stage: Node3D = GpuWarmup.call("stage_for", game, camera)
	var census: Dictionary = GpuWarmup.get("census")
	census.clear()
	for batch: StringName in GpuWarmup.call("batches"):
		stage.call("build", batch)
		for i in 2: await process_frame
		check(stage.get_child_count() == 2, "batch %s mounted into one group" % batch)
		stage.call("clear")
		check(stage.get_child_count() == 1, "batch %s cleared" % batch)
	check_boss_scenes_retained(GpuWarmup, "after clearing all warm-up batches")
	var expected := {"pickup": 20, "burst": 2, "hazard": 42, "boss": 12, "boss_fx": 5, "boss_marks": 1,
		"boss_projectile": 8, "projectile_swatch": 13, "pursuer": 2, "hoppy": 8, "canvas": 1}
	for category in expected:
		check(int(census.get(category, 0)) >= expected[category], "%s mounted (%d)" % [category, census.get(category, 0)])
	print("RUNNER WARMUP census: ", census)
	stage.free()
	camera.free()
	# Collect bursts detach to the scene root by design (they outlive the pickup); nothing else may.
	var extra: Array[String] = []
	for i in range(before, game.get_child_count()):
		if not game.get_child(i) is GPUParticles3D: extra.append(game.get_child(i).name)
	check(extra.is_empty(), "stage leaves the game tree as it found it: %s" % [extra])
	check(game.state == &"running", "run still live after staging")
	var played := await run_census(game)
	var missing: Array[String] = []
	for key: String in played:
		if not warmed.has(key): missing.append("%s (%s)" % [key, played[key]])
	print("RUNNER WARMUP coverage: %d draw states warmed, %d drawn by the scripted run, %d missing" % [warmed.size(), played.size(), missing.size()])
	for line in missing: print("  MISSING ", line)
	check(missing.is_empty(), "every draw state a run shows is warmed (%d missing)" % missing.size())
	game.free()
	var Cleanup: Script = load("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
	await Cleanup.call("release", self, [] as Array[Node])
	GpuWarmup.call("release")
	check((GpuWarmup.get("retained") as Dictionary).is_empty(), "GPU warm-up release drops retained boss scenes and draw materials")
	if failures == 0: print("RUNNER WARMUP: PASS (%d checks)" % checks)
	else: print("RUNNER WARMUP: FAIL (%d failures / %d checks)" % [failures, checks])
	quit(0 if failures == 0 else 2)

func check_boss_scenes_retained(GpuWarmup: Script, context: String) -> void:
	var retained: Dictionary = GpuWarmup.get("retained")
	var BossDefs: Script = load("res://scenes/runner/boss/boss_defs.gd")
	for slot: Dictionary in BossDefs.get("SLOTS"):
		var kind: StringName = slot.get("kind", &"")
		var visual_path := "res://scenes/runner/boss/visuals/%s_visual.tscn" % String(kind)
		var visual_scene := load(visual_path) as PackedScene
		var visual := visual_scene.instantiate()
		var model_path: String = visual.get_script().get_script_constant_map().get("MODEL_PATH", "")
		visual.free()
		var model := load(model_path) as PackedScene if not model_path.is_empty() else null
		check(model != null and retained.has(model), "%s retains imported boss model scene: %s" % [context, model_path])

## The scene at bind time (graybox detached, as run() does), with the live Hoppy dressed and the
## corridor posed mid-turn, plus every batch the stage mounts. Also the explicit C1/C2/C4 checks.
func warm_census(game: Node, GpuWarmup: Script) -> Dictionary:
	var warmed := {}
	GpuWarmup.call("_drop_doomed", game)
	collect(game, warmed)
	var hoppy: Node3D = GpuWarmup.call("_hoppy", game)
	var corridor: Node = GpuWarmup.call("_corridor", game)
	check(hoppy != null and corridor != null, "census finds the live Hoppy and corridor")
	var camera := Camera3D.new()
	root.add_child(camera)
	var stage: Node3D = GpuWarmup.call("stage_for", game, camera, hoppy.global_position)
	var looks := {}
	var clips := {}
	var props := {}
	var pickup_props := {}
	var led_lit := false
	var marks_lit := false
	var prop_shader: Shader = load("res://scenes/runner/hazards/visuals/hifi/prop.gdshader")
	var pickup_prop_shader: Shader = (load("res://scenes/runner/powerups/visuals/hifi/pickup_materials.gd") as Script).call("template", "prop").shader
	var ProjectileArt: Script = load("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
	var HazardDefs: Script = load("res://scenes/runner/hazards/hazard_defs.gd")
	var started := Time.get_ticks_usec()
	for batch: StringName in GpuWarmup.call("batches"):
		stage.call("build", batch)
		if batch == &"characters": GpuWarmup.call("_dress", hoppy, true)
		if batch == &"canvas": GpuWarmup.call("show_turn", game, corridor, true)
		collect(game, warmed)
		for node in stage.find_children("*", "", true, false):
			if node.get_script() == ProjectileArt: looks[node.get(&"look")] = true
			if node is GeometryInstance3D and node.material_override is ShaderMaterial:
				var shader: Shader = node.material_override.shader
				if shader == prop_shader: props[batch] = true
				if shader == pickup_prop_shader:
					var visual: Node = node
					while visual != null and not &"kind" in visual: visual = visual.get_parent()
					if visual != null: pickup_props[visual.get(&"kind")] = true
			if node.has_method(&"set_anim_state") and &"anim_state" in node:
				clips[node.get(&"anim_state")] = true
				for material: ShaderMaterial in node.get(&"_led_materials"):
					var level: Variant = material.get_shader_parameter("led_level")
					led_lit = led_lit or (level != null and float(level) > 0.0)
			if node.name == &"SignatureMarks" and node.is_visible_in_tree() and int(node.get(&"used")) > 0: marks_lit = true
		if batch == &"characters": GpuWarmup.call("_dress", hoppy, false)
		if batch == &"canvas": GpuWarmup.call("show_turn", game, corridor, false)
		stage.call("clear")
	print("RUNNER WARMUP: stage build of every batch %.0f ms (headless)" % ((Time.get_ticks_usec() - started) / 1000.0))
	stage.free()
	camera.free()
	# C4: every boss projectile look and every shared projectile material; the accent layer.
	for look: StringName in ProjectileArt.get("LOOKS"):
		check(looks.has(look), "warm-up mounts boss projectile look " + look)
	for key: String in ProjectileArt.get("MATERIAL_KEYS"):
		var print_key := fingerprint(ProjectileArt.call("material", key))
		check(warmed.keys().any(func(k: String) -> bool: return k.ends_with("|" + print_key)), "warm-up draws projectile material " + key)
	check(marks_lit, "warm-up lights BossFX SignatureMarks")
	# C1: every new clip, and the LED meter.
	var GpuScript: Script = GpuWarmup
	for clip: StringName in GpuScript.get("HOPPY_CLIPS"):
		check(clips.has(clip), "warm-up poses Hoppy clip " + clip)
	check(led_lit, "warm-up lights the cape LED meter")
	# C2: the prop shader on every hazard kind, the baked pickup prop on every pickup kind.
	for kind: StringName in HazardDefs.call("kinds"):
		if kind != &"projectile": check(props.has(kind), "warm-up draws the hazard prop shader for " + kind)
	for kind: StringName in (load("res://scenes/runner/powerups/power_up_defs.gd") as Script).call("kinds") + (load("res://scenes/runner/powerups/tool_defs.gd") as Script).call("kinds"):
		check(pickup_props.has(kind), "warm-up draws the pickup prop template for " + kind)
	return warmed

## Draw states of an autopiloted run into the stage-1 fight, then of every boss through every phase
## on the live encounter (invulnerable, so the run survives), sampled every few frames.
func run_census(game: Node) -> Dictionary:
	var played := {}
	var restore := [Engine.time_scale, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame]
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 32
	Engine.physics_ticks_per_second = PHYSICS_TICKS
	var fired := [0]
	var count_shot := func(_projectile: Area3D, _mask: int, _kind: StringName, _speed: float) -> void: fired[0] += 1
	game.boss_projectile_fired.connect(count_shot)
	game.set_autopilot(true)
	if game.autopilot != null and game.autopilot.has_method("set_mode"): game.autopilot.set_mode(2)
	var started := Time.get_ticks_msec()
	var frame := 0
	while fired[0] < 6 and game.state == &"running" and Time.get_ticks_msec() - started < RUN_WALL_TIMEOUT * 1000.0:
		await process_frame
		frame += 1
		if frame % 6 == 0: collect(game, played)
	check(fired[0] >= 6, "scripted run reached the stage-1 boss fight (%d shots, phase %s)" % [fired[0], game.phase])
	# Every boss, every phase, on the real encounter: its own mounts, attacks, projectiles and FX.
	var encounter: Node = game.boss_encounter
	game.hit_manager.invuln_sources[&"warmup_census"] = true
	for index in [1, 2, 3]:
		encounter.abort()
		encounter.start(index)
		for phase in [1, 2, 3]:
			encounter.phase = phase
			if is_instance_valid(encounter.visual) and encounter.visual.has_method(&"set_phase"): encounter.visual.set_phase(phase)
			var ticks := int(PHASE_SECONDS * 60.0)
			for tick in ticks:
				await physics_frame
				# The stage manager ticks the encounter itself during the boss phase.
				if game.phase != &"boss": encounter.tick(1.0 / 60.0)
				if tick % 20 == 0: collect(game, played)
		print("RUNNER WARMUP census fight: %s" % encounter.kind)
	encounter.abort()
	game.hit_manager.invuln_sources.erase(&"warmup_census")
	game.boss_projectile_fired.disconnect(count_shot)
	game.set_autopilot(false)
	Engine.time_scale = restore[0]
	Engine.physics_ticks_per_second = restore[1]
	Engine.max_physics_steps_per_frame = restore[2]
	return played

## Every visible draw state under `root`: geometry type (mesh, skinned mesh, multimesh with its
## per-instance flags, particles, label setup) with the material's shader or feature set, and canvas
## shaders. `into` maps each to the first node that showed it.
func collect(node_root: Node, into: Dictionary) -> void:
	for node in node_root.find_children("*", "", true, false):
		if node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			if not geometry.is_visible_in_tree(): continue
			var keys: Array[String] = []
			if geometry is Label3D:
				var label := geometry as Label3D
				keys.append("label|%s" % [[label.font, label.font_size, label.outline_size > 0, label.billboard, label.shaded,
					label.double_sided, label.no_depth_test, label.fixed_size, label.alpha_cut, label.texture_filter,
					label.alpha_antialiasing_mode]])
			elif geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
				var mesh_node := geometry as MeshInstance3D
				for i in mesh_node.mesh.get_surface_count():
					var skinned: bool = mesh_node.mesh is ArrayMesh and (mesh_node.mesh as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_BONES != 0
					keys.append("%s|%s" % ["skinned" if skinned else "mesh", fingerprint(mesh_node.get_active_material(i))])
			elif geometry is MultiMeshInstance3D and (geometry as MultiMeshInstance3D).multimesh != null and geometry.multimesh.mesh != null:
				var multi: MultiMesh = geometry.multimesh
				if multi.visible_instance_count == 0: continue
				for i in multi.mesh.get_surface_count():
					var material: Material = geometry.material_override if geometry.material_override != null else multi.mesh.surface_get_material(i)
					keys.append("multimesh%s%s|%s" % ["+color" if multi.use_colors else "", "+custom" if multi.use_custom_data else "", fingerprint(material)])
			elif geometry is GPUParticles3D:
				var particles := geometry as GPUParticles3D
				keys.append("particles_process|" + fingerprint(particles.process_material))
				for pass_index in particles.draw_passes:
					var pass_mesh := particles.get_draw_pass_mesh(pass_index)
					if pass_mesh == null: continue
					for i in pass_mesh.get_surface_count():
						keys.append("particles|" + fingerprint(geometry.material_override if geometry.material_override != null else pass_mesh.surface_get_material(i)))
			if geometry.material_overlay != null: keys.append("overlay|" + fingerprint(geometry.material_overlay))
			for key in keys:
				if not into.has(key): into[key] = _where(node)
		elif node is CanvasItem and (node as CanvasItem).material != null and (node as CanvasItem).is_visible_in_tree():
			var key := "canvas|" + fingerprint((node as CanvasItem).material)
			if not into.has(key): into[key] = _where(node)

## The node's last three path elements (enough to find it, short enough to read).
func _where(node: Node) -> String:
	var names := str(node.get_path()).split("/")
	return "/".join(names.slice(maxi(names.size() - 3, 0)))

## What decides the compiled program: a ShaderMaterial's shader code, a BaseMaterial3D's (or
## ParticleProcessMaterial's) feature switches and bound texture slots; uniform values do not.
func fingerprint(material: Material) -> String:
	if material == null: return "default"
	var id := material.get_instance_id()
	if _fingerprints.has(id): return _fingerprints[id]
	var parts: PackedStringArray = []
	if material is ShaderMaterial:
		var shader: Shader = (material as ShaderMaterial).shader
		parts.append("shader:%s:%d" % [shader.resource_path.get_file() if shader != null else "none", shader.code.hash() if shader != null else 0])
	else:
		parts.append(material.get_class())
		for property: Dictionary in material.get_property_list():
			if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
			var name: String = property.name
			if name.begins_with("resource_") or name in ["render_priority", "next_pass"]: continue
			var value: Variant = material.get(name)
			match int(property.type):
				TYPE_BOOL: parts.append("%s=%s" % [name, value])
				TYPE_INT:
					if int(property.hint) in [PROPERTY_HINT_ENUM, PROPERTY_HINT_FLAGS]: parts.append("%s=%s" % [name, value])
				TYPE_OBJECT:
					if value is Texture: parts.append(name)
	if material.next_pass != null: parts.append("next(%s)" % fingerprint(material.next_pass))
	var result := ",".join(parts)
	_fingerprints[id] = result
	return result
