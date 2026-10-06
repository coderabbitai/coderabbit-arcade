extends CharacterBody2D
## One independently damageable villain actor. The arena owns the dual encounter.
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
var arena: Node2D
var kind := "ai_slop"
var fused := false
var hp := 30.0
var max_hp := 30.0
var phase := 1
var dead := false
var is_boss := true
var body: AnimatedSprite2D
var state := "chase"
var timer := 1.1
var cooldown := 1.1
var action_index := 0
var action := "melee"
var facing := -1.0
var aim := Vector2.ZERO
var dash_direction := Vector2.ZERO
var shield_active := false
var triage_marked := false
var vector: Node2D
var vector_body: AnimatedSprite2D
var vector_aim := Vector2.ZERO
var vector_direction := Vector2.ZERO
var flash := 0.0

func _ready() -> void:
	max_hp = {"ai_slop":30.0,"agent_army":12.0 if fused else 8.0,"ten_thousand_line_pr":24.0,"ai_augmented_hacker":36.0}[kind]
	hp=max_hp
	collision_layer=0;collision_mask=0
	add_child(Art.shadow(62))
	body=Art.sprite(kind,"fused_idle" if fused else "idle",1.6)
	add_child(body)
	if kind=="ai_augmented_hacker":
		vector=Node2D.new()
		arena.actors.add_child(vector)
		vector.add_child(Art.shadow(45))
		vector_body=Art.sprite(kind,"vector_revealed",1.45)
		vector.add_child(vector_body)
		vector.hide()

func _physics_process(dt: float) -> void:
	if arena.playing: tick(dt)

func tick(dt: float) -> void:
	if dead: return
	timer-=dt;cooldown-=dt;flash=maxf(0,flash-dt)
	if shield_active:
		if arena.count_kind("slop_sprite")==0:
			shield_active=false
			state="recover";timer=2.2
			pose("shield_break")
			arena.toast("LGTM FIELD BROKEN — attack AI SLOP!",2)
		update_visual()
		return
	if state=="transition":
		if timer<=0: state="recover";timer=1.1
	elif state=="tell":
		if timer<=0: release_attack()
	elif state=="attack":
		if action in ["dash","rush","formation"]:
			var speed := 560.0 if action=="dash" else 330.0
			position=arena.clamp_ground(position+dash_direction*speed*dt)
			contact(position)
			if kind=="ai_augmented_hacker" and phase==3:
				vector.position=arena.clamp_ground(vector.position+vector_direction*speed*dt)
				contact(vector.position)
		if timer<=0:
			state="recover";timer=1.3 if kind!="ai_augmented_hacker" else 1.05
			pose("recover" if kind!="ai_slop" else "weakened")
	elif state=="recover":
		if timer<=0:
			state="chase";cooldown=.5
	else:
		var delta_to: Vector2=arena.player.position-position
		facing=-1 if delta_to.x<0 else 1
		var distance := 160.0 if kind in ["ai_slop","ten_thousand_line_pr"] else 230.0
		if delta_to.length()>distance:
			position=arena.clamp_ground(position+delta_to.normalized()*(80 if kind=="ten_thousand_line_pr" else 125)*dt)
		pose("fused_idle" if fused else "machine_mode" if phase==3 and kind=="ai_augmented_hacker" else "idle")
		if cooldown<=0: choose_attack()
	update_visual()

func pose(name: String) -> void:
	body.play(name if body.sprite_frames.has_animation(name) else "idle")

func choose_attack() -> void:
	action_index+=1
	aim=arena.player.position
	state="tell"
	match kind:
		"ai_slop":
			if phase==1:
				action=["summon","melee","burst"][action_index%3]
			else: action="barrage" if action_index%2==0 else "rush"
			timer=.8 if phase==1 else .6
			pose({"summon":"summon","melee":"melee_warning","burst":"burst_warning","barrage":"burst_warning","rush":"melee_warning"}[action])
		"agent_army":
			action="formation";timer=.8+(3-arena.alive_bosses())*.18 if not fused else .7
			pose("fused_idle" if fused else "jab_warning")
		"ten_thousand_line_pr":
			action="slam" if action_index%2==0 else "nightmare"
			timer=1.05
			pose("slam_warning" if action=="slam" else "nightmare_warning")
			arena.ground_warning(aim,Vector2(145,58) if action=="slam" else Vector2(510,30),timer,.35,action,self)
		"ai_augmented_hacker":
			action="injection" if phase==2 and action_index%2==0 else "dash"
			timer=.42 if phase<3 else .32
			pose("injection_warning" if action=="injection" else "dash_warning")
			if phase==1 and action_index%3==0:
				arena.spawn_enemy("security_gap_crawler",arena.clamp_ground(Vector2(arena.room_start()+1080,470)))
			if phase==3:
				vector.position=arena.clamp_ground(position+Vector2(-180,90 if position.y<550 else -90))
				vector_aim=arena.player.position+Vector2(0,65 if arena.player.position.y<550 else -65)
				vector_body.play("dash_warning")
	queue_redraw()

