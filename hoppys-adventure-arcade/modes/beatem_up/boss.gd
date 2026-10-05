extends Node2D
const Art = preload("res://modes/beatem_up/art.gd")
const CoreExposure = preload("res://modes/beatem_up/core_exposure.gd")
const RECOVERY_DURATION := [2.4, 2.1, 2.1]
# The exposed core has a broad ground-plane footprint instead of a point target.
const CORE_REACH_PADDING := 70.0
const CORE_DEPTH_PADDING := 44.0
var arena: Node2D
var body: AnimatedSprite2D
var core_cue: Node2D
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
var destination := Vector2.ZERO
var launch := Vector2.ZERO
var motion_clock := 0.0
var travel_duration := .65
var leaping := false

func _ready() -> void:
	add_child(Art.shadow(75))
	body = Art.sprite("conflict_spawner","idle",2.6)
	add_child(body)
	core_cue=CoreExposure.new()
	add_child(core_cue)
	core_cue.hide()

func _physics_process(dt: float) -> void:
	if arena.playing: tick(dt)

func tick(dt: float) -> void:
	if dead: return
	_tick_motion(dt)
	timer -= dt
	if timer > 0:
		_update_core_cue()
		return
	if state == "tell":
		fire()
	elif state == "active":
		if leaping:
			arena.shake=9
			arena.sound("kick",destination)
			arena.fx("combat_fx","slam_impact",destination,1.8,.3)
		leaping = false
		position = destination if move in ["slam","sweep","storm"] else position
		body.position = Vector2.ZERO
		body.scale = Vector2.ONE*2.6
		state = "recover"
		vulnerable = true
		timer = RECOVERY_DURATION[phase-1]
		body.play(move if phase==1 and move in ["slam","sweep"] else "recover" if phase<3 else "hurt")
		arena.toast("CORE EXPOSED — land a finisher!",1.7)
	elif state == "recover" or state == "transition":
		vulnerable = false
		begin_reposition()
	else: telegraph()
	_update_core_cue()

func _update_core_cue() -> void:
	core_cue.visible=phase==3 and state=="recover" and vulnerable and not dead
	if not core_cue.visible: return
	body.play("hurt")
	var duration: float=RECOVERY_DURATION[phase-1]
	var breath := sin((duration-timer)*TAU*1.7)
	body.scale=Vector2(1.0+breath*.025,1.0-breath*.015)*2.6
	# The core is 60 source pixels above the sprite's foot pivot.
	core_cue.position=body.position+Vector2(0,-60)*body.scale
	core_cue.update_window(timer,duration)

func arena_point(point: Vector2) -> Vector2:
	# Leave room for the boss silhouette and for attacks from either side.
	return Vector2(clampf(point.x,arena.room_start()+220,arena.room_start()+1060),clampf(point.y,480,615))

func begin_reposition() -> void:
	core_cue.hide()
	state = "reposition"
	timer = 1.25 if phase<3 else .95
	body.play("idle")
	var side := -1.0 if position.x>arena.player.position.x else 1.0
	if phase==1: side=-side # Pressure Hoppy without walking through them.
	destination=arena_point(arena.player.position+Vector2(side*(170 if phase==1 else 250),-45 if cycle%2 else 45))

func _tick_motion(dt: float) -> void:
	motion_clock += dt
	if state=="idle" or state=="reposition":
		if state=="idle":
			var side := 1.0 if position.x>=arena.player.position.x else -1.0
			destination=arena_point(arena.player.position+Vector2(side*170,0))
		var previous := position
		position=position.move_toward(destination,(145.0 if phase==1 else 370.0 if phase==2 else 460.0)*dt)
		body.flip_h=arena.player.position.x>position.x
		body.position.y=-absf(sin(motion_clock*11))*7 if position.distance_to(previous)>.1 else 0.0
	elif state=="active" and leaping:
		var t := clampf(1.0-(timer-dt)/travel_duration,0,1)
		position=launch.lerp(destination,smoothstep(0,1,t))
		body.position.y=-sin(t*PI)*(100 if phase==1 else 135)
	elif state=="tell":
		var charge := 1.0-clampf(timer/(.95 if phase<3 else .75),0,1)
		body.scale=Vector2(1+charge*.06,1-charge*.06)*2.6
	else:
		body.position=Vector2.ZERO
		body.scale=Vector2.ONE*2.6
		if state=="recover" and timer < RECOVERY_DURATION[phase-1]-.18:
			body.play("recover" if phase<3 else "hurt")

