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

func compare_clips(actual: SpriteFrames, original: SpriteFrames, label: String) -> void:
	check(actual.get_animation_names() == original.get_animation_names(), label+" retains animation names")
	for clip in original.get_animation_names():
		check(actual.get_frame_count(clip)==original.get_frame_count(clip), label+"/"+clip+" frame count")
		check(actual.get_animation_speed(clip)==original.get_animation_speed(clip), label+"/"+clip+" timing")
		check(actual.get_animation_loop(clip)==original.get_animation_loop(clip), label+"/"+clip+" looping")
		for i in actual.get_frame_count(clip):
			check(actual.get_frame_duration(clip,i)==original.get_frame_duration(clip,i), label+" frame duration")
			var texture := actual.get_frame_texture(clip,i) as AtlasTexture
			check(texture != null and texture.atlas.resource_path.begins_with(ROOT), label+" uses reference hero art")

func run() -> void:
	var manifest: Dictionary=Art.load_armed_manifest()
	check(manifest.get("version",0)==2 and manifest.sheets.size()==7,"seven reference-matched sheets")
	check(manifest.weapons.size()==5,"five independently calibrated weapons")
	check(Art.frames("hoppy")==Player.COMBAT_FRAMES,"runtime Hoppy aliases use corrected hero")
	compare_clips(Player.COMBAT_FRAMES,load(LEGACY+"hoppy.tres"),"combat")
	compare_clips(Player.MOTION_FRAMES,load(LEGACY+"hoppy_locomotion.tres"),"locomotion")
	var count := 0
	for name: String in manifest.sheets:
		var spec: Dictionary=manifest.sheets[name]
		var filename: String="coderabbit_hero" if name=="combat" else "coderabbit_hero_locomotion" if name=="locomotion" else "armed/"+name
		var atlas: Image=load(ROOT+filename+".png").get_image()
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
			compare_clips(Art.armed_frames(name),load("res://Assets/hoppy-armed/heroes/"+name+".tres"),name)
			check(Art.carry_texture(name).resource_path.begins_with(ROOT),name+" calibrated hero carry")
	check(count==120,"all 120 gameplay cels covered")
	for pose in ["walk_up","walk_down"]:
		check(manifest.carry_hands[pose].size()==8,pose+" per-frame glove anchors")
	# Walking away shows the white backs of the ears, never the orange inner surfaces.
	for i in 8:
		var cel: Image=Player.MOTION_FRAMES.get_frame_texture("walk_up",i).get_image()
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
		var packed: PackedScene=load("res://Assets/heroes-vs-villains-assets-only/presentation/"+scene+".tscn")
		var instance := packed.instantiate()
		var found := false
		for node in instance.find_children("*","AnimatedSprite2D",true,false):
			if node.sprite_frames==Player.COMBAT_FRAMES: found=true
		check(found,scene+" displays reference hero")
		instance.free()
	print("Hero reference assets: ", count, " cels, ", failures, " failures")
	await root.get_node("AudioService").settle()
	quit(0 if failures==0 else 1)
