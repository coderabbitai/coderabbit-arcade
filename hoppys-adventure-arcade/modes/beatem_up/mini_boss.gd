extends Node2D
## A district boss guarding the third room of districts 1 and 2. It takes game.gd's `boss` slot,
## so it answers the same duck-typed interface as boss.gd: hp, max_hp, phase, dead, body,
## melee_reaches() and take_hit() for the swing, the HUD bar, the minimap and the hazard pause.
## Its defeat goes through arena.boss_defeated(), which hands it to mini_boss_defeated().
##
## It alternates two telegraphed moves: a slam (a leap onto a warned spot that sends a shot
## along the lane each way) and a dash along Hoppy's lane past warning markers. Every hit
## lands; every `stagger_hits` hits it reels for `stagger` seconds. Below `rage_at` of its HP it
## tells faster and calls in two adds, once. Clock-driven: tick() runs while the arena plays,
## defeat_tick() while the arena celebrates.
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
## Its body is about twice an enemy's, so a swing reaches it a little further out.
const REACH_PADDING := 30.0
const DEPTH_PADDING := 12.0
const DROP_HEIGHT := 420.0
const DROP_TIME := .55
const INTRO_GRACE := .8
const SLAM_RADIUS := Vector2(105,44)
const LEAP_HEIGHT := 110.0
const DASH_REACH := 70.0
const DASH_DEPTH := 40.0
const DASH_FORCE := 300.0
## How fast it slides onto the warned lane while winding up a dash (px/s).
const LINE_UP := 260.0
const DEFEAT_HOLD := .4
const DEFEAT_FADE := .9
var arena: Node2D
var key := "stack_overflow"
var data: Dictionary
var title := ""
var body: AnimatedSprite2D
## The pose → clip map of the fallback sheet; empty while the boss draws its own atlas.
var clips: Dictionary = {}
var magnify := 1.0
var hp := 14.0
var max_hp := 14.0
## One phase: game.gd feeds boss.phase to the conflict shader, which stays clear below 2.
var phase := 1
var dead := false
var enraged := false
var adds_called := false
var state := "intro"             # intro, chase, tell, active, recover, stagger
var move := ""                   # "slam" or "dash" while telegraphing or acting
var timer := 0.0
var cycle := 0
var hits := 0
var aim := Vector2.ZERO
var launch := Vector2.ZERO
var dash_direction := 1.0
var leaping := false
var landed := false
var knock := Vector2.ZERO
var flash := 0.0
var defeat_clock := 0.0

func _ready() -> void:
	data = Catalog.MINI_BOSSES[key]
	title = data.title
	max_hp = float(data.hp)
	hp = max_hp
	add_child(Art.shadow(55))
	var sheet: String = data.sheet
	magnify = float(data.scale)
	if not sheet_ready(sheet):
		var fallback: Dictionary = data.fallback
		sheet = fallback.sheet
		magnify = float(fallback.scale)
		clips = fallback.clips
	body = Art.sprite(sheet,clip("idle"),magnify)
	add_child(body)
	# It drops in from above; the arena's slam feedback marks the landing.
	state = "intro"
	timer = DROP_TIME+INTRO_GRACE
	body.position.y = -DROP_HEIGHT

## True once S2's atlas for `sheet` is in the pack: its resource and its manifest entry (cell
## and pivot), which Art.sprite() needs to stand it on its feet.
static func sheet_ready(sheet: String) -> bool:
	if not ResourceLoader.exists(Art.BASE+sheet+".tres"): return false
	if Art.manifest.is_empty(): Art.manifest = JSON.parse_string(FileAccess.get_file_as_string(Art.BASE+"manifest.json"))
	return Art.manifest.get("atlases",{}).has(sheet)

## The sheet's clip for one of the boss's poses (the fallback maps them onto an enemy's).
func clip(pose_name: String) -> String:
	return clips.get(pose_name,pose_name)

func pose(pose_name: String) -> void:
	var name := clip(pose_name)
	if not body.sprite_frames.has_animation(name): name = clip("idle")
	if body.animation != name: body.play(name)

