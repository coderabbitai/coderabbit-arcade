extends SceneTree
## Assets-only validation; this does not test or implement Mode 2 combat.

const BASE := "res://Assets/heroes-vs-villains-assets-only/"
var failures := 0
var manifest: Dictionary
var resources: Dictionary = {}


func check(ok: bool, context: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", context)


func _initialize() -> void:
	call_deferred("run")


func validate_links(value: Variant) -> void:
	if value is Dictionary:
		if value.has("resource") and value.has("animation"):
			var frames := resources.get(value.resource) as SpriteFrames
			check(frames != null and frames.has_animation(value.animation), str(value))
		for child: Variant in value.values():
			validate_links(child)
	elif value is Array:
		for child: Variant in value:
			validate_links(child)


func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE + "heroes_villains/manifest.json"))
	var frame_count := 0
	var clip_count := 0
	for key: String in manifest.atlases:
		var spec: Dictionary = manifest.atlases[key]
		var frames := load(BASE + "heroes_villains/" + spec.resource) as SpriteFrames
		check(frames != null, key + " loads")
		if frames == null:
			continue
		resources[key] = frames
		check(frames.get_animation_names().size() == spec.clips.size(), key + " animation count")
		for clip: Dictionary in spec.clips:
			check(frames.has_animation(clip.name), key + "/" + clip.name)
			check(frames.get_frame_count(clip.name) == clip.frames.size(), clip.name + " frame count")
			check(frames.get_animation_loop(clip.name) == clip.loop, clip.name + " loop")
			check(is_equal_approx(frames.get_animation_speed(clip.name), float(clip.fps)), clip.name + " fps")
			for i: int in frames.get_frame_count(clip.name):
				var texture := frames.get_frame_texture(clip.name, i) as AtlasTexture
				check(texture != null and texture.atlas != null, clip.name + " texture")
				if texture == null or texture.atlas == null:
					continue
				check(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), clip.name + " atlas bounds")
				var image := texture.get_image()
				check(image != null and image.get_used_rect().has_area(), clip.name + " nonempty")
				check(image.detect_alpha() != Image.ALPHA_NONE, clip.name + " transparency")
			clip_count += 1
		frame_count += spec.frames.size()
	check(frame_count == 208 and resources.size() == 22, "208 frames / 22 resources")
	for background: Dictionary in manifest.backgrounds.values():
		var texture := load(BASE + "heroes_villains/" + background.file) as Texture2D
		check(texture != null and texture.get_size() == Vector2(1280, 720), background.file)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "content_catalog.json"))
	validate_links(catalog)
	check(catalog.enemies.size() == 12 and catalog.weapons.size() == 5, "roster coverage")
	check(catalog.bosses.army_and_pr.actors.size() == 2, "dual boss roster")
	var audio: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "audio/manifest.json"))
	check(audio.size() == 8, "eight original cues")
	for cue: Dictionary in audio.values():
		var stream := load(BASE + "audio/" + cue.file) as AudioStreamWAV
		check(stream != null and stream.get_length() > 0.0, "audio " + cue.file)
	var scenes := DirAccess.get_files_at(BASE + "presentation")
	var scene_count := 0
	root.size = Vector2i(1280, 720)
	for file: String in scenes:
		if not file.ends_with(".tscn"):
			continue
		scene_count += 1
		var packed := load(BASE + "presentation/" + file) as PackedScene
		check(packed != null, file)
		if packed == null:
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(BASE + file.get_basename() + "-preview.png") == OK, "capture " + file)
		scene.queue_free()
		await process_frame
	check(scene_count == 15, "15 presentation scenes")
	if failures == 0:
		print("PASS: Heroes vs. Villains: ", frame_count, " frames, ", clip_count, " clips, 22 resources, 3 backgrounds, 15 scenes; catalog links valid.")
	else:
		printerr(failures, " asset checks failed")
	resources.clear()
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	quit(0 if failures == 0 else 1)
