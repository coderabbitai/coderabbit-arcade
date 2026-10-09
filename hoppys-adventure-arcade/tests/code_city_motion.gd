extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const COMBAT_FRAMES = preload("res://Assets/code-city-brawl-player/combat.tres")
const PLATFORMER_FRAMES = preload("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
## The weapon captures' deliberate on-screen caption.
const CAPTION := "EQUIPPED WEAPON ANIMATION · windup / contact / recovery"
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

func carry_should_behind(kind: String, pose: String) -> bool:
	if pose=="walk_up" or pose=="jump": return true
	if pose=="walk_down": return kind=="firewall_shield"
	return false

func carry_face_hits(carry: Sprite2D, image: Image, box: Rect2, body_scale: float, pivot: Vector2) -> int:
	if image.is_compressed(): image.decompress()
	var size := Vector2(image.get_width(),image.get_height())
	var shift := size*.5 if carry.centered else Vector2.ZERO
	var xform := carry.get_transform()
	var hits := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a<=.5: continue
			var cel: Vector2=xform*(Vector2(x+.5,y+.5)+carry.offset-shift)/body_scale+pivot
			if box.has_point(cel): hits+=1
	return hits

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
				var hits := carry_face_hits(carry,image,FACE_BOX[pose],actor.body.scale.y,FACE_PIVOT)
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
## Mean x of opaque pixels behind the weapon paw, from the foot row up one unarmed body.
func body_reference_x(cell_image: Image, foot_y: int, hand_x: int, body_height: int) -> float:
	var y0 := maxi(0, foot_y - body_height)
	var y1 := mini(cell_image.get_height() - 1, foot_y)
	var x_end := mini(cell_image.get_width(), hand_x - 2)
	if y1 < y0 or x_end <= 0:
		return NAN
	var sum := 0.0
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x_end):
			if cell_image.get_pixel(x, y).a >= 128.0 / 255.0:
				sum += float(x)
				count += 1
	if count == 0:
		return NAN
	return sum / float(count)

func _fmt_xs(values: PackedFloat32Array) -> String:
	var text := ""
	for i in values.size():
		text += (", " if i > 0 else "") + "%.2f" % values[i]
	return text if not text.is_empty() else "none"

## Body reference of one armed run frame, measured on the texture the sprite is showing.
func armed_run_cel(body: AnimatedSprite2D, spec: Dictionary, anim_frame: int) -> float:
	var clips: Variant = spec.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var run_frames: Variant = run.get("frames", []) if run is Dictionary else []
	var anchors: Variant = spec.get("anchors", {})
	var hands: Variant = anchors.get("hand", {}) if anchors is Dictionary else {}
	var pivot: Variant = spec.get("pivot", [])
	var cell_data: Variant = spec.get("cell", [])
	if not run_frames is Array or anim_frame < 0 or anim_frame >= run_frames.size():
		return NAN
	if not hands is Dictionary or not pivot is Array or pivot.size() < 2 or not cell_data is Array or cell_data.size() < 2:
		return NAN
	if not spec.has("unarmed_idle_height"):
		return NAN
	var sheet_frame := int(run_frames[anim_frame])
	var hand: Variant = hands.get(str(sheet_frame), [])
	if not hand is Array or hand.size() < 2:
		return NAN
	if body.sprite_frames == null or not body.sprite_frames.has_animation("run"):
		return NAN
	var texture := body.sprite_frames.get_frame_texture("run", anim_frame)
	if texture == null:
		return NAN
	var image := texture.get_image()
	if image == null:
		return NAN
	if image.is_compressed():
		image.decompress()
	if image.get_size() != Vector2i(int(cell_data[0]), int(cell_data[1])):
		return NAN
	return body_reference_x(image, int(pivot[1]), int(hand[0]), int(spec.unarmed_idle_height))

func _restore_run_actor(actor, saved: Dictionary) -> void:
	actor.position = saved.position
	actor.facing = saved.facing
	actor.weapon = saved.weapon
	actor.visual_weapon = saved.visual_weapon
	actor.durability = saved.durability
	actor.pickup_time = saved.pickup_time
	actor.swing_left = saved.swing_left
	actor.combo = saved.combo
	actor.combo_window = saved.combo_window
	actor.height = saved.height
	actor.rise = saved.rise
	actor.stagger = saved.stagger
	actor.queued = saved.queued
	actor.knock = saved.knock
	actor.velocity = saved.velocity
	actor.held.visible = saved.held_visible
	actor.body.position = saved.body_position
	actor.body.modulate = saved.modulate
	actor.body.sprite_frames = saved.frames
	actor.body.flip_h = saved.flip
	actor.body.speed_scale = saved.speed_scale
	var anim := str(saved.animation)
	if actor.body.sprite_frames != null and actor.body.sprite_frames.has_animation(anim):
		actor.body.animation = anim
		actor.body.pause()
		var count: int = actor.body.sprite_frames.get_frame_count(anim)
		if count > 0:
			actor.body.frame = clampi(int(saved.frame), 0, count - 1)
	actor.body.offset = saved.offset

