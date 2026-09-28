extends Node3D
const Assets = preload("res://scenes/runner/environment/starship/starship_assets.gd")
var batches: Array[MultiMesh] = []
var materials: Array[ShaderMaterial] = []
var reactor_dock: Node3D
var arena_blend := 0.0
var deck_light: OmniLight3D

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

func sync(offset: float, clock: float, bend: float, frame: Transform3D, arena: bool, delta: float) -> void:
	for batch in batches:
		for i in batch.instance_count:
			var z := 12.0-fposmod(i*12.0-offset,96.0)
			batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(0,0,z)))
	for material in materials:
		material.set_shader_parameter("scroll",offset)
		material.set_shader_parameter("clock",clock)
		material.set_shader_parameter("bend",bend)
		material.set_shader_parameter("bend_frame",frame)
	arena_blend = move_toward(arena_blend,1.0 if arena else 0.0,delta*0.65)
	reactor_dock.visible = arena_blend > 0.001
	reactor_dock.position.z = lerpf(-72.0,-26.0,smoothstep(0.0,1.0,arena_blend))
	deck_light.light_energy = 0.55+0.015*sin(clock*1.5)
