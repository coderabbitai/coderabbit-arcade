extends CharacterBody2D
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
const Catalog = preload("res://modes/beatem_up/reinvent/catalog.gd")
var arena: Node2D
var kind := "slop_sprite"
var hp := 1.0
var max_hp := 1.0
var body: AnimatedSprite2D
var state := "chase"
var timer := 0.0
var cooldown := 1.0
var self_damage_clock := 6.0
var teleport_cooldown := 0.0
var facing := -1.0
var aim := Vector2.ZERO
var knock := Vector2.ZERO
var can_split := true
var armor := false
var shield := false
var dead := false
var is_boss := false
var hidden_enemy := false
var reveal_left := 0.0
var spawner: Node2D
var triage_marked := false
var data: Dictionary

func _ready() -> void:
	data = Catalog.ENEMIES[kind]
	hp = data.hp
	max_hp = hp
	armor = kind=="broken_test_bot"
	shield = kind=="change_stack_soldier"
	hidden_enemy = kind in ["security_gap_crawler","zero_day_phantom"]
	collision_layer = 0
	collision_mask = 0
	add_child(Art.shadow(26))
	body = Art.sprite(kind,"idle",1.7)
	add_child(body)
	cooldown += arena.rng.randf_range(0,.4)
	update_visual()

func _physics_process(dt: float) -> void:
	if arena.playing: tick(dt)

func tick(dt: float) -> void:
	if dead: return
	if is_instance_valid(spawner) and spawner.dead:
		finish_death(false)
		return
	timer -= dt
	cooldown -= dt
	reveal_left = maxf(0,reveal_left-dt)
	teleport_cooldown = maxf(0,teleport_cooldown-dt)
	if kind=="broken_test_bot":
		self_damage_clock -= dt
		if self_damage_clock<=0:
			self_damage_clock = 6.0
			hp -= 1
			arena.fx("capabilities_fx","unlock_sparkle",position-Vector2(0,40),.5,.3)
			if hp<=0: finish_death(); return
	if state=="hurt" or state=="stunned":
		position = arena.clamp_ground(position+knock*dt)
		knock = knock.move_toward(Vector2.ZERO,800*dt)
		if timer<=0: state="chase"; cooldown=.55
	elif state=="tell":
		if timer<=0: release_attack()
	elif state=="attack":
		if kind in ["ai_hacker_drone","security_gap_crawler"]:
			position = arena.clamp_ground(position+aim*400*dt)
		var delta_to: Vector2 = arena.player.position-position
		if delta_to.x*facing>=-20 and absf(delta_to.x)<95 and absf(delta_to.y)<42:
			arena.player.take_hit(position)
		if timer<=0: state="recover"; timer=.65; body.play("idle")
	elif state=="recover":
		if timer<=0: state="chase"; cooldown=.65
	else:
		var delta_to: Vector2 = arena.player.position-position
		facing = -1 if delta_to.x<0 else 1
		var ranged := kind in ["hallucinated_api_gremlin","vulnerability_injector"]
		var reach := 390.0 if ranged else 300.0 if kind in ["ai_hacker_drone","security_gap_crawler"] else 105.0
		if kind=="agent_spawner":
			if cooldown<=0: start_tell()
		elif cooldown<=0 and absf(delta_to.x)<reach and absf(delta_to.y)<(100 if ranged else 44):
			start_tell()
		else:
			var target: Vector2 = arena.player.position
			if ranged: target.x -= facing*270
			var movement := (target-position).normalized() if target.distance_to(position)>25 else Vector2.ZERO
			for other in arena.enemies:
				if other!=self and is_instance_valid(other) and not other.dead and position.distance_to(other.position)<50:
					movement += (position-other.position).normalized()*.7
			velocity = movement.limit_length()*float(data.speed)
			move_and_slide()
			position = arena.clamp_ground(position)
			body.play("idle")
	update_visual()

func start_tell() -> void:
	state="tell"
	timer=data.tell
	aim=arena.player.position
	body.play("attack_warning")

