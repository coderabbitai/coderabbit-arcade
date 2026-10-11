extends Node3D
const Assets = preload("res://scenes/runner/environment/starship/starship_assets.gd")
var batches: Array[MultiMesh] = []
var materials: Array[ShaderMaterial] = []
var reactor_dock: Node3D
var arena_blend := 0.0
var deck_light: OmniLight3D
## The corridor frame last handed to the surface materials; the corridor never turns, so it is only
## re-uploaded when a fixture moves the node.
var _frame := Transform3D()
var _frame_written := false

func _ready() -> void:
	name = "StarshipWorld"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var meshes := Assets.module_meshes()
	for i in meshes.size():
		var material := Assets.material(i)
		materials.append(material)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = meshes[i]
		batch.instance_count = 8
		batches.append(batch)
		var instance := MultiMeshInstance3D.new()
		instance.name = ["PressureBulkheads","RecessedHull","ServiceMachinery","LightConduits","ObservationWindows","PowerTrunks"][i]
		instance.multimesh = batch
		instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		instance.material_override = material
		instance.extra_cull_margin = 90.0
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	var floor_mat := Assets.material(Assets.HULL)
	floor_mat.set_shader_parameter("floor_mode",true)
	floor_mat.set_shader_parameter("tint",Color("435365"))
	_plane("ArmouredDeck",Vector2(8,108),Vector3(0,-0.018,-40),floor_mat)
	_end_cap()
	_entry_bulkhead()
	# The docking reactor remains behind the existing boss and its telegraphs.
	reactor_dock = Node3D.new()
	reactor_dock.name = "BossReactorDock"
	reactor_dock.position.z = -26
	reactor_dock.visible = false
	add_child(reactor_dock)
	for kind in [Assets.HULL,Assets.ALLOY,Assets.CONDUIT]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if kind == Assets.HULL:
			for step in 4:
				Assets.box(st,Vector3(0,0.1+step*0.24,-step*0.9),Vector3(10-step*0.7,0.3,4.0))
			for side in [-1.0,1.0]:
				Assets.box(st,Vector3(side*4.4,3,-1),Vector3(1.4,6,1.6))
				Assets.box(st,Vector3(side*4.4,6,-1),Vector3(1.9,0.5,2.0))
		else:
			var radius := 3.0 if kind == Assets.ALLOY else 2.7
			for segment in 36:
				Assets.wedge(st,(segment+0.5)*TAU/36.0,radius,3.5,-2.0,0.18 if kind == Assets.ALLOY else 0.06,0.20,TAU/36.0)
		st.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		var material := Assets.material(kind)
		materials.append(material)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		reactor_dock.add_child(mesh)
	deck_light = OmniLight3D.new()
	deck_light.name = "DeckBounce"
	deck_light.position = Vector3(0,3.0,-3.0)
	deck_light.light_color = Color("a8c6d5")
	deck_light.light_energy = 0.55
	deck_light.omni_range = 12
	deck_light.shadow_enabled = false
	add_child(deck_light)
	# Built after the corridor configured its cosmetics: freeze every part with the pause menu.
	for child in find_children("*", "Node", true, false):
		child.process_mode = Node.PROCESS_MODE_PAUSABLE

## Opaque far bulkhead past the last recycled module (modules start between z -84 and -72) and
## beyond the -90 m spawn horizon. A sleeve behind the module walls covers z -92..-71.5, so the
## far end is closed at every scroll offset.
func _end_cap() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Assets.slab(st,Vector3(0,3.6,-92.0),Vector3(12.6,8.4,0.3),0.55)
	Assets.slab(st,Vector3(0,2.8,-91.8),Vector3(4.4,5.2,0.12),0.85)
	Assets.slab(st,Vector3(0,2.8,-91.72),Vector3(0.08,5.2,0.05),0.3)
	Assets.slab(st,Vector3(0,7.45,-81.75),Vector3(12.8,0.3,20.5),0.45)
	for side in [-1.0,1.0]:
		Assets.slab(st,Vector3(side*6.1,3.6,-81.75),Vector3(0.3,8.4,20.5),0.5)
		Assets.slab(st,Vector3(side*5.0,-0.2,-81.75),Vector3(2.2,0.3,20.5),0.45)
	st.generate_tangents()
	var cap := MeshInstance3D.new()
	cap.name = "FarBulkhead"
	cap.mesh = st.commit()
	var material := Assets.material(Assets.HULL)
	materials.append(material)
	cap.material_override = material
	cap.extra_cull_margin = 90.0
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cap)