func telegraph() -> void:
	core_cue.hide()
	cycle += 1
	state = "tell"
	vulnerable = false
	timer = .95 if phase < 3 else .75
	aim = arena_point(arena.player.position)
	body.flip_h=arena.player.position.x>position.x
	body.position=Vector2.ZERO
	if phase == 1:
		move = "summon" if cycle%3==1 else "slam" if cycle%3==2 else "sweep"
		body.play("summon_warning" if move=="summon" else "slam_warning")
		if move != "summon":
			destination=aim
			arena.ground_warning(destination,Vector2(110,48),timer+travel_duration,.25,"slam",self)
	elif phase == 2:
		move = "split"
		body.play("left_warning" if cycle%2==0 else "right_warning")
		arena.ground_warning(Vector2(arena.room_start()+125,aim.y),Vector2(80,28),timer,.2,"signal",self)
		arena.ground_warning(Vector2(arena.room_start()+1155,aim.y),Vector2(80,28),timer,.2,"signal",self)
		arena.toast("SPLIT SCREEN — jump or change lanes",1.2)
	else:
		move = "storm" if cycle%2 else "clone"
		body.play("storm_warning" if move=="storm" else "clone_summon")
		if move=="storm":
			destination=aim
			arena.ground_warning(destination,Vector2(105,45),timer+travel_duration,.25,"slam",self)
		arena.toast("REBASE STORM — find the open lane" if move=="storm" else "CLONE SURGE",1.2)

func fire() -> void:
	state = "active"
	timer = .45
	body.scale=Vector2.ONE*2.6
	leaping=move in ["slam","sweep","storm"]
	if leaping:
		launch=position
		timer=travel_duration
	match move:
		"summon", "clone":
			body.play("summon" if phase==1 else "clone_summon")
			if arena.living_enemies() < 3:
				for offset in [Vector2(-200,-55),Vector2(-350,55)]: arena.spawn_enemy("merge_conflict_soldier",arena.clamp_ground(position+offset),false)
		"slam", "sweep":
			body.play("slam_warning")
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

func melee_reaches(offset: Vector2, facing: float, reach: float, depth: float) -> bool:
	if dead: return false
	var reach_padding := CORE_REACH_PADDING if vulnerable else 0.0
	var depth_padding := CORE_DEPTH_PADDING if vulnerable else 0.0
	var forward := offset.x*facing
	# Keep the facing requirement: an exposed core is not a hit behind Hoppy.
	return forward >= -20 and forward <= reach+reach_padding and absf(offset.y) <= depth+depth_padding

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
		core_cue.hide()
		leaping=false
		body.position=Vector2.ZERO
		body.scale=Vector2.ONE*2.6
		dead = true
		vulnerable = false
		body.sprite_frames = Art.frames("merge_chaos")
		body.play("collapse")
		arena.boss_defeated()
		return true
	var next_phase := 3 if hp/max_hp <= .25 else 2 if hp/max_hp <= .5 else 1
	if next_phase > phase:
		core_cue.hide()
		phase = next_phase
		transition_count += 1
		vulnerable = false
		leaping=false
		body.position=Vector2.ZERO
		body.scale=Vector2.ONE*2.6
		state = "transition"
		timer = 1.4
		arena.clear_threats()
		body.sprite_frames = Art.frames("split_screen" if phase==2 else "merge_chaos")
		body.play("transition" if phase==2 else "idle")
		arena.sound("phase",position)
		arena.toast("PHASE %d — %s" % [phase,"SPLIT SCREEN" if phase==2 else "FULL MERGE CHAOS"],2)
	return true