func _physics_process(dt: float) -> void:
	if arena.playing: tick(dt)

func tick(dt: float) -> void:
	if dead: return
	timer -= dt
	flash = maxf(0,flash-dt)
	body.modulate = Color(1.6,.75,.75) if flash > 0 else Color.WHITE
	match state:
		"intro": _tick_intro()
		"chase": _tick_chase(dt)
		"tell": _tick_tell(dt)
		"active": _tick_active(dt)
		"recover":
			if timer <= 0: _rest()
		"stagger":
			position = arena_point(position+knock*dt)
			knock = knock.move_toward(Vector2.ZERO,900*dt)
			if timer <= 0: _rest()
	queue_redraw()

func _tick_intro() -> void:
	var t := clampf(1.0-(timer-INTRO_GRACE)/DROP_TIME,0,1)
	body.position.y = -DROP_HEIGHT*(1.0-t*t)
	if t >= 1 and not landed:
		landed = true
		arena.shake = maxf(arena.shake,9)
		arena.sound("kick",position)
		arena.fx("combat_fx","slam_impact",position,1.8,.3)
	if timer <= 0: _rest(0.0)

func _tick_chase(dt: float) -> void:
	var player: Node2D = arena.player
	var side := -1.0 if player.position.x < position.x else 1.0
	_face(player.position.x)
	var goal := arena_point(player.position-Vector2(side*150,0))
	var before := position
	position = position.move_toward(goal,float(data.speed)*dt)
	pose("walk" if position.distance_to(before) > .1 else "idle")
	if timer <= 0: telegraph()

func _tick_tell(dt: float) -> void:
	if move == "dash":
		# Line up on the warned lane while winding up.
		position.y = move_toward(position.y,aim.y,LINE_UP*dt)
	var charge := 1.0-clampf(timer/maxf(tell_time(move),.001),0,1)
	body.scale = Vector2(1+charge*.06,1-charge*.06)*magnify
	if timer <= 0: fire()

func _tick_active(dt: float) -> void:
	if move == "slam":
		var t := clampf(1.0-timer/float(data.leap),0,1)
		position = launch.lerp(aim,smoothstep(0,1,t))
		body.position.y = -sin(t*PI)*LEAP_HEIGHT
		if timer <= 0: _land()
		return
	position = arena_point(position+Vector2(dash_direction*float(data.dash_speed)*dt,0))
	var player: Node2D = arena.player
	var offset: Vector2 = player.position-position
	if absf(offset.x) < DASH_REACH and absf(offset.y) < DASH_DEPTH:
		player.take_hit(position,"",DASH_FORCE)
	var wall: float = arena.room_start()+(1160.0 if dash_direction > 0 else 120.0)
	if timer <= 0 or absf(position.x-wall) < 1: _recover()

## Leave room for the boss's silhouette and for attacks from either side.
func arena_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x,arena.room_start()+120,arena.room_start()+1160),clampf(point.y,470,630))

## The tells shorten once it is enraged.
func tell_time(kind: String) -> float:
	return float(data.slam_tell if kind == "slam" else data.dash_tell)*(float(data.rage) if enraged else 1.0)

func telegraph() -> void:
	cycle += 1
	move = "slam" if cycle%2 == 1 else "dash"
	state = "tell"
	timer = tell_time(move)
	var player: Node2D = arena.player
	_face(player.position.x)
	body.position = Vector2.ZERO
	if move == "slam":
		aim = arena_point(player.position)
		pose("slam_warning")
		# The warning fires on landing, after the tell and the flight.
		arena.ground_warning(aim,SLAM_RADIUS,timer+float(data.leap),.25,"slam",self)
	else:
		aim = Vector2(position.x,clampf(player.position.y,470,630))
		dash_direction = 1.0 if player.position.x >= position.x else -1.0
		pose("dash_warning")
		for n in 3:
			var marker := arena_point(Vector2(position.x+dash_direction*(170+n*190),aim.y))
			arena.ground_warning(marker,Vector2(60,24),timer,.2,"signal",self)

