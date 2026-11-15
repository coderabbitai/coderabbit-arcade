extends SceneTree
## Validate the resources the player actually uses, independently of legacy Hoppy.
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
const Player = preload("res://modes/beatem_up/reinvent/player.gd")
const ROOT := "res://Assets/Character/CodeRabbit/2D/heroes_villains/"
const LEGACY := "res://Assets/heroes-vs-villains-assets-only/heroes_villains/"
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func asset(path: String) -> Resource:
	return load(path) if ResourceLoader.exists(path) else null

func finish() -> void:
	await root.get_node("AudioService").settle()
	quit(0 if failures==0 else 1)

func compare_clips(actual: SpriteFrames, original: SpriteFrames, label: String) -> void:
	check(actual != null, label+" hero SpriteFrames exists")
	check(original != null, label+" reference SpriteFrames exists")
	if actual == null or original == null:
		return
	check(actual.get_animation_names() == original.get_animation_names(), label+" retains animation names")
	for clip in original.get_animation_names():
		if not actual.has_animation(clip):
			continue # The name comparison already recorded the missing clip.
		check(actual.get_frame_count(clip)==original.get_frame_count(clip), label+"/"+clip+" frame count")
		check(actual.get_animation_speed(clip)==original.get_animation_speed(clip), label+"/"+clip+" timing")
		check(actual.get_animation_loop(clip)==original.get_animation_loop(clip), label+"/"+clip+" looping")
		for i in mini(actual.get_frame_count(clip), original.get_frame_count(clip)):
			check(actual.get_frame_duration(clip,i)==original.get_frame_duration(clip,i), label+" frame duration")
			var texture := actual.get_frame_texture(clip,i) as AtlasTexture
			check(texture != null and texture.atlas != null and texture.atlas.resource_path.begins_with(ROOT), label+" uses reference hero art")

func run() -> void:
	var manifest: Dictionary=Art.load_armed_manifest()
	var valid_manifest: bool=(
		manifest.get("version",0)==2
		and manifest.get("sheets",{}) is Dictionary and manifest.get("sheets",{}).size()==7
		and manifest.get("weapons",{}) is Dictionary and manifest.get("weapons",{}).size()==5
		and manifest.get("carry_hands",{}) is Dictionary
		and manifest.get("carry_hands",{}).has_all(["walk_up","walk_down"])
	)
	check(valid_manifest,"version-2 hero manifest includes seven sheets, five weapons and directional carry anchors")
	if not valid_manifest:
		await finish()
		return
	check(Art.frames("hoppy")==Player.COMBAT_FRAMES,"runtime Hoppy aliases use corrected hero")
	compare_clips(Player.COMBAT_FRAMES,asset(LEGACY+"hoppy.tres") as SpriteFrames,"combat")
	compare_clips(Player.MOTION_FRAMES,asset(LEGACY+"hoppy_locomotion.tres") as SpriteFrames,"locomotion")
	var count := 0
	for name: String in manifest.sheets:
		var spec: Dictionary=manifest.sheets[name]
		var filename: String="coderabbit_hero" if name=="combat" else "coderabbit_hero_locomotion" if name=="locomotion" else "armed/"+name
		var atlas_texture := asset(ROOT+filename+".png") as Texture2D
		check(atlas_texture != null,name+" atlas exists")
		if atlas_texture == null: continue
		var atlas: Image=atlas_texture.get_image()
		check(atlas != null,name+" atlas image is readable")
		if atlas == null: continue
		var size := Vector2i(int(spec.cell[0]),int(spec.cell[1]))
		check(atlas.get_size()==Vector2i(size.x*4,size.y*(6 if name=="locomotion" else 4)),name+" atlas dimensions")
		for i in spec.frames.size():
			count+=1
			var cel := atlas.get_region(Rect2i(Vector2i(i%4,i/4)*size,size))
			check(cel.get_used_rect().has_area(),name+"/%d nonempty"%i)
			# Ignore soft alpha fringes but reject clipped solid ears, feet or weapons.
			for x in size.x:
				check(cel.get_pixel(x,0).a<.5 and cel.get_pixel(x,size.y-1).a<.5,name+" vertical clipping")
			for y in size.y:
				check(cel.get_pixel(0,y).a<.5 and cel.get_pixel(size.x-1,y).a<.5,name+" horizontal clipping")
			if name in manifest.weapons:
				for kind in ["hand","tip"]:
					var a: Array=spec.anchors[kind][str(i)]
					check(cel.get_pixel(int(a[0]),int(a[1])).a>=.5,name+"/%d %s on painted pixels"%[i,kind])
		if name in manifest.weapons:
			compare_clips(Art.armed_frames(name),asset("res://Assets/hoppy-armed/heroes/"+name+".tres") as SpriteFrames,name)
			var carry := Art.carry_texture(name)
			check(carry != null and carry.resource_path.begins_with(ROOT),name+" calibrated hero carry")
	check(count==120,"all 120 gameplay cels covered")
	for pose in ["walk_up","walk_down"]:
		check(manifest.carry_hands[pose].size()==8,pose+" per-frame glove anchors")
	# Walking away shows the white backs of the ears, never the orange inner surfaces.
	for i in 8:
		var texture: Texture2D = null
		if Player.MOTION_FRAMES.has_animation("walk_up") and i<Player.MOTION_FRAMES.get_frame_count("walk_up"):
			texture=Player.MOTION_FRAMES.get_frame_texture("walk_up",i)
		check(texture != null,"walk_up/%d texture exists"%i)
		if texture == null: continue
		var cel := texture.get_image()
		check(cel != null,"walk_up/%d image is readable"%i)
		if cel == null: continue
		var orange := 0
		var white := 0
		for y in range(20,54):
			for x in range(35,90):
				var color := cel.get_pixel(x,y)
				if color.a < .5: continue
				if color.r>.6 and color.g>.2 and color.g<.7 and color.b<.35: orange+=1
				if color.r>.65 and color.g>.65 and color.b>.65: white+=1
		check(orange<=2 and white>30,"walk_up/%d shows white outer ears (%d orange, %d white)"%[i,orange,white])
	for scene in ["victory","generation_floor","review_gauntlet","agentic_core"]:
		var packed := asset("res://Assets/heroes-vs-villains-assets-only/presentation/"+scene+".tscn") as PackedScene
		check(packed != null,scene+" presentation exists")
		if packed == null: continue
		var instance := packed.instantiate()
		check(instance != null,scene+" presentation instantiates")
		if instance == null: continue
		var found := false
		for node in instance.find_children("*","AnimatedSprite2D",true,false):
			if node.sprite_frames==Player.COMBAT_FRAMES: found=true
		check(found,scene+" displays reference hero")
		instance.free()
	print("Hero reference assets: ", count, " cels, ", failures, " failures")
	await finish()
