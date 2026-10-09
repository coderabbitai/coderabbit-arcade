extends "res://scenes/runner/boss/boss_visual_base.gd"
## The visual owns one clock. Imported clips are sampled manually, including hit-stop.
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const BossModel = preload("res://scenes/runner/boss/hifi/boss_model.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const MODEL_PATH := "res://Assets/runner/bosses/flaky_test_swarm/flaky_test_swarm.glb"
const ACCENT := Color("8fd14f")
const COMMIT_ARC := [Vector3(1.74, 1.10, 0.20), Vector3(1.03, 2.40, -0.25),
	Vector3(-1.03, 2.40, 0.25), Vector3(-1.74, 1.10, -0.20),
	Vector3(-1.32, 0.0, 0.15), Vector3(1.32, 0.0, -0.15)]
var model_path := MODEL_PATH
var _art: Art
var _model: Node3D
var _skeleton: Skeleton3D
var _tag: Label3D
var _drone_bones: Array[int] = []
var show_name_plate := true
var intro_calls := 0
var _intro_tag_visible := false
var _clock := 0.0
var _time_factor := 1.0
var _phase := 1
var _health := 1.0
var _state: StringName = &"idle"
var _state_age := 0.0
var _state_duration := 1.0
var _terminal := false
var _aim := 0.0
var _commit_age := -1.0
var _projectile_kind: StringName = &""
var _flash_age := 1.0
var _flash_strength := 0.0
var _cinematic_mode: StringName = &""
var _cinematic_age := 0.0
var _cinematic_seconds := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	if _model == null and _art == null:
		_model = BossModel.load_model(model_path)
		if _model != null:
			add_child(_model)
			_model.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for material: ShaderMaterial in _model.materials:
				material.set_shader_parameter("dissolve_color", ACCENT)
			var rigs := _model.find_children("*", "Skeleton3D", true, false)
			if not rigs.is_empty(): _skeleton = rigs[0] as Skeleton3D
			if _skeleton != null:
				for i in 6: _drone_bones.append(_skeleton.find_bone("drone_%d" % i))
			_tag = Art.label(self, "", Vector3(0, 3.15, 0), 0.005)
			_tag.font_size = 40
			_tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		else:
			_art = Art.new()
			add_child(_art)
			_art.build(&"flaky_test_swarm")
			_tag = _art.tag
	_clock = 0.0
	_phase = 1
	_health = 1.0
	_time_factor = 1.0
	_terminal = false
	_commit_age = -1.0
	_aim = 0.0
	_cinematic_mode = &""
	_cinematic_age = 0.0
	_flash_age = 1.0
	_flash_strength = 0.0
	_projectile_kind = &""
	_tag.text = boss_name if not boss_name.is_empty() else "Flaky Test Swarm"
	_intro_tag_visible = show_name_plate
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.get_node_or_null("HUD/BossHud") != null or ancestor.get_node_or_null("HUD/BossHUD") != null:
			_intro_tag_visible = false
			break
		ancestor = ancestor.get_parent()
	_tag.visible = _intro_tag_visible
	if _art != null: _art.reset()
	if _model != null:
		_model.show()
		_model.transform = Transform3D.IDENTITY
		_model.set_dissolve(0.0)
		_model.set_flash(0.0)
		_model.set_phase_tint(Color.WHITE)
		_model.set_time_factor(1.0)
		_play(&"idle")
	position = Vector3(0, 0, hover_z - get_parent_node_3d().position.z) if get_parent_node_3d() != null else Vector3(0, 0, hover_z)
	show()

func _ensure_art() -> void:
	if _model == null and _art == null: on_spawned()

func _play(action: StringName, seconds: float = -1.0) -> void:
	_state = action
	_state_age = 0.0
	if _model == null: return
	var player: AnimationPlayer = _model.animation_player
	_state_duration = maxf(seconds if seconds >= 0.0 else player.get_animation(action).length, 0.001)
	# Zero blending is intentional: one deterministic seek controls bones and sockets.
	player.play(action, 0.0)
	if _skeleton != null: _skeleton.reset_bone_poses()
	player.seek(0.0, true)
	_tag.visible = _intro_tag_visible and action not in [&"intro", &"defeat", &"retreat"]

func set_phase(value: int) -> void:
	_ensure_art()
	if _terminal: return
	_phase = clampi(value, 1, maxi(phase_count, 1))
	if _art != null:
		_art.phase = _phase
		_art.react(&"phase_change", 0.9)
	else:
		_model.set_phase_tint(Color.WHITE.lerp(ACCENT, (_phase - 1) * 0.15))
		_play(&"phase_change")

func set_health(hp: int, max_health: int) -> void:
	_ensure_art()
	_health = clampf(float(hp) / maxi(max_health, 1), 0, 1)
	if _art != null: _art.health = _health

func play_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	_ensure_art()
	if _terminal: return
	_aim = Art.mask_center(lane_mask)
	_commit_age = -1.0
	_projectile_kind = projectile_kind
	if _art != null: _art.signature_telegraph(lane_mask, projectile_kind, seconds)
	else: _play(&"telegraph", seconds)

## The backend owns flickering candidates and floor marks. Commitment makes the
## six drones converge on the final lane and hold their red failure faces.
func play_commit(lane_mask: int, _kind: StringName, seconds: float) -> void:
	_ensure_art()
	if _terminal: return
	_aim = Art.mask_center(lane_mask)
	_commit_age = 0.0
	if _art != null:
		_art.signature_commit(lane_mask, seconds)
	else:
		if _state != &"telegraph": _play(&"telegraph", seconds)
		else: _state_duration = _state_age + maxf(seconds, 0.001)

func play_attack(projectile_kind: StringName) -> void:
	_ensure_art()
	if _terminal: return
	_commit_age = -1.0
	_projectile_kind = projectile_kind
	if _art != null: _art.signature_attack(projectile_kind)
	else: _play(&"attack")

func play_hit(_tool_kind: StringName, _damage: int) -> void:
	_ensure_art()
	if _terminal: return
	if _art != null: _art.flash()
	else:
		_play(&"hurt")
		_flash_age = 0.0
		_flash_strength = 1.0
		_model.set_flash(1.0)

func play_resist(_tool_kind: StringName) -> void:
	_ensure_art()
	if _terminal: return
	if _art != null: _art.flash(true)
	else:
		_flash_age = 0.0
		_flash_strength = 0.24
		_model.set_flash(_flash_strength)

func play_defeat() -> void:
	_ensure_art()
	_terminal = true
	_cinematic_mode = &""
	_flash_strength = 0.0
	_tag.hide()
	if _art != null: _art.shatter()
	else: _play(&"defeat", 0.95)

func play_retreat() -> void:
	_ensure_art()
	_terminal = true
	_cinematic_mode = &""
	_tag.hide()
	if _art != null: _art.react(&"retreat", 0.95)
	else: _play(&"retreat", 0.95)

func play_intro(seconds: float) -> void:
	_ensure_art()
	if _terminal: return
	intro_calls += 1
	_clock = 0.0
	_tag.hide()
	if _art != null:
		_art.react(&"intro", seconds)
		_art.advance(0.0)
	else:
		position.x = 0.0
		position.y = 0.0
		_play(&"intro", seconds)

func play_cinematic(mode: StringName, seconds: float) -> void:
	if mode not in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]: return
	_ensure_art()
	if _terminal and mode in [&"intro_full", &"intro_short"]: return
	_cinematic_mode = mode
	_cinematic_age = 0.0
	_cinematic_seconds = maxf(seconds, 0.001)
	_tag.hide()
	if mode in [&"intro_full", &"intro_short"]:
		play_intro(_cinematic_seconds * 0.55)
	else:
		_terminal = true
		_flash_strength = 0.0
		if _art != null: _art.shatter()
		else:
			_play(&"defeat", _cinematic_seconds)
			_model.set_flash(1.0)
			_model.set_dissolve(0.0)
	set_cinematic_progress(mode, 0.0)