func fire() -> void:
	state = "active"
	body.scale = Vector2.ONE*magnify
	if move == "slam":
		leaping = true
		launch = position
		timer = float(data.leap)
		pose("slam")
	else:
		# The dash runs exactly along the warned lane.
		position.y = aim.y
		timer = float(data.dash_time)
		pose("dash")
		arena.sound("swing",position)

func _land() -> void:
	leaping = false
	position = aim
	body.position = Vector2.ZERO
	arena.shake = maxf(arena.shake,8)
	arena.sound("kick",position)
	arena.fx("combat_fx","slam_impact",position,1.8,.3)
	for side in [-1.0,1.0]:
		arena.projectile(position+Vector2(side*50,0),Vector2(side*float(data.shot_speed),0),data.shot)
	_recover()

func _recover() -> void:
	leaping = false
	body.position = Vector2.ZERO
	body.scale = Vector2.ONE*magnify
	state = "recover"
	timer = float(data.recover)
	pose("recover")
	if hits >= int(data.stagger_hits): stagger()

func _rest(seconds := -1.0) -> void:
	state = "chase"
	move = ""
	timer = float(data.rest) if seconds < 0 else seconds
	body.position = Vector2.ZERO
	body.scale = Vector2.ONE*magnify
	pose("idle")

func _face(x: float) -> void:
	# Its sheets face left.
	body.flip_h = x > position.x

## Reels for `stagger` seconds, dropping a telegraphed move and its warnings.
func stagger() -> void:
	hits = 0
	state = "stagger"
	timer = float(data.stagger)
	move = ""
	body.position = Vector2.ZERO
	body.scale = Vector2.ONE*magnify
	arena.drop_warnings(self)
	pose("hurt")

func melee_reaches(offset: Vector2, facing: float, reach: float, depth: float) -> bool:
	if dead: return false
	var forward := offset.x*facing
	return forward >= -20 and forward <= reach+REACH_PADDING and absf(offset.y) <= depth+DEPTH_PADDING

func take_hit(damage: float, force: float, from: Vector2, _finisher := false) -> bool:
	if dead or state == "intro": return false
	hp = maxf(0,hp-damage)
	hits += 1
	flash = .1
	arena.shake = maxf(arena.shake,4)
	arena.sound("jab",position)
	if hp <= 0:
		_defeat()
		return true
	if not enraged and hp <= max_hp*float(data.rage_at): _enrage()
	# A committed leap lands first; its recovery staggers instead.
	if hits >= int(data.stagger_hits) and not leaping:
		knock = Vector2(signf(position.x-from.x),0)*minf(force,200.0)
		stagger()
	return true

func _enrage() -> void:
	enraged = true
	arena.toast("%s ENRAGED — adds incoming" % title,1.6)
	arena.sound("phase",position)
	if adds_called: return
	adds_called = true
	for side in [-1.0,1.0]:
		var spot: Vector2 = arena.clamp_ground(Vector2(arena.room_start()+640+side*430,position.y+side*45))
		var add: Node2D = arena.spawn_enemy(data.add,spot,false)
		if add: arena.fx("combat_fx","duplicate_spawn",spot,1,.6)

func _defeat() -> void:
	dead = true
	leaping = false
	state = "defeat"
	body.position = Vector2.ZERO
	body.scale = Vector2.ONE*magnify
	body.modulate = Color.WHITE
	defeat_clock = 0
	pose("defeat")
	queue_redraw()
	arena.boss_defeated()

## The arena ticks this through the victory hop: a beat on the defeat pose, then a fade.
func defeat_tick(dt: float) -> void:
	if not dead: return
	defeat_clock += dt
	modulate.a = 1.0-clampf((defeat_clock-DEFEAT_HOLD)/DEFEAT_FADE,0,1)

func _draw() -> void:
	if dead or state != "tell": return
	draw_arc(Vector2.ZERO,60,0,TAU,32,Color("ffb84a"),3)
