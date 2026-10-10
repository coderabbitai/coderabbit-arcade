extends SceneTree
const Scene = preload("res://scenes/runner/pursuer/pursuer_visual.tscn")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
## The hunter rig's bounds. The quarantine field is a separate world-space effect dropped around
## Hoppy during a catch, so it is not part of the hunter's envelope.
func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh == node.get("_field"): continue
		var box: AABB = node.global_transform.affine_inverse()*mesh.global_transform*mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
func run() -> void:
	var visual := Scene.instantiate()
	root.add_child(visual)
	visual.set_process(false)
	check(visual.find_children("*","CollisionObject3D",true,false).is_empty(),"Cosmetic rig never adds hitboxes")
	check(not visual.has_node("Wall") and visual.find_children("*","Label3D",true,false).is_empty(),"Hunter is not a panel wall or text grid")
	check(visual._arms.size() == 2 and visual._ears.size() == 2 and visual._fans.size() == 2,"Two articulated claws, receivers and lift rotors")
	var draws := 0
	var triangles := 0
	for mesh: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		draws += mesh.mesh.get_surface_count()
		for i in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(i)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
		check(mesh.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and mesh.process_mode == Node.PROCESS_MODE_PAUSABLE,"Pausable cosmetic " + str(mesh.name))
	check(draws <= 14 and triangles <= 20000,"Shipping performance caps")
	visual.set_threat(-1)
	check(not visual.visible,"Zero threat hides")
	visual.set_threat(1.5)
	var envelope := AABB()
	for i in 180:
		visual._process(1.0/60)
		var box := bounds(visual)
		envelope = box if i == 0 else envelope.merge(box)
		check(box.size.x <= 2.5 and box.size.y <= 2.6 and box.position.y >= 0,"Compact single-lane hunter envelope")
	var rotor: Vector3 = visual._fans[0].rotation
	visual._process(0.1)
	check(not visual._fans[0].rotation.is_equal_approx(rotor),"Visible propulsion rotates")
	var count := visual.find_children("*","",true,false).size()
	var start_z: float = visual._wall.global_position.z
	visual.play_catch()
	visual._process(visual.CLAMP_AT)
	check(absf(visual._arms[0].rotation.x) > 0.3,"Capture clamps the claws at CLAMP_AT")
	check(visual._field.visible,"Quarantine field drops once the claws shut")
	visual.play_catch()
	check(is_equal_approx(visual._reaction_time,visual.CLAMP_AT),"Catch idempotent")
	visual._process(1.0)
	var held: Transform3D = visual._wall.global_transform
	var unscaled := held.basis.get_scale().is_equal_approx(Vector3.ONE)
	check(unscaled and held.origin.z < start_z - 4.0,"Catch leaps past Hoppy without giant growth")
	visual.set_threat(1)
	check(visual._reaction == &"catch","Catch holds while the threat stays at 1")
	visual.set_threat(0)
	check(visual._reaction == &"idle" and not visual._field.visible,
		"Run reset ends the catch and lifts the field")
	visual.set_threat(1)
	var pose: Transform3D = visual._wall.transform
	visual.set_threat(0)
	visual.play_retreat()
	check(visual._wall.transform.is_equal_approx(pose),"Retreat starts at last pursuit pose")
	visual._process(0.35)
	visual.play_retreat()
	check(is_equal_approx(visual._reaction_time,0.35),"Retreat idempotent")
	visual._process(0.35)
	check(not visual.visible and visual._light.light_energy == 0,"Retreat ends at 0.7s")
	visual.set_threat(0.7)
	check(visual.visible and count == visual.find_children("*","",true,false).size(),"Reuse without allocations")
	visual.set_process(true)
	paused = true
	var clock: float = visual._t
	await process_frame
	await process_frame
	check(visual._t == clock,"Pause freezes animation")
	paused = false
	print("A6 HUNTER CENSUS: %d draws, %d triangles, no textures" % [draws,triangles])
	print("A6 HUNTER ENVELOPE: ",envelope)
	visual.free()
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("ASSET A6: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
