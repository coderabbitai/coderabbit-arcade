extends RefCounted
## Turning between swings, shared by both beat'em up logic suites (code_city_logic and
## heroes_villains_logic): a held turn waits for a queued step, a mid-swing tap turns at the
## swing's end, stale input never overrides a scripted facing, and a contact during a held turn
## keeps the swing's facing. The suite passes its own check(ok, message), its enemy(kind, pos)
## spawner (which may return null), the enemy kind to hit and its clear_enemies().

const DT := 1.0/60.0

static func release_move() -> void:
	for action in ["move_left","move_right","move_up","move_down"]:
		if Input.is_action_pressed(action): Input.action_release(action)

## Park Hoppy clear of the room's props so a facing swing cannot crack them.
static func rest_player(p, at := Vector2(700,550)) -> void:
	release_move()
	p.position=at
	p.velocity=Vector2.ZERO
	p.knock=Vector2.ZERO
	p.effects.clear()
	p.controlled=true
	p.input_lock=0
	p.stagger=0
	p.pickup_time=0
	p.hp=3
	p.shield=false
	p.weapon=""
	p.durability=0
	p.visual_weapon=""
	p.attack_weapon=""
	p.queued=false
	p.swing_left=0
	p.combo=0
	p.combo_window=0
	p.steer=0
	p.facing=1
	p.height=0
	p.rise=0

static func check_facing(p, check: Callable, spawn: Callable, kind: String, clear: Callable) -> void:
	rest_player(p)
	p.start_attack()
	check.call(p.combo==1 and p.facing==1 and p.swing_left>.24,"Combo swing starts facing right, past the queue window")
	Input.action_press("move_left")
	check.call(Input.is_action_pressed("move_left"),"move_left is held for the queued turn")
	var held := true
	var guard := 0
	while p.swing_left>=.24 and guard<40:
		p.tick(DT)
		if p.facing!=1 or p.steer!=-1: held=false
		guard+=1
	check.call(held and p.swing_left<.24 and p.swing_left>0,"A held turn is stored while the first swing still faces right")
	p.request_attack()
	check.call(p.queued,"The queue window buffers the next combo step")
	var turned := false
	guard=0
	while not turned and guard<50:
		var first: bool = p.combo==1
		p.tick(DT)
		if first and p.combo==1 and (p.facing!=1 or p.steer!=-1): held=false
		elif p.combo==2: turned=p.facing==-1 and not p.queued and p.swing_left>0
		guard+=1
	release_move()
	check.call(held and turned,"The queued step starts facing left when the first swing ends")
	rest_player(p)
	p.start_attack()
	p.tick(DT)
	check.call(p.facing==1 and p.steer==0 and p.swing_left>0,"A swing with no input keeps its facing and a clear steer")
	Input.action_press("move_left")
	p.tick(DT)
	var tapped: bool=p.facing==1 and p.steer==-1 and p.swing_left>0
	Input.action_release("move_left")
	var stayed := true
	guard=0
	while p.swing_left>0 and guard<50:
		p.tick(DT)
		if p.swing_left>0 and p.facing!=1: stayed=false
		guard+=1
	check.call(tapped and stayed and p.facing==-1 and p.swing_left<=0,"A one-tick tap mid-swing turns only when the swing ends")
	p.tick(DT)
	check.call(p.steer==0 and p.facing==-1,"Steer clears once the swing is over and the stick is neutral")
	p.facing=1
	p.start_attack()
	check.call(p.facing==1,"A spent tap does not override the next swing's facing")
	rest_player(p)
	p.start_attack()
	stayed=true
	guard=0
	while p.swing_left>0 and guard<50:
		p.tick(DT)
		if p.facing!=1: stayed=false
		guard+=1
	check.call(stayed and p.swing_left<=0 and p.steer==0 and p.facing==1,"A swing with no horizontal input ends with steer at 0")
	p.facing=1
	p.start_attack()
	check.call(p.facing==1 and p.steer==0,"start_attack keeps a scripted facing when steer is 0")
	p.tick(DT)
	check.call(p.facing==1 and p.steer==0,"That facing stays through the next tick with no input")
	rest_player(p)
	var origin: Vector2=p.position
	var front=spawn.call(kind,origin+Vector2(50,0))
	var rear=spawn.call(kind,origin+Vector2(-80,0))
	if front==null or rear==null:
		check.call(false,"Facing hit-check spawned both targets")
	else:
		var front_hp: float=front.hp
		var rear_hp: float=rear.hp
		p.start_attack()
		Input.action_press("move_left")
		# Physics is frozen, so move_and_slide uses the engine's last step. A long one
		# walks Hoppy through these targets before the hit frame; pin him so the
		# contact is about facing, not travel.
		var pinned: Vector2=p.position
		guard=0
		while not p.swing_fired and p.swing_left>0 and guard<40:
			p.position=pinned
			p.tick(DT)
			guard+=1
		check.call(p.swing_fired and p.facing==1 and front.hp==front_hp-1 and rear.hp==rear_hp,"A contact during a held turn still uses the swing's facing")
	release_move()
	clear.call()
	rest_player(p,Vector2(400,550))
	p.controlled=false
