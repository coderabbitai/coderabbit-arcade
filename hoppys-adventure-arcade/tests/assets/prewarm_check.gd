extends SceneTree
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
const BossForge = preload("res://scenes/runner/boss/hifi/forge.gd")
const EnvironmentForge = preload("res://scenes/runner/environment/hifi/texture_forge.gd")
const Audio = preload("res://scenes/runner/audio/runner_audio.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const Pickups = preload("res://scenes/runner/powerups/visuals/power_up_art.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PREWARM: " + message)

func identities(value: Variant) -> Array:
	var result: Array = []
	if value is Object:
		result.append(value.get_instance_id())
	elif value is Dictionary:
		for key in value: result.append_array(identities(value[key]))
	elif value is Array:
		for item in value: result.append_array(identities(item))
	return result

func cache_ids() -> Array:
	var result: Array = []
	for entry in [
		["player/hifi/forge.gd", "cache"],
		["environment/hifi/texture_forge.gd", "cache", "floor_cache"],
		["environment/runner_materials.gd", "_materials", "_fonts"],
		["shaders/glyph_atlas.gd", "_texture"],
		["hazards/visuals/hifi/texture_forge.gd", "_cache", "_border"],
		["hazards/visuals/hifi/mesh_forge.gd", "_cache"],
		["powerups/visuals/hifi/texture_forge.gd", "cache"],
		["powerups/visuals/hifi/pickup_materials.gd", "cache"],
		["boss/hifi/forge.gd", "maps", "atlas", "meshes"],
		["pursuer/hifi/forge.gd", "cache"],
		["ui/hud_style.gd", "_theme"],
		["audio/sfx_synth.gd", "_cache"],
	]:
		var script := load(Prewarm.BASE + entry[0])
		for field in entry.slice(1):
			var ids := identities(script.get(field))
			check(not ids.is_empty(), "%s.%s populated" % [entry[0], field])
			result.append_array(ids)
	return result

func run() -> void:
	# Let autoload audio finish startup before stopping its unrelated default music.
	await process_frame
	await Cleanup.release(self, [])
	check(Prewarm.runs == 0, "fresh process starts cold")
	var corridor := Corridor.instantiate()
	var corridor_started := Time.get_ticks_usec()
	root.add_child(corridor)
	print("PREWARM cold corridor ready(): %.3f ms" % ((Time.get_ticks_usec() - corridor_started) / 1000.0))
	check(Prewarm.runs == 1, "corridor ready called warm synchronously")
	check(corridor.get_script().get("_warmed"), "corridor guard is set")
	check(Prewarm.elapsed_ms > 0.0, "cold warm measured")
	print("PREWARM cold warm(): %.3f ms" % Prewarm.elapsed_ms)
	check(Prewarm.elapsed_ms < 1000.0, "synchronous cold warm under 1000 ms")
	var sync_timings := Prewarm.timings.duplicate()
	for package in sync_timings:
		print("PREWARM sync %s: %.3f ms" % [package, Prewarm.timings[package]])
	check(not Prewarm.is_complete(), "heavy packages remain asynchronous")
	check((Audio as Script).source_code.contains("Prewarm.warm()"), "audio bind relies on shared prewarm")
	for kind in [&"boss_intro", &"turn_warning", &"turn_whoosh"]:
		check(Synth._cache.has(kind), "critical cue warm before gameplay: " + kind)
	for kind in Synth.PERCUSSIVE:
		check(Synth._cache.has(kind), "percussive ready: " + kind)
	for kind in [&"projectile_whoosh", &"turn_whoosh"]:
		for mask in 8:
			check(Synth._cache.has(StringName("%s_pan_%d" % [kind, mask])), "panned cue ready")
	var queued_jobs := Prewarm.jobs.duplicate()
	var environment_ids := identities(EnvironmentForge.cache)
	var floor_ids := identities(EnvironmentForge.floor_cache)
	# Force a boss ahead of the worker finalizer, exercising the real lazy fallback.
	var fallback := BossForge.textures()
	var fallback_ids := identities(fallback)
	var fallback_pixels: PackedByteArray = fallback.albedo.get_image().get_data()
	var repeat_started := Time.get_ticks_usec()
	Prewarm.warm()
	print("PREWARM pending repeat warm(): %.3f ms" % ((Time.get_ticks_usec() - repeat_started) / 1000.0))
	var deadline := Time.get_ticks_msec() + 15000
	while not Prewarm.is_complete() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(Prewarm.is_complete(), "worker images and deferred packages completed")
	check(Prewarm.generated_on_workers, "image generation ran on workers")
	check(Prewarm.finalized_on_main, "ImageTexture finalization ran on main")
	check(identities(BossForge.maps) == fallback_ids, "early boss fallback cache survives worker completion")
	check(BossForge.maps.albedo.get_image().get_data() == fallback_pixels, "worker completion preserves fallback pixels")
	check(identities(EnvironmentForge.cache) == environment_ids, "environment bindings retain texture identities")
	check(identities(EnvironmentForge.floor_cache) == floor_ids, "floor bindings retain texture identities")
	check(EnvironmentForge.cache.normal_map.get_width() == 1024, "environment placeholder replaced by full image")
	check(EnvironmentForge.floor_cache.normal_map.get_width() == 512, "floor placeholder replaced by full image")
	check(EnvironmentForge.pending.is_empty(), "no unfinished environment maps")
	for job in queued_jobs:
		if job.package != "environment": continue
		for key in job.result:
			var generated: Image = job.result[key]
			check(generated.has_mipmaps(), "worker output has mipmaps: " + key)
			check(generated.get_width() > 1, "worker output contains full image: " + key)
	print("PREWARM GPU replacement: NOT VERIFIED (headless dummy retains initial pixel snapshot)")
	for package in Prewarm.async_timings:
		var timing: Dictionary = Prewarm.async_timings[package]
		print("PREWARM async %s: image=%.3f ms finalize=%.3f ms" % [package, timing.image_ms, timing.finalize_ms])
	for package in Prewarm.timings:
		var deferred_ms := float(Prewarm.timings[package]) - float(sync_timings.get(package, 0.0))
		if deferred_ms > 0.0: print("PREWARM deferred main %s: %.3f ms" % [package, deferred_ms])
	var census: Dictionary = Prewarm._census
	var expected := {"player": 6, "environment": 9, "materials": 11, "hazards": 4,
		"hazard_meshes": 16, "pickups": 4, "pickup_templates": 3,
		"boss": 4, "boss_meshes": 42, "boss_fx": 2, "pursuer": 3,
		"ui": 1, "audio": 32, "footsteps": 6, "whooshes": 16}
	for package in expected:
		check(census.has(package), package + " present in census")
		var count := identities(census.get(package, {})).size()
		check(count >= expected[package], "%s census populated (%d)" % [package, count])
		print("PREWARM census %s: %d resources" % [package, count])
	var before := cache_ids()
	var census_ids := identities(census)
	var started := Time.get_ticks_usec()
	var second := Prewarm.warm()
	print("PREWARM repeat warm(): %.3f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(is_same(census, second), "same census dictionary")
	check(identities(second) == census_ids, "same census resource identities")
	check(cache_ids() == before, "second warm preserves actual cache identities")
	# All ten authored kinds consume the warmed maps/templates without adding keys.
	for kind in Pickups.TAGS:
		var art := Pickups.new()
		art.build(kind)
		check(cache_ids() == before, "pickup %s reuses caches" % kind)
		art.free()
	corridor.free()
	var retry := Corridor.instantiate()
	root.add_child(retry)
	check(Prewarm.runs == 1, "retry does not rebuild")
	check(cache_ids() == before, "retry preserves cache identities")
	await Cleanup.release(self, [retry])
	if failures == 0: print("PREWARM: PASS (%d checks)" % checks)
	else: print("PREWARM: FAIL (%d failures / %d checks)" % [failures, checks])
	quit(0 if failures == 0 else 2)
