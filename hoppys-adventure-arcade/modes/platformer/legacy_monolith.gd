extends "res://modes/platformer/enemy.gd"
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
signal shockwave(start: Vector2, direction: Vector2)
const STATES := ["tracking","slam_warning","slam","slam_recover","tracking","sweep_warning","sweep","sweep_recover","tracking","stomp_warning","stomp","stomp_recover"]
const DURATIONS := [1.1,1.0,.18,1.4,.8,.9,.25,1.4,.8,1.0,.2,1.6]
var active := false
var state_index := 0
var state_time := 0.0
var armor_stage := 0
var break_time := 0.0
var direction := -1.0
var attack_name := "TECHNICAL DEBT SEALED"
var sheet := ""

func _ready() -> void:
	kind = "legacy_monolith"
	hp = 12 # 3 outer armor + 3 inner armor + 6 core.
	sprite = AnimatedSprite2D.new()
	add_child(sprite)
	_pose("idle")
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 2
	hurtbox.add_child(Art.shape(Vector2(124,150),Vector2(0,-75)))
	add_child(hurtbox)

func state() -> String:
	return STATES[state_index]

func vulnerable() -> bool:
	return active and not dead and break_time <= 0 and state().ends_with("recover")

func _pose(clip: String) -> void:
	var next_sheet := "legacy_monolith" if armor_stage == 0 or clip == "defeat" else "monolith_armor"
	if sheet != next_sheet:
		sheet = next_sheet
		sprite.sprite_frames = load(ForestArt.ROOT+sheet+".tres")
		sprite.offset = Vector2(0,-77 if sheet == "legacy_monolith" else -102)
		# Match neutral standing heights across independently authored armor atlases.
		sprite.scale = Vector2.ONE * (1.35 if sheet == "legacy_monolith" else 1.35*141.0/134.0)
	if next_sheet == "monolith_armor":
		if clip.ends_with("recover") or clip == "armor_break": clip = "exposed"
		clip = ("cracked_" if armor_stage == 1 else "bare_") + clip
	sprite.play(clip)

func _physics_process(dt: float) -> void:
	if dead or not active or player.hp <= 0: return
	hit_flash = maxf(0,hit_flash-dt)
	sprite.modulate = Color(2,1,1) if hit_flash > 0 else (Color(.7,1,.9) if vulnerable() else Color.WHITE)
	if break_time > 0:
		break_time = maxf(0,break_time-dt)
		attack_name = "ARMOR STRIPPED — " + ("INNER LAYER REMAINS" if armor_stage == 1 else "CORE EXPOSED")
		_pose("armor_break")
		if break_time <= 0: _enter_state(3)
		queue_redraw()
		return
	state_time += dt
	if state_time >= DURATIONS[state_index]: _enter_state((state_index+1)%STATES.size())
	var current := state()
	var layer_text := "OUTER ARMOR %d/3" % (hp-9) if armor_stage == 0 else ("INNER ARMOR %d/3" % (hp-6) if armor_stage == 1 else "CORE %d/6" % hp)
	attack_name = layer_text + " · " + ("RECOVERY — ATTACK!" if vulnerable() else {"tracking":"KEEP YOUR DISTANCE", "slam_warning":"DEBT SLAM — JUMP!", "sweep_warning":"LOW SWEEP — JUMP!", "stomp_warning":"STOMP — WATCH THE WAVE"}.get(current,current.replace("_"," ").to_upper()))
	_pose("idle" if current == "tracking" else current)
	if current == "tracking":
		var dx := player.position.x-position.x
		if absf(dx)>160: position.x=clampf(position.x+signf(dx)*65*dt,4350,4810)
		sprite.flip_h=dx>0
	elif current in ["slam","stomp"]:
		var reach := 175.0 if current == "slam" else 95.0
		if absf(player.position.x-position.x)<reach and player.position.y>position.y-42 and player.position.y<position.y+30:
			player.damage(position.x)
	elif current == "sweep":
		var dx := (player.position.x-position.x)*direction
		if dx>-30 and dx<215 and player.position.y>position.y-58 and player.position.y<position.y+30:
			player.damage(position.x)
	if hurtbox.overlaps_body(player):
		if player.velocity.y>120 and player.position.y<position.y-115:
			take_hit()
			player.velocity.y=-440
		elif not vulnerable(): player.damage(position.x)
	queue_redraw()

func _enter_state(index: int) -> void:
	state_index=index
	state_time=0
	if state().ends_with("warning"):
		direction=1 if player.position.x>position.x else -1
		sprite.flip_h=direction>0
	if state()=="stomp": shockwave.emit(position+Vector2(direction*105,-18),Vector2(direction,0))
	sprite.stop()

func take_hit() -> void:
	if not vulnerable() or hit_flash>0: return
	hp-=1
	hit_flash=.28
	if hp<=0:
		dead=true
		active=false
		hurtbox.set_deferred("monitorable",false)
		_pose("defeat")
		defeated.emit(1000)
		queue_redraw()
		# Leave the final rubble in the cleared arena.
		return
	if hp in [9,6]:
		armor_stage+=1
		break_time=1.0
		_spawn_fragments()

func _spawn_fragments() -> void:
	for side in [-1,1]:
		var fragment := Sprite2D.new()
		fragment.texture=ForestArt.crop("hazards","armor_chunk")
		fragment.position=Vector2(side*40,-125)
		fragment.scale=Vector2.ONE*.35
		add_child(fragment)
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_parallel()
		tween.tween_property(fragment,"position",Vector2(side*140,-10),.8)
		tween.tween_property(fragment,"rotation",side*1.8,.8)
		tween.tween_property(fragment,"modulate:a",0.0,.8)
		tween.chain().tween_callback(fragment.queue_free)

func _draw() -> void:
	if dead or not active: return
	if break_time>0:
		draw_arc(Vector2(0,-95),75,0,TAU,32,Color(.4,1,.85,break_time),4)
		return
	var current := state()
	if current in ["slam_warning","slam","stomp_warning","stomp","sweep_warning","sweep"]:
		var warning := current.ends_with("warning")
		var reach := 175.0 if current.begins_with("slam") else 95.0
		var rect := Rect2(-reach,-8,reach*2,8)
		if current.begins_with("sweep"): rect=Rect2(-30 if direction>0 else -215,-58,245,58)
		if warning: draw_rect(rect,Color(1,.75,.25,.55),false,3)
		else: draw_rect(rect,Color(.85,.25,1,.7))
		if current=="stomp_warning":
			draw_line(Vector2(direction*105,-18),Vector2(direction*310,-18),Color("ffc769"),3)
