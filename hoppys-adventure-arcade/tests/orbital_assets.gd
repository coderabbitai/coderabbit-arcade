extends SceneTree

const BASE = "res://Assets/orbital-ops-assets-only/"
var manifest: Dictionary
var stage: Node2D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE + "orbital_ops/manifest.json"))
	var clips := 0
	var frames := 0
	for key in manifest.atlases:
		var spec: Dictionary = manifest.atlases[key]
		var resource := load(BASE + "orbital_ops/" + spec.resource) as SpriteFrames
		assert(resource != null, key)
		assert(resource.get_animation_names().size() == spec.clips.size(), key)
		for clip in spec.clips:
			assert(resource.has_animation(clip.name), clip.name)
			assert(resource.get_frame_count(clip.name) == clip.frames.size(), clip.name)
			assert(resource.get_animation_loop(clip.name) == clip.loop, clip.name)
			for i in resource.get_frame_count(clip.name):
				var texture := resource.get_frame_texture(clip.name, i) as AtlasTexture
				assert(texture != null and texture.atlas != null, clip.name)
				assert(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), clip.name)
				assert(texture.get_image().get_used_rect().has_area(), clip.name)
			clips += 1
		frames += spec.frames.size()
	for bg in manifest.backgrounds.values():
		var texture := load(BASE + "orbital_ops/" + bg.file) as Texture2D
		assert(texture.get_size() == Vector2(960, 540), bg.file)
	print("PASS: Orbital Ops — ", frames, " frames, ", clips, " named clips, 5 SpriteFrames resources, 2 background plates.")
	if DisplayServer.get_name() == "headless":
		await finish()
		return
	root.size = Vector2i(1280,720)
	stage = Node2D.new()
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(stage)
	plate("starfield", Vector2.ZERO, Vector2(1280,720))
	plate("station_hull", Vector2(0,65), Vector2(1280,720), 0.65)
	for x in range(0,1280,128):
		piece("station_kit", "floor_slab", Vector2(x,600), Vector2(130,50))
	piece("station_kit", "foreground_strut", Vector2(40,180), Vector2(65,390))
	piece("station_kit", "orbital_ring", Vector2(960,125), Vector2(210,210))
	piece("station_kit", "scaffold_horizontal", Vector2(430,420), Vector2(270,68))
	piece("station_kit", "service_platform", Vector2(710,290), Vector2(180,80))
	piece("station_kit", "terminal", Vector2(120,485), Vector2(90,115))
	actor("rogue_ai", "walk", Vector2(425,601), 1.55)
	actor("deprecated_api", "idle", Vector2(1045,601), 1.55)
	actor("security_drone", "hover", Vector2(635,328), 1.65)
	piece("hazards", "laser_warning", Vector2(545,500), Vector2(90,100))
	piece("hazards", "vent_active", Vector2(775,468), Vector2(130,132))
	piece("hazards", "zero_g_beacon", Vector2(725,230), Vector2(70,60))
	var hoppy := AnimatedSprite2D.new()
	hoppy.sprite_frames = load("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
	hoppy.animation = "idle"
	hoppy.position = Vector2(285, 545)
	hoppy.scale = Vector2(1.7,1.7)
	stage.add_child(hoppy)
	var title := Label.new()
	title.text = "ORBITAL OPS"
	title.position = Vector2(65,42)
	title.add_theme_font_size_override("font_size",42)
	stage.add_child(title)
	var note := Label.new()
	note.text = "ASSET STAGING  /  DEPRECATED API + STATION KIT\nVisual scale study — gameplay assembly comes next"
	note.position = Vector2(68,99)
	note.add_theme_font_size_override("font_size",17)
	note.modulate = Color("97dce9")
	stage.add_child(note)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(BASE + "orbital-ops-preview.png")
	assert(error == OK)
	print("Saved rendered Orbital Ops staging preview.")
	await finish()

func finish() -> void:
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	quit()

func plate(key: String, pos: Vector2, size: Vector2, opacity: float = 1.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(BASE + "orbital_ops/" + key + ".png")
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size / sprite.texture.get_size()
	sprite.modulate.a = opacity
	stage.add_child(sprite)

func actor(key: String, clip: String, pos: Vector2, magnify: float) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load(BASE + "orbital_ops/" + key + ".tres")
	sprite.animation = clip
	var spec: Dictionary = manifest.atlases[key]
	sprite.offset = Vector2(spec.cell[0]/2.0-spec.pivot[0],spec.cell[1]/2.0-spec.pivot[1])
	sprite.position = pos
	sprite.scale = Vector2.ONE*magnify
	stage.add_child(sprite)

func piece(key: String, clip: String, pos: Vector2, size: Vector2) -> void:
	var spec: Dictionary = manifest.atlases[key]
	var index := 0
	for c in spec.clips:
		if c.name == clip:
			index = int(c.frames[0])
	var frame: Dictionary = spec.frames[index]
	var b: Array = frame.visible_bounds
	var texture := AtlasTexture.new()
	texture.atlas = load(BASE + "orbital_ops/" + key + ".png")
	texture.region = Rect2(frame.rect[0]+b[0],frame.rect[1]+b[1],b[2]-b[0],b[3]-b[1])
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size/texture.get_size()
	stage.add_child(sprite)
