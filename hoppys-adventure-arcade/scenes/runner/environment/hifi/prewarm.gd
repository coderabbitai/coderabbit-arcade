extends RefCounted
## CPU/resource cache warmup only. Instance-owned animated materials stay private.
## Keep scripts alive with their static caches across menu/game transitions.
const ImageJob = preload("res://scenes/runner/environment/hifi/image_warm_job.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const BASE := "res://scenes/runner/"
static var _scripts: Dictionary = {}
static var _census: Dictionary = {}
static var timings: Dictionary = {}
static var jobs: Array = []
static var deferred: Array[Callable] = []
static var async_timings: Dictionary = {}
static var finalized_on_main := true
static var generated_on_workers := true
static var runs := 0
static var elapsed_ms := 0.0

static func warm() -> Dictionary:
	if runs > 0: return _census
	var started := Time.get_ticks_usec()
	_record("environment", "shaders/glyph_atlas.gd", "texture")
	_record("wall_atlas", "environment/hifi/wall_atlas.gd", "texture")
	_record("environment", "environment/runner_materials.gd", "font")
	# Finite shared material variants used by player, corridor, turns and hazards.
	for color in [Palette.SLATE, Palette.CREAM, Color.WHITE]:
		_record("materials", "environment/runner_materials.gd", "lit", [color])
	_record("materials", "environment/runner_materials.gd", "glow", [Palette.CREAM])
	_record("materials", "environment/runner_materials.gd", "glow", [Color.WHITE, 1.5])
	for args in [[Palette.MINT, 0.18], [Palette.MINT, 0.15], [Palette.ORANGE, 0.85], [Palette.DANGER, 0.35], [Palette.MATRIX, 0.25], [Palette.DANGER, 0.55]]:
		_record("materials", "environment/runner_materials.gd", "additive", args)
	_record("hazards", "hazards/visuals/hifi/texture_forge.gd", "maps")
	_record("hazards", "hazards/visuals/hifi/texture_forge.gd", "marker_border")
	# Includes all projectile shapes and trails, not just the first spawn variant.
	for method in ["bevel_box", "ring", "sphere", "quad", "cylinder", "carapace", "limb", "wing", "wedge", "shard", "crescent", "trail", "wave_arc", "jointed_leg", "plasma_sphere", "shard_glint"]:
		_record("hazard_meshes", "hazards/visuals/hifi/mesh_forge.gd", method)
	_record("pickups", "powerups/visuals/hifi/texture_forge.gd", "maps")
	# All six power-ups and four tools use these same three templates.
	for variant in ["opaque", "glass", "pool"]:
		_record("pickup_templates", "powerups/visuals/hifi/pickup_materials.gd", "template", [variant])
	_record("ui", "ui/hud_style.gd", "theme")
	var synth := _script("audio/sfx_synth.gd")
	if synth != null:
		# First-use gameplay sounds and turn/intro cues are ready before bind.
		for kind in synth.get("RECIPES"):
			if synth.get("PERCUSSIVE").has(kind) or kind in [&"turn_warning", &"turn_whoosh", &"boss_intro", &"jump", &"projectile_whoosh"]:
				_record("audio", "audio/sfx_synth.gd", "sound", [kind])
			else:
				deferred.append(_record.bind("audio", "audio/sfx_synth.gd", "sound", [kind]))
		for surface in 3:
			for strike in 2:
				_record("footsteps", "audio/sfx_synth.gd", "footstep", [surface, strike])
		for kind in [&"projectile_whoosh", &"turn_whoosh"]:
			for mask in 8:
				_record("whooshes", "audio/sfx_synth.gd", "panned_whoosh", [mask, kind])
	# Queue CPU-only images after urgent work, avoiding contention during warm().
	for method in ["maps", "floor_maps"]:
		var environment := _script("environment/hifi/texture_forge.gd")
		environment.call("prepare_async", method)
		_queue_images("environment", "environment/hifi/texture_forge.gd", method)
	_queue_images("boss", "boss/hifi/forge.gd", "textures")
	_queue_images("pursuer", "pursuer/hifi/forge.gd", "maps")
	deferred.append(_record.bind("boss", "boss/hifi/forge.gd", "glyph_atlas"))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		if not tree.process_frame.is_connected(poll): tree.process_frame.connect(poll)
		if not tree.root.tree_exiting.is_connected(shutdown): tree.root.tree_exiting.connect(shutdown)
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
	runs += 1
	return _census

static func _script(path: String) -> Script:
	if _scripts.has(path): return _scripts[path]
	if not ResourceLoader.exists(BASE + path): return null
	var script := load(BASE + path) as Script
	if script != null: _scripts[path] = script
	return script

static func _record(package: String, path: String, method: String, args: Array = []) -> void:
	var started := Time.get_ticks_usec()
	var script := _script(path)
	if script == null or not script.has_method(method): return
	var value: Variant = script.callv(method, args)
	timings[package] = float(timings.get(package, 0.0)) + (Time.get_ticks_usec() - started) / 1000.0
	if value == null: return
	if not _census.has(package): _census[package] = {}
	_census[package][method + str(args)] = value
	if package == "boss_fx": _census["boss_meshes"] = script.get("meshes").duplicate()

static func _queue_images(package: String, path: String, method: String, args: Array = []) -> void:
	var script := _script(path)
	var job := ImageJob.new()
	job.package = package
	job.key = method + str(args)
	job.generator = Callable(script, "generate_" + method).bindv(args)
	if package == "environment":
		# bind() appends arguments; a closure keeps install's method argument first.
		job.finalizer = func(images: Variant) -> Variant: return script.call("install_async", method, images)
	else:
		job.finalizer = Callable(script, "finish_" + method)
	job.task_id = WorkerThreadPool.add_task(job.generate, false, "Runner " + package + " " + method)
	jobs.append(job)

static func is_complete() -> bool:
	return runs > 0 and jobs.is_empty() and deferred.is_empty()

## At most one image package upload or deferred package per frame, always on main.
static func poll() -> void:
	assert(Thread.is_main_thread())
	for job in jobs:
		if not WorkerThreadPool.is_task_completed(job.task_id): continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		generated_on_workers = generated_on_workers and job.worker_thread
		finalized_on_main = finalized_on_main and Thread.is_main_thread()
		var started := Time.get_ticks_usec()
		var value: Variant = job.finalizer.call(job.result)
		if not _census.has(job.package): _census[job.package] = {}
		_census[job.package][job.key] = value
		async_timings[job.package + "/" + job.key] = {"image_ms": job.cpu_ms, "finalize_ms": (Time.get_ticks_usec() - started) / 1000.0}
		if job.package == "boss":
			for kind in ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]:
				deferred.append(_boss_art.bind(kind))
			deferred.append(_record.bind("boss_fx", "boss/hifi/forge.gd", "bevel_box", [Vector3(0.045, 0.045, 1.0)]))
			deferred.append(_record.bind("boss_fx", "boss/hifi/forge.gd", "bevel_box", [Vector3(0.13, 0.13, 0.17)]))
		jobs.erase(job)
		return
	if not deferred.is_empty():
		var work: Callable = deferred.pop_front()
		work.call()
	if is_complete():
		_census["boss_meshes"] = _script("boss/hifi/forge.gd").get("meshes").duplicate()
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(poll): tree.process_frame.disconnect(poll)

static func _boss_art(kind: String) -> void:
	var started := Time.get_ticks_usec()
	var art: Node = _script("boss/boss_art.gd").new()
	art.call("build", StringName(kind))
	art.free()
	_census["boss_meshes"] = _script("boss/hifi/forge.gd").get("meshes").duplicate()
	timings["boss_meshes"] = float(timings.get("boss_meshes", 0.0)) + (Time.get_ticks_usec() - started) / 1000.0

## Join outstanding tasks on application exit, even if no further frames run.
static func shutdown() -> void:
	for job in jobs: WorkerThreadPool.wait_for_task_completion(job.task_id)
	jobs.clear()
	deferred.clear()

## Terminal fixture teardown only, after all scene users have been freed.
## Runtime menu/retry transitions must retain the shared cache.
static func release_fixture_cache(tree: SceneTree) -> void:
	shutdown()
	if tree.process_frame.is_connected(poll): tree.process_frame.disconnect(poll)
	_census.clear()
	_scripts.clear()
	timings.clear()
	async_timings.clear()
	runs = 0
