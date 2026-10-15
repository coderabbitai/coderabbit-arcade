extends "res://scenes/runner/boss/boss_visual_base.gd"
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Model = preload("res://scenes/runner/boss/hifi/boss_model.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const MODEL_PATH := "res://Assets/runner/bosses/legacy_monolith/legacy_monolith.glb"
const SIGNATURE_MODES := {&"slab": &"wall", &"quake": &"quake", &"debris": &"debris"}
var model_path := MODEL_PATH
var _model: Node3D
var _art: Art
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _tag: Label3D
var show_name_plate := true
var intro_calls := 0
var _clock := 0.0
var _intro_tag_visible := false
var _state: StringName = &"idle"
var _age := 0.0
var _duration := 4.0
var _phase := 1
var _health := 1.0
var _time_factor := 1.0
var _cinematic_mode: StringName = &""
var _mode: StringName = &""
var _wall_mask := 0
var _aim := 0.0
var _terminal := false
var _flash_remaining := 0.0
var _flash_strength := 0.0
var _hitstop_pose: Array[Transform3D] = []
var _emission_base: Array[Color] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ensure() -> void:
	if _model == null and _art == null:
		on_spawned()

func on_spawned() -> void:
	if _model == null and _art == null:
		_model = Model.load_model(model_path)
		if _model != null:
			add_child(_model)
			# Contract 11.5 leaves 4.5 m of vertical space for the complete posed rig.
			_model.position.y = -0.065
			_player = _model.get("animation_player") as AnimationPlayer
			_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			# Contract 2.6: local combat clock, authoritative cinematic progress.
			_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_player.playback_default_blend_time = 0.0
			for material: ShaderMaterial in _model.get("materials"):
				# Art review r2: reactor fire overrides the slate chassis accent.
				material.set_shader_parameter("dissolve_color", Palette.ORANGE)
				_emission_base.append(material.get_shader_parameter("emission_color"))
			_tag = Art.label(self, "", Vector3(0, 3.65, 0), 0.005)
			_tag.font_size = 40
			_tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		else:
			_art = Art.new()
			add_child(_art)
			_art.build(&"legacy_monolith")
			_tag = _art.tag
	_clock = 0.0
	_phase = 1
	_health = 1.0
	_time_factor = 1.0
	_terminal = false
	_cinematic_mode = &""
	_mode = &""
	_wall_mask = 0
	_aim = 0.0
	_flash_remaining = 0.0
	_hitstop_pose.clear()
	_tag.text = boss_name if not boss_name.is_empty() else String(kind).replace("_", " ")
	_tag.visible = show_name_plate
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.get_node_or_null("HUD/BossHud") != null or ancestor.get_node_or_null("HUD/BossHUD") != null:
			_tag.hide()
			break
		ancestor = ancestor.get_parent()
	_intro_tag_visible = _tag.visible
	position = Vector3(0, 0, hover_z - get_parent_node_3d().position.z) if get_parent_node_3d() != null else Vector3(0, 0, hover_z)
	show()
	if _art != null:
		_art.reset()
		_state = &"idle"
		_age = 0.0
	else:
		_model.show()
		_model.call("set_dissolve", 0.0)
		_model.call("set_flash", 0.0)
		_model.call("set_phase_tint", Color.WHITE)
		_model.call("set_time_factor", 1.0)
		_play_action(&"idle")
		_sample_pose()

func set_phase(value: int) -> void:
	_ensure()
	_phase = clampi(value, 1, phase_count)
	if _art != null:
		_art.phase = _phase
		_art.react(&"phase_change", 0.9)
		return
	_model.call("set_phase_tint", Color.WHITE.lerp(Color(1.0, 0.87, 0.72), float(_phase - 1) / 2.0))
	if not _terminal:
		_play_action(&"phase_change")

func set_health(hp: int, max_health: int) -> void:
	_ensure()
	_health = clampf(float(hp) / maxi(max_health, 1), 0, 1)
	if _art != null:
		_art.health = _health

func _play_action(action: StringName, seconds: float = -1.0) -> void:
	_state = action
	_age = 0.0
	var clip := _player.get_animation(action)
	_duration = maxf(clip.length if seconds < 0.0 else seconds, 0.001)
	_player.stop()
	_player.play(action, 0.0)
	_player.advance(0.0)

func play_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	_ensure()
	if _terminal: return
	if _art != null:
		_art.signature_telegraph(lane_mask, projectile_kind, seconds)
		return
	_mode = SIGNATURE_MODES.get(projectile_kind, &"")
	_wall_mask = lane_mask
	_aim = Art.mask_center(lane_mask)
	_cinematic_mode = &""
	_play_action(&"telegraph", seconds)

func play_commit(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	if _terminal: return
	if _art != null:
		_art.signature_commit(lane_mask, seconds)
	elif _model != null:
		_aim = Art.mask_center(lane_mask)
		_wall_mask = lane_mask
		if _state != &"telegraph":
			play_telegraph(lane_mask, projectile_kind, seconds)
		else:
			_duration = _age + maxf(seconds, 0.001)

func play_attack(projectile_kind: StringName) -> void:
	if _terminal: return
	if _art != null:
		_art.signature_attack(projectile_kind)
	elif _model != null:
		_mode = SIGNATURE_MODES.get(projectile_kind, &"")
		_play_action(&"attack", 0.55 if _mode == &"quake" else 0.38)

func play_hit(_tool_kind: StringName, _damage: int) -> void:
	if _terminal: return
	if _art != null:
		_art.flash()
	elif _model != null:
		_flash_remaining = 0.14
		_flash_strength = 1.0
		_play_action(&"hurt")

func play_resist(_tool_kind: StringName) -> void:
	if _terminal: return
	if _art != null:
		_art.flash(true)
	elif _model != null:
		_flash_remaining = 0.12
		_flash_strength = 0.22

func play_defeat() -> void:
	_ensure()
	if _terminal: return
	if _art != null:
		_art.shatter()
	else:
		_capture_hitstop()
		_play_action(&"defeat")
	_terminal = true
	_tag.hide()

func play_retreat() -> void:
	if _terminal: return
	if _art != null:
		_art.react(&"retreat", 0.95)
	elif _model != null:
		# Finish the clip and dissolve before the backend's 1.0 s outro frees the visual.
		_play_action(&"retreat", 0.95)
	_terminal = true
	if _tag != null: _tag.hide()

func play_intro(seconds: float) -> void:
	_ensure()
	if _terminal: return
	intro_calls += 1
	_clock = 0.0
	_intro_tag_visible = _tag.visible
	_tag.hide()
	if _art != null:
		_art.react(&"intro", seconds)
		_art.advance(0.0)
	else:
		_cinematic_mode = &""
		position.x = 0.0
		position.y = 0.0
		_play_action(&"intro", seconds)
		_sample_pose()

func play_cinematic(mode: StringName, seconds: float) -> void:
	_ensure()
	if mode in [&"intro_full", &"intro_short"]:
		if _terminal: return
		# The legacy intro signal and the new cinematic signal can arrive on the same tick.
		if (_art != null and _art.state == &"intro") or (_model != null and _state == &"intro"):
			_age = 0.0
			_duration = maxf(seconds, 0.001)
			if _art != null:
				_art.age = 0.0
				_art.duration = _duration
		else:
			play_intro(seconds)
	elif mode in [&"defeat_full", &"defeat_short"]:
		if _model != null:
			if _hitstop_pose.is_empty(): _capture_hitstop()
			_play_action(&"defeat", seconds)
		else:
			_art.shatter()
			_art.duration = maxf(seconds, 0.001)
		_terminal = true
		_tag.hide()
	else:
		return
	_cinematic_mode = mode
	_duration = maxf(seconds, 0.001)
	_flash_remaining = 0.0
	set_cinematic_progress(mode, 0.0)

func set_cinematic_progress(mode: StringName, progress: float) -> void:
	if mode != _cinematic_mode or mode.is_empty(): return
	var u := clampf(progress, 0.0, 1.0)
	_age = u * _duration
	if _model != null:
		_sample_pose()
	elif _art != null:
		_art.age = minf(u / float(INTRO_POSE_AT[mode]), 0.999999) * _duration if mode in INTRO_POSE_AT else u * _duration
		_art.clock = _art.age
		_art.advance(0.0)
		_state = _art.state
	if u >= 1.0 and mode in [&"intro_full", &"intro_short"]:
		_cinematic_mode = &""
		_tag.visible = _intro_tag_visible
		if _model != null:
			_play_action(&"idle")
			_sample_pose()
		else:
			_art.react(&"idle", 4.0)
			_advance_fallback(0.0)

func set_time_factor(factor: float) -> void:
	_time_factor = maxf(factor, 0.0)
	if _model != null:
		_model.call("set_time_factor", _time_factor)

func socket(socket_name: StringName) -> Node3D:
	return _model.call("socket", socket_name) as Node3D if _model != null else null

func _capture_hitstop() -> void:
	_hitstop_pose.clear()
	for index in _skeleton.get_bone_count():
		_hitstop_pose.append(_skeleton.get_bone_pose(index))

func _process(delta: float) -> void:
	if _art == null and _model == null: return
	# Pause, skip and accelerated smokes all use the encounter's progress.
	if not _cinematic_mode.is_empty(): return
	var dt := maxf(delta, 0.0) * _time_factor
	if dt <= 0.0: return
	_clock += dt
	if _art != null:
		_advance_fallback(dt)
		return
	_age += dt
	_flash_remaining = maxf(_flash_remaining - dt, 0.0)
	if _age >= _duration and _state not in [&"idle", &"defeat", &"retreat"]:
		if _state == &"intro": _tag.visible = _intro_tag_visible
		_cinematic_mode = &""
		_play_action(&"idle")
	_sample_pose()
	if _state not in [&"intro", &"defeat", &"retreat"]:
		var period := maxf(sway_period * (1 - 0.12 * (_phase - 1)), 0.1)
		position.x = sin(_clock * TAU / period) * minf(sway_amplitude, 0.14)
		position.y = 0.01 + sin(_clock * 2) * 0.01

func _sample_pose() -> void:
	var progress := clampf(_age / _duration, 0, 1)
	var hitstop := minf(0.12, _duration)
	var clip := _player.get_animation(_state)
	var sample := fmod(_age, clip.length) if _state == &"idle" else progress * clip.length
	if _state == &"intro" and not _cinematic_mode.is_empty():
		# The title-card cue lands on this pose; keep it frozen until the cinematic ends.
		sample = minf(progress / float(INTRO_POSE_AT[_cinematic_mode]), 1.0) * clip.length
	if _state == &"defeat" and not _cinematic_mode.is_empty():
		sample = clampf((_age - hitstop) / maxf(_duration - hitstop, 0.001), 0.0, 1.0) * clip.length
	_skeleton.reset_bone_poses()
	_player.seek(sample, true)
	_player.advance(0.0)
	var frozen := _state == &"defeat" and not _cinematic_mode.is_empty() and _age < hitstop and not _hitstop_pose.is_empty()
	if frozen:
		for index in _hitstop_pose.size():
			_skeleton.set_bone_pose(index, _hitstop_pose[index])
	else:
		_apply_phase_and_signature(progress)
	var flash := _flash_strength * minf(_flash_remaining / 0.08, 1.0)
	if _state == &"defeat":
		if progress < 0.25:
			flash = 1.0 if int(progress * 64.0) % 2 == 0 else 0.12
		_model.call("set_dissolve", clampf((progress - 0.55) / 0.45, 0, 1))
	elif _state == &"retreat":
		_model.call("set_dissolve", smoothstep(0.72, 1.0, progress))
	_model.call("set_flash", flash)
	var heat := minf(_age / 0.12, 1.0) if _state == &"telegraph" else (1.0 if _state == &"attack" else 0.0)
	if _state == &"intro":
		var intro_progress := minf(progress / float(INTRO_POSE_AT[_cinematic_mode]), 1.0) if not _cinematic_mode.is_empty() else progress
		heat = smoothstep(0.64, 0.84, intro_progress)
	# Phase tint carries escalation; extra emission washes the CRT orange into yellow.
	var emission := 1.0 + heat * 0.7
	if _state == &"defeat":
		# Power down the reactor as the head topples; the burn edge stays emissive.
		emission *= 1.0 - smoothstep(0.45, 0.70, progress)
	elif _state == &"retreat":
		emission *= 1.0 - 0.7 * progress
	var mats: Array = _model.get("materials")
	for index in mats.size():
		mats[index].set_shader_parameter("emission_color", _emission_base[index] * Color.WHITE.lerp(Color(1.0, 0.20, 0.08), heat))
		mats[index].set_shader_parameter("emission_energy", emission)

func _offset_bone(bone_name: String, shift: Vector3) -> void:
	var index := _skeleton.find_bone(bone_name)
	if index < 0: return
	var parent := _skeleton.get_bone_parent(index)
	var basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_position(index, _skeleton.get_bone_pose_position(index) + basis.inverse() * shift)

func _apply_phase_and_signature(progress: float) -> void:
	var spread := (_phase - 1) * 0.11 + (1.0 - _health) * 0.035
	_offset_bone("shell_L", Vector3(-spread, 0, 0))
	_offset_bone("shell_R", Vector3(spread, 0, 0))
	var charge := progress if _state == &"telegraph" else (1.0 - progress if _state == &"attack" else 0.0)
	_offset_bone("reactor", Vector3(_aim * 0.07 * charge, 0, 0))
	if _mode == &"wall":
		for lane in 3:
			if _wall_mask & (1 << lane):
				_offset_bone("wall_%d" % lane, Vector3(0, 0, 0.42 * charge))
	elif _mode == &"debris" and _state == &"telegraph":
		for i in 3:
			_offset_bone("debris_%d" % i, Vector3(sin(_clock * 43.0 + i), cos(_clock * 37.0 + i), 0) * 0.035 * charge)

func _advance_fallback(delta: float) -> void:
	var was_intro: bool = _art.state == &"intro"
	_art.advance(delta)
	_state = _art.state
	_age = _art.age
	_duration = _art.duration
	if was_intro and _art.state != &"intro": _art.tag.visible = _intro_tag_visible
	if _art.state == &"intro": return
	var period := maxf(sway_period * (1 - 0.12 * (_art.phase - 1)), 0.1)
	position.x = sin(_clock * TAU / period) * minf(sway_amplitude, 0.35)
	position.y = 0.04 + sin(_clock * 2) * 0.04
	if _art.state == &"phase_change": position.y += 0.12 * sin(PI * minf(_art.age / 0.9, 1))
	if _art.state == &"retreat": position.y += minf(_art.age, 0.95) * 0.12
