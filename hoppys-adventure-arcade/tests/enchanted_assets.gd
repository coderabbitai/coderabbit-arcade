extends SceneTree

const BASE = "res://Assets/enchanted-repo-assets-only/"
var manifest: Dictionary
var stage: Node2D
var failures := 0

func check(condition: bool, context: String) -> void:
	if not condition:
		failures += 1
		printerr("FAILED: ", context)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE + "enchanted_repo/manifest.json"))
	var clips := 0
	var frames := 0
	for key in manifest.atlases:
		var spec: Dictionary = manifest.atlases[key]
		var resource := load(BASE + "enchanted_repo/" + spec.resource) as SpriteFrames
		check(resource != null, key)
		if resource == null:
			continue
		check(resource.get_animation_names().size() == spec.clips.size(), key)
		for clip in spec.clips:
			check(resource.has_animation(clip.name), clip.name)
			if not resource.has_animation(clip.name):
				continue
			check(resource.get_frame_count(clip.name) == clip.frames.size(), clip.name)
			check(is_equal_approx(resource.get_animation_speed(clip.name), float(clip.fps)), clip.name)
			check(resource.get_animation_loop(clip.name) == clip.loop, clip.name)
			for i in resource.get_frame_count(clip.name):
				var texture := resource.get_frame_texture(clip.name, i) as AtlasTexture
				check(texture != null and texture.atlas != null, clip.name)
				if texture == null or texture.atlas == null:
					continue
				check(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), clip.name)
				var image := texture.get_image()
				check(image != null and image.get_used_rect().has_area(), clip.name)
			clips += 1
		frames += spec.frames.size()
	for bg in manifest.backgrounds.values():
		var texture := load(BASE + "enchanted_repo/" + bg.file) as Texture2D
		check(texture != null, bg.file)
		if texture == null:
			continue
		check(texture.get_size() == Vector2(960, 540), bg.file)
	check(frames == 104 and clips == 78, "Complete frame/state inventory")
	check(manifest.atlases.size() == 6 and manifest.backgrounds.size() == 2, "Complete resource inventory")
	if failures > 0:
		printerr(failures, " Enchanted Repo asset checks failed")
		await finish(1)
		return
	print("PASS: Enchanted Repo — ", frames, " frames, ", clips, " named clips, 6 SpriteFrames resources, 2 background plates.")
	if DisplayServer.get_name() == "headless":
		await finish()
		return
	root.size = Vector2i(1280,720)
	stage = Node2D.new()
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(stage)
	plate("sky", Vector2.ZERO, Vector2(1280,720))
	plate("treeline", Vector2.ZERO, Vector2(1280,720), 0.7)
	for x in range(0,1280,128):
		piece("forest_kit", "ground_slab" if x < 768 else "arena_slab", Vector2(x,604), Vector2(130,100))
	piece("forest_kit", "castle_arch", Vector2(1030,310), Vector2(185,290))
	piece("forest_kit", "root_platform", Vector2(385,395), Vector2(230,55))
	piece("hazards", "branch_warning", Vector2(655,283), Vector2(230,82))
	piece("forest_kit", "scroll_banner", Vector2(490,245), Vector2(52,100))
	piece("forest_kit", "rune_lantern", Vector2(70,491), Vector2(65,115))
	piece("forest_kit", "foreground_flora", Vector2(15,644), Vector2(190,72))
	piece("forest_kit", "foreground_flora", Vector2(1090,644), Vector2(190,72))
	actor("nitpick_gnome", "walk", Vector2(444,395), 1.2)
	actor("bloat_troll", "walk", Vector2(559,605), 1.9)
	actor("legacy_monolith", "idle", Vector2(1014,605), 1.9)
	piece("hazards", "comment_warning", Vector2(695,502), Vector2(75,103))
	piece("hazards", "vine_warning", Vector2(790,480), Vector2(98,125))
	var hoppy := AnimatedSprite2D.new()
	hoppy.sprite_frames = load("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
	hoppy.animation = "idle"
	hoppy.position = Vector2(277, 539)
	hoppy.scale = Vector2(1.7,1.7)
	stage.add_child(hoppy)
	var title := Label.new()
	title.text = "THE ENCHANTED REPO"
	title.position = Vector2(65,42)
	title.add_theme_font_size_override("font_size",42)
	stage.add_child(title)
	var note := Label.new()
	note.text = "ASSET STAGING  /  LEGACY MONOLITH + FOREST KIT\nVisual scale study — gameplay assembly comes next"
	note.position = Vector2(68,99)
	note.add_theme_font_size_override("font_size",17)
	note.modulate = Color("c7edb0")
	stage.add_child(note)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(BASE + "enchanted-repo-preview.png")
	assert(error == OK)
	print("Saved rendered Enchanted Repo staging preview.")
	await finish()

func finish(code: int = 0) -> void:
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	quit(code)

func plate(key: String, pos: Vector2, size: Vector2, opacity: float = 1.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(BASE + "enchanted_repo/" + key + ".png")
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size / sprite.texture.get_size()
	sprite.modulate.a = opacity
	stage.add_child(sprite)

func actor(key: String, clip: String, pos: Vector2, magnify: float) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load(BASE + "enchanted_repo/" + key + ".tres")
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
	texture.atlas = load(BASE + "enchanted_repo/" + key + ".png")
	texture.region = Rect2(frame.rect[0]+b[0],frame.rect[1]+b[1],b[2]-b[0],b[3]-b[1])
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size/texture.get_size()
	stage.add_child(sprite)