func release_attack() -> void:
	body.play("attack")
	if kind=="agent_spawner":
		var child: Node2D = arena.spawn_enemy("slop_sprite",arena.clamp_ground(position+Vector2(-70,25)))
		if child!=null: child.spawner=self
		arena.sound("spawn",position)
		state="recover";timer=2.4
	elif kind in ["hallucinated_api_gremlin","vulnerability_injector"]:
		arena.projectile(position,(aim-position).normalized()*270,"api_projectile" if kind=="hallucinated_api_gremlin" else "injector_projectile","confused" if kind=="hallucinated_api_gremlin" else "strength_down")
		state="recover";timer=1.1
	else:
		aim=(aim-position).normalized()
		state="attack";timer=.38

func update_visual() -> void:
	body.flip_h = facing>0
	var revealed: bool = reveal_left>0 or arena.reveal_time>0 or arena.capabilities.security
	# Hidden threats retain faint silhouettes and bright committed attack warnings.
	body.modulate = Color(1,1,1,.16 if hidden_enemy and not revealed and state not in ["tell","attack","hurt","stunned"] else 1.0)
	if state=="tell": body.modulate=Color(1.4,1.05,.65,1)
	queue_redraw()

func take_hit(damage: float, force: float, from: Vector2, finisher := false) -> bool:
	if dead: return false
	if shield and (from.x-position.x)*facing>0 and not finisher:
		arena.toast("FLANK THE SHIELD — or finish a combo",1)
		return false
	if kind=="zero_day_phantom" and hp<max_hp*.5 and teleport_cooldown<=0 and state=="chase":
		teleport_cooldown=3.5
		position=arena.clamp_ground(position+Vector2(110*facing,80 if position.y<550 else -80))
		reveal_left=.6
		arena.fx("core_kit","reveal_ring",position,.8,.4)
		return false
	if kind=="duplicate_logic_clone" and can_split:
		# Replace the original before registering two non-splitting 1-HP children.
		dead=true
		for side in [-1,1]:
			var child: Node2D = arena.spawn_enemy(kind,arena.clamp_ground(position+Vector2(side*42,side*20)),false)
			if child!=null: child.hp=1;child.max_hp=1
		arena.fx("capabilities_fx","spawn_burst",position,.8,.4)
		queue_free()
		return true
	if armor: armor=false;hp-=1
	else: hp-=damage
	if finisher: shield=false
	knock=Vector2.ZERO if kind in ["review_blocker","agent_spawner"] else (position-from).normalized()*force
	state="hurt";timer=.35
	body.play("attack_warning")
	reveal_left=maxf(reveal_left,.7)
	if hp<=0: finish_death()
	update_visual()
	return true

func stun(seconds: float) -> void:
	if dead: return
	state="stunned";timer=seconds;knock=Vector2.ZERO
	body.play("attack_warning")

func finish_death(reward := true) -> void:
	if dead: return
	dead=true
	body.modulate=Color.WHITE
	body.play("defeat")
	if reward: arena.enemy_defeated(self)
	if kind=="agent_spawner":
		arena.player.effects.erase("overwhelmed")
		for other in arena.enemies.duplicate():
			if is_instance_valid(other) and other.spawner==self: other.finish_death(false)
	var tween := create_tween()
	tween.tween_interval(.5)
	tween.tween_property(self,"modulate:a",0.0,.35)
	tween.tween_callback(queue_free)

func _draw() -> void:
	if dead: return
	if state=="tell":
		draw_arc(Vector2.ZERO,34,0,TAU,28,Color("ffac45"),3)
		draw_line(Vector2.ZERO,aim-position,Color(1,.4,.1,.55),2)
	if triage_marked:
		draw_colored_polygon(PackedVector2Array([Vector2(-10,-133),Vector2(10,-133),Vector2(0,-118)]),Color("ff9b24"))
	if hp<max_hp or kind=="agent_spawner":
		draw_rect(Rect2(-24,-112,48,5),Color("171923"))
		draw_rect(Rect2(-24,-112,48*maxf(0,hp)/max_hp,5),Color("ff9b24"))
