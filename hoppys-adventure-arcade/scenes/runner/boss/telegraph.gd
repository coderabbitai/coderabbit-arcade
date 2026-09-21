extends Node3D
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Hologram = preload("res://scenes/runner/shaders/boss_beam.gdshader")
var active := false
var remaining := 0.0
var seconds := 1.0
var inset: MeshInstance3D
var beam_material: ShaderMaterial
var tag: Label3D
var countdown_material: ShaderMaterial

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var floor_mesh := QuadMesh.new()
	floor_mesh.size = Vector2(2, 30)
	countdown_material = ShaderMaterial.new()
	countdown_material.shader = Hologram
	countdown_material.set_shader_parameter("floor_projection", true)
	countdown_material.set_shader_parameter("color", Color(Palette.DANGER, 0.9))
	inset = Art.shape(self, floor_mesh, Vector3(0, 0.025, -14), countdown_material)
	inset.rotation.x = -PI / 2
	var beam := QuadMesh.new()
	beam.size = Vector2(1.9, 5)
	beam_material = ShaderMaterial.new()
	beam_material.shader = Hologram
	Art.shape(self, beam, Vector3(0, 2.5, -10), beam_material)
	tag = Art.label(self, "ORB", Vector3(0, 2.4, -7), 0.006)
	# Retain text metadata for the existing hook/smoke contract, without drawing it.
	tag.hide()
	hide()

func start(lane: int, kind: StringName, duration: float) -> void:
	position.x = (lane - 1) * 2.0
	seconds = maxf(duration, 0.001)
	remaining = seconds
	tag.text = String(kind).to_upper()
	active = true
	show()
	_process(0.0)

func clear() -> void:
	active = false
	hide()

func _process(delta: float) -> void:
	if not active: return
	remaining = maxf(0, remaining - delta)
	var progress := 1 - remaining / seconds
	countdown_material.set_shader_parameter("clock", seconds - remaining)
	countdown_material.set_shader_parameter("progress", progress)
	beam_material.set_shader_parameter("clock", seconds - remaining)
	beam_material.set_shader_parameter("color", Color(Palette.DANGER, lerpf(0.15, 0.55, progress)))
	if remaining <= 0: clear()
