extends Node2D
## Draws the weapon wherever Hoppy's body doesn't already hold it: the carry icon for
## poses with no armed frame, the swing trail from an armed sheet's tip anchor, and the
## legacy hand-animated cel for weapons that have no armed sheet yet. Driven by combat
## time, so pause, hit interruption and facing changes cannot desynchronize a tween.
const Art = preload("res://modes/beatem_up/art.gd")
## Grip texel in each 128 px weapon cel. The carry icon is that cel downsampled, unless
## the manifest gives a reoriented carry its own grip (Art.carry_grip).
const GRIPS := {
	"debug_stick": Vector2(33,86), "linter_staff": Vector2(24,91),
	"api_key_whip": Vector2(28,91), "git_branch": Vector2(25,90),
	"firewall_shield": Vector2(41,64), "refactor_hammer": Vector2(106,91)}
const ANGLES := {"debug_stick":.6,"linter_staff":.6,"api_key_whip":.0,
	"git_branch":.6,"firewall_shield":0.0,"refactor_hammer":2.5}
## Paw texel per frame of the unarmed poses that have no armed frame (96 px combat
## cells, foot pivot (48,86)). See BEHIND_POSES for where the carry draws behind the body.
const CARRY_HANDS := {
	"walk_up": [Vector2(58,64), Vector2(60,61)],
	"walk_down": [Vector2(60,68), Vector2(58,64)],
	"jump": [Vector2(60,66)]}
const UNARMED_PIVOT := Vector2(48,86)
## Carries drawn behind the body: the back view, and the jump, where the paw is at Hoppy's chin.
## Toward the camera only the shield is wide enough to reach his cheek.
const BEHIND_POSES := ["walk_up","jump"]
const BEHIND_WALK_DOWN := ["firewall_shield"]
var body: AnimatedSprite2D
var sprite: AnimatedSprite2D
var carry: Sprite2D
var trail: Line2D
var tip := Vector2(65,-50)
var clock := 0.0

func _ready() -> void:
	trail = Line2D.new()
	trail.width = 5
	trail.default_color = Color(.3,.95,1,.65)
	add_child(trail)
	carry = Sprite2D.new()
	carry.centered = false
	carry.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	carry.hide()
	add_child(carry)
	sprite = Art.sprite("weapons","debug_stick",.72,false)
	sprite.hide()
	add_child(sprite)

func animate(kind: String, step: int, progress: float, active: bool, movement: Vector2, dt: float, block: float) -> void:
	clock += dt * (12 if movement.length() > .1 else 3)
	visible = kind != ""
	clear()
	if not visible: return
	var sheet := Art.armed(kind)
	if sheet != null and body.sprite_frames == sheet: _armed_trail(kind, step, progress, active)
	elif CARRY_HANDS.has(body.animation): _carry(kind)
	elif sheet == null: _legacy(kind, step, progress, active, movement, block)
	_layer(carry.visible and carry_behind(kind, body.animation))

## True when this weapon's carry draws behind the body in this pose, so it never covers the face.
func carry_behind(kind: String, pose: String) -> bool:
	return pose in BEHIND_POSES or (pose == "walk_down" and kind in BEHIND_WALK_DOWN)

## Hides every overlay; the body alone shows the weapon until the next animate().
func clear() -> void:
	sprite.hide()
	carry.hide()
	trail.clear_points()

## Rig-local tip of the weapon at contact, where the swing effect is anchored.
func tip_at(kind: String, step: int) -> Vector2:
	if kind == "": return Vector2(65,-50)
	if Art.armed(kind) == null: return tip
	# Contact-frame tip, else the contact paw, else the rig's current tip.
	var spec := Art.armed_spec(kind)
	for kind_of in ["tip", "hand"]:
		var anchor: Variant = _step_anchor(spec, kind_of, step, 1)
		if anchor != null: return _texel(spec, anchor)
	return tip

