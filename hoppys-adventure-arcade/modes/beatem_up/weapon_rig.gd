extends Node2D
## Hand-anchored animation of the existing weapon art. Driven by combat time,
## so pause, hit interruption and facing changes cannot desynchronize a tween.
const Art = preload("res://modes/beatem_up/art.gd")
const GRIPS := {
	"debug_stick": Vector2(33,86), "linter_staff": Vector2(24,91),
	"api_key_whip": Vector2(28,91), "git_branch": Vector2(25,90),
	"firewall_shield": Vector2(41,64), "refactor_hammer": Vector2(106,91)}
const ANGLES := {"debug_stick":.6,"linter_staff":.6,"api_key_whip":.0,
	"git_branch":.6,"firewall_shield":0.0,"refactor_hammer":2.5}
var sprite: AnimatedSprite2D
var trail: Line2D
var clock := 0.0

func _ready() -> void:
	trail = Line2D.new()
	trail.width = 5
	trail.default_color = Color(.3,.95,1,.65)
	add_child(trail)
	sprite = Art.sprite("weapons","debug_stick",.72,false)
	add_child(sprite)

func animate(kind: String, step: int, progress: float, active: bool, movement: Vector2, dt: float, block: float) -> void:
	clock += dt * (12 if movement.length() > .1 else 3)
	visible = kind != ""
	if not visible: return
	var hand := Vector2(22,-29 + sin(clock)* (3 if movement.length() > .1 else 1))
	var angle := -.65
	var start := Vector2(8,-53)
	var contact := Vector2(30,-25)
	var finish := Vector2(30,-18)
	var wind := -1.7
	var strike := .35
	var follow := .8
	match kind:
		"debug_stick":
			if step==1: wind=-.25;strike=0;follow=.15;contact=Vector2(34,-25)
			elif step==2: wind=-2.2;strike=.4;follow=1.1
		"linter_staff":
			if step==1: wind=0;strike=0;follow=.15;start=Vector2(-12,-43);contact=Vector2(34,-25)
			elif step==2: wind=1.8;strike=-.2;follow=-1.0
			else: wind=-2.8;strike=.2;follow=1.2
		"api_key_whip":
			wind=-1.4 if step!=2 else 1.4
			strike=0;follow=.65
			contact=Vector2(30,-25)
		"git_branch":
			wind=-2.1 if step!=2 else 1.9
			strike=.1;follow=1.2 if step!=2 else -1.2
			contact=Vector2(30,-25)
		"firewall_shield":
			angle=0;wind=-.15;strike=.15;follow=0
			start=Vector2(18,-30);contact=Vector2(30,-30);finish=Vector2(22,-30)
		"refactor_hammer":
			start=Vector2(0,-72);contact=Vector2(30,-25);finish=Vector2(30,-18)
			wind=-2.0;strike=.65;follow=1.2
			if step==2: start=Vector2(-8,-45);wind=-3.0;strike=.1;follow=.7
	if active:
		if progress < .3:
			var t := smoothstep(0,.3,progress)
			hand = hand.lerp(start,t);angle=lerpf(angle,wind,t)
		elif progress < .44:
			var t := smoothstep(.3,.44,progress)
			hand=start.lerp(contact,t);angle=lerpf(wind,strike,t)
		elif progress < .64:
			var t := smoothstep(.44,.64,progress)
			hand=contact.lerp(finish,t);angle=lerpf(strike,follow,t)
		else:
			var t := smoothstep(.64,1,progress)
			hand=finish.lerp(hand,t);angle=lerpf(follow,angle,t)
	if kind=="firewall_shield" and active and step==3:
		hand=Vector2(-10,-47)
		angle=-.15
	if kind=="firewall_shield" and block>0:
		hand.x -= sin(block/.28*PI)*12
		angle -= sin(block/.28*PI)*.4
	var pose := kind
	var extended := kind=="api_key_whip" and active and progress>=.3 and progress<.68
	if extended: pose="api_key_whip_extended"
	sprite.play(pose)
	sprite.offset=Vector2(64,64)-GRIPS[kind]
	sprite.position=hand
	sprite.rotation=ANGLES[kind]+angle
	sprite.scale=Vector2.ONE*(.95 if kind=="linter_staff" else .85 if kind=="git_branch" else .72)
	if extended:
		# The extended cel's handle is at its right edge; mirror around that grip.
		sprite.offset=Vector2(64,64)-Vector2(106,53)
		sprite.scale=Vector2(-1.7,.72)
		sprite.rotation=angle
	trail.clear_points()
	if active and progress>=.3 and progress<.64 and kind!="firewall_shield":
		var length := 77.0 if kind!="linter_staff" else 102.0
		if kind=="refactor_hammer": length=72
		trail.width=8 if kind=="refactor_hammer" else 4
		trail.default_color=Color(1,.68,.22,.65) if kind=="refactor_hammer" else Color(.3,.95,1,.65)
		for i in 9:
			var a := angle-float(i)*.07*(1 if step!=2 else -1)
			trail.add_point(hand+Vector2(cos(a),sin(a))*length)
