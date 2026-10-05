extends CharacterBody2D
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
var arena: Node2D
var kind := "cli_gremlin"
var hp := 1.0
var max_hp := 1.0
var data: Dictionary
var body: AnimatedSprite2D
var state := "chase"
var timer := .8
var cooldown := 1.0
var dodge_timer := 3.0
var facing := -1.0
var aim := Vector2.ZERO
var knock := Vector2.ZERO
var can_split := true
var resurrected := false
var armor := false
var dead := false
var final_reported := false

func _ready() -> void:
	data = Catalog.ENEMIES[kind]
	hp = data.hp
	max_hp = hp
	armor = kind == "linter_enforcer"
	collision_layer = 0
	collision_mask = 0
	add_child(Art.shadow(30))
	body = Art.sprite(kind,"armored_idle" if armor else "idle",1.7)
	add_child(body)
	cooldown += arena.rng.randf_range(0,.5)

func pose(name: String) -> void:
	if body.sprite_frames.has_animation(name): body.play(name)
	else: body.play("bare_idle" if body.sprite_frames.has_animation("bare_idle") else "idle")

func _physics_process(dt: float) -> void:
	if not arena.playing: return
	tick(dt)

func tick(dt: float) -> void:
	if dead: return
	timer -= dt
	cooldown -= dt
	dodge_timer -= dt
	body.modulate = Color.WHITE
	if state == "fallen":
		if timer <= 0:
			resurrected = true
			hp = 2
			state = "rise"
			timer = .6
			pose("resurrect")
			arena.fx("combat_fx","resurrection",position-Vector2(0,40),1.0,.6)
		queue_redraw()
		return
	if state == "rise" or state == "hurt":
		position += knock*dt
		knock = knock.move_toward(Vector2.ZERO,750*dt)
		position = arena.clamp_ground(position)
		if timer <= 0:
			state = "chase"
			cooldown = .55
		return
	var delta_to: Vector2 = arena.player.position-position
	if state == "tell":
		body.modulate = Color(1.25,1.05,.65)
		if timer <= 0: release_attack()
	elif state == "attack":
		if kind in ["force_push_bandit","cve_crawler"]:
			velocity = aim * (480 if kind == "force_push_bandit" else 330)
			move_and_slide()
			position = arena.clamp_ground(position)
		if delta_to.x*facing >= -20 and absf(delta_to.x) < 90 and absf(delta_to.y) < 40:
			arena.player.take_hit(position,"strength_down" if kind=="stale_branch_zombie" else "",290 if kind=="force_push_bandit" else 170)
		if timer <= 0:
			state = "recover"
			timer = .6
			pose("recover")
	elif state == "recover" or state == "dodge":
		if state == "dodge": position = arena.clamp_ground(position+aim*220*dt)
		if timer <= 0:
			state = "chase"
			cooldown = .7
	else:
		facing = -1 if delta_to.x < 0 else 1
		var ranged := kind in ["syntax_error_sprite","injection_attack_drone"]
		var reach := 360.0 if ranged else 300.0 if kind=="force_push_bandit" else 92.0
		if cooldown <= 0 and absf(delta_to.x) < reach and absf(delta_to.y) < (100 if ranged else 43):
			state = "tell"
			timer = data.tell
			aim = arena.player.position
			pose(data.warning)
		else:
			var target: Vector2 = arena.player.position
			if ranged: target.x -= facing*260
			if kind=="cve_crawler" and absf(delta_to.x)>150: target.y += 65 if get_index()%2==0 else -65
			var move := (target-position).normalized() if target.distance_to(position)>20 else Vector2.ZERO
			for other in arena.enemies:
				if other != self and is_instance_valid(other) and not other.dead and position.distance_to(other.position)<52:
					move += (position-other.position).normalized()*.6
			velocity = move.limit_length()*float(data.speed)
			move_and_slide()
			position = arena.clamp_ground(position)
			pose("armored_walk" if armor else "walk" if body.sprite_frames.has_animation("walk") else "hover" if ranged and kind=="injection_attack_drone" else "drift" if ranged else "idle")
	body.flip_h = facing > 0
	queue_redraw()

func release_attack() -> void:
	pose(data.attack)
	if kind in ["syntax_error_sprite","injection_attack_drone"]:
		var direction: Vector2 = (aim-position).normalized()
		for i in (3 if kind=="injection_attack_drone" else 1):
			arena.projectile(position+Vector2(0,-2),direction.rotated((i-1)*.12 if kind=="injection_attack_drone" else 0)*255,"injection_projectile" if kind=="injection_attack_drone" else "syntax_projectile","confused" if kind=="injection_attack_drone" else "")
		state = "recover"
		timer = 1.1
	else:
		aim = (aim-position).normalized()
		state = "attack"
		timer = .6 if kind=="force_push_bandit" else .35

func take_hit(damage: float, force: float, from: Vector2, _finisher := false) -> bool:
	if dead or state in ["fallen","rise","dodge"]: return false
	if kind=="cve_crawler" and dodge_timer <= 0 and state=="chase":
		state = "dodge"
		timer = .32
		dodge_timer = 4.2
		aim = Vector2(0,1 if position.y<555 else -1)
		pose("roll")
		return false
	if armor:
		armor = false
		hp -= 1 # The first hit breaks armor AND removes one of the listed three HP.
		arena.fx("combat_fx","slam_impact",position-Vector2(0,35),.5,.35)
		body.sprite_frames = Art.frames("linter_bare")
	else: hp -= damage
	if kind=="merge_conflict_soldier" and can_split:
		can_split = false
		arena.spawn_enemy(kind,arena.clamp_ground(position+Vector2(65,45)),false)
		arena.fx("combat_fx","duplicate_spawn",position,1,.7)
	knock = (position-from).normalized()*force
	state = "hurt"
	timer = .28
	pose("hurt")
	arena.sound("jab",position)
	if hp <= 0:
		if kind=="stale_branch_zombie" and not resurrected:
			state = "fallen"
			timer = 1.8
			pose("first_fall")
		else: finish_death()
	queue_redraw()
	return true

func finish_death() -> void:
	if final_reported: return
	final_reported = true
	dead = true
	pose("final_defeat" if kind=="stale_branch_zombie" else "defeat")
	arena.enemy_defeated(self)
	var tween := create_tween()
	tween.tween_interval(.6)
	tween.tween_property(self,"modulate:a",0.0,.5)
	tween.tween_callback(queue_free)

func _draw() -> void:
	if dead: return
	if state=="tell":
		draw_arc(Vector2.ZERO,35,0,TAU,28,Color("ffb84a"),3)
		var relative := aim-position
		draw_line(Vector2.ZERO,relative,Color(1,.5,.2,.45),2)
	if hp < max_hp and hp > 0:
		draw_rect(Rect2(-24,-117,48,5),Color("142735"))
		draw_rect(Rect2(-24,-117,48*hp/max_hp,5),Color("ffb84a"))
