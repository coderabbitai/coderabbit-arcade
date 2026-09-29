extends SceneTree
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("STARSHIP CAPTURE: graphical renderer required")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	root.get_node("AudioService").music.stop()
	var world := Node3D.new()
	root.add_child(world)
	var corridor := Corridor.instantiate()
	world.add_child(corridor)
	while not Prewarm.is_complete(): await process_frame
	corridor.set_process(false)
	corridor._offset = 5.0
	corridor._process(0.0)
	var hero := Hoppy.instantiate()
	world.add_child(hero)
	hero.set_anim_state(&"run")
	hero.set_run_speed(0.7)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 60
	var output := ProjectSettings.globalize_path("res://../docs/previews/starship")
	DirAccess.make_dir_recursive_absolute(output)
	for view in ["run","architecture","boss","turn"]:
		camera.position = Vector3(0,4,8)
		camera.look_at(Vector3(0,1,-8))
		if view == "architecture":
			camera.position = Vector3(1.4,2.1,5.0)
			camera.look_at(Vector3(-1.8,3.2,-9))
		if view == "boss":
			corridor.set_boss_arena(true)
			corridor.starship.sync(5.0,1.0,0.0,corridor.global_transform,true,2.0)
			var mount := Node3D.new()
			mount.position = Vector3(0,2.6,-14)
			world.add_child(mount)
			var boss := preload("res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.tscn").instantiate()
			mount.add_child(boss)
			boss.hover_z = -14.0
			boss.show_name_plate = false
			boss.on_spawned()
			boss._process(1.4)
			boss.set_process(false)
			mount.name = "BossFixture"
		if view == "turn":
			world.get_node("BossFixture").queue_free()
			corridor.set_boss_arena(false)
			corridor.set_turn(0.5,1)
			corridor._process(2.0)
			camera.position = corridor.transform * Vector3(0,4,8)
			camera.look_at(corridor.transform * Vector3(0,1,-8))
			hero.visible = false
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output+"/starship-"+view+".png")
		print("STARSHIP CAPTURE: %s draws=%d save=%d" % [view,root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),error])
	await Cleanup.release(self,[world])
	quit()
