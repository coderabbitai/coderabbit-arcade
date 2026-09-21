extends SceneTree
## Host-only fixture. Run from repository root; captures are never generated headlessly.
const KINDS := [&"approve_shield",&"auto_fix",&"lgtm",&"nitro",&"super_jump",&"code_review",&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const CorridorMaterials = preload("res://scenes/runner/environment/runner_materials.gd")
const FILL_ENERGY := 0.16
var stage: Node3D
var pickups: Node3D
var camera: Camera3D

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A4 CAPTURE: FAIL (graphical renderer required)")
		quit(1)
		return
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	stage = Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := fixture_environment()
	world.environment = environment
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35,-25,0)
	key.light_color = Palette.CREAM
	key.light_energy = 1.8
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15,150,0)
	fill.light_color = Palette.MINT
	fill.light_energy = FILL_ENERGY
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8,60)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Palette.NAVY_BG
	material.roughness = 0.4
	material.metallic = 0.7
	floor_mesh.material_override = material
	floor_mesh.position.z = -20
	stage.add_child(floor_mesh)
	# Neutral corridor walls and lane guides frame actual gameplay spacing.
	for side: float in [-1,1]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15,5,60)
		wall.mesh = box
		wall.material_override = material
		wall.position = Vector3(side*4,2.5,-20)
		stage.add_child(wall)
	var guides := MultiMeshInstance3D.new()
	guides.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	guides.multimesh = MultiMesh.new()
	guides.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var strip := PlaneMesh.new()
	strip.size = Vector2(0.012,60)
	guides.multimesh.mesh = strip
	guides.multimesh.instance_count = 4
	for i in 4:
		guides.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(-3+i*2,0.003,-20)))
	var guide_material := StandardMaterial3D.new()
	guide_material.albedo_color = Palette.SLATE
	guide_material.roughness = 0.4
	guides.material_override = guide_material
	stage.add_child(guides)
	camera = Camera3D.new()
	camera.fov = 60
	stage.add_child(camera)
	camera.make_current()
	pickups = Node3D.new()
	stage.add_child(pickups)
	var directory := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(directory)
	for view in ["powerups","tools","closeup","gameplay"]:
		for child in pickups.get_children(): child.free()
		var selection: Array = KINDS.slice(0,6) if view == "powerups" else KINDS.slice(6)
		if view == "closeup": selection = [&"approve_shield",&"super_jump",&"code_review"]
		if view == "gameplay": selection = KINDS
		for i in selection.size():
			var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % selection[i]) as PackedScene).instantiate() as Node3D
			pickups.add_child(visual)
			visual.set("kind",selection[i])
			visual.position = Vector3((i-(selection.size()-1)/2.0)*0.85,1,0)
			if view == "gameplay": visual.position = Vector3((i%3-1)*2,2.2 if selection[i] == &"auto_fix_patch" else 1,-3-float(i/3)*4)
			visual.on_spawned()
			visual._art._process(0.10)
			visual._art.set_process(false)
		camera.position = Vector3(0,2.0,4.8)
		camera.look_at(Vector3(0,0.95,0))
		if view == "closeup":
			camera.position = Vector3(0.12,1.55,2.25)
			camera.look_at(Vector3(0,0.98,0))
		if view == "gameplay":
			camera.position = Vector3(0,4,8)
			camera.look_at(Vector3(0,1,-8))
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var result := root.get_texture().get_image().save_png(directory+"/a4-"+view+".png")
		if result != OK:
			printerr("ASSET A4 CAPTURE: FAIL (save %s: %d)" % [view,result])
			quit(1)
			return
		print("ASSET A4 CAPTURE %s: %d measured scene draw calls" % [view,draws])
	print("ASSET A4 CAPTURE: PASS")
	quit(0)

static func fixture_environment() -> Environment:
	return CorridorMaterials.environment()
