extends Node2D
## Weapon transforms follow the attack clock, including interruption and pause.
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
var sprite: AnimatedSprite2D
var trail: Line2D
var clock := 0.0

func _ready() -> void:
	sprite = Art.sprite("items_allies","review_stamp",.36,false)
	add_child(sprite)
	trail = Line2D.new()
	trail.width = 4
	trail.default_color = Color(1,.4,.08,.75)
	add_child(trail)

func animate(kind: String, step: int, progress: float, active: bool, movement: Vector2, dt: float, _block: float) -> void:
	clock += dt*(10 if movement.length()>.1 else 3)
	visible = kind!=""
	if not visible: return
	sprite.play(kind)
	var p := sin(progress*PI) if active else 0.0
	var hand := Vector2(28+p*35,-47-sin(clock)*2)
	var angle := -.35
	if active:
		angle = lerpf(-1.8,.65,smoothstep(.18,.52,progress)) if step!=2 else lerpf(1.7,-.55,smoothstep(.18,.52,progress))
		if progress>.7: angle = lerpf(angle,-.35,(progress-.7)/.3)
	if kind=="triage_hammer": hand.y-=sin(progress*PI)*26 if active else 0
	if kind=="security_scanner": angle=0.0; hand.x+=p*15
	sprite.position = hand
	sprite.rotation = angle
	sprite.scale = Vector2.ONE*(.48 if kind=="change_stack_baton" else .4 if kind=="triage_hammer" else .32)
	trail.clear_points()
	if active and progress>.3 and progress<.66:
		for i in 9:
			var a := angle-i*.07
			trail.add_point(hand+Vector2(cos(a),sin(a))*55)
