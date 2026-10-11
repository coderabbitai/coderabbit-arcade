extends SceneTree

const BASE = "res://Assets/code-city-brawl-assets-only/"
var manifest: Dictionary
var stage: Node2D
var failures := 0
## Mini-bosses face left and stand about 1.6x a linter_enforcer.
const MINI_BOSSES := ["stack_overflow", "zero_day"]
## clip name: [frames, fps, loop]. Each mini-boss has 16 populated cells in a 256 square cell.
const MINI_BOSS_CLIPS := {
	"idle": [[0, 1], 3, true],
	"walk": [[2, 3, 4, 5], 6, true],
	"slam_warning": [[6, 7], 5, false],
	"slam": [[8, 9], 10, false],
	"dash_warning": [[10], 1, false],
	"dash": [[11, 12], 10, false],
	"recover": [[13], 1, false],
	"hurt": [[14], 1, false],
	"defeat": [[15], 1, false],
}

func check(condition: bool, context: String) -> void:
	if not condition:
		failures += 1
		printerr("FAILED: ", context)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE + "code_city/manifest.json"))
	var frame_count := 0
	var clip_count := 0
	for key in manifest.atlases:
		var spec: Dictionary = manifest.atlases[key]
		var resource := load(BASE + "code_city/" + spec.resource) as SpriteFrames
		check(resource != null, key)
		if resource == null:
			continue
		check(resource.get_animation_names().size() == spec.clips.size(), key + " names")
		for clip in spec.clips:
			check(resource.has_animation(clip.name), key + "/" + clip.name)
			check(resource.get_frame_count(clip.name) == clip.frames.size(), clip.name)
			check(resource.get_animation_loop(clip.name) == clip.loop, clip.name + " loop")
			check(is_equal_approx(resource.get_animation_speed(clip.name), float(clip.fps)), clip.name + " fps")
			for i in resource.get_frame_count(clip.name):
				var texture := resource.get_frame_texture(clip.name, i) as AtlasTexture
				check(texture != null and texture.atlas != null, clip.name + " texture")
				if texture == null or texture.atlas == null:
					continue
				check(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), clip.name + " bounds")
				var image := texture.get_image()
				check(image != null and image.get_used_rect().has_area(), clip.name + " nonempty")
				check(image.detect_alpha() != Image.ALPHA_NONE, clip.name + " alpha")
			clip_count += 1
		if not MINI_BOSSES.has(key):
			frame_count += spec.frames.size()
	for bg in manifest.backgrounds.values():
		var texture := load(BASE + "code_city/" + bg.file) as Texture2D
		check(texture != null and texture.get_size() == Vector2(1280,720), bg.file)
	check(frame_count == 200, "200 source frames outside the mini-boss atlases")
	check_mini_bosses()
	check(manifest.atlases.size() == 19 + MINI_BOSSES.size() and manifest.backgrounds.size() == 3, "resource coverage")
	if failures > 0:
		await finish(1)
		return
	print("PASS: Code City Brawl — ", frame_count, " frames, ", clip_count, " states, 21 SpriteFrames resources, 3 panoramas.")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,720)
		for theme in ["district", "security", "hq"]:
			stage = Node2D.new()
			stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			root.add_child(stage)
			build_preview(theme)
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(BASE + theme + "-preview.png") == OK, "preview save")
			stage.queue_free()
			await process_frame
	await finish(0 if failures == 0 else 1)

func standing_height(key: String, clip_name: String) -> float:
	var spec: Dictionary = manifest.atlases[key]
	for clip in spec.clips:
		if clip.name == clip_name:
			var bounds: Array = spec.frames[int(clip.frames[0])].visible_bounds
			return float(bounds[3] - bounds[1])
	return 0.0

