extends SceneTree
## Standalone F0/F1 checks. Every engine/script error after initialization fails.
var failures := 0
var _errors := ErrorCapture.new()

class ErrorCapture extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != 1: # Logger warning, not an engine/script/shader error.
			count += 1

func _initialize() -> void:
	OS.add_logger(_errors)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("CHECK FAILED: ", message)

func frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func run() -> void:
	var scene := load("res://scenes/runner/environment/corridor.tscn") as PackedScene
	check(scene != null, "Corridor resource loads")
	if scene != null:
		var corridor := scene.instantiate()
		root.add_child(corridor)
		corridor.set_scroll_speed(12.0)
		corridor.set_pursuit(0.5)
		await frames()
		check(corridor.name == "Corridor" and corridor is Node3D, "Contract root")
		check(is_equal_approx(root.scaling_3d_scale, 0.5), "Retro scale set")
		check(corridor.get_node("Pillars").multimesh.instance_count == 24, "24 recycled pillars")
		check(corridor.get_node("Rain").amount == 320, "320 rain particles")
		corridor.set_process(false)
		for speed in [0.0, 4.0, 8.0, 12.0, 16.0, 24.0, 26.0, 32.0]:
			corridor.set_scroll_speed(speed)
			var before: float = corridor._offset
			corridor._process(0.25)
			check(is_equal_approx(corridor._offset, fposmod(before + speed * 0.25, 96.0)), "Scroll distance at %s" % speed)
		corridor._offset = 95.0
		corridor.set_scroll_speed(26.0)
		corridor._process(1.0)
		check(is_equal_approx(corridor._offset, 25.0), "Scroll wraps without loss")
		var positions: PackedFloat32Array = corridor.pillar_z_positions()
		check(positions.size() == 24, "CPU pillar count")
		for i in positions.size():
			check(positions[i] > -88.0 and positions[i] <= 8.0, "Pillar wrap bounds")
			check(is_equal_approx(positions[i], 8.0 - fposmod(float(i % 12) * 8.0 - 25.0, 96.0)), "CPU pillar wrapped position")
		corridor.set_process(true)
		paused = true
		var offset: float = corridor._offset
		var clock: float = corridor._clock
		await frames()
		check(corridor._offset == offset and corridor._clock == clock, "Pause freezes shader clocks and pillars")
		check(not corridor.get_node("Rain").can_process(), "Rain inherits pause")
		paused = false
		corridor.free()
		check(is_equal_approx(root.scaling_3d_scale, 1.0), "Corridor restores scale")
	if scene != null:
		# Check both removal orders, different exports, and a non-default baseline.
		for oldest_first in [true, false]:
			root.scaling_3d_scale = 0.8
			var first := scene.instantiate()
			var second := scene.instantiate()
			second.retro_scale = 0.6
			root.add_child(first)
			root.add_child(second)
			if oldest_first:
				first.free()
				check(is_equal_approx(root.scaling_3d_scale, 0.6), "Older exit preserves newer scale")
				second.free()
			else:
				second.free()
				check(is_equal_approx(root.scaling_3d_scale, 0.5), "Newer exit restores older scale")
				first.free()
			check(is_equal_approx(root.scaling_3d_scale, 0.8), "Last exit restores original scale")
		var overridden := scene.instantiate()
		root.add_child(overridden)
		root.scaling_3d_scale = 0.9
		overridden.free()
		check(is_equal_approx(root.scaling_3d_scale, 0.9), "External scaling change preserved")
		root.scaling_3d_scale = 1.0
	var spike_scene := load("res://scenes/runner/environment/dev/renderer_spike.tscn") as PackedScene
	check(spike_scene != null, "Spike resource loads")
	if spike_scene != null:
		root.scaling_3d_scale = 0.8
		var previous_mode := root.scaling_3d_mode
		var spike := spike_scene.instantiate()
		root.add_child(spike)
		await frames()
		check(is_equal_approx(root.scaling_3d_scale, 0.5), "Spike starts at 50 percent")
		var toggle := InputEventKey.new()
		toggle.physical_keycode = KEY_R
		toggle.pressed = true
		for expected_scale in [1.0, 0.5]:
			spike._unhandled_key_input(toggle)
			check(is_equal_approx(root.scaling_3d_scale, expected_scale), "Spike R toggles 50/100 percent")
		spike.free()
		check(is_equal_approx(root.scaling_3d_scale, 0.8), "Spike restores original scale")
		check(root.scaling_3d_mode == previous_mode, "Spike restores original mode")
		root.scaling_3d_scale = 1.0
	var preview_scene := load("res://scenes/runner/environment/dev/corridor_preview.tscn") as PackedScene
	if preview_scene != null:
		var preview := preview_scene.instantiate()
		root.add_child(preview)
		await frames()
		for key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_P]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.pressed = true
			preview._unhandled_key_input(event)
			if key != KEY_P:
				check(preview._speed == [0.0, 4.0, 8.0, 12.0, 16.0, 26.0, 32.0][key - KEY_1], "Preview speed key %s" % key)
		check(preview._speed == 32.0 and preview._pursuit, "Preview speed and pursuit controls")
		var camera := root.get_camera_3d()
		check(camera.position == Vector3(0, 4, 8) and camera.fov == 60.0, "Contract camera")
		preview.free()
	else:
		check(false, "Preview loads")
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	await frames()
	failures += _errors.count
	print("ENV CHECK: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	OS.remove_logger(_errors)
	quit(failures)
