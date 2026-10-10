extends CanvasLayer
## A single Compatibility post draw. Mount above world and below ungraded UI (layer > 9).
const PostGrade = preload("res://scenes/runner/shaders/post_grade.gdshader")
const DEFAULT_SETTINGS := {"grade": true, "grain": true, "vignette": true, "pursuit": false, "aberration": true, "letterbox": true, "speed": true, "bloom_lift": true}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var material := ShaderMaterial.new()
var screen := ColorRect.new()
var clock := 0.0
var game: Node
var values := {"strength": 0.0, "corner_bars": 0.0, "aberration": 0.0, "letterbox": 0.0, "speed": 0.0, "bloom_lift": 0.0}
var transitions: Dictionary = {}
## Hold-free transitions (speed, pursuit, Nitro bloom) retarget every tick; they ease here in
## _process instead of allocating a Tween per physics step. key -> {from, to, age, seconds}.
var channels: Dictionary = {}
## Last value written per uniform, so unchanged uniforms are not re-sent every frame.
var _written: Dictionary = {}
# Only tweens observed running before our pause may be resumed.
var suspended: Dictionary = {}
var signal_handlers: Dictionary = {}
var signal_paused := false
var grain_seed := 17
var cinematic_hold := false
var cinematic_released := false
var cinematic_seconds := 1.0
var cinematic_skip_tail := 0.3

func _init() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material.shader = PostGrade
	screen.name = "PostPass"
	screen.material = material
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.process_mode = Node.PROCESS_MODE_PAUSABLE
	screen.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	signal_handlers = {
		&"run_started": _run_started, &"damage_taken": _damage, &"tool_collected": _tool,
		&"pursuit_started": _pursuit_started, &"pursuit_progress": _pursuit_progress,
		&"pursuit_recovered": _recovered, &"caught": _caught,
		&"speed_changed": _speed, &"power_up_collected": _power_up, &"power_up_expired": _expired,
		&"boss_cinematic": _boss_cinematic, &"boss_cinematic_skipped": _boss_skipped, &"boss_cinematic_ended": _boss_ended, &"stage_cleared": _stage_clear,
		&"phase_changed": _phase, &"run_finished": _finished, &"paused_changed": _paused,
	}
	_apply()

func bind(runner: Node) -> void:
	if game == runner:
		return
	if is_instance_valid(game):
		for event: StringName in signal_handlers:
			if game.has_signal(event) and game.is_connected(event, signal_handlers[event]):
				game.disconnect(event, signal_handlers[event])
	game = runner
	_reset()
	if not is_instance_valid(game):
		return
	for event: StringName in signal_handlers:
		if game.has_signal(event) and not game.is_connected(event, signal_handlers[event]):
			game.connect(event, signal_handlers[event])

func set_settings(overrides: Dictionary) -> void:
	for key: String in DEFAULT_SETTINGS:
		if overrides.has(key):
			settings[key] = bool(overrides[key])
	_apply()

func _enabled(key: String) -> float:
	return 1.0 if bool(settings.get(key, true)) else 0.0

func _uniform(key: String, value: float) -> void:
	if _written.get(key) != value:
		_written[key] = value
		material.set_shader_parameter(key, value)

func _apply() -> void:
	_uniform("clock", clock)
	_uniform("grain_seed", float(grain_seed))
	_uniform("grade", 0.85 * _enabled("grade"))
	_uniform("grain", 0.018 * _enabled("grain"))
	_uniform("vignette", 0.16 * _enabled("vignette"))
	_uniform("pulse", 0.5 + 0.5 * sin(clock * 6.0))
	for key: String in values:
		var setting := "pursuit" if key in ["strength", "corner_bars"] else key
		_uniform(key, float(values[key]) * _enabled(setting))

func _process(delta: float) -> void:
	if signal_paused:
		return
	if is_instance_valid(game) and "boss_time_factor" in game:
		delta *= float(game.get("boss_time_factor"))
	clock += delta
	for key: String in channels.keys():
		var channel: Dictionary = channels[key]
		channel.age += delta
		var t := minf(1.0, channel.age / channel.seconds)
		# Same curve the per-tick Tween used: TRANS_QUAD, EASE_OUT.
		values[key] = lerpf(channel.from, channel.to, 1.0 - (1.0 - t) * (1.0 - t))
		if t >= 1.0:
			channels.erase(key)
	if cinematic_hold and is_instance_valid(game):
		var p := clampf(float(game.get("boss_cinematic_progress")), 0, 1)
		values.letterbox = smoothstep(0.0, 0.18, p * cinematic_seconds) if not cinematic_released else 1.0 - smoothstep(1.0 - minf(cinematic_skip_tail / cinematic_seconds, 1.0), 1.0, p)
	_apply()

func _write(value: float, key: String) -> void:
	values[key] = value
	_apply()

func _cancel(key: String) -> void:
	channels.erase(key)
	if transitions.has(key):
		var old: Tween = transitions[key]
		if old.is_valid():
			old.kill()
		transitions.erase(key)
	suspended.erase(key)