func check_mini_bosses() -> void:
	var reference := standing_height("linter_enforcer", "armored_idle")
	check(reference > 0.0, "linter_enforcer reference height measured")
	for key in MINI_BOSSES:
		check(manifest.atlases.has(key), key + " atlas is in the manifest")
		if not manifest.atlases.has(key):
			continue
		var spec: Dictionary = manifest.atlases[key]
		check(spec.get("facing", "") == "left", key + " faces left")
		check(Vector2i(int(spec.cell[0]), int(spec.cell[1])) == Vector2i(256, 256) and Vector2i(int(spec.pivot[0]), int(spec.pivot[1])) == Vector2i(128, 230), key + " keeps the 256 square cell and (128, 230) pivot")
		check(spec.frames.size() == 16, key + " has 16 populated cells")
		var names := []
		for clip in spec.clips:
			names.append(clip.name)
		var wanted: Array = MINI_BOSS_CLIPS.keys()
		wanted.sort()
		var got := names.duplicate()
		got.sort()
		check(got == wanted, key + " clips are exactly " + ", ".join(MINI_BOSS_CLIPS.keys()) + " (got " + ", ".join(names) + ")")
		for clip in spec.clips:
			if not MINI_BOSS_CLIPS.has(clip.name):
				continue
			var contract: Array = MINI_BOSS_CLIPS[clip.name]
			var listed := []
			for index in clip.frames:
				listed.append(int(index))
			check(listed == contract[0], key + "/" + clip.name + " frames " + str(listed) + " should be " + str(contract[0]))
			check(is_equal_approx(float(clip.fps), float(contract[1])), key + "/" + clip.name + " fps")
			check(clip.loop == contract[2], key + "/" + clip.name + " loop flag")
			for index in clip.frames:
				var b: Array = spec.frames[int(index)].visible_bounds
				check(int(b[0]) >= 0 and int(b[1]) >= 0 and int(b[2]) <= int(spec.cell[0]) and int(b[3]) <= int(spec.cell[1]), key + "/" + clip.name + " art fits its cell")
				check(int(b[3]) <= int(spec.pivot[1]) + 2, key + "/" + clip.name + " does not sink below the foot pivot")
		var stand := standing_height(key, "idle")
		check(stand >= 85.0 and stand <= 110.0, key + " idle stands about 98 px (got %.0f)" % stand)
		var ratio := standing_height(key, "idle") / maxf(reference, 1.0)
		check(ratio >= 1.35 and ratio <= 1.85, key + " idle stands about 1.6x a linter_enforcer (ratio %.2f)" % ratio)

func build_preview(theme: String) -> void:
	var bg := Sprite2D.new()
	bg.texture = load(BASE + "code_city/" + theme + "_background.png")
	bg.centered = false
	stage.add_child(bg)
	var title := Label.new()
	title.text = {"district":"CLI / IDE DISTRICT", "security":"SECURITY SECTOR", "hq":"GIT REPOSITORY HQ"}[theme]
	title.position = Vector2(45,25)
	title.add_theme_font_size_override("font_size",34)
	stage.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "CODE CITY BRAWL  /  ASSET STAGING — gameplay assembly comes next"
	subtitle.position = Vector2(47,70)
	subtitle.add_theme_font_size_override("font_size",16)
	stage.add_child(subtitle)
	var hoppy := AnimatedSprite2D.new()
	hoppy.sprite_frames = load("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
	hoppy.animation = "idle"
	hoppy.position = Vector2(230,540)
	hoppy.scale = Vector2(1.7,1.7)
	stage.add_child(hoppy)
	match theme:
		"district":
			piece("district_kit","ide_cluster",Vector2(650,145),Vector2(290,165))
			piece("district_kit","kiosk_intact",Vector2(50,388),Vector2(125,190))
			piece("district_kit","street_lamp",Vector2(1140,120),Vector2(95,370))
			actor("cli_gremlin","idle",Vector2(450,610),1.6)
			actor("syntax_error_sprite","idle",Vector2(720,480),1.5)
			actor("linter_enforcer","armored_idle",Vector2(960,625),2.0)
			piece("district_kit","bomb_warning",Vector2(575,592),Vector2(120,55))
			piece("district_kit","injection_bomb",Vector2(610,355),Vector2(50,70))
			piece("weapons","debug_stick",Vector2(325,617),Vector2(78,53))
		"security":
			piece("security_kit","server_cracked",Vector2(60,345),Vector2(140,210))
			piece("security_kit","crate_intact",Vector2(1050,490),Vector2(145,110))
			actor("cve_crawler","idle",Vector2(450,635),1.6)
			actor("injection_attack_drone","burst_warning",Vector2(705,480),1.7)
			actor("dependency_bot","idle",Vector2(920,640),1.5)
			piece("security_kit","laser_warning",Vector2(570,565),Vector2(90,90))
			piece("weapons","firewall_shield",Vector2(300,570),Vector2(60,80))
		"hq":
			piece("hq_kit","pillar_cracked",Vector2(30,350),Vector2(100,190))
			actor("merge_conflict_soldier","idle",Vector2(430,600),1.6)
			actor("force_push_bandit","idle",Vector2(640,660),1.5)
			actor("stale_branch_zombie","idle",Vector2(790,550),1.3)
			actor("conflict_spawner","idle",Vector2(1050,640),1.6)
			piece("items_allies","merge_button",Vector2(870,605),Vector2(80,65))
			piece("hq_kit","head_warning",Vector2(320,635),Vector2(100,45))

func actor(key: String, clip: String, pos: Vector2, magnify: float) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load(BASE + "code_city/" + key + ".tres")
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
	texture.atlas = load(BASE + "code_city/" + key + ".png")
	texture.region = Rect2(frame.rect[0]+b[0],frame.rect[1]+b[1],b[2]-b[0],b[3]-b[1])
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = pos
	sprite.scale = size/texture.get_size()
	stage.add_child(sprite)

func finish(code: int = 0) -> void:
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	quit(code)