func release_attack() -> void:
	dash_direction=(aim-position).normalized()
	state="attack";timer=.36
	match action:
		"summon":
			if arena.count_kind("slop_sprite")<5:
				for side in [-1,1]: arena.spawn_enemy("slop_sprite",arena.clamp_ground(position+Vector2(side*110,45)))
			arena.sound("spawn",position)
			pose("summon")
		"melee":
			pose("melee")
			arena.ground_warning(aim,Vector2(145,48),0,.24,"slam",self)
		"burst","barrage":
			pose("burst" if action=="burst" else "barrage")
			for i in 5:
				arena.projectile(position,dash_direction.rotated((i-2)*.18)*260,"tracking_projectile" if action=="barrage" else "api_projectile","confused",action=="barrage")
		"rush": pose("rush");timer=.6
		"formation": pose("fused_attack" if fused else "jab");timer=.45
		"slam": pose("slam");arena.sound("collapse",position)
		"nightmare": pose("nightmare");arena.sound("collapse",position)
		"injection":
			pose("injection")
			for i in 3: arena.projectile(position,dash_direction.rotated((i-1)*.16)*335,"injector_projectile","strength_down")
		"dash":
			pose("vector_attack" if phase==3 else "dash")
			timer=.5
			arena.sound("whoosh",position)
			if phase==3:
				vector_direction=(vector_aim-vector.position).normalized()
				vector_body.play("vector_attack")

func contact(pos: Vector2) -> void:
	var offset: Vector2=arena.player.position-pos
	if absf(offset.x)<85 and absf(offset.y)<42:
		arena.player.take_hit(pos,"strength_down" if kind=="ai_augmented_hacker" and phase>=2 else "",220)

func take_hit(damage: float, _force: float, _from: Vector2, _finisher := false) -> bool:
	if dead or shield_active or state=="transition": return false
	var next := hp-damage
	if kind in ["ai_slop","ai_augmented_hacker"]:
		if phase==1 and next<=max_hp*.6:
			hp=max_hp*.6
			change_phase(2)
		elif phase==2 and next<=max_hp*.3:
			hp=max_hp*.3
			change_phase(3)
		else: hp=next
	else: hp=next
	flash=.14
	if hp<=0:
		hp=0;dead=true
		pose("defeat" if body.sprite_frames.has_animation("defeat") else "melt")
		arena.clear_owned_threats(self)
		if is_instance_valid(vector): vector.hide()
		arena.score+=500
		arena.sound("collapse",position)
	return true

func change_phase(next: int) -> void:
	phase=next
	state="transition";timer=.8
	arena.clear_owned_threats(self)
	arena.clear_projectiles()
	arena.sound("phase",position)
	if kind=="ai_slop":
		if phase==3:
			shield_active=arena.count_kind("slop_sprite")>0
			pose("shield_raise" if shield_active else "shield_break")
			arena.toast("CLEAR THE SLOP TO BREAK LGTM" if shield_active else "NO SLOP LEFT — LGTM FIELD SHATTERED",3)
		else: arena.toast("AI SLOP: AGGRESSIVE API BARRAGE",2)
	else:
		if phase==2: arena.spawn_enemy("zero_day_phantom",arena.clamp_ground(position+Vector2(-160,50)))
		if phase==3: vector.show();vector.position=arena.clamp_ground(position+Vector2(-180,-65))
		arena.toast("INJECTION MODE" if phase==2 else "MACHINE MODE — TWO ATTACK VECTORS",3)

func stun(seconds: float) -> void:
	if dead or shield_active or state=="transition": return
	state="recover";timer=maxf(timer,seconds)
	arena.clear_owned_threats(self)
	pose("recover")

func update_visual() -> void:
	body.flip_h=facing>0
	body.modulate=Color(1.6,1.4,1.2) if flash>0 else Color.WHITE
	if shield_active:
		pose("shield")
		body.modulate=Color(.75,1.2,1.0,.78+.15*sin(arena.elapsed*6))
	if is_instance_valid(vector) and phase==3:
		vector.visible=not dead
		vector_body.modulate.a=1.0 if arena.reveal_time>0 or arena.capabilities.security else .04
		vector_body.flip_h=vector_direction.x>0
	queue_redraw()

func _draw() -> void:
	if dead: return
	if state=="tell":
		draw_arc(Vector2.ZERO,62,0,TAU,32,Color("ff8740"),4)
		draw_line(Vector2.ZERO,aim-position,Color(1,.4,.1,.7),3)
		if kind=="ai_augmented_hacker" and phase==3 and is_instance_valid(vector):
			draw_line(vector.position-position,vector_aim-position,Color(.4,1,.5,.7),3)
	if state=="recover": draw_arc(Vector2(0,-92),80,0,TAU,32,Color(1,.75,.2,.7),3)
	if triage_marked: draw_colored_polygon(PackedVector2Array([Vector2(-13,-220),Vector2(13,-220),Vector2(0,-201)]),Color("ffae24"))

func _exit_tree() -> void:
	if is_instance_valid(vector): vector.queue_free()