## Contract 2.6: the encounter owns cinematic time, including pause and skip jumps.
## Time factor only affects normal ambient/action motion in _process.
func set_cinematic_progress(mode: StringName, progress: float) -> void:
	if mode != _cinematic_mode or _cinematic_mode.is_empty(): return
	_cinematic_age = clampf(progress, 0.0, 1.0) * _cinematic_seconds
	if _model != null:
		_sample_cinematic()
		_apply_formation()
	else:
		var p := clampf(progress, 0.0, 1.0)
		_art.clock = _cinematic_age
		if mode in [&"intro_full", &"intro_short"]:
			_art.state = &"intro" if p < 0.80 else &"idle"
			_art.age = minf(p / 0.55, 0.99999) * _art.duration if p < 0.80 else (p - 0.80) * _cinematic_seconds
		else:
			_art.state = &"defeated"
			var hitstop := minf(0.12, _cinematic_seconds)
			_art.age = clampf((_cinematic_age - hitstop) / maxf(_cinematic_seconds - hitstop, 0.001), 0, 1) * _art.duration
		_art.advance(0.0)
		_tag.hide()
		if p >= 1.0:
			_cinematic_mode = &""
			if not _terminal: _tag.visible = _intro_tag_visible

func set_time_factor(factor: float) -> void:
	_time_factor = maxf(factor, 0.0)
	if _model != null: _model.set_time_factor(_time_factor)

## Optional socket facade for cinematic FX. The same bones drive the mesh.
func socket(key: StringName) -> Node3D:
	return _model.socket(key) if _model != null else null

