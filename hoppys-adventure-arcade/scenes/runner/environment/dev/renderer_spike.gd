extends Node3D
## Standalone Compatibility fixture. G toggles glow, F fog, R retro scaling.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
var _viewport: Viewport
var _previous_mode: int
var _previous_scale: float
var _environment: Environment
var _clock := 0.0
var _hologram: ShaderMaterial
var _wall: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_viewport = get_viewport()
	_previous_mode = _viewport.scaling_3d_mode
	_previous_scale = _viewport.scaling_3d_scale
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 0.5
	var world := WorldEnvironment.new()
	_environment = Materials.environment()
	world.environment = _environment
	add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4, 8)
	camera.fov = 60
	add_child(camera)
	camera.look_at(Vector3(0, 1, -8))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 0.8
	light.shadow_enabled = false
	add_child(light)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 100)
	var grid := ShaderMaterial.new()
	grid.shader = preload("res://scenes/runner/shaders/floor_grid.gdshader")
	_mesh(floor_mesh, grid, Vector3(0, -0.02, -40))
	_wall = ShaderMaterial.new()
	_wall.shader = preload("res://scenes/runner/shaders/code_wall.gdshader")
	_wall.set_shader_parameter("horizontal_axis", Vector3.RIGHT)
	_wall.set_shader_parameter("atlas", preload("res://scenes/runner/shaders/glyph_atlas.gd").texture())
	var wall_mesh := QuadMesh.new()
	wall_mesh.size = Vector2(6, 4)
	_mesh(wall_mesh, _wall, Vector3(0, 3, -18))
	var far := ShaderMaterial.new()
	far.shader = preload("res://scenes/runner/shaders/far_glow.gdshader")
	var far_mesh := QuadMesh.new()
	far_mesh.size = Vector2(10, 10)
	_mesh(far_mesh, far, Vector3(0, 3, -88))
	for i in 9:
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 2, 0.6)
		_mesh(box, Materials.glow(Palette.MATRIX, 1.2), Vector3(-3, 1, -i * 10))
	for i in 3:
		var sphere := SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
		_mesh(sphere, Materials.glow(Palette.ORANGE, [0.3, 1.2, 3.0][i]), Vector3(i * 1.8 - 1.8, 1, -3))
		var tag := Materials.label(self, "EMISSION %.1f" % [0.3, 1.2, 3.0][i], 24, Palette.CREAM)
		tag.position = Vector3(i * 1.8 - 1.8, 1.9, -3)
	_hologram = ShaderMaterial.new()
	_hologram.shader = preload("res://scenes/runner/shaders/hologram.gdshader")
	_mesh(SphereMesh.new(), _hologram, Vector3(3, 1.2, -4))
	var rain := Materials.glyph_particles(320, Vector3(3.9, 0.2, 10))
	rain.position = Vector3(0, 6.2, -10)
	add_child(rain)
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette := ShaderMaterial.new()
	vignette.shader = preload("res://scenes/runner/shaders/vignette.gdshader")
	vignette.set_shader_parameter("strength", 0.12)
	overlay.material = vignette
	layer.add_child(overlay)
	var label := Style.label("RENDERER SPIKE   /   G glow   F fog   R 50% / 100%", 18)
	label.position = Vector2(28, 28)
	layer.add_child(label)
	print("SPIKE: renderer=", RenderingServer.get_current_rendering_method(), " scale=", _viewport.scaling_3d_scale, " glow_threshold=", _environment.glow_hdr_threshold, " fog=22..88 particles=320")

func _mesh(shape: Mesh, material: Material, location: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material
	instance.position = location
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _process(delta: float) -> void:
	_clock += delta
	_hologram.set_shader_parameter("clock", _clock)
	_wall.set_shader_parameter("clock", _clock)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.physical_keycode:
		KEY_G: _environment.glow_enabled = not _environment.glow_enabled
		KEY_F: _environment.fog_enabled = not _environment.fog_enabled
		KEY_R: _viewport.scaling_3d_scale = 1.0 if _viewport.scaling_3d_scale < 1.0 else 0.5

func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.scaling_3d_scale = _previous_scale
		_viewport.scaling_3d_mode = _previous_mode
