extends Node2D
## Carry icon, swing trail, and the legacy weapon sprite for sheets that are
## not packed yet. The body draws a baked sheet when one exists.
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
const BODY_SCALE := 1.65
const CELL := Vector2(192, 192)
const UNARMED_PIVOT := Vector2(64, 115)
## Grip pixel in the 192px item cel. The sprite offset pins this point to the paw,
## so the hammer is held by its handle instead of its middle.
const GRIPS := {
	"review_stamp": Vector2(78, 92),
	"triage_hammer": Vector2(40, 128),
	"change_stack_baton": Vector2(48, 136),
	"security_scanner": Vector2(128, 168),
	"pr_merger": Vector2(60, 158),
}
const TIPS := {
	"review_stamp": Vector2(86, 148),
	"triage_hammer": Vector2(140, 72),
	"change_stack_baton": Vector2(168, 32),
	"security_scanner": Vector2(124, 36),
	"pr_merger": Vector2(124, 52),
}
const SCALES := {
	"review_stamp": 0.32, "triage_hammer": 0.4, "change_stack_baton": 0.48,
	"security_scanner": 0.32, "pr_merger": 0.32,
}
## Paw position in the unarmed 128px cel. Side poses match the baked hold_idle paw.
const HANDS := {
	"idle": Vector2(78, 87),
	"walk_up": Vector2(72, 86),
	"walk_down": Vector2(80, 84),
	"jump": Vector2(86, 78),
	"pickup": Vector2(82, 98),
	"defeat": Vector2(90, 102),
	"victory": Vector2(76, 72),
}
const CARRY_POSES := ["walk_up", "walk_down", "jump", "defeat", "victory"]
var sprite: AnimatedSprite2D
var carry: Sprite2D
var trail: Line2D
var clock := 0.0
var tip_local := Vector2(36, -48)

func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = Art.frames("items_allies")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = false
	add_child(sprite)
	carry = Sprite2D.new()
	carry.centered = true
	carry.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	carry.visible = false
	add_child(carry)
	trail = Line2D.new()
	trail.width = 4
	trail.default_color = Color(1, .4, .08, .75)
	add_child(trail)

func tip_global() -> Vector2:
	return to_global(tip_local)

func animate(kind: String, step: int, progress: float, active: bool, movement: Vector2, dt: float, pose: String) -> void:
	clock += dt * (10.0 if movement.length() > .1 else 3.0)
	visible = kind != ""
	trail.clear_points()
	if not visible:
		sprite.hide()
		carry.hide()
		return
	var armed: SpriteFrames = Art.armed_frames(kind)
	if armed != null and pose not in CARRY_POSES:
		_armed(kind, step, progress, active)
	elif pose in CARRY_POSES and Art.carry_texture(kind) != null:
		_carry(kind, pose, movement)
	else:
		_fallback(kind, step, progress, active)

func _armed(kind: String, step: int, progress: float, active: bool) -> void:
	sprite.hide()
	carry.hide()
	var sheet_frame := 0
	if active:
		var clip_frame := 0 if progress < .30 else 1 if progress < .64 else 2
		sheet_frame = 5 + (maxi(step, 1) - 1) * 3 + clip_frame
	var pivot := _pivot(kind)
	var hand: Variant = Art.sheet_anchor(kind, "hand", sheet_frame)
	var tip: Variant = Art.sheet_anchor(kind, "tip", sheet_frame)
	if tip == null and active:
		tip = Art.sheet_anchor(kind, "tip", 5 + (maxi(step, 1) - 1) * 3 + 1)
	if tip == null:
		tip = hand
	if tip is Vector2:
		tip_local = (tip - pivot) * BODY_SCALE
	if active and progress >= .30 and progress < .64 and tip is Vector2 and hand is Vector2:
		var aim: Vector2 = tip - hand
		var angle := aim.angle() if aim.length() > 1.0 else 0.0
		var sign := -1.0 if step == 2 else 1.0
		for i in 8:
			var a := angle + float(i) * .1 * sign
			trail.add_point(tip_local + Vector2(cos(a), sin(a)) * (12.0 + float(i) * 6.0))

func _carry(kind: String, pose: String, movement: Vector2) -> void:
	sprite.hide()
	carry.show()
	var texture := Art.carry_texture(kind)
	if carry.texture != texture:
		carry.texture = texture
	var hand_cell: Vector2 = HANDS.get(pose, HANDS.idle)
	var hand := (hand_cell - UNARMED_PIVOT) * BODY_SCALE
	if movement.length() > .1:
		hand.y -= sin(clock) * 2.0
	var grip: Vector2 = GRIPS.get(kind, CELL * .5) * .25
	var size := Vector2(texture.get_width(), texture.get_height())
	carry.offset = size * .5 - grip
	carry.position = hand
	carry.rotation = 0.0
	carry.scale = Vector2.ONE * BODY_SCALE
	tip_local = hand

func _fallback(kind: String, step: int, progress: float, active: bool) -> void:
	carry.hide()
	sprite.show()
	if sprite.animation != kind:
		sprite.play(kind)
	var p := sin(progress * PI) if active else 0.0
	var hand := Vector2(28.0 + p * 35.0, -47.0 - sin(clock) * 2.0)
	var angle := -.35
	if active:
		angle = lerpf(-1.8, .65, smoothstep(.18, .52, progress)) if step != 2 else lerpf(1.7, -.55, smoothstep(.18, .52, progress))
		if progress > .7:
			angle = lerpf(angle, -.35, (progress - .7) / .3)
	if kind == "triage_hammer":
		hand.y -= sin(progress * PI) * 26.0 if active else 0.0
	if kind == "security_scanner":
		angle = 0.0
		hand.x += p * 15.0
	var grip: Vector2 = GRIPS.get(kind, CELL * .5)
	var scale := float(SCALES.get(kind, 0.32))
	sprite.offset = CELL * .5 - grip
	sprite.position = hand
	sprite.rotation = angle
	sprite.scale = Vector2.ONE * scale
	var tip_tex: Vector2 = TIPS.get(kind, grip)
	tip_local = hand + ((tip_tex - grip) * scale).rotated(angle)
	if active and progress >= .30 and progress < .64:
		var sign := -1.0 if step == 2 else 1.0
		for i in 8:
			var a := angle + float(i) * .09 * sign
			trail.add_point(tip_local + Vector2(cos(a), sin(a)) * (8.0 + float(i) * 5.0))

func _pivot(kind: String) -> Vector2:
	var spec := Art.armed_spec(kind)
	if spec.has("pivot"):
		return Vector2(spec.pivot[0], spec.pivot[1])
	return Vector2(96, 147)