## The `kind_of` anchor ("hand" or "tip") of a step's windup (phase 0) or contact (phase 1)
## frame, or null when the manifest lacks the clip, its frame list or that anchor. Frame
## indices are manifest keys; JSON parses them as floats.
func _step_anchor(spec: Dictionary, kind_of: String, step: int, phase: int) -> Variant:
	var clips: Variant = spec.get("clips", {})
	var clip: Variant = clips.get("step%d" % step) if clips is Dictionary else null
	var frames: Variant = clip.get("frames") if clip is Dictionary else null
	if not frames is Array or frames.size() <= phase: return null
	var anchors: Variant = spec.get("anchors", {})
	var table: Variant = anchors.get(kind_of, {}) if anchors is Dictionary else {}
	var anchor: Variant = table.get(str(int(frames[phase]))) if table is Dictionary else null
	return anchor if anchor is Array and anchor.size() >= 2 else null

func _texel(spec: Dictionary, anchor: Array) -> Vector2:
	return (Vector2(anchor[0], anchor[1]) - Vector2(spec.pivot[0], spec.pivot[1])) * body.scale.y

## The armed body holds the weapon itself; only the contact frame adds a trail ending at
## the tip: a streak back to the windup grip for a thrust, else an arc around the contact
## grip on the side the swing came from.
func _armed_trail(kind: String, step: int, progress: float, active: bool) -> void:
	tip = tip_at(kind, step)
	if not active or kind == "firewall_shield" or progress < .3 or progress >= .64: return
	var spec := Art.armed_spec(kind)
	# Without a windup or contact paw anchor, both collapse onto the tip and the trail ends there.
	var windup_anchor: Variant = _step_anchor(spec, "hand", step, 0)
	var grip_anchor: Variant = _step_anchor(spec, "hand", step, 1)
	var windup: Vector2 = tip if windup_anchor == null else _texel(spec, windup_anchor)
	var grip: Vector2 = tip if grip_anchor == null else _texel(spec, grip_anchor)
	var reach := tip-grip
	var back := windup-grip
	var side := reach.cross(back)
	trail.width = 8 if kind == "refactor_hammer" else 4
	trail.default_color = Color(1,.68,.22,.65) if kind == "refactor_hammer" else Color(.3,.95,1,.65)
	for i in 9:
		var t := float(i)/8.0
		if absf(side) < .5*reach.length()*back.length(): trail.add_point(tip.lerp(windup, t))
		else: trail.add_point(grip+reach.rotated(signf(side)*t))

## A pixel-matched carry icon gripped at the pose's paw: one icon texel per body texel.
func _carry(kind: String) -> void:
	var hands: Array = CARRY_HANDS[body.animation]
	var hand: Vector2 = hands[mini(body.frame, hands.size()-1)]
	var icon := Art.carry(kind)
	carry.texture = icon
	carry.scale = body.scale
	var grip: Variant = Art.carry_grip(kind)
	carry.offset = -(GRIPS[kind]*float(icon.get_width())/128.0).round() if grip == null else -Vector2(grip)
	carry.position = (hand-UNARMED_PIVOT)*body.scale.y
	carry.show()

## Draws the rig under the body (see carry_behind) or over it.
func _layer(behind: bool) -> void:
	var parent := get_parent()
	if body == null or parent != body.get_parent(): return
	if behind != (get_index() < body.get_index()): parent.move_child(self, body.get_index())

func _legacy(kind: String, step: int, progress: float, active: bool, movement: Vector2, block: float) -> void:
	sprite.show()
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
	var length := 77.0 if kind!="linter_staff" else 102.0
	if kind=="refactor_hammer": length=72
	tip = hand if kind=="firewall_shield" else hand+Vector2(cos(angle),sin(angle))*length
	if active and progress>=.3 and progress<.64 and kind!="firewall_shield":
		trail.width=8 if kind=="refactor_hammer" else 4
		trail.default_color=Color(1,.68,.22,.65) if kind=="refactor_hammer" else Color(.3,.95,1,.65)
		for i in 9:
			var a := angle-float(i)*.07*(1 if step!=2 else -1)
			trail.add_point(hand+Vector2(cos(a),sin(a))*length)
