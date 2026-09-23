extends "res://scenes/runner/boss/boss_visual_base.gd"
const Art = preload("res://scenes/runner/boss/boss_art.gd")
var _art: Art
var show_name_plate := true
var _clock := 0.0
var intro_calls := 0
var _intro_tag_visible := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	if _art == null:
		_art = Art.new()
		add_child(_art)
		_art.build(&"flaky_test_swarm")
	_art.reset()
	_art.tag.text = (boss_name if not boss_name.is_empty() else String(kind).replace("_", " "))
	_art.tag.visible = show_name_plate
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.get_node_or_null("HUD/BossHud") != null or ancestor.get_node_or_null("HUD/BossHUD") != null:
			_art.tag.hide()
			break
		ancestor = ancestor.get_parent()
	set_health(max_hp, max_hp)
	_clock = 0.0
	# Backend parents already supply hover_z; standalone mounts use the same depth.
	position = Vector3(0, 0, hover_z - get_parent_node_3d().position.z) if get_parent_node_3d() != null else Vector3(0, 0, hover_z)
	show()

func set_phase(value: int) -> void:
	if _art == null: on_spawned()
	_art.phase = clampi(value, 1, phase_count)
	_art.react(&"phase_change", 0.9)

func set_health(hp: int, max_health: int) -> void:
	if _art == null: on_spawned()
	_art.health = clampf(float(hp) / maxi(max_health, 1), 0, 1)

func play_telegraph(lane_mask: int, _projectile_kind: StringName, seconds: float) -> void:
	if _art == null: on_spawned()
	var total := 0.0
	var count := 0
	for lane in 3:
		if lane_mask & (1 << lane):
			total += (lane - 1) * 2.0
			count += 1
	_art.aim = total / maxi(count, 1)
	_art.react(&"telegraph", seconds)

func play_attack(_projectile_kind: StringName) -> void:
	if _art != null: _art.react(&"attack", 0.12)

func play_hit(_tool_kind: StringName, _damage: int) -> void:
	if _art != null: _art.flash()

func play_resist(_tool_kind: StringName) -> void:
	if _art != null: _art.flash(true)

func play_defeat() -> void:
	if _art != null: _art.shatter()

func play_retreat() -> void:
	if _art != null: _art.react(&"retreat", 0.95)

func _process(delta: float) -> void:
	if _art == null: return
	_clock += delta
	var was_intro: bool = _art.state == &"intro"
	_art.advance(delta)
	if was_intro and _art.state != &"intro": _art.tag.visible = _intro_tag_visible
	if _art.state == &"intro": return
	var period := maxf(sway_period * (1 - 0.12 * (_art.phase - 1)), 0.1)
	position.x = sin(_clock * TAU / period) * minf(sway_amplitude, 0.35)
	position.y = 0.04 + sin(_clock * 2) * 0.04
	if _art.state == &"phase_change": position.y += 0.12 * sin(PI * minf(_art.age / 0.9, 1))
	if _art.state == &"retreat": position.y += minf(_art.age, 0.95) * 0.12

func play_intro(seconds: float) -> void:
	if _art == null: on_spawned()
	intro_calls += 1
	_clock = 0.0
	_intro_tag_visible = _art.tag.visible
	_art.tag.hide()
	_art.react(&"intro", seconds)
	_art.advance(0.0)
