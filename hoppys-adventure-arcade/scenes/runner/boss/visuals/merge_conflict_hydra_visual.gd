extends "res://scenes/runner/boss/boss_visual_base.gd"
## One visual clock drives clips, per-lane reactions, flash and cinematic dissolve.
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const BossModel = preload("res://scenes/runner/boss/hifi/boss_model.gd")
const MODEL_PATH := "res://Assets/runner/bosses/merge_conflict_hydra/merge_conflict_hydra.glb"
const ACCENT := Color("d46ad4")
const QUEUE := 6
const HEAD_RECOIL := 0.5
const PHASE_TWO_DROP := 0.30
const PHASE_TWO_HEIGHT_SCALE := 0.95
var model_path := MODEL_PATH
var _art: Art
var _model: Node3D
var _skeleton: Skeleton3D
var _tag: Label3D
var _idle_player: AnimationPlayer
var _head_players: Array[AnimationPlayer] = []
var show_name_plate := true
var intro_calls := 0
var _intro_tag_visible := false
var _clock := 0.0
var _phase := 1
var _health := 1.0
var _state: StringName = &"idle"
var _age := 0.0
var _duration := 1.0
var _time_factor := 1.0
var _flash_age := 9.0
var _flash_strength := 0.0
var _cinematic_mode: StringName = &""
var _cinematic_age := 0.0
var _cinematic_seconds := 1.0
var _terminal := false
var _queue_mask := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _queue_due := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _head_recoil := PackedFloat32Array([9.0, 9.0, 9.0, 9.0])
var _head_state: Array[StringName] = [&"", &"", &"", &""]
var _head_age := PackedFloat32Array([0, 0, 0, 0])
var _head_duration := PackedFloat32Array([1, 1, 1, 1])
var _last_head := 1
var _sprout_age := 9.0
var _fourth_bone := -1
var _crown_target_x := 0.0
var _defeat_pose: Array[Transform3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func cinematic_focus() -> Vector3:
	# Raise the faces above the title band while retaining the base rest-focus cache.
	return super.cinematic_focus() - Vector3(0, 0.3, 0)

func _ensure_model() -> void:
	if _model != null or _art != null: return
	_model = BossModel.load_model(model_path)
	if _model == null:
		_art = Art.new()
		add_child(_art)
		_art.build(&"merge_conflict_hydra")
		_tag = _art.tag
		return
	add_child(_model)
	_skeleton = _model.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_fourth_bone = _skeleton.find_bone("branch_3")
	var main: AnimationPlayer = _model.animation_player
	main.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	main.playback_default_blend_time = 0.0
	# Copies are per-instance. Lane clips contain only that branch's tracks.
	_idle_player = _clip_player(main, -2)
	for i in 4: _head_players.append(_clip_player(main, i))
	for action in [&"telegraph", &"attack", &"hurt"]:
		var clip := main.get_animation(action)
		for track in range(clip.get_track_count() - 1, -1, -1):
			if _branch_track(clip.track_get_path(track)) >= 0: clip.remove_track(track)
	for material in _model.materials: material.set_shader_parameter(&"dissolve_color", ACCENT)
	# Dev/gallery nameplate; the production BossHUD suppresses this label.
	_tag = Art.label(self, "", Vector3(0, 3.15, 0), 0.005)
	_tag.font_size = 40
	_tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED

func _branch_track(path: NodePath) -> int:
	if path.get_subname_count() == 0: return -1
	var bone := String(path.get_subname(0))
	for i in 4:
		for prefix in ["branch_", "neck_lo_", "neck_hi_", "head_", "jaw_"]:
			if bone == prefix + str(i): return i
	return -1

func _clip_player(source: AnimationPlayer, branch: int) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "HydraRest" if branch == -2 else "HydraHead%d" % branch
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	source.get_parent().add_child(player)
	player.root_node = source.root_node
	var library := AnimationLibrary.new()
	var actions: Array = [&"idle"] if branch == -2 else [&"telegraph", &"attack", &"hurt"]
	for action in actions:
		var clip := source.get_animation(action).duplicate(true) as Animation
		if branch >= 0:
			for track in range(clip.get_track_count() - 1, -1, -1):
				if _branch_track(clip.track_get_path(track)) != branch: clip.remove_track(track)
		library.add_animation(action, clip)
	player.add_animation_library(&"", library)
	return player

func on_spawned() -> void:
	_ensure_model()
	if _art != null: _art.reset()
	_phase = 1
	_health = 1.0
	_clock = 0.0
	_time_factor = 1.0
	_terminal = false
	_cinematic_mode = &""
	_cinematic_age = 0.0
	_flash_age = 9.0
	_sprout_age = 9.0
	_queue_mask.fill(0)
	_queue_due.fill(0)
	_head_recoil.fill(9.0)
	_head_state.fill(&"")
	_crown_target_x = 0.0
	_tag.text = boss_name if not boss_name.is_empty() else "Merge Conflict Hydra"
	_tag.visible = show_name_plate
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.get_node_or_null("HUD/BossHud") != null or ancestor.get_node_or_null("HUD/BossHUD") != null:
			_tag.hide()
			break
		ancestor = ancestor.get_parent()
	position = Vector3(0, 0, hover_z - get_parent_node_3d().position.z) if get_parent_node_3d() != null else Vector3(0, 0, hover_z)
	scale = Vector3.ONE
	show()
	if _model != null:
		_model.set_dissolve(0.0)
		_model.set_flash(0.0)
		_model.set_phase_tint(Color.WHITE)
		_model.set_time_factor(1.0)
	_action(&"idle")
	_process(0.0)

func _action(action: StringName, seconds: float = -1.0) -> void:
	_state = action
	_age = 0.0
	_duration = maxf(seconds, 0.001) if seconds >= 0.0 else (float(_model.animation_player.get_animation(action).length) if _model != null else 1.0)
	if _model != null:
		_model.play(action)

func set_phase(value: int) -> void:
	_ensure_model()
	var next := clampi(value, 1, phase_count)
	if _terminal: return
	if _phase < 2 and next >= 2: _sprout_age = 0.0
	_phase = next
	if _art != null:
		_art.phase = _phase
		_art.react(&"phase_change", 0.9)
	else:
		_model.set_phase_tint(Color.WHITE.lerp(Color("e5bcff"), .12 * (_phase - 1)))
	_action(&"phase_change", 1.2)

func set_health(hp: int, max_health: int) -> void:
	_ensure_model()
	_health = clampf(float(hp) / maxi(max_health, 1), 0, 1)
	if _art != null: _art.health = _health

func _head_action(head: int, action: StringName, seconds: float, delay: float = 0.0) -> void:
	_head_state[head] = action
	_head_age[head] = -delay
	_head_duration[head] = maxf(seconds, .001)
	if action == &"attack": _head_recoil[head] = -delay
	_last_head = head

func play_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	_ensure_model()
	if _terminal: return
	if _art != null: _art.signature_telegraph(lane_mask, projectile_kind, seconds)
	_action(&"telegraph", seconds)
	for lane in 3:
		if lane_mask & (1 << lane): _head_action(lane, &"telegraph", seconds)
	if projectile_kind == &"force_push" and _phase >= 2:
		_crown_target_x = _lane_midpoint(lane_mask)
		_head_action(3, &"telegraph", seconds)
	var slot := 0
	for i in QUEUE:
		if _queue_due[i] < _queue_due[slot]: slot = i
	for i in QUEUE:
		if _queue_mask[i] == 0: slot = i
	_queue_mask[slot] = lane_mask
	_queue_due[slot] = _clock + seconds

func play_commit(lane_mask: int, _projectile_kind: StringName, seconds: float) -> void:
	if _terminal: return
	if _art != null: _art.signature_commit(lane_mask, seconds)
	for lane in 3:
		if lane_mask & (1 << lane) and _head_state[lane] == &"telegraph":
			_head_duration[lane] = _head_age[lane] + maxf(seconds, .001)

func play_attack(projectile_kind: StringName) -> void:
	if _terminal or (_model == null and _art == null): return
	if _art != null: _art.signature_attack(projectile_kind)
	_action(&"attack")
	var slot := -1
	for i in QUEUE:
		if _queue_mask[i] != 0 and (slot < 0 or _queue_due[i] < _queue_due[slot]): slot = i
	var mask := _queue_mask[slot] if slot >= 0 else 0b010
	if slot >= 0: _queue_mask[slot] = 0
	var order := 0
	for lane in 3:
		if mask & (1 << lane):
			if _art != null: _art.recoil_head(_art.head_for_x((lane - 1) * 2.0), order * .07)
			_head_action(lane, &"attack", HEAD_RECOIL, order * .07)
			order += 1
	if projectile_kind == &"force_push" and _phase >= 2:
		_crown_target_x = _lane_midpoint(mask)
		_head_action(3, &"attack", HEAD_RECOIL)

func _lane_midpoint(mask: int) -> float:
	var sum := 0.0
	var count := 0
	for lane in 3:
		if mask & (1 << lane):
			sum += (lane - 1) * 2.0
			count += 1
	return sum / maxi(count, 1)

func _steer_crown() -> void:
	if _phase < 2 or _head_state[3].is_empty() or _head_age[3] < 0.0: return
	var p := clampf(_head_age[3] / _head_duration[3], 0.0, 1.0)
	var weight := smoothstep(0.0, .3, p) if _head_state[3] == &"telegraph" else 1.0 - smoothstep(.45, 1.0, p)
	for entry in [["neck_lo_3", Vector3.BACK, -.20], ["head_3", Vector3.UP, .24]]:
		var bone := _skeleton.find_bone(entry[0])
		var rest := _skeleton.get_bone_global_rest(bone).basis.get_rotation_quaternion()
		var turn := Quaternion(entry[1], _crown_target_x * weight * float(entry[2]))
		_skeleton.set_bone_pose_rotation(bone, rest.inverse() * turn * rest * _skeleton.get_bone_pose_rotation(bone))

func play_hit(_tool_kind: StringName, _damage: int) -> void:
	if _terminal: return
	if _art != null: _art.flash()
	if _model != null:
		_action(&"hurt")
		_head_action(_last_head, &"hurt", .35)
	_flash_age = 0.0
	_flash_strength = 1.0

func play_resist(_tool_kind: StringName) -> void:
	if _terminal: return
	if _art != null: _art.flash(true)
	_flash_age = 0.0
	_flash_strength = .22

func play_defeat() -> void:
	_ensure_model()
	if not _terminal and _skeleton != null:
		_defeat_pose.clear()
		for i in _skeleton.get_bone_count(): _defeat_pose.append(_skeleton.get_bone_pose(i))
	_terminal = true
	_queue_mask.fill(0)
	_head_state.fill(&"")
	_tag.hide()
	if _art != null: _art.shatter()
	_action(&"defeat", .95)

func play_retreat() -> void:
	_ensure_model()
	_terminal = true
	_cinematic_mode = &""
	_queue_mask.fill(0)
	_head_state.fill(&"")
	_tag.hide()
	if _art != null: _art.react(&"retreat", .95)
	_action(&"retreat", .95)

func play_intro(seconds: float) -> void:
	_ensure_model()
	intro_calls += 1
	_clock = 0.0
	_terminal = false
	_cinematic_mode = &""
	if _state != &"intro": _intro_tag_visible = _tag.visible
	_tag.hide()
	_head_state.fill(&"")
	_action(&"intro", seconds)
	if _art != null:
		_art.react(&"intro", seconds)
		_art.advance(0.0)
	else:
		_sample(_model.animation_player, &"intro", 0.0)
		_apply_fourth()

func play_cinematic(mode: StringName, seconds: float) -> void:
	if mode not in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]: return
	_ensure_model()
	if String(mode).begins_with("intro"):
		play_intro(seconds)
	else:
		play_defeat()
		if _model != null: _model.set_dissolve(0.0)
	_cinematic_mode = mode
	_cinematic_seconds = maxf(seconds, .001)
	_cinematic_age = 0.0
	_process(0.0)

