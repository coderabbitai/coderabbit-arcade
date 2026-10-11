extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const ArmedMeasure = preload("res://tests/support/armed_measure.gd")
const COMBAT_FRAMES = preload("res://Assets/code-city-brawl-player/combat.tres")
const PLATFORMER_FRAMES = preload("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
## The weapon captures' deliberate on-screen caption.
const CAPTION := "EQUIPPED WEAPON ANIMATION · windup / contact / recovery"
## Frame caps on the capture's waits (autoloads ready, one viewport draw), so a stuck run fails
## instead of hanging.
const READY_FRAMES := 600
const DRAW_FRAMES := 120
var game
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func phase_frame(phase: float) -> int:
	return 0 if phase < .3 else 1 if phase < .64 else 2
func opaque_width(frames: SpriteFrames, clip: String, index: int) -> float:
	return frames.get_frame_texture(clip, index).get_image().get_used_rect().size.x
## A swing that misses, or lands on one enemy placed `distance` ahead. The burst is the last child of actors.
func swing_effect(actor, facing: float, landed: bool, distance := 60.0) -> void:
	actor.facing = facing
	actor.swing_left = 0
	actor.combo_window = 0
	actor.queued = false
	actor.held.show()
	var foe = null
	var foe_hp := 0.0
	# Durability drops only when resolve_swing actually lands, so a hit can't pass as a miss.
	var uses: int = actor.durability
	if landed:
		foe = game.spawn_enemy("syntax_error_sprite", actor.position + Vector2(facing * distance, 0), false)
		foe.set_physics_process(false)
		foe_hp = foe.hp
	actor.start_attack()
	game.resolve_swing(actor)
	var fx := game.actors.get_child(game.actors.get_child_count() - 1) as AnimatedSprite2D
	# Misses always use melee_sweep at the weapon tip. Hits burst on the victim; a hammer hit uses hammer_impact.
	var pose := "hammer_impact" if landed and actor.attack_weapon == "refactor_hammer" else "melee_sweep"
	var at: Vector2 = foe.position - Vector2(0, 55) if landed else actor.tip_position()
	var kind := "hit bursts on the enemy" if landed else "miss sweeps from the tip"
	check(fx != null and fx.animation == pose and fx.flip_h == (facing > 0) and fx.position.is_equal_approx(at), actor.weapon + " " + kind + " (" + pose + ") facing " + str(facing))
	if landed:
		check((actor.durability == uses - 1 or actor.weapon == "") and (foe.dead or foe.hp < foe_hp), actor.weapon + " hit spends a charge and damages the foe facing " + str(facing))
	if foe != null:
		game.enemies.erase(foe)
		foe.position = Vector2(-10000, -10000)
		foe.queue_free()
	if fx != null: fx.queue_free()
	for item in game.pickups:
		if is_instance_valid(item.node): item.node.queue_free()
	game.pickups.clear()
## Face boxes measured on the unarmed 96px cel (eyes + muzzle). Pivot is the rig's unarmed foot.
const FACE_BOX := {
	"walk_down": Rect2(36,40,24,22),
	"jump": Rect2(44,46,22,20),
}
const FACE_PIVOT := Vector2(48,86)

## The armed clip the player routes `pose` to, or "" while the player (or the sheet) has no such clip.
## Read from the player script's ARMED_CLIPS, so the same test holds before and after S1 maps
## walk_up and walk_down, and it never guesses from the body's current frame.
func armed_clip_for(actor, pose: String) -> String:
	var script: Script=actor.get_script() if actor!=null else null
	if script==null: return ""
	var constants: Dictionary=script.get_script_constant_map()
	var map: Variant=constants.get("ARMED_CLIPS",{})
	var sheet := Art.armed(actor.weapon)
	if not map is Dictionary or sheet==null or not map.has(pose): return ""
	var clip_value: Variant=map[pose]
	if not (clip_value is String or clip_value is StringName): return ""
	var clip := str(clip_value)
	return clip if sheet.has_animation(clip) else ""

## A mapped armed pose must play the armed sheet's own clip and show no carry icon or legacy cel.
## Returns true when the pose is mapped, so callers skip the carry icon checks that no longer apply.
func check_armed_pose(actor, pose: String) -> bool:
	var clip := armed_clip_for(actor,pose)
	if clip=="": return false
	var sheet := Art.armed(actor.weapon)
	var label := "%s %s facing %d" % [actor.weapon,pose,int(actor.facing)]
	if sheet==null:
		check(false,label+" plays the armed %s clip (got %s)" % [clip,actor.body.animation])
		return true
	check(actor.body.sprite_frames==sheet and actor.body.animation==clip,label+" plays the armed %s clip (got %s)" % [clip,actor.body.animation])
	if pose=="walk_up" or pose=="walk_down":
		check(sheet.get_frame_count(clip)==4 and sheet.get_animation_loop(clip),label+" armed clip is a 4 frame loop")
	check(not actor.held.carry.visible and not actor.held.sprite.visible,label+" hides the carry icon and legacy cel on the armed clip")
	# The next tick animates the rig again with no attack active; it must not paste the icon back.
	actor.held.animate(actor.weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
	check(actor.body.sprite_frames==sheet and actor.body.animation==clip and not actor.held.carry.visible and not actor.held.sprite.visible,label+" keeps the carry hidden after the rig animates again")
	return true

func carry_should_behind(kind: String, pose: String) -> bool:
	if pose=="walk_up" or pose=="jump": return true
	if pose=="walk_down": return kind=="firewall_shield"
	return false

## Every weapon, both facings. walk_up is behind for all and has no face box. Jump is behind for
## all. walk_down is in front except the shield, so those carries must miss the face box.
func check_carry_faces(players: Array) -> void:
	check(players.size()==Catalog.WEAPONS.size() and players.size()==6,"Code City face check covers all 6 weapons")
	var covered: PackedStringArray=PackedStringArray()
	for actor in players:
		var weapon: String=actor.weapon
		for pose in ["walk_up","walk_down","jump"]:
			for face in [1,-1]:
				actor.facing=face
				actor.show_pose(pose)
				if check_armed_pose(actor,pose): continue
				actor.body.frame=0
				actor.held.scale=Vector2(face,1)
				actor.held.animate(weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
				var carry: Sprite2D=actor.held.carry
				var expect: bool=carry_should_behind(weapon,pose)
				var drawn: bool=actor.held.get_index()<actor.body.get_index()
				var told: bool=actor.held.carry_behind(weapon,pose)
				var label := "%s %s facing %d"%[weapon,pose,face]
				var layer_ok: bool=carry.visible and not actor.held.sprite.visible and carry.scale==actor.body.scale and actor.body.animation==pose
				check(layer_ok,label+" shows the carry")
				check(drawn==expect and told==expect,label+(" draws behind the body" if expect else " draws in front of the body")+" (held %d, body %d)"%[actor.held.get_index(),actor.body.get_index()])
				if not FACE_BOX.has(pose): continue
				var image: Image=Art.carry(weapon).get_image()
				var hits := ArmedMeasure.carry_face_hits(carry,image,FACE_BOX[pose],actor.body.scale.y,FACE_PIVOT)
				if hits>0: covered.append("%s %s facing %d: %d"%[weapon,pose,face,hits])
				check(drawn or hits==0,label+" keeps the face clear (%d texels in the face box, behind %s)"%[hits,drawn])
		actor.facing=1
		actor.body.flip_h=false
		actor.held.scale=Vector2.ONE
	print("Code City opaque carry texels inside the face box: "+("; ".join(covered) if covered.size() else "none"))

## tip_at must survive a manifest that lost its tip anchor, its clips, or a step's frame list,
## without touching the armed-sheet cache. The original spec is put back before returning.
func check_tip_fallback(actor) -> void:
	var weapon := "debug_stick"
	if Art.armed(weapon)==null:
		for kind in Catalog.WEAPONS:
			if Art.armed(kind)!=null:
				weapon=kind
				break
	var sheet: SpriteFrames=Art.armed(weapon)
	var weapons: Dictionary=Art.armed_manifest["weapons"]
	var original: Dictionary=weapons[weapon]
	var step := 1
	var frames: Array=original["clips"]["step%d"%step]["frames"]
	var contact := str(int(frames[1]))
	var hands: Dictionary=original["anchors"]["hand"]
	var tips: Dictionary=original["anchors"]["tip"]
	var pivot := Vector2(original["pivot"][0],original["pivot"][1])
	var scale_y: float=actor.body.scale.y
	var hand: Array=hands[contact]
	var hand_tip := (Vector2(hand[0],hand[1])-pivot)*scale_y
	var tip_anchor: Array=tips[contact]
	var tip_expected := (Vector2(tip_anchor[0],tip_anchor[1])-pivot)*scale_y
	var sentinel := Vector2(12.5,-34.5)
	check(sheet!=null and hands.has(contact) and tips.has(contact) and not hand_tip.is_equal_approx(tip_expected) and not hand_tip.is_equal_approx(sentinel),weapon+" contact tip and hand differ, so the tip_at fallback is observable")
	var missing_tip: Dictionary=original.duplicate(true)
	(missing_tip["anchors"] as Dictionary).erase("tip")
	weapons[weapon]=missing_tip
	actor.held.tip=sentinel
	var got: Vector2=actor.held.tip_at(weapon,step)
	weapons[weapon]=original
	check(got.is_equal_approx(hand_tip) and is_same(weapons[weapon],original) and Art.armed(weapon)==sheet,weapon+" tip_at without anchors.tip uses the hand anchor (got %s, hand %s)"%[got,hand_tip])
	var no_clips: Dictionary=original.duplicate(true)
	no_clips.erase("clips")
	weapons[weapon]=no_clips
	actor.held.tip=sentinel
	var kept: Vector2=actor.held.tip_at(weapon,step)
	weapons[weapon]=original
	check(kept.is_equal_approx(sentinel) and actor.held.tip.is_equal_approx(sentinel) and Art.armed(weapon)==sheet,weapon+" tip_at without clips returns the current tip")
	var bad_frames: Dictionary=original.duplicate(true)
	bad_frames["clips"]["step%d"%step]["frames"]=4
	weapons[weapon]=bad_frames
	actor.held.tip=sentinel
	var malformed: Vector2=actor.held.tip_at(weapon,step)
	weapons[weapon]=original
	check(malformed.is_equal_approx(sentinel) and actor.held.tip.is_equal_approx(sentinel) and is_same(weapons[weapon],original) and Art.armed(weapon)==sheet,weapon+" tip_at with a numeric frame list returns the current tip")
	var restored: Vector2=actor.held.tip_at(weapon,step)
	check(restored.is_equal_approx(tip_expected),weapon+" tip_at uses the tip anchor again after the spec is restored (got %s, tip %s)"%[restored,tip_expected])
	# The contact trail reads the windup and contact paw anchors; without them it collapses onto the tip.
	var no_hands: Dictionary=original.duplicate(true)
	(no_hands["anchors"] as Dictionary).erase("hand")
	weapons[weapon]=no_hands
	actor.held.trail.clear_points()
	actor.held._armed_trail(weapon,step,.5,true)
	var points: PackedVector2Array=actor.held.trail.points
	weapons[weapon]=original
	check(points.size()>0 and points[points.size()-1].is_equal_approx(tip_expected) and actor.held.tip.is_equal_approx(tip_expected) and Art.armed(weapon)==sheet,weapon+" contact trail without anchors.hand ends at the tip (%d points, last %s, tip %s)"%[points.size(),points[points.size()-1] if points.size() else Vector2.ZERO,tip_expected])
	actor.held.trail.clear_points()
	actor.held._armed_trail(weapon,step,.5,true)
	var full: PackedVector2Array=actor.held.trail.points
	check(full.size()==9 and full[0].distance_to(tip_expected)<=.5 and full[full.size()-1].distance_to(tip_expected)>4,weapon+" contact trail with every anchor still sweeps back from the tip")
	actor.held.trail.clear_points()

## Saves a rendered preview. Asserted at capture time (after the saved draw when rendering): only
## `toast_text` may show, and nothing may be held behind a banner, so no test text leaks in.
func capture(name: String, toast_text := "") -> void:
	var rendered := DisplayServer.get_name()!="headless"
	if rendered:
		game.world.reset_physics_interpolation()
		game.camera.reset_physics_interpolation()
		game.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
	var shown: String = game.toast_label.text if game.toast_label.visible else ""
	check(game.held_toast=="" and shown==toast_text,name+" shows only its expected toast (got '%s')" % shown)
	if not rendered: return
	DirAccess.make_dir_recursive_absolute("res://../docs/previews/code-city-motion")
	root.get_texture().get_image().save_png("res://../docs/previews/code-city-motion/"+name+".png")

## Armed run keeps the body still, in the sheet and on the stage-exit run-out.
func check_armed_run_registration(actor) -> void:
	var sheet_for := func(weapon): return Art.armed(weapon)
	var spec_for := func(weapon): return Art.armed_spec(weapon)
	var offset_for := func(weapon, facing: float) -> Vector2:
		var base_offset: Vector2 = Art.armed_offset(weapon)
		return Vector2(-base_offset.x if facing < 0.0 else base_offset.x, base_offset.y)
	var require_cell := true
	var show_held := true
	ArmedMeasure.check_armed_run_registration(actor, Catalog.WEAPONS, check, sheet_for, spec_for, offset_for, "debug_stick", game.flow, require_cell, show_held)

## Run is a 6 frame cycle and the vertical walks are 4 frame loops on every Code City armed sheet.
## This reads only the sheets and manifest, so it holds before player.gd plays walk_up or walk_down.
func check_armed_locomotion_clips() -> void:
	var contract := {"run": 6, "walk_up": 4, "walk_down": 4}
	for weapon in Catalog.WEAPONS:
		var sheet := Art.armed(weapon)
		var spec := Art.armed_spec(weapon)
		check(sheet != null and not spec.is_empty(), weapon+" has an armed sheet and manifest entry")
		if sheet == null or spec.is_empty(): continue
		var cell: Variant=spec.get("cell",[])
		var pivot_data: Variant=spec.get("pivot",[])
		var cell_ok: bool=cell is Array and cell.size()==2
		var pivot_ok: bool=pivot_data is Array and pivot_data.size()==2
		var pivot := Vector2(pivot_data[0],pivot_data[1]) if pivot_ok else Vector2.ZERO
		check(cell_ok and pivot_ok and Vector2(cell[0],cell[1])==Vector2(192,128) and pivot==Vector2(72,118),weapon+" keeps the 192x128 cell and (72,118) pivot")
		var clips: Variant=spec.get("clips",{})
		var anchors: Variant=spec.get("anchors",{})
		var hands: Dictionary={}
		if anchors is Dictionary and anchors.get("hand",{}) is Dictionary:
			hands=anchors.hand
		for clip in contract:
			var count: int=contract[clip]
			check(sheet.has_animation(clip) and sheet.get_frame_count(clip)==count and sheet.get_animation_loop(clip),weapon+" "+clip+" loops over "+str(count)+" frames")
			var clip_spec: Variant=clips.get(clip,{}) if clips is Dictionary else {}
			var listed_v: Variant=clip_spec.get("frames",[]) if clip_spec is Dictionary else []
			var listed: Array=listed_v if listed_v is Array else []
			check(listed.size()==count,weapon+" manifest lists "+str(count)+" "+clip+" frames")
			if not sheet.has_animation(clip): continue
			var fps := sheet.get_animation_speed(clip)
			check(fps>=(12.0 if clip=="run" else 8.0) and fps<=(15.0 if clip=="run" else 10.0),weapon+" "+clip+" fps %.1f is in range" % fps)
			if not pivot_ok: continue
			for i in sheet.get_frame_count(clip):
				var texture := sheet.get_frame_texture(clip,i)
				var image := texture.get_image() if texture!=null else null
				if image!=null and image.is_compressed(): image.decompress()
				if image==null:
					check(false,weapon+" "+clip+" frame "+str(i)+" has a texture")
					continue
				var used := image.get_used_rect()
				# Rect2i.end is exclusive, so the lowest occupied row is end.y - 1.
				var lowest_row := used.end.y-1
				check(used.has_area() and lowest_row>=pivot.y-3 and lowest_row<=pivot.y+3,weapon+" "+clip+" frame "+str(i)+" stands on the foot pivot row")
				if i<listed.size():
					if listed[i] is int or listed[i] is float:
						check(hands.has(str(int(listed[i]))),weapon+" "+clip+" frame "+str(i)+" has a hand anchor")
					else:
						check(false,weapon+" "+clip+" frame "+str(i)+" has a hand anchor")
		# Vertical walks keep every pre-existing cell: attack and idle clips still sit in cells 0 to 15.
		for clip in ["hold_idle","run","step1","step2","step3","equip","hurt","walk_up","walk_down"]:
			check(clips is Dictionary and clips.has(clip),weapon+" manifest keeps clip "+clip)

## `-- --capture-locomotion [--capture-path=<png>]` renders every armed sheet's locomotion frames
## through the engine and quits without running the suite. Rows per weapon: run facing right, run
## facing left (flipped like the player), walk_up, walk_down. Frames are selected explicitly, so
## this does not depend on the player routing walk_up or walk_down. Launch with --always-on-top.
const CAPTURE_PATH := "res://../docs/previews/code-city-motion/locomotion_contact_sheet.png"
const CAPTURE_CELL := Vector2i(192,128)
const CAPTURE_COLUMNS := 6
const CAPTURE_ROWS := [["run",false,"run right"],["run",true,"run left"],["walk_up",false,"walk up"],["walk_down",false,"walk down"]]

func capture_target() -> String:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture-locomotion"): return ""
	for i in args.size():
		if args[i].begins_with("--capture-path="): return args[i].trim_prefix("--capture-path=")
		if args[i]=="--capture-path" and i+1<args.size(): return args[i+1]
	return CAPTURE_PATH

## Resuming inside an autoload's _ready (SaveService pumps frames there) makes add_child fail on
## root, so wait until root and every autoload report ready, from a clean frame.
## Gives up after READY_FRAMES, so a stuck start fails instead of hanging.
func autoloads_ready() -> bool:
	for frame in READY_FRAMES:
		await process_frame
		var ready := root.is_node_ready()
		for child in root.get_children():
			ready = ready and child.is_node_ready()
		if ready: return true
	return false

func capture_locomotion(path: String) -> void:
	if not await autoloads_ready():
		printerr("FAIL: root and its autoloads were not ready within %d frames" % READY_FRAMES)
		quit(1)
		return
	if DisplayServer.get_name()=="headless":
		printerr("FAIL: --capture-locomotion needs a rendered run, not --headless")
		quit(1)
		return
	var weapons: Array=Catalog.WEAPONS.keys()
	var columns := 2
	var block_h := CAPTURE_ROWS.size()*CAPTURE_CELL.y
	var rows_per_column := int(ceil(float(weapons.size())/columns))
	var size := Vector2i(columns*CAPTURE_COLUMNS*CAPTURE_CELL.x,rows_per_column*block_h)
	var viewport := SubViewport.new()
	viewport.size=size
	viewport.transparent_bg=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var stage := Node2D.new()
	stage.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(stage)
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color=Color(.18,.2,.24)
	backdrop.size=Vector2(size)
	stage.add_child(backdrop)
	var count := 0
	for w in weapons.size():
		var weapon: String=weapons[w]
		var sheet := Art.armed(weapon)
		if sheet==null:
			printerr("FAIL: no armed sheet for "+weapon)
			failures+=1
			continue
		var pivot_data: Variant=Art.armed_spec(weapon).get("pivot",[])
		if not pivot_data is Array or pivot_data.size()<2:
			printerr("FAIL: "+weapon+" armed spec has no foot pivot")
			failures+=1
			continue
		var foot_pivot := Vector2(pivot_data[0],pivot_data[1])
		var origin := Vector2i((w/rows_per_column)*CAPTURE_COLUMNS*CAPTURE_CELL.x,(w%rows_per_column)*block_h)
		var label := Label.new()
		label.text=weapon
		label.position=Vector2(origin)+Vector2(4,2)
		stage.add_child(label)
		for r in CAPTURE_ROWS.size():
			var row: Array=CAPTURE_ROWS[r]
			if not sheet.has_animation(row[0]):
				printerr("FAIL: "+weapon+" has no "+row[0]+" clip")
				failures+=1
				continue
			for f in sheet.get_frame_count(row[0]):
				var cell_origin := Vector2(origin)+Vector2(f*CAPTURE_CELL.x,r*CAPTURE_CELL.y)
				var ground := ColorRect.new()
				ground.color=Color(.3,.33,.38)
				ground.position=cell_origin+Vector2(0,foot_pivot.y)
				ground.size=Vector2(CAPTURE_CELL.x,1)
				stage.add_child(ground)
				var sprite := AnimatedSprite2D.new()
				sprite.sprite_frames=sheet
				sprite.animation=row[0]
				sprite.frame=f
				sprite.pause()
				sprite.flip_h=row[1]
				var offset: Vector2=Art.armed_offset(weapon)
				sprite.offset=Vector2(-offset.x if row[1] else offset.x,offset.y)
				# The offset moves the texture so the foot pivot lands on the sprite position.
				sprite.position=cell_origin+Vector2(foot_pivot.x,foot_pivot.y)
				stage.add_child(sprite)
				count+=1
			var tag := Label.new()
			tag.text=row[2]
			tag.position=Vector2(origin)+Vector2(4,r*CAPTURE_CELL.y+18)
			stage.add_child(tag)
	# One explicit update. The renderer's own mode drops back to disabled once the viewport has drawn.
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	var rid := viewport.get_viewport_rid()
	await RenderingServer.frame_post_draw
	var drawn := 0
	while RenderingServer.viewport_get_update_mode(rid)!=RenderingServer.VIEWPORT_UPDATE_DISABLED and drawn<DRAW_FRAMES:
		await RenderingServer.frame_post_draw
		drawn+=1
	var drew: bool=RenderingServer.viewport_get_update_mode(rid)==RenderingServer.VIEWPORT_UPDATE_DISABLED
	check(drew,"The contact sheet viewport draws within %d frames" % DRAW_FRAMES)
	if drew:
		var viewport_texture := viewport.get_texture()
		var image: Image=viewport_texture.get_image() if viewport_texture!=null else null
		if image==null:
			check(false,"The contact sheet viewport produced an image")
		else:
			var dir := ProjectSettings.globalize_path(path).get_base_dir()
			DirAccess.make_dir_recursive_absolute(dir)
			var saved := image.save_png(ProjectSettings.globalize_path(path))
			check(saved==OK and count>0,"Locomotion contact sheet saved with %d frames to %s" % [count,path])
	viewport.queue_free()
	await finish_capture()

func finish_capture() -> void:
	if root.has_node("AudioService"): root.get_node("AudioService").shutdown()
	await create_timer(.2).timeout
	quit(1 if failures else 0)

## Torso registration at runtime. The player ticks at the physics rate (move_and_slide steps by the
## physics delta) while the sprite animates on the engine clock. The drawn shirt x comes from the
## body's own transform, mirrored inside the texture when flipped, so an offset or scale bug shows.
## Side runs read the shirt back edge + 6, every other pose the shirt centroid.
const RUN_PX_PER_S := 240.0
const RUN_FPS := 13.0
## The animation clock and the physics ticks are independent, so a frame boundary can land a tick
## either side of its ideal time: up to 8.5 px at 240 px/s. This only widens the per-animation-frame
## step; each physics tick is held to 240 * dt within TORSO_TICK_SLACK, and whole cycles to 1 px.
const TORSO_STEP_SLACK := 8.5
const TORSO_TICK_SLACK := 1.0
## Shirt x within 2 cel px of the node, times the 1.55 body scale, plus rounding.
const TORSO_POSE_SLACK := 3.2
const TORSO_TICK_CAP := 900
var landmark_cache := {}

## Shirt x (cel px) for every frame of `clip` on the weapon's armed sheet. NaN where unreadable.
func shirt_xs(weapon: String, clip: String) -> PackedFloat32Array:
	var key := weapon+"/"+clip
	if landmark_cache.has(key): return landmark_cache[key]
	var sheet := Art.armed(weapon)
	var xs := PackedFloat32Array()
	for i in sheet.get_frame_count(clip):
		var measured := ArmedMeasure.shirt_measure(sheet.get_frame_texture(clip,i).get_image(),clip=="run")
		xs.append(measured.position.x if measured.size>=15 else NAN)
	landmark_cache[key]=xs
	return xs

## World x of the shirt landmark on the frame the body is showing, or NaN.
func drawn_torso(actor) -> float:
	var body: AnimatedSprite2D=actor.body
	var xs := shirt_xs(actor.weapon,body.animation)
	if body.frame>=xs.size() or is_nan(xs[body.frame]): return NAN
	var cell: Vector2=body.sprite_frames.get_frame_texture(body.animation,body.frame).get_size()
	var texel := xs[body.frame]+.5
	var u := cell.x-texel if body.flip_h else texel
	return body.to_global(Vector2(u,cell.y/2.0)-cell/2.0+body.offset).x

func hold_move(action: String, strength := 1.0) -> void:
	for name in ["move_left","move_right","move_up","move_down"]:
		Input.action_release(name)
	if action!="": Input.action_press(action,strength)

## One physics tick: the sprite animates on the real clock, the player steps by the physics delta.
func step_player(actor) -> float:
	await physics_frame
	var dt := 1.0/float(Engine.physics_ticks_per_second)
	actor.tick(dt)
	return dt

func sample_of(actor, clock: float) -> Dictionary:
	return {"t":clock,"x":drawn_torso(actor),"clip":actor.body.animation,"frame":actor.body.frame,"pos":actor.position.x}

## Runs `ticks` ticks and returns a sample after each.
func run_samples(actor, ticks: int) -> Array:
	var out := []
	var clock := 0.0
	for _i in ticks:
		clock+=await step_player(actor)
		out.append(sample_of(actor,clock))
	return out

## Runs until the run clip has wrapped `wraps` times (frame returns to 0), bounded by TORSO_TICK_CAP.
func run_cycles(actor, wraps: int) -> Array:
	var out := []
	var clock := 0.0
	var seen := 0
	var last_frame := -1
	while seen<wraps and out.size()<TORSO_TICK_CAP:
		clock+=await step_player(actor)
		var sample := sample_of(actor,clock)
		if sample.clip=="run" and sample.frame==0 and last_frame!=0 and not out.is_empty(): seen+=1
		last_frame=sample.frame
		out.append(sample)
	return out

func torso_offset_ok(sample: Dictionary) -> bool:
	return not is_nan(sample.x) and absf(sample.x-sample.pos)<=TORSO_POSE_SLACK

func check_torso_motion(actor, weapon: String, facing: float) -> void:
	var label := "%s facing %d" % [weapon,int(facing)]
	actor.equip(weapon);actor.pickup_time=0;actor.stagger=0;actor.input_lock=0
	actor.swing_left=0;actor.combo_window=0;actor.held.show();actor.controlled=true
	actor.facing=facing;actor.steer=facing
	actor.position=Vector2(game.room_start()+(180 if facing>0 else 1020),560)
	var run_action := "move_right" if facing>0 else "move_left"
	hold_move(run_action)
	await run_samples(actor,12)
	# Two full wraps after the settle: three wraps are run so the first, partial cycle is dropped.
	var samples: Array=await run_cycles(actor,3)
	check(samples.size()<TORSO_TICK_CAP and samples.all(func(s): return s.clip=="run"),label+" runs three wraps on the armed run clip (%d ticks)" % samples.size())
	check(absf(actor.body.speed_scale-1.0)<.001,label+" cadence is 1.0 at full stick")
	var backward := 0
	var unreadable := 0
	var worst_back := 0.0
	for i in range(1,samples.size()):
		if is_nan(samples[i].x) or is_nan(samples[i-1].x):
			unreadable+=1
			continue
		var delta: float=(samples[i].x-samples[i-1].x)*facing
		if delta<-0.001:
			backward+=1
			worst_back=minf(worst_back,delta)
	var worst_tick := 0.0
	for i in range(1,samples.size()):
		if is_nan(samples[i].x) or is_nan(samples[i-1].x): continue
		var tick_dt: float=samples[i].t-samples[i-1].t
		worst_tick=maxf(worst_tick,absf((samples[i].x-samples[i-1].x)*facing-RUN_PX_PER_S*tick_dt))
	check(worst_tick<=TORSO_TICK_SLACK,label+" each physics tick moves the torso by 240*dt (worst %.2f px off, slack %.1f)" % [worst_tick,TORSO_TICK_SLACK])
	check(unreadable==0,label+" every drawn run frame has a readable shirt")
	check(backward==0,label+" drawn torso never steps backward (%d backward ticks, worst %.2f px)" % [backward,worst_back])
	# Animation-frame steps: the first tick of each frame, skipping the partial first interval.
	var starts := []
	for i in range(1,samples.size()):
		if samples[i].frame!=samples[i-1].frame: starts.append(i)
	var expected := RUN_PX_PER_S/RUN_FPS
	var worst_step := 0.0
	for k in range(1,starts.size()):
		var a: Dictionary=samples[starts[k-1]]
		var b: Dictionary=samples[starts[k]]
		if is_nan(a.x) or is_nan(b.x): continue
		worst_step=maxf(worst_step,absf((b.x-a.x)*facing-expected))
	check(starts.size()>=13,label+" shows at least 2 full run cycles after the partial one (%d frame changes)" % starts.size())
	check(worst_step<=TORSO_STEP_SLACK,label+" each frame step is near %.1f px (worst %.1f px off, slack %.1f)" % [expected,worst_step,TORSO_STEP_SLACK])
	var firsts := starts.filter(func(i): return samples[i].frame==0)
	if firsts.size()>=2:
		var first: Dictionary=samples[firsts[0]]
		var last: Dictionary=samples[firsts[firsts.size()-1]]
		var travelled: float=(last.x-first.x)*facing
		var wanted: float=RUN_PX_PER_S*(last.t-first.t)
		check(not is_nan(travelled) and absf(travelled-wanted)<=1.0,label+" torso travels %.2f px over %d cycles, ground covered is %.2f" % [travelled,firsts.size()-1,wanted])
		var per_frame := travelled/float((firsts.size()-1)*6)
		check(not is_nan(per_frame) and absf(per_frame-expected)<=1.0,label+" cycle average is %.2f px per animation frame, 240/13 is %.2f" % [per_frame,expected])
	var run_offset: float=samples[samples.size()-1].x-samples[samples.size()-1].pos
	check(absf(run_offset)<=TORSO_POSE_SLACK,label+" side run torso sits on the pivot (%.2f px)" % run_offset)
	# Every switch is judged from its first new pose, with no ticks skipped.
	for move in [["","hold_idle"],[run_action,"run"],["move_up","walk_up"],["move_down","walk_down"],[run_action,"run"]]:
		hold_move(move[0])
		var first_ticks: Array=await run_samples(actor,6)
		var worst := 0.0
		var wrong := ""
		for sample in first_ticks:
			if sample.clip!=move[1]:
				wrong=sample.clip
				break
			if is_nan(sample.x):
				wrong="unreadable"
				break
			worst=maxf(worst,absf(sample.x-sample.pos))
		check(wrong=="" and worst<=TORSO_POSE_SLACK,label+" switch to "+move[1]+" holds the torso within %.1f px of the pivot from its first tick (worst %.2f, wrong '%s')" % [TORSO_POSE_SLACK,worst,wrong])
	hold_move("")
	actor.controlled=false

func check_torso_motion_all(actor) -> void:
	var saved_fps := Engine.max_fps
	Engine.max_fps=60
	for weapon in Catalog.WEAPONS:
		for facing in [1.0,-1.0]:
			await check_torso_motion(actor,weapon,facing)
	hold_move("")
	Engine.max_fps=saved_fps

## `-- --capture-running [--capture-path=<png>]` renders the real player running through the game
## scene. For each weapon and facing, one row shows ghost copies of the body every few physics ticks
## in world x across: run, stop, start, then side to up and back. Red ticks mark the drawn shirt x.
## Needs a rendered run (use --always-on-top); the suite does not run.
const RUNNING_PATH := "res://../docs/previews/code-city-motion/running_world_space.png"
const RUNNING_ROW := 200
const RUNNING_GHOST_EVERY := 9
const RUNNING_SEGMENTS := [["run",54,""],["stop",9,""],["start",27,""],["up",18,""],["side",18,""]]

func running_target() -> String:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture-running"): return ""
	for i in args.size():
		if args[i].begins_with("--capture-path="): return args[i].trim_prefix("--capture-path=")
		if args[i]=="--capture-path" and i+1<args.size(): return args[i+1]
	return RUNNING_PATH

func ghost(stage: Node2D, actor, at: Vector2, alpha: float) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames=actor.body.sprite_frames
	sprite.animation=actor.body.animation
	sprite.frame=actor.body.frame
	sprite.pause()
	sprite.flip_h=actor.body.flip_h
	sprite.offset=actor.body.offset
	sprite.scale=actor.body.scale
	sprite.modulate=Color(1,1,1,alpha)
	sprite.z_index=0
	sprite.position=at
	stage.add_child(sprite)

func capture_running(path: String) -> void:
	if DisplayServer.get_name()=="headless":
		printerr("FAIL: --capture-running needs a rendered run, not --headless")
		quit(1)
		return
	var weapons: Array=Catalog.WEAPONS.keys()
	var rows := weapons.size()*2
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,rows*RUNNING_ROW)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var stage := Node2D.new()
	stage.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(stage)
	var backdrop := ColorRect.new()
	backdrop.color=Color(.18,.2,.24)
	backdrop.size=Vector2(viewport.size)
	stage.add_child(backdrop)
	game.add_child(viewport)
	var saved_fps := Engine.max_fps
	Engine.max_fps=60
	var actor=game.player
	var row := 0
	for weapon in weapons:
		for facing in [1.0,-1.0]:
			var base_y := row*RUNNING_ROW+RUNNING_ROW-30.0
			var run_action := "move_right" if facing>0 else "move_left"
			actor.equip(weapon);actor.pickup_time=0;actor.stagger=0;actor.input_lock=0
			actor.swing_left=0;actor.combo_window=0;actor.held.show();actor.controlled=true
			actor.facing=facing;actor.steer=facing
			var start_x: float=game.room_start()+(140 if facing>0 else 1000)
			actor.position=Vector2(start_x,560)
			var label := Label.new()
			label.text="%s facing %d" % [weapon,int(facing)]
			label.position=Vector2(6,row*RUNNING_ROW+2)
			stage.add_child(label)
			var ground := ColorRect.new()
			ground.color=Color(.32,.35,.4)
			ground.position=Vector2(0,base_y)
			ground.size=Vector2(1280,1)
			stage.add_child(ground)
			var tick := 0
			var drawn_marks := 0
			for segment in RUNNING_SEGMENTS:
				var action: String={"run":run_action,"stop":"","start":run_action,"up":"move_up","side":run_action}[segment[0]]
				hold_move(action)
				for _i in segment[1]:
					await step_player(actor)
					tick+=1
					var world_x: float=actor.position.x-game.room_start()
					var at := Vector2(world_x,base_y+(actor.position.y-560.0)*0.5)
					if tick%RUNNING_GHOST_EVERY==0: ghost(stage,actor,at,.75)
					var torso := drawn_torso(actor)
					if not is_nan(torso):
						var mark := ColorRect.new()
						mark.color=Color(1,.2,.3,.9)
						mark.position=Vector2(torso-game.room_start(),base_y-110)
						mark.size=Vector2(1,16)
						stage.add_child(mark)
						drawn_marks+=1
				var tag := Label.new()
				tag.text=segment[0]
				tag.add_theme_font_size_override("font_size",11)
				tag.position=Vector2(actor.position.x-game.room_start()-14,row*RUNNING_ROW+RUNNING_ROW-16-(10 if segment[0]=="stop" or segment[0]=="up" else 0))
				stage.add_child(tag)
			check(drawn_marks>40,"%s facing %d running capture has %d torso marks" % [weapon,int(facing),drawn_marks])
			row+=1
	hold_move("")
	Engine.max_fps=saved_fps
	actor.controlled=false
	await process_frame
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	var rid := viewport.get_viewport_rid()
	await RenderingServer.frame_post_draw
	var drawn := 0
	while RenderingServer.viewport_get_update_mode(rid)!=RenderingServer.VIEWPORT_UPDATE_DISABLED and drawn<DRAW_FRAMES:
		await RenderingServer.frame_post_draw
		drawn+=1
	var drew: bool=RenderingServer.viewport_get_update_mode(rid)==RenderingServer.VIEWPORT_UPDATE_DISABLED
	check(drew,"The running world-space viewport draws within %d frames" % DRAW_FRAMES)
	if drew:
		var viewport_texture := viewport.get_texture()
		var image: Image=viewport_texture.get_image() if viewport_texture!=null else null
		if image==null:
			check(false,"The running world-space viewport produced an image")
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
			check(image.save_png(ProjectSettings.globalize_path(path))==OK,"Running world-space sheet saved with %d rows to %s" % [rows,path])
	viewport.queue_free()
	await finish_capture()

func run() -> void:
	var target := capture_target()
	if target!="":
		await capture_locomotion(target)
		return
	if running_target()!="" and not await autoloads_ready():
		printerr("FAIL: root and its autoloads were not ready within %d frames" % READY_FRAMES)
		quit(1)
		return
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame;await process_frame
	game=current_scene
	game.test_mode=true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused=false
	if game.state=="paused": game.resume()
	game.begin_play()
	game.set_physics_process(false)
	var running := running_target()
	if running=="": check_armed_locomotion_clips()
	var p=game.player
	p.set_physics_process(false);p.controlled=false
	for e in game.enemies: e.queue_free()
	game.enemies.clear()
	for prop in game.props: prop.node.queue_free()
	game.props.clear()
	for item in game.pickups: item.node.queue_free()
	game.pickups.clear()
	if running!="":
		await capture_running(running)
		return
	var players: Array=[]
	var i:=0
	for weapon in Catalog.WEAPONS:
		var actor=p if i==0 else game.Player.new()
		if i>0:
			actor.arena=game;game.actors.add_child(actor)
		actor.set_physics_process(false);actor.controlled=false
		actor.position=Vector2(120+i*185,565)
		actor.equip(weapon);actor.pickup_time=0
		actor.tick(.01)
		var sheet = Art.armed(weapon)
		var ready_position: Vector2=actor.held.sprite.position
		if sheet != null:
			check(actor.body.sprite_frames==sheet and actor.body.animation=="hold_idle",weapon+" holds idle on its armed sheet")
			check(not actor.held.sprite.visible,weapon+" hides the legacy cel while armed")
		actor.start_attack();actor.swing_left=actor.swing_duration*.56;actor.swing_fired=true;actor.tick(0)
		if sheet != null:
			check(actor.combo==1 and actor.body.animation=="step1" and actor.body.frame==1,weapon+" contact plays step1 frame 1")
			check(not actor.held.sprite.visible and actor.body.position.x==0,weapon+" keeps the legacy cel hidden and the feet planted")
			var contact_trail: bool = weapon != "firewall_shield"
			check((not actor.held.trail.points.is_empty())==contact_trail,weapon+" trail follows the armed contact window")
		else:
			check(actor.combo==1 and actor.held.sprite.position.distance_to(ready_position)>8,weapon+" animates from guard to contact")
			if weapon=="api_key_whip": check(actor.held.sprite.animation=="api_key_whip_extended","Whip uses its extended contact cel")
		for step in [2,3]:
			actor.swing_left=0;actor.combo_window=.4;actor.start_attack()
			check(actor.combo==step,weapon+" chains step "+str(step))
			if sheet != null: check(actor.body.animation=="step%d"%step,weapon+" plays step "+str(step))
		actor.facing=-1;actor.tick(0)
		check(is_equal_approx(actor.held.scale.x,actor.facing),weapon+" mirrors around the hand when facing left")
		if sheet != null:
			check(actor.body.flip_h and is_equal_approx(actor.body.offset.x,-Art.armed_offset(weapon).x),weapon+" flips the armed pivot when facing left")
		actor.facing=1;actor.tick(0)
		check(is_equal_approx(actor.held.scale.x,actor.facing),weapon+" keeps the rig scale facing right")
		if sheet != null:
			check(not actor.body.flip_h and is_equal_approx(actor.body.offset.x,Art.armed_offset(weapon).x),weapon+" uses the armed pivot when facing right")
		players.append(actor)
		var label := Label.new()
		label.text=weapon.replace("_"," ");label.position=Vector2(-75,20)
		actor.add_child(label)
		i+=1
	# Capture real character/weapon rigs at synchronized contact, windup and recovery.
	game.toast(CAPTION,99)
	for phase in [0.25,0.44,0.7]:
		for actor in players:
			actor.swing_left=actor.swing_duration*(1-phase)
			actor.swing_fired=true
			actor.tick(0)
			var sheet = Art.armed(actor.weapon)
			if sheet == null: continue
			var frame := phase_frame(phase)
			check(actor.body.sprite_frames==sheet and actor.body.animation=="step%d"%actor.combo and actor.body.frame==frame,actor.weapon+" step frame "+str(frame)+" at "+str(phase))
			check(actor.body.position.x==0 and not actor.held.sprite.visible,actor.weapon+" stays planted with the legacy cel hidden at "+str(phase))
			var contact: bool = phase >= .3 and phase < .64 and actor.weapon != "firewall_shield"
			check((not actor.held.trail.points.is_empty())==contact,actor.weapon+" trail at "+str(phase))
		await capture("weapons_%02d" % int(phase*100),CAPTION)
	# Forced cache miss: still the legacy rig after every weapon has a sheet.
	var fallback=game.Player.new()
	fallback.arena=game;game.actors.add_child(fallback)
	fallback.set_physics_process(false);fallback.controlled=false
	fallback.position=Vector2(-500,565)
	Art.armed_sheets["debug_stick"]=null
	fallback.equip("debug_stick");fallback.pickup_time=0;fallback.tick(.01)
	var guard_position: Vector2=fallback.held.sprite.position
	fallback.start_attack();fallback.swing_left=fallback.swing_duration*.56;fallback.swing_fired=true;fallback.tick(0)
	check(fallback.held.sprite.visible and fallback.held.sprite.position.distance_to(guard_position)>8,"Fallback debug stick animates from guard to contact")
	check(fallback.body.sprite_frames==COMBAT_FRAMES and not fallback.armed,"Fallback debug stick uses the unarmed combat frames")
	Art.armed_sheets.erase("debug_stick")
	fallback.queue_free()
	var carrier=null
	for actor in players:
		if Art.armed(actor.weapon)!=null:
			carrier=actor
			break
	if carrier!=null:
		for pose in ["walk_up","walk_down","jump"]:
			carrier.show_pose(pose)
			if check_armed_pose(carrier,pose): continue
			carrier.held.animate(carrier.weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
			# Jump draws behind with the back view. Toward the camera only the shield reaches the cheek.
			var behind: bool=pose=="walk_up" or pose=="jump" or (pose=="walk_down" and carrier.weapon=="firewall_shield")
			check(carrier.held.carry.visible and not carrier.held.sprite.visible and carrier.held.carry.scale==carrier.body.scale and (carrier.held.get_index()<carrier.body.get_index())==behind,carrier.weapon+" carry on "+pose+(" sits behind the body" if behind else " sits in front of the body"))
	check(Art.carry_grip("api_key_whip")==Vector2(8,24),"Whip carry grip is the paw texel (8, 24)")
	check(Art.carry_grip("refactor_hammer")==Vector2(8,38),"Hammer carry grip is the paw texel (8, 38)")
	for weapon in Catalog.WEAPONS:
		if weapon=="api_key_whip" or weapon=="refactor_hammer": continue
		check(Art.carry_grip(weapon)==null,weapon+" keeps the cel grip")
	var whip_actor=players.filter(func(a): return a.weapon=="api_key_whip")[0]
	for pose in ["walk_up","walk_down","jump"]:
		whip_actor.show_pose(pose)
		if check_armed_pose(whip_actor,pose): continue
		whip_actor.held.animate(whip_actor.weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
		check(whip_actor.held.carry.visible and whip_actor.held.carry.offset==-Vector2(8,24),"Whip carry on "+pose+" is gripped at texel (8, 24)")
	var whip_icon: Image=Art.carry("api_key_whip").get_image()
	check(whip_icon.get_pixel(8,24).a>.5,"Whip carry grip texel is opaque")
	var gold_sum := Vector2.ZERO
	var gold_count := 0
	for y in whip_icon.get_height():
		for x in whip_icon.get_width():
			var px := whip_icon.get_pixel(x,y)
			if px.a>.5 and px.r>.55 and px.g>.3 and px.b<.35:
				gold_sum+=Vector2(x,y)
				gold_count+=1
	var gold_mean_x := gold_sum.x/maxf(gold_count,1)
	check(gold_count>0 and gold_mean_x>8.0+15.0,"Whip key sits to the right of the paw")
	var hammer_actor=players.filter(func(a): return a.weapon=="refactor_hammer")[0]
	for pose in ["walk_up","walk_down","jump"]:
		hammer_actor.show_pose(pose)
		if check_armed_pose(hammer_actor,pose): continue
		hammer_actor.held.animate(hammer_actor.weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
		check(hammer_actor.held.carry.visible and hammer_actor.held.carry.offset==-Vector2(8,38),"Hammer carry on "+pose+" is gripped at texel (8, 38)")
	var hammer_icon: Image=Art.carry("refactor_hammer").get_image()
	check(hammer_icon.get_pixel(8,38).a>.5,"Hammer carry grip texel is opaque")
	var mass_sum := 0.0
	var mass_count := 0
	for y in hammer_icon.get_height():
		for x in hammer_icon.get_width():
			if hammer_icon.get_pixel(x,y).a>.5:
				mass_sum+=x
				mass_count+=1
	check(mass_count>0 and mass_sum/maxf(mass_count,1)>8.0+15.0,"Hammer head sits to the right of the paw")
	check_carry_faces(players)
	check_tip_fallback(p)
	p.invulnerable=0;p.swing_left=p.swing_duration*.56;p.swing_fired=true;p.tick(0)
	if Art.armed(p.weapon)!=null and p.weapon!="firewall_shield":
		check(not p.held.trail.points.is_empty(),p.weapon+" draws a contact trail before the hit")
	p.take_hit(p.position-Vector2(30,0));p.tick(.01)
	check(p.swing_left==0 and p.held.trail.points.is_empty(),"Damage cancels the swing trail and returns weapon to carry")
	if Art.armed(p.weapon)!=null: check(p.body.animation=="hurt","Damage leaves the armed step clip for hurt")
	var shield=players.filter(func(a): return a.weapon=="firewall_shield")[0]
	shield.invulnerable=0;shield.swing_left=0;shield.tick(0)
	if Art.armed("firewall_shield")!=null:
		shield.take_hit(shield.position-Vector2(30,0));shield.tick(.1)
		check(shield.hp==3 and shield.block_time>0 and shield.body.animation=="hurt","Shield block plays hurt without damaging Hoppy")
	else:
		var guard_rotation: float=shield.held.sprite.rotation
		var guard_x: float=shield.held.sprite.position.x
		shield.take_hit(shield.position-Vector2(30,0));shield.tick(.1)
		check(shield.hp==3 and shield.block_time>0 and shield.held.sprite.rotation<guard_rotation-.1 and shield.held.sprite.position.x<guard_x-4,"Shield block recoils without damaging Hoppy")
	var whip=Art.armed("api_key_whip")
	if whip!=null:
		var contact_width:=opaque_width(whip,"step2",1)
		var widest:=contact_width
		for frame_index in whip.get_frame_count("step2"):
			widest=maxf(widest,opaque_width(whip,"step2",frame_index))
		check(whip.get_frame_count("step2")>1 and contact_width==widest,"Whip contact frame is the widest step2 frame")
	# Shield swings clear attack_weapon (unarmed combo damage), so only its misses are checked here.
	for weapon in Catalog.WEAPONS:
		if Art.armed(weapon)==null: continue
		p.held.show();p.equip(weapon);p.pickup_time=0;p.hp=3;p.position=Vector2(400,560)
		for facing in [1.0,-1.0]:
			swing_effect(p,facing,false)
		if weapon=="firewall_shield": continue
		p.equip(weapon);p.pickup_time=0
		for facing in [1.0,-1.0]:
			swing_effect(p,facing,true)
	# The whip outreaches any tip: a hit 200 px out still bursts on the enemy (armed sheet or legacy rig).
	p.held.show();p.equip("api_key_whip");p.pickup_time=0;p.hp=3;p.position=Vector2(400,560)
	for facing in [1.0,-1.0]:
		swing_effect(p,facing,true,200.0)
	check_armed_run_registration(p)
	var sheet_weapon:=""
	for weapon in Catalog.WEAPONS:
		if Art.armed(weapon)!=null:
			sheet_weapon=weapon
			break
	if sheet_weapon!="":
		p.held.show();p.equip(sheet_weapon);p.pickup_time=0;p.swing_left=0;p.stagger=0;p.facing=1
		p.show_pose("run",true)
		check(p.body.sprite_frames==Art.armed(sheet_weapon) and p.body.animation=="run" and not p.held.sprite.visible and not p.held.carry.visible,"Stage run plays the armed clip without carry or legacy overlays")
		p.held.hide();p.show_pose("run",true)
		check(p.armed_sheet()==null and not p.armed and p.body.sprite_frames==PLATFORMER_FRAMES and p.body.animation=="run","Hiding the weapon returns the finisher to the unarmed platformer frames")
	for actor in players:
		if actor!=p: actor.queue_free()
	p.hp=3;p.invulnerable=0
	await check_torso_motion_all(p)
	game.start_stage(2)
	await process_frame;await process_frame
	game.begin_play();game.set_physics_process(false)
	game.flow.banner("","",0) # the test jumps straight into the boss room; the title banner has long finished
	p=game.player;p.set_physics_process(false);p.controlled=false
	for e in game.enemies: e.queue_free()
	game.enemies.clear()
	game.enter_room(2)
	var boss=game.boss;boss.set_physics_process(false)
	p.position=Vector2(game.room_start()+500,580)
	game.camera.position=Vector2(game.room_start()+640,360)
	var original: Vector2=boss.position
	boss.tick(.5)
	check(boss.position.distance_to(original)>60,"Phase 1 advances toward Hoppy before attacking")
	boss.cycle=1;boss.telegraph()
	var committed: Vector2=boss.destination
	check(game.warnings.back().left>boss.timer+0.6,"Landing warning includes the leap travel time")
	p.position.x-=220
	boss.tick(.96);boss.tick(.3)
	check(boss.position.distance_to(original)>100 and boss.body.position.y < -70,"Slam travels across the ground with visible airborne height")
	check(boss.destination==committed,"Leap does not retarget after its warning")
	game._update_hud()
	await capture("boss_leap","THE GRAND MERGE CONFLICT")
	boss.tick(.36)
	check(boss.state=="recover" and boss.vulnerable and boss.position.is_equal_approx(committed),"Landing exposes the core at the committed destination")
	var landing: Vector2=boss.position
	boss.tick(.5)
	check(boss.position==landing,"Recovery gives Hoppy a stationary punish window")
	for phase in [2,3]:
		boss.position=Vector2(game.room_start()+900,560)
		p.position=Vector2(game.room_start()+500,560)
		boss.phase=phase
		boss.body.sprite_frames=game.Art.frames("split_screen" if phase==2 else "merge_chaos")
		boss.begin_reposition()
		var from: Vector2=boss.position
		boss.tick(.5)
		check(boss.position.distance_to(from)>150,"Phase %d actively flanks between attacks" % phase)
		check(boss.position==boss.arena_point(boss.position),"Boss movement stays within the arena")
	# Both Phase 3 attacks must advertise their entire punish window.
	for attack in ["clone","storm"]:
		boss.phase=3;boss.move=attack;boss.state="active";boss.timer=.01
		boss.destination=boss.position;boss.leaping=false
		boss.tick(.02)
		check(boss.vulnerable and boss.body.animation=="hurt" and boss.core_cue.visible,attack+" recovery immediately displays the exposed-core animation")
		var recovery_pos: Vector2=boss.position
		var first_scale: Vector2=boss.body.scale
		boss.tick(.2)
		check(boss.body.scale!=first_scale and boss.position==recovery_pos,"Core breathes while boss stays stationary")
		check(boss.core_cue.remaining<1 and boss.core_cue.remaining>.8,"Core ring counts down the damage window")
		if attack=="storm":
			var saved_timer: float=boss.timer
			var saved_pulse: float=boss.core_cue.elapsed
			boss.set_physics_process(true)
			paused=true
			for frame in 3: await physics_frame
			check(boss.timer==saved_timer and boss.core_cue.elapsed==saved_pulse,"Pause freezes recovery and the visual countdown together")
			boss.set_physics_process(false)
			paused=false
			game._update_hud()
			await capture("boss_phase3_exposed","CORE EXPOSED — land a finisher!")
		boss.tick(1.85)
		check(boss.vulnerable and boss.core_cue.visible and boss.body.animation=="hurt","Exposure cue persists to the end of recovery")
		boss.tick(.06)
		check(not boss.vulnerable and not boss.core_cue.visible and boss.body.animation=="idle","Exposure cue clears when the boss resumes moving")
	boss.phase=1;boss.hp=24;boss.vulnerable=true
	boss.take_hit(12,0,p.position,true)
	var transition_pos: Vector2=boss.position
	boss.tick(.2)
	check(boss.position==transition_pos and not boss.leaping and boss.body.position==Vector2.ZERO,"Phase transition cancels travel and aerial offsets")
	boss.phase=3;boss.state="recover";boss.timer=1;boss.vulnerable=true
	boss.body.sprite_frames=game.Art.frames("merge_chaos")
	boss.tick(0)
	check(boss.core_cue.visible,"Final strike begins with the core visibly exposed")
	boss.take_hit(24,0,p.position,true)
	boss.tick(.5)
	check(boss.position==transition_pos and not boss.leaping and not boss.core_cue.visible,"Defeat clears movement and the exposed-core cue")
	print("Code City motion failures: ",failures)
	game.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
