extends Node3D
## One lane's DANGER telegraph (floor countdown inset + beam). Contract 2.4 overlaps telegraphs
## on a lane (a branching volley's heads, a flaky beat's candidates, a slow wall still counting
## down under the next beat), so the slot holds up to MAX_ENTRIES countdowns at once and always
## shows the one that fires first; start() never overwrites an entry that is still counting.
## `gain` (0..1, set by boss_fx.gd every frame) dims a flaky candidate that is not the one showing.
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Hologram = preload("res://scenes/runner/shaders/boss_beam.gdshader")
const MAX_ENTRIES := 4
var active := false
## The shown entry's seconds left and total seconds.
var remaining := 0.0
var seconds := 1.0
var gain := 1.0
var inset: MeshInstance3D
var beam_material: ShaderMaterial
var tag: Label3D
var countdown_material: ShaderMaterial
## Fixed-capacity countdowns (no per-telegraph allocation): owner id, seconds left, total seconds.
var _ids := PackedInt32Array()
var _left := PackedFloat32Array()
var _total := PackedFloat32Array()
var _kinds: Array[StringName] = []
var _count := 0

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ids.resize(MAX_ENTRIES)
	_left.resize(MAX_ENTRIES)
	_total.resize(MAX_ENTRIES)
	_kinds.resize(MAX_ENTRIES)

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

## Adds a countdown on `lane`. `id` names its owner so remove() can take it back (a flaky
## candidate that was not committed); -1 is anonymous. When the slot is full the entry that fires
## first is replaced, since it is the one closest to being over.
func start(lane: int, kind: StringName, duration: float, id: int = -1, elapsed: float = 0.0) -> void:
	position.x = (lane - 1) * 2.0
	var total := maxf(duration, 0.001)
	var slot := _count
	if id >= 0:
		for i in _count:
			if _ids[i] == id: slot = i
	if slot >= MAX_ENTRIES:
		slot = _soonest()
	elif slot == _count:
		_count += 1
	_ids[slot] = id
	_total[slot] = total
	_left[slot] = clampf(total - elapsed, 0.0, total)
	_kinds[slot] = kind
	active = true
	show()
	_process(0.0)

## Drops the countdown owned by `id`; the slot hides once nothing is left.
func remove(id: int) -> void:
	for i in range(_count - 1, -1, -1):
		if _ids[i] == id: _drop(i)
	if _count == 0: clear()
	elif active: _process(0.0)

func has_entry(id: int) -> bool:
	for i in _count:
		if _ids[i] == id: return true
	return false

func entry_count() -> int:
	return _count

func clear() -> void:
	active = false
	_count = 0
	gain = 1.0
	hide()

func _soonest() -> int:
	var best := 0
	for i in _count:
		if _left[i] < _left[best]: best = i
	return best

func _drop(index: int) -> void:
	_count -= 1
	_ids[index] = _ids[_count]
	_left[index] = _left[_count]
	_total[index] = _total[_count]
	_kinds[index] = _kinds[_count]

func _process(delta: float) -> void:
	if not active: return
	for i in range(_count - 1, -1, -1):
		_left[i] = maxf(0.0, _left[i] - delta)
		if _left[i] <= 0.0 and delta > 0.0: _drop(i)
	if _count == 0:
		remaining = 0.0
		clear()
		return
	var shown := _soonest()
	remaining = _left[shown]
	seconds = _total[shown]
	tag.text = String(_kinds[shown]).to_upper()
	var progress := 1 - remaining / seconds
	var strength := clampf(gain, 0.0, 1.0)
	countdown_material.set_shader_parameter("clock", seconds - remaining)
	countdown_material.set_shader_parameter("progress", progress)
	countdown_material.set_shader_parameter("color", Color(Palette.DANGER, 0.9 * strength))
	beam_material.set_shader_parameter("clock", seconds - remaining)
	beam_material.set_shader_parameter("color", Color(Palette.DANGER, lerpf(0.15, 0.55, progress) * strength))
