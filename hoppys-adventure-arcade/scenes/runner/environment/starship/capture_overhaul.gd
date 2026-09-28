extends SceneTree
const Cases = preload("res://tests/assets/a3_check.gd")
const Pickups = preload("res://scenes/runner/powerups/visuals/power_up_art.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
var camera: Camera3D
var stage: Node3D
var objects: Node3D
var output: String

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1440,900)
	root.get_node("AudioService").music.stop()
	stage = Node3D.new()
	root.add_child(stage)
	var corridor := Corridor.instantiate()
	stage.add_child(corridor)
	while not Prewarm.is_complete(): await process_frame
	corridor.set_process(false)
	corridor._offset = 5.0
	corridor._process(0.0)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,4,8)
	camera.look_at(Vector3(0,1,-8))
	camera.fov = 60
	camera.current = true
	var hero := Hoppy.instantiate()
	stage.add_child(hero)
	hero.set_anim_state(&"run")
	hero.animation_player.seek(0.24,true)
	hero.animation_player.pause()
	hero.set_process(false)
	objects = Node3D.new()
	stage.add_child(objects)
	var phase := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	output = ProjectSettings.globalize_path("res://../docs/previews/overhaul/"+phase)
	DirAccess.make_dir_recursive_absolute(output)
	for entry in Cases.CASES:
		clear_objects()
		var hazard := Cases.spawn(entry,objects)
		hazard.position.z = -12.0
		hazard._art.advance(0.0)
		hazard.set_process(false)
		await save("hazard-"+entry[0]+("-"+entry[1] if entry[1] != "" else ""))
	clear_objects()
	for i in 3:
		var hazard := Cases.spawn(Cases.CASES[2],objects)
		hazard.position = Vector3((i-1)*2,0,[-8,-16,-28][i])
		hazard._art.advance(0.0)
		hazard.set_process(false)
	await save("bugs-range")
	for kind in Pickups.BACKED_KINDS:
		clear_objects()
		for i in 3:
			var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % kind) as PackedScene).instantiate()
			objects.add_child(visual)
			visual.position = Vector3((i-1)*2,1,[-8,-16,-28][i])
			visual.kind = kind
			visual.on_spawned()
			for tick in 40: visual._art._process(1.0/60.0)
			visual._art.set_process(false)
		await save("pickup-"+str(kind))
	hero.hide()
	for kind in Pickups.BACKED_KINDS:
		clear_objects()
		camera.position = Vector3(1.1,1.65,2.7)
		camera.look_at(Vector3(0,1,0))
		var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % kind) as PackedScene).instantiate()
		objects.add_child(visual)
		visual.position.y = 1
		visual.kind = kind
		visual.on_spawned()
		visual._art.set_process(false)
		for node in [visual._art._glyph,visual._art._pool,visual._art._tag,visual._art._tag_plate]: node.hide()
		await save("detail-"+str(kind))
	clear_objects()
	hero.show()
	camera.position = Vector3(1.35,1.4,-2.1)
	camera.look_at(Vector3(0,0.95,0))
	await save("hoppy-detail")
	await Cleanup.release(self,[stage])
	quit()

func clear_objects() -> void:
	for child in objects.get_children(): child.free()

func save(title: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output+"/"+title+".png")
	print("READABILITY CAPTURE: %s save=%d" % [title,error])
