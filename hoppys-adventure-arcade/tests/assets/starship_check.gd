extends SceneTree
const Scene = preload("res://scenes/runner/environment/corridor.tscn")
const Assets = preload("res://scenes/runner/environment/starship/starship_assets.gd")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STARSHIP FAIL: ", message)

func visit(node: Node) -> void:
	check(not node is CollisionObject3D, "asset must not add gameplay collision")
	for child in node.get_children(): visit(child)

func run() -> void:
	var original_scale := root.scaling_3d_scale
	var corridor := Scene.instantiate()
	root.add_child(corridor)
	while not Prewarm.is_complete(): await process_frame
	corridor.set_process(false)
	visit(corridor.starship)
	var triangles := 0
	var extra_triangles := 0
	for mesh in Assets.module_meshes():
		check(mesh.get_surface_count() == 1, "one surface per batch")
		triangles += mesh.surface_get_array_len(0) / 3 * 8
		var lane_clear := true
		for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if absf(vertex.x) < 3.1 and vertex.y < 3.0: lane_clear = false
		check(lane_clear, "architectural dressing stays outside playable lane clearance")
	for node in [corridor.starship.get_node("ArmouredDeck"), corridor.starship.get_node("FarBulkhead"), corridor.starship.get_node("EntryBulkhead"), corridor.starship.get_node("EntryBulkhead/EntryDoorGlow")] + corridor.starship.reactor_dock.get_children():
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		extra_triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	check(triangles + extra_triangles < 60000, "whole starship including boss dock stays within 60k triangles")
	check(triangles < 60000, "starship module geometry stays within 60k triangles")
	check(corridor.starship.batches.size() == 6, "bounded material batches")
	for i in 8:
		var z: float = corridor.starship.batches[0].get_instance_transform(i).origin.z
		check(z <= 12 and z > -84, "recycle bounds")
	corridor.set_scroll_speed(32)
	corridor._process(3.0)
	check(is_zero_approx(corridor._offset), "maximum-speed 96m wrap has no drift")
	check(corridor.rotation == Vector3.ZERO, "the corridor stays square")
	var bulkhead: MeshInstance3D = corridor.starship.get_node("EntryBulkhead")
	var hull: ShaderMaterial = bulkhead.material_override
	var glow := bulkhead.get_node_or_null("EntryDoorGlow") as MeshInstance3D
	check(glow != null, "entry door has its glow child")
	check(is_zero_approx(bulkhead.extra_cull_margin),
		"entry bulkhead cull margin is 0, got %.2f" % bulkhead.extra_cull_margin)
	check(glow != null and is_zero_approx(glow.extra_cull_margin),
		"entry door glow cull margin is 0, got %.2f" % (glow.extra_cull_margin if glow != null else -1.0))
	if glow != null:
		var box: AABB = bulkhead.global_transform * bulkhead.get_aabb()
		check(box.position.z > 8.0 and box.end.z > 8.0,
			"entry bulkhead sits behind the gameplay camera at z 8 (z %.2f..%.2f)" % [box.position.z, box.end.z])
	check(is_equal_approx(float(hull.get_shader_parameter("metallic")), 0.68)
		and not bool(hull.get_shader_parameter("window_mode"))
		and is_zero_approx(float(hull.get_shader_parameter("glow")))
		and not hull.shader.code.contains("blend_"),
		"entry bulkhead is opaque hull")
	var beyond := false
	var sleeve := false
	var z_min := 1000.0
	var z_max := -1000.0
	for vertex in bulkhead.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		z_min = minf(z_min, vertex.z)
		z_max = maxf(z_max, vertex.z)
		beyond = beyond or vertex.z > 24.0
		sleeve = sleeve or (vertex.z < 24.0 and vertex.z >= 11.0)
	check(beyond and z_max > 24.0, "entry door sits beyond z +24 (max %.2f)" % z_max)
	check(sleeve and z_min > 10.0 and z_min < 12.5, "entry sleeve reaches back over the near modules (min %.2f)" % z_min)
	for material in corridor.starship.materials:
		var bend_value: Variant = material.get_shader_parameter("bend")
		# An unset uniform keeps the shader default, which is square.
		check(bend_value == null or is_zero_approx(float(bend_value)), "starship surfaces stay unbent")
	corridor.set_boss_arena(true)
	corridor._process(2.0)
	check(corridor.starship.reactor_dock.visible, "boss reactor_dock appears")
	check(is_equal_approx(corridor.starship.reactor_dock.position.z,-26), "reactor_dock remains behind boss gameplay volume")
	corridor.set_boss_arena(false)
	corridor._process(2.0)
	check(not corridor.starship.reactor_dock.visible, "reactor_dock resets after encounter")
	corridor.set_process(true)
	paused = true
	var before: float = corridor._clock
	for i in 5: await process_frame
	check(is_equal_approx(before,corridor._clock), "pause freezes asset animation")
	paused = false
	var second := Scene.instantiate()
	root.add_child(second)
	check(second.starship.materials[0] != corridor.starship.materials[0], "instance materials are private")
	check(second.starship.batches[0].mesh == corridor.starship.batches[0].mesh, "immutable geometry is cached")
	corridor.free()
	check(is_equal_approx(root.scaling_3d_scale,0.85), "newest viewport owner retains quality scale")
	await Cleanup.release(self,[second])
	check(is_equal_approx(root.scaling_3d_scale,original_scale), "viewport quality restores after exit")
	print("STARSHIP TOTAL: %d triangles including deck, far bulkhead, entry bulkhead and reactor dock" % (triangles + extra_triangles))
	print("STARSHIP GEOMETRY: repeated modules=%d triangles; 6 batches; 1 shared 256x256 texture" % triangles)
	print("STARSHIP CHECK: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(0 if failures == 0 else 1)