## The near end, behind Hoppy: a sealed entry door the run intro's reverse shots land on. Modules
## span local z 0..12 and recycle with their origin in (-84, 12], so the near wall edge wanders
## between +12 and +24 and the deck stops at +14. A wall at +24.4 with a sleeve behind the module
## walls over z 11.5..24.5 (ceiling, sides, and the floor past the deck) closes the end at every
## scroll offset. It sits behind the gameplay camera and every boss shot, so normal play never
## draws it; the pursuer (z 4.5..12) always stays in front of it. Two draw calls, static.
func _entry_bulkhead() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Assets.slab(st,Vector3(0,3.6,24.4),Vector3(12.6,8.4,0.3),0.55)
	Assets.slab(st,Vector3(0,2.8,24.2),Vector3(4.4,5.2,0.12),0.85)
	Assets.slab(st,Vector3(0,2.8,24.12),Vector3(0.08,5.2,0.05),0.3)
	Assets.slab(st,Vector3(0,5.55,24.1),Vector3(5.2,0.35,0.3),0.4)
	Assets.slab(st,Vector3(0,7.45,18.0),Vector3(12.8,0.3,13.0),0.45)
	Assets.slab(st,Vector3(0,-0.2,19.25),Vector3(12.6,0.3,10.5),0.5)
	for side in [-1.0,1.0]:
		Assets.slab(st,Vector3(side*2.45,2.8,24.1),Vector3(0.3,5.6,0.3),0.4)
		Assets.slab(st,Vector3(side*6.1,3.6,18.0),Vector3(0.3,8.4,13.0),0.5)
		Assets.slab(st,Vector3(side*4.3,1.2,24.2),Vector3(2.6,0.24,0.1),0.7)
	st.generate_tangents()
	var door := MeshInstance3D.new()
	door.name = "EntryBulkhead"
	door.mesh = st.commit()
	var material := Assets.material(Assets.HULL)
	materials.append(material)
	door.material_override = material
	door.extra_cull_margin = 90.0
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(door)
	# The sealed-door glow: two conduit strips up the door leaves and a lintel bar, on the glowing
	# conduit material so the end reads as a door rather than a blank wall.
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		Assets.slab(glow,Vector3(side*1.6,2.8,24.1),Vector3(0.1,4.6,0.05),1.0)
	Assets.slab(glow,Vector3(0,5.3,24.0),Vector3(4.0,0.08,0.05),1.0)
	glow.generate_tangents()
	var strips := MeshInstance3D.new()
	strips.name = "EntryDoorGlow"
	strips.mesh = glow.commit()
	var conduit := Assets.material(Assets.CONDUIT)
	materials.append(conduit)
	strips.material_override = conduit
	strips.extra_cull_margin = 90.0
	strips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strips.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	door.add_child(strips)

func _plane(title: String, size: Vector2, location: Vector3, material: ShaderMaterial) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_depth = 80
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.position = location
	node.material_override = material
	node.extra_cull_margin = 90.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	if not materials.has(material): materials.append(material)

## `frame` is the corridor's global transform: the floor-mode surfaces measure their plating in it.
func sync(offset: float, clock: float, frame: Transform3D, arena: bool, delta: float) -> void:
	for batch in batches:
		for i in batch.instance_count:
			var z := 12.0-fposmod(i*12.0-offset,96.0)
			batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(0,0,z)))
	var frame_changed := not _frame_written or frame != _frame
	_frame = frame
	_frame_written = true
	for material in materials:
		material.set_shader_parameter("scroll",offset)
		material.set_shader_parameter("clock",clock)
		if frame_changed:
			material.set_shader_parameter("bend_frame",frame)
	arena_blend = move_toward(arena_blend,1.0 if arena else 0.0,delta*0.65)
	reactor_dock.visible = arena_blend > 0.001
	reactor_dock.position.z = lerpf(-72.0,-26.0,smoothstep(0.0,1.0,arena_blend))
	deck_light.light_energy = 0.55+0.015*sin(clock*1.5)