## Armed run keeps the body still, in the sheet and on the stage-exit run-out.
func check_armed_run_registration(actor) -> void:
	var saved := {
		"position": actor.position,
		"facing": actor.facing,
		"weapon": actor.weapon,
		"visual_weapon": actor.visual_weapon,
		"durability": actor.durability,
		"pickup_time": actor.pickup_time,
		"swing_left": actor.swing_left,
		"combo": actor.combo,
		"combo_window": actor.combo_window,
		"height": actor.height,
		"rise": actor.rise,
		"stagger": actor.stagger,
		"queued": actor.queued,
		"knock": actor.knock,
		"velocity": actor.velocity,
		"held_visible": actor.held.visible,
		"frames": actor.body.sprite_frames,
		"animation": actor.body.animation,
		"offset": actor.body.offset,
		"flip": actor.body.flip_h,
		"speed_scale": actor.body.speed_scale,
		"body_position": actor.body.position,
		"modulate": actor.body.modulate,
		"frame": actor.body.frame,
	}
	for weapon in Catalog.WEAPONS:
		var sheet: SpriteFrames = Art.armed(weapon)
		var spec: Dictionary = Art.armed_spec(weapon)
		if sheet == null or spec.is_empty() or not spec.has("cell") or not spec.has("pivot"):
			for facing in [1.0, -1.0]:
				check(false, "%s facing %d armed run uses the sheet, clip run, and armed offset (no armed sheet)" % [weapon, int(facing)])
				check(false, "%s facing %d armed run body stays within 3 * scale px (no armed sheet)" % [weapon, int(facing)])
			continue
		actor.swing_left = 0
		actor.visual_weapon = ""
		actor.stagger = 0
		actor.height = 0
		actor.held.show()
		actor.equip(weapon)
		actor.pickup_time = 0
		var base_offset: Vector2 = Art.armed_offset(weapon)
		for facing in [1.0, -1.0]:
			actor.facing = facing
			actor.swing_left = 0
			actor.show_pose("run")
			var expected_offset := Vector2(-base_offset.x if facing < 0.0 else base_offset.x, base_offset.y)
			var frames: SpriteFrames = actor.body.sprite_frames
			var pose_ok: bool = frames == sheet and actor.body.animation == "run" and frames.has_animation("run") and frames.get_frame_count("run") == 4
			var detail: String = "clip %s offset %s expected %s" % [actor.body.animation, actor.body.offset, expected_offset]
			var worlds := PackedFloat32Array()
			var cels := PackedFloat32Array()
			var measured: bool = pose_ok
			var limit: float = 3.0 * float(actor.body.scale.x)
			if pose_ok:
				var pivot_x := float(spec.pivot[0])
				var sign: float = -1.0 if facing < 0.0 else 1.0
				for f in 4:
					actor.body.pause()
					actor.body.frame = f
					var frame_ok: bool = actor.body.sprite_frames == sheet and actor.body.animation == "run" and actor.body.offset.is_equal_approx(expected_offset) and actor.body.flip_h == (facing < 0.0)
					if not frame_ok:
						pose_ok = false
						measured = false
						detail = "frame %d clip %s offset %s expected %s flip %s" % [f, actor.body.animation, actor.body.offset, expected_offset, actor.body.flip_h]
						break
					var cel := armed_run_cel(actor.body, spec, f)
					if is_nan(cel):
						measured = false
						detail = "frame %d has no body pixels behind the paw" % f
						break
					cels.append(cel)
					worlds.append((cel - pivot_x) * actor.body.scale.x * sign)
			else:
				measured = false
			check(pose_ok, "%s facing %d armed run uses the sheet, clip run, and armed offset (%s)" % [weapon, int(facing), detail])
			var worst := 0.0
			var worst_at := "n/a"
			if worlds.size() == 4:
				for i in worlds.size():
					var nxt := (i + 1) % worlds.size()
					var step := absf(worlds[nxt] - worlds[i])
					if step > worst:
						worst = step
						worst_at = "%d to %d" % [i + 1, nxt + 1]
			check(measured and worlds.size() == 4 and worst <= limit, "%s facing %d armed run body stays within %.2f px across run frames (worst %.2f between %s; world x %s; cel x %s)" % [weapon, int(facing), limit, worst, worst_at, _fmt_xs(worlds), _fmt_xs(cels)])
	actor.swing_left = 0
	actor.visual_weapon = ""
	actor.held.show()
	actor.equip("debug_stick")
	actor.pickup_time = 0
	var exit_sheet: SpriteFrames = Art.armed("debug_stick")
	game.flow.play_exit(func(): pass)
	for _tick in 4:
		game.flow.tick(1.0 / 60.0, actor)
	check(exit_sheet != null and actor.body.animation == "run" and actor.body.sprite_frames == exit_sheet, "debug_stick stage exit run uses the armed sheet (clip %s)" % actor.body.animation)
	game.flow.cancel()
	_restore_run_actor(actor, saved)

func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame;await process_frame
	game=current_scene
	game.test_mode=true
	game.begin_play()
	game.set_physics_process(false)
	var p=game.player
	p.set_physics_process(false);p.controlled=false
	for e in game.enemies: e.queue_free()
	game.enemies.clear()
	for prop in game.props: prop.node.queue_free()
	game.props.clear()
	for item in game.pickups: item.node.queue_free()
	game.pickups.clear()
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
