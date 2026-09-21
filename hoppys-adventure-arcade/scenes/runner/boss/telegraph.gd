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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var floor_mesh := QuadMesh.new()
	floor_mesh.size = Vector2(2, 30)
	var floor_decal := Art.shape(self, floor_mesh, Vector3(0, 0.008, -14), Materials.additive(Palette.DANGER, 0.35))
	floor_decal.rotation.x = -PI / 2
	var inset_mesh := QuadMesh.new()
	inset_mesh.size = Vector2(1.7, 29.5)
	inset = Art.shape(self, inset_mesh, Vector3(0, 0.012, -14), Materials.additive(Palette.MATRIX, 0.4))
	inset.rotation.x = -PI / 2
	var beam := QuadMesh.new()
	beam.size = Vector2(1.9, 5)
	beam_material = ShaderMaterial.new()
	beam_material.shader = Hologram
	Art.shape(self, beam, Vector3(0, 2.5, -10), beam_material)
	tag = Art.label(self, "ORB", Vector3(0, 2.4, -7), 0.006)
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
	inset.scale.y = maxf(1 - progress, 0.001)
	beam_material.set_shader_parameter("clock", seconds - remaining)
	beam_material.set_shader_parameter("color", Color(Palette.DANGER, lerpf(0.15, 0.55, progress)))
	if remaining <= 0: clear()
