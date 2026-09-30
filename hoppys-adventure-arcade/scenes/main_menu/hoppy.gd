extends Node2D
## Menu-only presentation. Both versions share a ground anchor and the menu's input selection.
const PLATFORMER = preload("res://Assets/Character/Hoppy/2D/hoppy-sprite-pack/hoppy/platformer.tres")
const BRAWLER = preload("res://Assets/Character/Hoppy/2D/hoppy-sprite-pack/hoppy/brawler.tres")
const RUNNER = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
@export var sprite_scale := 3.0
@export var transition_seconds := 0.22
var reaction := -1:
	set(value):
		if reaction == value:
			return
		reaction = value
		if is_node_ready():
			_apply_reaction()
var sprite: AnimatedSprite2D
var runner_view: SubViewport
var runner_image: Sprite2D
var runner: Node3D
var fade: Tween

func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "Hoppy2D"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = PLATFORMER
	sprite.offset = Vector2(0, -40)
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.flip_h = true # Face the mode buttons.
	add_child(sprite)
	sprite.animation_finished.connect(_finish_reaction)
	_build_runner()
	_apply_reaction()

func _build_runner() -> void:
	runner_view = SubViewport.new()
	runner_view.name = "RunnerPortrait"
	runner_view.size = Vector2i(512, 512)
	runner_view.transparent_bg = true
	runner_view.own_world_3d = true
	runner_view.gui_disable_input = true
	runner_view.msaa_3d = Viewport.MSAA_4X
	add_child(runner_view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff1df")
	environment.environment.ambient_light_energy = 0.65
	runner_view.add_child(environment)
	runner = RUNNER.instantiate()
	runner_view.add_child(runner)
	runner.set_anim_state(&"run")
	runner.set_run_speed(0.25)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(-2.8, 1.6, -5)
	runner_view.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.3
	runner_view.add_child(light)
	runner_image = Sprite2D.new()
	runner_image.name = "Hoppy3D"
	runner_image.texture = runner_view.get_texture()
	runner_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	runner_image.scale = Vector2.ONE * (300.0 / 512.0)
	runner_image.position = Vector2(0, -116)
	runner_image.modulate.a = 0
	runner_image.visible = false
	add_child(runner_image)
	_suspend_runner()

func _apply_reaction() -> void:
	if fade:
		fade.kill()
	var use_runner := reaction == 1
	if use_runner:
		runner.process_mode = Node.PROCESS_MODE_INHERIT
		runner_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		runner_image.show()
		sprite.stop()
	else:
		sprite.sprite_frames = BRAWLER if reaction == 2 else PLATFORMER
		sprite.play(&"jab" if reaction == 2 else (&"jump" if reaction == 0 else &"idle"))
	fade = create_tween().set_parallel(true)
	fade.tween_property(sprite, "modulate:a", 0.0 if use_runner else 1.0, transition_seconds)
	fade.tween_property(runner_image, "modulate:a", 1.0 if use_runner else 0.0, transition_seconds)
	if not use_runner:
		fade.chain().tween_callback(_suspend_runner)

func _finish_reaction() -> void:
	# Both one-shot reactions settle into the same calm menu idle.
	sprite.sprite_frames = PLATFORMER
	sprite.play(&"idle")

func _suspend_runner() -> void:
	runner_image.hide()
	runner_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	runner.process_mode = Node.PROCESS_MODE_DISABLED

func _draw() -> void:
	# Shared contact shadow keeps both presentations grounded during a crossfade.
	draw_set_transform(Vector2(0, 8), 0, Vector2(1, 0.16))
	draw_circle(Vector2.ZERO, 70, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