## Backend progress owns cinematic time, including skip jumps and slow-motion tails.
func set_cinematic_progress(mode: StringName, progress: float) -> void:
	if mode != _cinematic_mode or _cinematic_mode.is_empty(): return
	_cinematic_age = clampf(progress, 0.0, 1.0) * _cinematic_seconds
	_tick_cinematic()
	if _model != null: _apply_fourth()

func set_time_factor(factor: float) -> void:
	_time_factor = maxf(factor, 0.0)
	if _model != null: _model.set_time_factor(_time_factor)

func socket(key: StringName) -> Node3D:
	return _model.socket(key) if _model != null else null

func _sample(player: AnimationPlayer, action: StringName, seconds: float) -> void:
	if player.current_animation != action: player.play(action, 0.0)
	player.seek(seconds, true)

func _apply_fourth() -> void:
	if _fourth_bone < 0: return
	if String(_cinematic_mode).begins_with("defeat") and _cinematic_age < minf(.12, _cinematic_seconds * .08): return
	var growth := smoothstep(.24, .94, _sprout_age) if _phase >= 2 else 0.0
	# Keep the crown/centre crest spacing while fitting the entire phase-two rig
	# inside the contract's world y [1.6, 6.1], including hurt and force-push poses.
	_model.position.y = -PHASE_TWO_DROP * growth
	_model.scale.y = lerpf(1.0, PHASE_TWO_HEIGHT_SCALE, growth)
	var amount := lerpf(.001, 1.0, growth)
	_skeleton.set_bone_pose_scale(_fourth_bone, Vector3.ONE * amount)

