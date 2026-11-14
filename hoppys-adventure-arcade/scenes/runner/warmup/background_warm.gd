extends Node
## Background GPU warm-up for the Endless Runner. gl_compatibility compiles every shader variant on
## its first draw, and macOS keeps no shader cache between launches, so the runner's warm-up
## (gpu_warmup.gd) used to spend seconds (minutes on a slow GPU) of forced draws inside the runner
## menu's _ready, behind the black route veil, with the main loop stopped: no frames, no booth
## heartbeat, and a watchdog restart once the block outlasted its hang limit. This node, added by
## AppRouter for the life of the process, does the same work while the hub sits idle instead: after
## IDLE_SECONDS without input it spends one warm-up unit (a batch build or one forced draw) per
## rendered frame on a small offscreen viewport that mirrors the runner's lighting and environment,
## so frames keep flowing between compiles. The runner menu and the game still run their own
## warm-up on entry; whatever this pass compiled, those find already compiled, so they finish in a
## fraction of the time, and anything it missed compiles there exactly as before. Any input pauses
## the pass; leaving the hub pauses it too; it resumes on the next idle hub. Once the game has run
## its own warm-up the pass is pointless and the node frees itself.
const GpuWarmup = preload("res://scenes/runner/warmup/gpu_warmup.gd")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const IDLE_SECONDS := 5.0
const STICK_DEADZONE := 0.4
## Small: shader compilation does not depend on the pixel count (measured: 4.7 s at 480x270 and at
## 3024x1898 alike), and nothing of this is ever shown.
const VIEW_SIZE := Vector2i(256, 144)
const CONTEXT := &"background"

## The hub scene path: the pass only runs while this is the current scene.
var hub_path := ""
var view: SubViewport
var camera: Camera3D
## The warm-up stage in progress (a gpu_warmup.gd node), between begin() and its last step().
var stage
var idle := 0.0
var started_at := 0
var units := 0
var finished := false

func _init(hub_scene_path: String) -> void:
	name = "RunnerBackgroundWarm"
	hub_path = hub_scene_path
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or GpuWarmup.done:
		queue_free()
		return
	view = SubViewport.new()
	view.name = "WarmView"
	view.size = VIEW_SIZE
	view.own_world_3d = true
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Materials.environment()
	view.add_child(environment)
	# The corridor's Sun, the starship key light and the deck bounce: the light types play draws
	# under, so the same shader variants compile (the warm omni in gpu_warmup.gd covers the rest).
	var sun := DirectionalLight3D.new()
	sun.light_color = Palette.MATRIX
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = false
	view.add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.15
	camera.far = 200.0
	camera.position = Vector3(0, 1.9, 3.4)
	view.add_child(camera)
	camera.look_at(Vector3(0, 1.0, -2))
	camera.current = true
	for light: Array in [["KeyLight", Color("e9edf5"), 0.35, 5.0, Vector3(0, 1.6, -2.6)],
			["DeckBounce", Color("a8c6d5"), 0.55, 12.0, Vector3(0, 3.0, -5.6)]]:
		var omni := OmniLight3D.new()
		omni.name = light[0]
		omni.light_color = light[1]
		omni.light_energy = light[2]
		omni.omni_range = light[3]
		omni.position = light[4]
		omni.shadow_enabled = false
		view.add_child(omni)

## Any press, stick push or mouse move means a visitor is here: the pass waits.
func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventJoypadButton or event is InputEventScreenTouch \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE):
		idle = 0.0

func _process(delta: float) -> void:
	if finished:
		return
	if GpuWarmup.done:
		_finish("the game warmed itself")
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != hub_path or get_tree().paused or view == null:
		return
	idle += delta
	if idle < IDLE_SECONDS:
		return
	if stage == null:
		# The CPU prewarm (textures on the main thread, audio synthesis on worker threads) goes
		# first, so the runner menu finds it done too.
		Prewarm.warm()
		stage = GpuWarmup.begin(view, camera, CONTEXT)
		if stage == null:
			_finish("nothing to do")
			return
		started_at = Time.get_ticks_msec()
		print("RUNNER WARMUP background pass started on the idle hub (%d batches)" % GpuWarmup.batches().size())
		return
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	units += 1
	if stage.step():
		stage.free()
		stage = null
		_finish("%d units; %s" % [units, GpuWarmup.summary(Time.get_ticks_msec() - started_at)])

func _finish(why: String) -> void:
	finished = true
	print("RUNNER WARMUP background pass done: %s" % why)
	queue_free()
