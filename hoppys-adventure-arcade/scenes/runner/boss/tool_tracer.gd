extends Node3D
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
signal arrived(kind: StringName, damage: int, point: Vector3)
var active := false
var age := 0.0
var kind := &""
var damage := 0
var origin := Vector3.ZERO
var target := Vector3.ZERO
var strip: MeshInstance3D
var energy: ShaderMaterial

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(Art.Forge.bevel_box(Vector3(0.045, 0.045, 1.0)), 0, Transform3D.IDENTITY)
	surface.append_from(Art.Forge.bevel_box(Vector3(0.13, 0.13, 0.17)), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.42)))
	energy = ShaderMaterial.new()
	energy.shader = preload("res://scenes/runner/shaders/boss_beam.gdshader")
	strip = Art.shape(self, surface.commit(), Vector3.ZERO, energy)
	hide()

func fire(from: Vector3, to: Vector3, tool: StringName, amount: int) -> void:
	origin = from
	target = to
	kind = tool
	damage = amount
	age = 0.0
	active = true
	energy.set_shader_parameter("color", Color(Palette.ORANGE if tool == &"lint_rule" else Palette.MATRIX, 0.65))
	show()
	_process(0.0)

func clear() -> void:
	active = false
	hide()

func _process(delta: float) -> void:
	if not active: return
	age += delta
	var end := origin.lerp(target, minf(age / 0.14, 1))
	var tail := origin.lerp(target, clampf((age - 0.045) / 0.14, 0, 1))
	var distance := maxf(tail.distance_to(end), 0.001)
	position = (tail + end) * 0.5
	if origin.distance_squared_to(target) > 0.001: basis = Basis.looking_at(target - origin, Vector3.UP)
	strip.scale.z = distance
	energy.set_shader_parameter("clock", age)
	if age >= 0.14:
		clear()
		arrived.emit(kind, damage, target)
