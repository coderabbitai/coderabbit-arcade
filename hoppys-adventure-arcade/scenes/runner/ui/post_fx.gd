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
# Only tweens observed running before our pause may be resumed.
var suspended: Dictionary = {}
var signal_handlers: Dictionary = {}
var signal_paused := false
var grain_seed := 17

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
		&"boss_intro": _boss_intro, &"stage_cleared": _stage_clear,
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

func _apply() -> void:
	material.set_shader_parameter("clock", clock)
	material.set_shader_parameter("grain_seed", float(grain_seed))
	material.set_shader_parameter("grade", 0.85 * _enabled("grade"))
	material.set_shader_parameter("grain", 0.018 * _enabled("grain"))
	material.set_shader_parameter("vignette", 0.16 * _enabled("vignette"))
	material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(clock * 6.0))
	for key: String in values:
		var setting := "pursuit" if key in ["strength", "corner_bars"] else key
		material.set_shader_parameter(key, float(values[key]) * _enabled(setting))

func _process(delta: float) -> void:
	if signal_paused:
		return
	clock += delta
	_apply()

func _write(value: float, key: String) -> void:
	values[key] = value
	_apply()

func _cancel(key: String) -> void:
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
	_cancel(key)
	if not is_inside_tree():
		_write(target, key)
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
	for key: String in transitions.keys():
		_cancel(key)
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

func _boss_intro(_kind: StringName, _name: String, seconds: float) -> void:
	var entrance := minf(0.2, maxf(seconds, 0.0))
	_animate("letterbox", 1.0, entrance, maxf(0.0, seconds - entrance))

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