func _process(delta: float) -> void:
	if (_model == null and _art == null) or (is_inside_tree() and get_tree().paused): return
	var step := maxf(delta, 0.0) * _time_factor
	if step <= 0.0: return
	if not _cinematic_mode.is_empty(): return
	_clock += step
	if _art != null:
		var was_intro := _art.state == &"intro"
		_art.advance(step)
		if was_intro and _art.state != &"intro": _tag.visible = _intro_tag_visible
		if _art.state == &"intro": return
		var fallback_period := maxf(sway_period * (1 - 0.12 * (_art.phase - 1)), 0.1)
		position.x = sin(_clock * TAU / fallback_period) * minf(sway_amplitude, 0.35)
		position.y = 0.04 + sin(_clock * 2) * 0.04
		if _art.state == &"phase_change": position.y += 0.12 * sin(PI * minf(_art.age / 0.9, 1))
		if _art.state == &"retreat": position.y += minf(_art.age, 0.95) * 0.12
		return
	else:
		_state_age += step
		_flash_age += step
		if _commit_age >= 0.0: _commit_age += step
		_sample_action()
		_model.set_flash(_flash_strength * (1.0 - clampf(_flash_age / 0.16, 0, 1)))
		_apply_formation()
		if _state == &"intro" or _terminal: return
	var period := maxf(sway_period * (1 - 0.12 * (_phase - 1)), 0.1)
	position.x = sin(_clock * TAU / period) * minf(sway_amplitude, 0.18)
	position.y = 0.04 + sin(_clock * 2) * 0.04

func _seek(action: StringName, progress: float) -> void:
	var player: AnimationPlayer = _model.animation_player
	if player.current_animation != action: player.play(action, 0.0)
	# Imported clips may omit constant tracks. Reset before adding formation offsets.
	if _skeleton != null: _skeleton.reset_bone_poses()
	player.seek(clampf(progress, 0.0, 1.0) * player.get_animation(action).length, true)

func _sample_action() -> void:
	var progress := _state_age / _state_duration
	if _state == &"idle":
		_seek(&"idle", fposmod(progress, 1.0))
	elif _terminal:
		_seek(_state, progress)
		if _state == &"defeat": _model.set_dissolve(clampf((progress - 0.55) / 0.45, 0, 1))
		if progress >= 1.0: _model.hide()
	elif progress >= 1.0:
		var remainder := _state_age - _state_duration
		_play(&"idle")
		_state_age = remainder
		_seek(&"idle", fposmod(_state_age / _state_duration, 1.0))
	else:
		_seek(_state, progress)

func _sample_cinematic() -> void:
	var p := clampf(_cinematic_age / _cinematic_seconds, 0, 1)
	if _cinematic_mode in [&"intro_full", &"intro_short"]:
		# Assemble, hold the finished pose for the card, then ease into idle.
		if p < 0.80:
			_seek(&"intro", minf(p / 0.55, 1.0))
		else:
			if _state != &"idle": _play(&"idle")
			_seek(&"idle", (_cinematic_age - _cinematic_seconds * 0.80) / _state_duration)
		_tag.hide()
		if p >= 1.0:
			_cinematic_mode = &""
			_play(&"idle")
	else:
		# The struck pose holds for 0.12 s. Collapse starts immediately after it,
		# with the opening strobe overlapping the action instead of delaying it.
		var hitstop := minf(0.12, _cinematic_seconds)
		_seek(&"defeat", maxf((_cinematic_age - hitstop) / maxf(_cinematic_seconds - hitstop, 0.001), 0.0))
		var strobe := 1.0 if _cinematic_age < hitstop else (0.85 if p < 0.25 and int(p * 32.0) % 2 == 0 else 0.0)
		_model.set_flash(strobe)
		_model.set_dissolve(clampf((p - 0.55) / 0.45, 0, 1))
		if p >= 1.0:
			_model.hide()
			_state_age = _state_duration
			_cinematic_mode = &""

func _apply_formation() -> void:
	if _skeleton == null or _terminal or _state == &"intro": return
	var committed := smoothstep(0.0, 0.12, _commit_age) if _state == &"telegraph" and _commit_age >= 0 else 0.0
	var tighter := (_phase - 1) * 0.035
	var scatter := 0.09 * sin(PI * clampf(_state_age / _state_duration, 0, 1)) if _projectile_kind == &"scatter" and _state in [&"telegraph", &"attack"] else 0.0
	for i in _drone_bones.size():
		var index := _drone_bones[i]
		if index < 0: continue
		var point := _skeleton.get_bone_pose_position(index)
		point.x *= 1.0 - tighter + scatter
		point.y = 1.02 + (point.y - 1.02) * (1.0 - tighter + scatter)
		if committed > 0.0:
			# Each drone keeps an individual slot around the queen. Only the arc
			# centre tracks the committed lane, preserving separation in close-up.
			var target: Vector3 = COMMIT_ARC[i]
			target.x = target.x * (1.0 - tighter) + _aim * 0.08
			target.y = 1.02 + (target.y - 1.02) * (1.0 - tighter)
			point = point.lerp(target, committed)
			_skeleton.set_bone_pose_rotation(index, Quaternion(Vector3.UP, PI))
		# Keep the lower-left worker clear of the opened phase carapace.
		if i == 4 and _phase >= 2: point.x -= 0.15
		_skeleton.set_bone_pose_position(index, point)
	# The phase split stays visible after the phase-change action returns to idle.
	for side in [-1, 1]:
		var index := _skeleton.find_bone("carapace_L" if side < 0 else "carapace_R")
		if index >= 0:
			var point := _skeleton.get_bone_pose_position(index)
			point.x += side * (_phase - 1) * 0.08
			_skeleton.set_bone_pose_position(index, point)
