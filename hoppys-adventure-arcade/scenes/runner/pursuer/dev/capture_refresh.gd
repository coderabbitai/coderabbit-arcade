extends SceneTree
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
var output: String
func _initialize() -> void: call_deferred("capture")
func save_frame(title: String) -> void:
	paused = true
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(title+".png"))
	print("PURSUER CAPTURE: ", title, " save=", error)
	paused = false
func hit(game: Node) -> void:
	var hazard := load("res://scenes/runner/hazards/hazard.tscn").instantiate() as Area3D
	hazard.kind = &"pr_backlog_low"
	assert(game.hit_manager.report_hit(hazard) == &"damaged")
	hazard.free()
func capture() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1440,900)
	output = ProjectSettings.globalize_path("res://../docs/previews/overhaul/pursuer-" + ("after" if "--after" in OS.get_cmdline_user_args() else "before"))
	DirAccess.make_dir_recursive_absolute(output)
	var game = load("res://scenes/runner/runner_game.tscn").instantiate()
	game.autostart = false
	game.leaderboard_path = "user://pursuer_capture_unused.cfg"
	root.add_child(game)
	while not Prewarm.is_complete(): await process_frame
	game.start_run(12345)
	await create_timer(0.3).timeout
	hit(game)
	await create_timer(1.5).timeout
	await save_frame("pursuit")
	while game.hit_manager.is_invulnerable(): await process_frame
	hit(game)
	for i in 4:
		await create_timer(0.3).timeout
		assert(game.state == &"caught")
		await save_frame("catch-%02d" % ((i+1)*3))
	await create_timer(1).timeout
	assert(game.state == &"finished")
	await save_frame("results")
	await Cleanup.release(self,[game])
	# Isolated asset portrait uses the same spaceship lighting.
	var stage := Node3D.new()
	root.add_child(stage)
	var corridor = load("res://scenes/runner/environment/corridor.tscn").instantiate()
	stage.add_child(corridor)
	corridor.set_process(false)
	var visual = load("res://scenes/runner/pursuer/pursuer_visual.tscn").instantiate()
	stage.add_child(visual)
	visual.set_threat(1)
	visual.set_process(false)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(3.7,2.7,6.2)
	camera.look_at(Vector3(0,1.1,0))
	camera.current = true
	for i in 4: await process_frame
	await save_frame("portrait")
	await Cleanup.release(self,[stage])
	quit(0)