func _process(delta: float) -> void:
	if (_model == null and _art == null) or (is_inside_tree() and get_tree().paused): return
	var dt := maxf(delta, 0.0) * _time_factor
	_clock += dt
	_age += dt
	_flash_age += dt
	_sprout_age += dt
	if _art != null and _cinematic_mode.is_empty():
		var was_intro := _art.state == &"intro"
		_art.advance(dt)
		_state = &"defeat" if _art.state == &"defeated" else _art.state
		if was_intro and _art.state != &"intro": _tag.visible = _intro_tag_visible
	if _model != null:
		_model.set_flash(_flash_strength * (1.0 - smoothstep(0.0, .18, _flash_age)))
	if not _cinematic_mode.is_empty():
		_tick_cinematic()
	elif _model != null:
		_tick_action(dt)
	if _model != null: _apply_fourth()
	if not _terminal and _state != &"intro":
		var period := maxf(sway_period * (1.0 - .12 * (_phase - 1)), .1)
		position.x = sin(_clock * TAU / period) * minf(sway_amplitude, .12)
		position.y = .04 + sin(_clock * 2) * .04

func _tick_action(dt: float) -> void:
	var main: AnimationPlayer = _model.animation_player
	if _state not in [&"idle", &"defeat", &"retreat"] and _age >= _duration:
		if _state == &"intro": _tag.visible = _intro_tag_visible
		_action(&"idle")
	var clip: Animation = main.get_animation(_state)
	var t := fmod(_clock, clip.length) if _state == &"idle" else clampf(_age / _duration, 0.0, 1.0) * clip.length
	# Reset all branch channels before sparse head overlays, preventing stale jaw poses.
	_sample(_idle_player, &"idle", fmod(_clock, _idle_player.get_animation(&"idle").length))
	_sample(main, _state, t)
	for i in 4:
		_head_age[i] += dt
		if _head_recoil[i] < HEAD_RECOIL: _head_recoil[i] += dt
	if not _terminal and _state != &"intro" and _state != &"phase_change":
		for i in 4:
			if _head_state[i].is_empty() or _head_age[i] < 0.0: continue
			if _head_age[i] >= _head_duration[i]:
				_head_state[i] = &""
				continue
			var head_clip := _head_players[i].get_animation(_head_state[i])
			_sample(_head_players[i], _head_state[i], _head_age[i] / _head_duration[i] * head_clip.length)
		_steer_crown()
	if _state == &"defeat": _model.set_dissolve(clampf((_age / _duration - .55) / .45, 0.0, 1.0))
	if _state == &"retreat" and _age >= _duration: hide()

