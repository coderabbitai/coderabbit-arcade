extends Node2D
## Carry icon, swing trail, and the legacy weapon sprite for sheets that are
## not packed yet. The body draws a baked sheet when one exists.
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
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
	"defeat": Vector2(90, 102),
	"victory": Vector2(90, 96),
}
const CARRY_POSES := ["walk_up", "walk_down", "jump", "defeat", "victory"]
## Contact trail per combo step, as in Code City: an arc around the paw for swings and slams,
## a short streak behind the tip for thrusts and punches.
const TRAIL_STYLE := {
	"review_stamp": ["streak", "arc", "streak"],
	"triage_hammer": ["arc", "arc", "arc"],
	"change_stack_baton": ["streak", "arc", "streak"],
	"security_scanner": ["arc", "streak", "streak"],
	"pr_merger": ["streak", "streak", "streak"],
}
const TRAIL_POINTS := 9
const TRAIL_ARC := 1.0 # radians swept back from the tip
const TRAIL_STREAK := 36.0 # rig pixels behind the tip
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
		# An unarmed whiff must not reuse the previous weapon's tip.
		tip_local = Vector2(70, -50)
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
	var pivot := Art.armed_pivot(kind)
	var hand: Variant = Art.sheet_anchor(kind, "hand", sheet_frame)
	var tip: Variant = Art.sheet_anchor(kind, "tip", sheet_frame)
	var contact := 5 + (maxi(step, 1) - 1) * 3 + 1
	if tip == null and active:
		tip = Art.sheet_anchor(kind, "tip", contact)
	if tip == null:
		tip = hand
	if tip is Vector2:
		tip_local = (tip - pivot) * Art.BODY_SCALE
	if active and progress >= .30 and progress < .64 and tip is Vector2:
		var windup: Variant = Art.sheet_anchor(kind, "tip", contact - 1)
		if windup == null:
			windup = Art.sheet_anchor(kind, "hand", contact - 1)
		var paw: Variant = Art.sheet_anchor(kind, "hand", contact)
		var paw_local: Vector2 = tip_local if paw == null else (paw - pivot) * Art.BODY_SCALE
		var windup_local: Vector2 = tip_local if windup == null else (windup - pivot) * Art.BODY_SCALE
		var styles: Array = TRAIL_STYLE.get(kind, ["arc", "arc", "arc"])
		_armed_trail(styles[clampi(step, 1, 3) - 1], paw_local, windup_local, torso_box(kind, step))

## Rig-space box behind the contact paw, from the hips to eye level. No trail point enters it.
func torso_box(kind: String, step: int) -> Rect2:
	var pivot := Art.armed_pivot(kind)
	var paw: Variant = Art.sheet_anchor(kind, "hand", 5 + (clampi(step, 1, 3) - 1) * 3 + 1)
	var height := float(Art.armed_spec(kind).get("body_height", 86))
	var right: float = paw.x - 8.0 if paw is Vector2 else pivot.x
	var top_left := (Vector2(pivot.x - 24.0, pivot.y - .8 * height) - pivot) * Art.BODY_SCALE
	var bottom_right := (Vector2(right, pivot.y - .3 * height) - pivot) * Art.BODY_SCALE
	return Rect2(top_left, (bottom_right - top_left).max(Vector2.ZERO))

## Arcs sweep back from the tip on whichever side stays out of the torso (ties: the forward
## side); streaks run back along the tip's motion from the windup. Either way the trail ends on
## the tip, stops before the torso and stays above the feet.
func _armed_trail(style: String, paw: Vector2, windup: Vector2, torso: Rect2) -> void:
	var points: Array[Vector2] = []
	if style == "arc":
		var reach := tip_local - paw
		var best := INF
		for side in [1.0, -1.0]:
			var arc: Array[Vector2] = []
			var score := 0.0
			for i in TRAIL_POINTS:
				var point: Vector2 = paw + reach.rotated(side * TRAIL_ARC * float(i) / float(TRAIL_POINTS - 1))
				arc.append(point)
				score += (1000.0 if torso.has_point(point) else 0.0) - point.x * .001
			if score < best:
				best = score
				points = arc
	else:
		var motion := tip_local - windup
		if motion.length() < 1.0:
			motion = tip_local - paw
		var back := -motion.normalized() if motion.length() >= 1.0 else Vector2.LEFT
		for i in TRAIL_POINTS:
			points.append(tip_local + back * TRAIL_STREAK * float(i) / float(TRAIL_POINTS - 1))
	var kept: Array[Vector2] = []
	for i in points.size():
		if torso.has_point(points[i]) or (i > 0 and torso.has_point((points[i] + points[i - 1]) * .5)):
			break
		kept.append(Vector2(points[i].x, minf(points[i].y, 0.0)))
	kept.reverse()
	for point in kept:
		trail.add_point(point)

func _carry(kind: String, pose: String, movement: Vector2) -> void:
	sprite.hide()
	carry.show()
	var texture := Art.carry_texture(kind)
	if carry.texture != texture:
		carry.texture = texture
	var hand_cell: Vector2 = HANDS.get(pose, HANDS.idle)
	var hand := (hand_cell - UNARMED_PIVOT) * Art.BODY_SCALE
	if movement.length() > .1:
		hand.y -= sin(clock) * 2.0
	var grip: Vector2 = GRIPS.get(kind, CELL * .5) * .25
	var size := Vector2(texture.get_width(), texture.get_height())
	carry.offset = size * .5 - grip
	carry.position = hand
	carry.rotation = 0.0
	carry.scale = Vector2.ONE * Art.BODY_SCALE
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
		var start := tip_local - Vector2(cos(angle - .35 * sign), sin(angle - .35 * sign)) * 36.0
		_trail_toward(start, tip_local)

## The arc ends on the tip and stays at or above the feet.
func _trail_toward(start: Vector2, tip: Vector2) -> void:
	for i in 8:
		var point := start.lerp(tip, float(i) / 7.0)
		point.y = minf(point.y, 0.0)
		trail.add_point(point)