func _transition_finished(key: String, instance_id: int) -> void:
	# A replaced tween must never erase the newer transition under the same key.
	if transitions.has(key) and transitions[key].get_instance_id() == instance_id:
		transitions.erase(key)
		suspended.erase(key)

func _suspend(key: String, tween: Tween) -> void:
	if tween.is_valid() and tween.is_running():
		suspended[key] = tween.get_instance_id()
		tween.pause()

func _animate(key: String, target: float, seconds: float = 0.18, hold: float = -1.0) -> void:
	if hold < 0.0 and channels.has(key) and is_equal_approx(channels[key].to, target):
		return
	_cancel(key)
	if not is_inside_tree():
		_write(target, key)
		return
	if hold < 0.0:
		channels[key] = {"from": float(values[key]), "to": target, "age": 0.0, "seconds": maxf(seconds, 0.001)}
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	transitions[key] = tween
	tween.finished.connect(_transition_finished.bind(key, tween.get_instance_id()), CONNECT_ONE_SHOT)
	tween.tween_method(_write.bind(key), float(values[key]), target, maxf(seconds, 0.001)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if hold >= 0.0:
		tween.tween_interval(hold)
		tween.tween_method(_write.bind(key), target, 0.0, 0.22).set_trans(Tween.TRANS_SINE)
	if signal_paused:
		_suspend(key, tween)

func _reset() -> void:
	cinematic_hold = false
	cinematic_released = false
	for key: String in transitions.keys():
		_cancel(key)
	channels.clear()
	for key: String in values:
		values[key] = 0.0
	clock = 0.0
	signal_paused = false
	_apply()

func _run_started(seed_value: int) -> void:
	_reset()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	grain_seed = random.randi_range(1, 4095)
	_apply()

func _damage(_kind: StringName, _hp: int) -> void:
	_animate("aberration", 1.0, 0.035, 0.015)

func _tool(_kind: StringName, damage: int) -> void:
	if damage > 0:
		_animate("aberration", 0.42, 0.025, 0.0)

func _pursuit_started(seconds: float) -> void:
	_pursuit_progress(seconds, seconds)

func _pursuit_progress(remaining: float, total: float) -> void:
	var threat := 1.0 - clampf(remaining / maxf(total, 0.001), 0.0, 1.0)
	_animate("strength", 0.25 + 0.6 * threat, 0.08)
	_animate("corner_bars", threat, 0.08)

func _recovered(_reason: StringName) -> void:
	_animate("strength", 0.0, 0.3)
	_animate("corner_bars", 0.0, 0.3)

func _caught() -> void:
	_animate("strength", 1.0)
	_animate("corner_bars", 0.0)

func _speed(_meters: float, normalized: float) -> void:
	_animate("speed", clampf(normalized, 0.0, 1.0), 0.1)

func _power_up(kind: StringName, _duration: float) -> void:
	if kind == &"nitro":
		_animate("bloom_lift", 1.0, 0.15)

func _expired(kind: StringName) -> void:
	if kind == &"nitro":
		_animate("bloom_lift", 0.0, 0.35)

func _boss_cinematic(_kind: StringName, _mode: StringName, seconds: float) -> void:
	_cancel("letterbox")
	cinematic_hold = true
	cinematic_released = false
	cinematic_seconds = maxf(seconds, 0.001)
	cinematic_skip_tail = 0.3
	if is_instance_valid(game) and "config" in game:
		var config: Resource = game.get("config")
		if config != null and "boss_cinematic_skip_tail" in config:
			cinematic_skip_tail = maxf(0.001, float(config.get("boss_cinematic_skip_tail")))
	_process(0.0)

func _boss_skipped(_mode: StringName) -> void:
	cinematic_released = true
	_process(0.0)

func _boss_ended(_mode: StringName) -> void:
	cinematic_hold = false
	cinematic_released = false
	_animate("letterbox", 0.0, 0.18)

func _stage_clear(_index: int, _bonus: int) -> void:
	# Matches the existing stage_clear.gd card's 2.8 second lifetime.
	_animate("letterbox", 1.0, 0.18, 2.4)

func _phase(phase: StringName) -> void:
	if phase == &"idle":
		_reset()
	elif phase in [&"run", &"turn"]:
		_animate("letterbox", 0.0)

func _finished(_result: Dictionary) -> void:
	_reset()

func _paused(value: bool) -> void:
	signal_paused = value
	for key: String in transitions.keys():
		var tween: Tween = transitions[key]
		if not tween.is_valid():
			transitions.erase(key)
			suspended.erase(key)
		elif value:
			_suspend(key, tween)
		elif suspended.get(key, 0) == tween.get_instance_id():
			# pause() makes is_running() false. Resume only our recorded live pause,
			# never an arbitrary non-running tween (which may already be finished).
			suspended.erase(key)
			if not tween.is_running():
				tween.play()

func _exit_tree() -> void:
	bind(null)
	for key: String in transitions.keys():
		_cancel(key)
