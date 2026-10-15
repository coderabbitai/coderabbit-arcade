extends Node3D
## Isolated presentation fixture. Tests opt into scenery only when rendered proof is needed.
const Shots = preload("res://scenes/runner/data/run_intro_shots.gd")
signal run_started(seed: int)
signal run_intro(mode: StringName, seconds: float)
signal run_intro_beat(index: int, label: String)
signal run_intro_skipped
signal run_intro_ended
signal phase_changed(phase: StringName)
signal paused_changed(paused: bool)
signal caught
signal run_finished(result: Dictionary)
signal boss_cinematic(kind: StringName, mode: StringName, seconds: float)
signal boss_cinematic_skipped(mode: StringName)
signal boss_cinematic_ended(mode: StringName)
var run_intro_mode: StringName = &""
var run_intro_progress := 0.0
var boss_cinematic_progress := 0.0
var boss_time_factor := 1.0
var phase: StringName = &"idle"
var paused := false
var autoplay := false
var scenery := false
var seconds := 6.0
var elapsed := 0.0
var skipped := false
var emitted_beats := 0
var skip_calls := 0
var camera: Camera3D
var visual: Node3D
var ui: CanvasLayer
var post_fx: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not scenery: return
	var corridor := load("res://scenes/runner/environment/corridor.tscn").instantiate() as Node3D
	add_child(corridor)
	corridor.set_scroll_speed(0)
	visual = load("res://scenes/runner/player/hoppy_runner_visual.tscn").instantiate() as Node3D
	add_child(visual)
	visual.set_anim_state(&"idle")
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.15
	camera.far = 200
	add_child(camera)
	ui = load("res://scenes/runner/ui/run_intro.tscn").instantiate()
	add_child(ui)
	ui.bind(self)
	post_fx = load("res://scenes/runner/ui/post_fx.tscn").instantiate()
	add_child(post_fx)
	post_fx.bind(self)

func begin_intro(value: StringName = &"full") -> void:
	run_started.emit(4704)
	run_intro_mode = value
	run_intro_progress = 0
	seconds = 2.2 if value == &"short" else 6.0
	elapsed = 0
	skipped = false
	emitted_beats = 0
	paused = false
	phase = &"intro"
	phase_changed.emit(phase)
	run_intro.emit(value, seconds)
	update_visuals()

func advance_intro(delta: float) -> void:
	if paused or phase != &"intro": return
	elapsed = minf(seconds, elapsed + maxf(delta, 0))
	run_intro_progress = elapsed / seconds
	var times := [1.0, 1.6] if run_intro_mode == &"short" else [1.0, 3.0, 3.8, 4.6, 5.4]
	var labels := ["READY", "GO!"] if run_intro_mode == &"short" else ["title", "3", "2", "1", "GO!"]
	while not skipped and emitted_beats < times.size() and elapsed >= float(times[emitted_beats]):
		var index := emitted_beats
		emitted_beats += 1
		run_intro_beat.emit(index, labels[index])
	update_visuals()
	if elapsed >= seconds:
		run_intro_mode = &""
		run_intro_ended.emit()
		phase = &"run"
		phase_changed.emit(phase)

func can_skip_run_intro() -> bool:
	var final_index := 1 if run_intro_mode == &"short" else 4
	return emitted_beats <= final_index and phase == &"intro" and not paused and not skipped and elapsed >= 0.3 and elapsed < seconds - 0.4

func skip_run_intro() -> bool:
	if not can_skip_run_intro(): return false
	skip_calls += 1
	skipped = true
	elapsed = seconds - 0.4
	run_intro_progress = elapsed / seconds
	run_intro_skipped.emit()
	var final_index := 1 if run_intro_mode == &"short" else 4
	if emitted_beats <= final_index:
		emitted_beats = final_index + 1
		run_intro_beat.emit(final_index, "GO!")
	update_visuals()
	return true

func pause_intro(value: bool) -> void:
	paused = value
	paused_changed.emit(value)

func _process(delta: float) -> void:
	if autoplay: advance_intro(delta)

func update_visuals() -> void:
	if is_instance_valid(ui): ui._process(0)
	if is_instance_valid(post_fx): post_fx._process(0)
	if not is_instance_valid(camera): return
	var table: Dictionary = Shots.SHOTS.get(run_intro_mode, {})
	var keys: Array = table.get("keys", [])
	if keys.is_empty(): return
	var p := run_intro_progress
	var row: Array = keys.back()
	for i in range(1, keys.size()):
		if p > float(keys[i][0]): continue
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		var t := smoothstep(float(a[0]), float(b[0]), p)
		row = [p]
		for column in range(1, 6): row.append(lerpf(a[column], b[column], t))
		break
	var blend := 1.0 - smoothstep(float(table.ret), 1, p)
	if float(table.cut) > 0: blend *= smoothstep(0, float(table.cut), p)
	var lens := Vector3(0, row[2], row[1]).rotated(Vector3.UP, deg_to_rad(row[3]))
	var rest := Vector3(0, 4, 8)
	camera.position = rest.lerp(lens, blend)
	var follow := Basis.looking_at(Vector3(0, 1, -8) - rest).get_rotation_quaternion()
	var pose := Basis.looking_at(Vector3(0, row[5], 0) - lens).get_rotation_quaternion()
	camera.quaternion = follow.slerp(pose, blend)
	camera.fov = lerpf(60, row[4], blend)
	if is_instance_valid(visual):
		var player: AnimationPlayer = visual.get("animation_player")
		if player != null:
			var victory := player.get_animation(&"victory")
			var title_age := elapsed - 1.0
			var title_active := run_intro_mode == &"full" and title_age >= 0 and title_age < victory.length and not skipped
			var clip: StringName = &"victory" if title_active else &"idle"
			visual.set_anim_state(clip)
			# Sample the one-shot once, exactly as the real title beat's celebrate() hook.
			player.play(clip, 0)
			player.seek(title_age if title_active else 0.0, true)
			player.pause()
