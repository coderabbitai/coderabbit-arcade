extends "res://scenes/runner/hazards/hazard_visual_base.gd"
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Hologram = preload("res://scenes/runner/shaders/hologram.gdshader")
var _body: Node3D
var _clock := 0.0
var _shell: ShaderMaterial
var _batch: Art
var _core: MeshInstance3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func on_spawned() -> void:
	if _body != null:
		remove_child(_body)
		_body.queue_free()
	_body = Node3D.new()
	add_child(_body)
	_body.position = hitbox_offset
	_clock = 0.0
	_shell = null
	_batch = null
	show()
	match variant:
		&"orb":
			_core = Art.sphere(_body, Vector3.ZERO, 0.75, Palette.DANGER)
			var shell := Art.sphere(_body, Vector3.ZERO, 0.85, Palette.DANGER)
			_shell = ShaderMaterial.new()
			_shell.shader = Hologram
			_shell.set_shader_parameter("color", Color(Palette.DANGER, 0.5))
			shell.material_override = _shell
			_batch = Art.new()
			_body.add_child(_batch)
			var poses: Array[Transform3D] = []
			for i in 12:
				poses.append(Art.pose(Vector3(sin(float(i)) * 0.3, cos(float(i)) * 0.25, -0.5 + i * 0.025), Vector3.ONE * 0.07))
			_batch.batch(poses, Palette.DANGER)
		&"low", &"high":
			_core = Art.box(_body, Vector3.ZERO, hitbox_size, Palette.DANGER)
			_core.material_override = Materials.additive(Palette.DANGER, 0.18)
			Art.box(_body, Vector3(0, 0, 0.02), hitbox_size * Vector3(0.98, 0.20, 0.5), Palette.DANGER)
		&"wide":
			_core = Art.box(_body, Vector3.ZERO, hitbox_size * Vector3(1, 0.65, 0.7), Palette.ORANGE)
			_core.material_override = Materials.additive(Palette.ORANGE, 0.20)
			_batch = Art.new()
			_body.add_child(_batch)
			var poses: Array[Transform3D] = []
			for i in 8: poses.append(Art.pose(Vector3((i - 3.5) * 0.42, 0, 0.45), Vector3(0.12, 0.25, 0.04)))
			_batch.batch(poses, Palette.ORANGE)

func _process(delta: float) -> void:
	_clock += delta
	if _shell != null: _shell.set_shader_parameter("clock", _clock * maxf(closing_speed / 20.0, 1))
	if _core != null and variant == &"high": _core.scale.y = clampf(_clock / 0.1, 0.01, 1.0)

func on_hit_player() -> void:
	hide()

func on_cleared() -> void:
	hide()
