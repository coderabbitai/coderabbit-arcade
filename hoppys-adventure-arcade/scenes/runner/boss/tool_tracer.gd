extends Node3D
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
signal arrived(kind: StringName, damage: int, point: Vector3)
var active := false
var age := 0.0
var kind := &""
var damage := 0
var origin := Vector3.ZERO
var target := Vector3.ZERO
var strip: MeshInstance3D

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	strip = Art.box(self, Vector3.ZERO, Vector3(0.04, 0.04, 1), Palette.MATRIX)
	hide()

func fire(from: Vector3, to: Vector3, tool: StringName, amount: int) -> void:
	origin = from
	target = to
	kind = tool
	damage = amount
	age = 0.0
	active = true
	strip.material_override = Materials.additive(Palette.ORANGE if tool == &"lint_rule" else Palette.MATRIX, 0.8)
	show()
	_process(0.0)

func clear() -> void:
	active = false
	hide()

func _process(delta: float) -> void:
	if not active: return
	age += delta
	var end := origin.lerp(target, minf(age / 0.14, 1))
	var distance := maxf(origin.distance_to(end), 0.001)
	position = (origin + end) * 0.5
	if origin.distance_squared_to(target) > 0.001: basis = Basis.looking_at(target - origin, Vector3.UP)
	strip.scale.z = distance
	if age >= 0.14:
		clear()
		arrived.emit(kind, damage, target)
