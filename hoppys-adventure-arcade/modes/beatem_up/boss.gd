extends Node2D
const Art = preload("res://modes/beatem_up/art.gd")
var arena: Node2D
var body: AnimatedSprite2D
var hp := 24.0
var max_hp := 24.0
var phase := 1
var state := "idle"
var timer := 1.5
var cycle := 0
var dead := false
var vulnerable := false
var aim := Vector2.ZERO
var move := ""
var transition_count := 0

func _ready() -> void:
	add_child(Art.shadow(75))
	body = Art.sprite("conflict_spawner","idle",2.6)
	add_child(body)

func _physics_process(dt: float) -> void:
	if arena.playing: tick(dt)

func tick(dt: float) -> void:
	if dead: return
	timer -= dt
	if timer > 0: return
	if state == "tell":
		fire()
	elif state == "active":
		state = "recover"
		vulnerable = true
		timer = 2.2 if phase==1 else 1.8
		body.play("recover" if phase < 3 else "idle")
		arena.toast("CORE EXPOSED — land a finisher!",1.7)
	elif state == "recover" or state == "transition":
		vulnerable = false
		state = "idle"
		timer = .5
		body.play("idle")
	else: telegraph()

func telegraph() -> void:
	cycle += 1
	state = "tell"
	vulnerable = false
	timer = .95 if phase < 3 else .75
	aim = arena.player.position
	if phase == 1:
		move = "summon" if cycle%3==1 else "slam" if cycle%3==2 else "sweep"
		body.play("summon_warning" if move=="summon" else "slam_warning")
		if move != "summon": arena.ground_warning(aim,Vector2(110,48),timer,.22,"slam",self)
	elif phase == 2:
		move = "split"
		body.play("left_warning" if cycle%2==0 else "right_warning")
		arena.ground_warning(Vector2(arena.room_start()+125,aim.y),Vector2(80,28),timer,.2,"signal",self)
		arena.ground_warning(Vector2(arena.room_start()+1155,aim.y),Vector2(80,28),timer,.2,"signal",self)
		arena.toast("SPLIT SCREEN — jump or change lanes",1.2)
	else:
		move = "storm" if cycle%2 else "clone"
		body.play("storm_warning" if move=="storm" else "clone_summon")
		arena.toast("REBASE STORM — find the open lane" if move=="storm" else "CLONE SURGE",1.2)

func fire() -> void:
	state = "active"
	timer = .45
	match move:
		"summon", "clone":
			body.play("summon" if phase==1 else "clone_summon")
			if arena.living_enemies() < 3:
				for offset in [Vector2(-200,-55),Vector2(-350,55)]: arena.spawn_enemy("merge_conflict_soldier",arena.clamp_ground(position+offset),false)
		"slam", "sweep":
			body.play(move)
			arena.shake = 9
			arena.sound("kick",position)
		"split":
			body.play("dual_impact")
			arena.projectile(Vector2(arena.room_start()+35,aim.y),Vector2(330,0),"cyan_projectile")
			arena.projectile(Vector2(arena.room_start()+1245,aim.y),Vector2(-330,0),"red_projectile")
		"storm":
			body.play("storm")
			var safe := cycle%3
			for lane in 3:
				if lane==safe: continue
				for n in 3:
					arena.projectile(Vector2(arena.room_start()+1220+n*75,475+lane*72),Vector2(-310,0),"red_projectile")
			arena.shake = 5

func take_hit(damage: float, _force: float, _from: Vector2, finisher := false) -> bool:
	if dead: return false
	if not vulnerable or not finisher:
		arena.toast("Wait for the exposed core · J / X × 3",1.0)
		return false
	hp = maxf(0,hp-damage)
	arena.score += 50
	arena.shake = 7
	arena.sound("kick",position)
	if hp <= 0:
		dead = true
		vulnerable = false
		body.sprite_frames = Art.frames("merge_chaos")
		body.play("collapse")
		arena.boss_defeated()
		return true
	var next_phase := 3 if hp/max_hp <= .25 else 2 if hp/max_hp <= .5 else 1
	if next_phase > phase:
		phase = next_phase
		transition_count += 1
		vulnerable = false
		state = "transition"
		timer = 1.4
		arena.clear_threats()
		body.sprite_frames = Art.frames("split_screen" if phase==2 else "merge_chaos")
		body.play("transition" if phase==2 else "idle")
		arena.sound("phase",position)
		arena.toast("PHASE %d — %s" % [phase,"SPLIT SCREEN" if phase==2 else "FULL MERGE CHAOS"],2)
	return true