func _tick_cinematic() -> void:
	var p := clampf(_cinematic_age / _cinematic_seconds, 0.0, 1.0)
	var intro := String(_cinematic_mode).begins_with("intro")
	var pose_progress := minf(p / float(INTRO_POSE_AT[_cinematic_mode]), 1.0) if intro else p
	if _art != null:
		# Reuse the original geometry and reactions when the GLB is unavailable.
		_art.state = &"intro" if intro else &"defeated"
		_art.duration = 1.0
		_art.age = minf(pose_progress, .9999) if intro else p
		# The procedural head and neck sway also freezes when the title pose lands.
		_art.clock = minf(p, float(INTRO_POSE_AT[_cinematic_mode])) * _cinematic_seconds if intro else _cinematic_age
		_art.advance(0.0)
	if intro:
		if _model != null:
			# Land with the title slam, holding through INTRO_HOLD_UNTIL and camera return.
			var clip: Animation = _model.animation_player.get_animation(&"intro")
			_sample(_model.animation_player, &"intro", clip.length * pose_progress)
		if p >= 1.0:
			_cinematic_mode = &""
			_tag.visible = _intro_tag_visible
			_action(&"idle")
			if _art != null:
				_art.react(&"idle", 1.0)
				_art.advance(0.0)
	else:
		if _model != null:
			var stop := minf(.12 / _cinematic_seconds, .08)
			var clip: Animation = _model.animation_player.get_animation(&"defeat")
			if p < stop and _defeat_pose.size() == _skeleton.get_bone_count():
				for i in _defeat_pose.size():
					var held := _defeat_pose[i]
					_skeleton.set_bone_pose_position(i, held.origin)
					_skeleton.set_bone_pose_rotation(i, held.basis.get_rotation_quaternion())
					_skeleton.set_bone_pose_scale(i, held.basis.get_scale())
			else:
				_sample(_model.animation_player, &"defeat", clip.length * smoothstep(stop, .88, p))
			_model.set_flash((1.0 if int(_cinematic_age * 24.0) % 2 == 0 else .08) if p < .25 else 0.0)
			_model.set_dissolve(clampf((p - .55) / .45, 0.0, 1.0))
