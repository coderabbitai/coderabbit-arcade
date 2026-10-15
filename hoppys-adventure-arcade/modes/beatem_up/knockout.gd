extends RefCounted
## Last-life knockout shared by the beat'em up modes: a hit-stop under a white flash, Hoppy thrown
## back on an arc away from the hit, a landing with dust and a bounce, then dizzy stars and a
## "K.O." callout under ducked music, a failure card, and finally the owner's game over. Clock-driven from the
## owner's _physics_process (no Tweens), so tests step it with tick(); a paused tree freezes it
## because the owner stops ticking. Its effects run on the same clock and are freed when it ends.
##
## Owner contract (duck-typed, as boss.gd uses its arena): `player` (body, facing, show_pose),
## `actors`, `ui_layer`, `screen_fx`, `flow`, `shake`, sound(key, pos), clamp_ground(pos) and
## room_start(). Optional camera and knockout_hud_nodes() -> Array[CanvasItem]: return only
## gameplay chrome, never pause/retry menus. Visibility is captured once and restored on exit.
## The owner stops play, calls play() with its game over, then tick(dt) on every unpaused physics
## frame while its state is "knockout", and keeps its camera shake decaying. cancel() on any path
## that rebuilds or leaves the stage.

const Style = preload("res://scenes/main_menu/menu_style.gd")
## Both modes' rooms are one 1280 px screen wide (room_start() = room*1280).
const ROOM_WIDTH := 1280.0
const ROOM_HEIGHT := 720.0
## Every key a mode's KNOCKOUT may override. Seconds since the hit, world px, radians and dB.
const DEFAULTS := {
	# Phase ends: hit-stop, launch (touchdown), land (settled), out cold (game over).
	"hit_stop":.12, "launch_end":.75, "land_end":1.0, "length":2.2,
	# The arc away from the hit, its peak, the rebound after touchdown and how long that takes.
	# He lands at least `edge` inside the room's 1280 px, so the lying head and stars stay on screen.
	"distance":140.0, "height":70.0, "bounce":12.0, "bounce_time":.16, "edge":60.0,
	# Pitch at touchdown (+ leads with the head along the throw) around a point this far above the
	# feet. He faces the hit until `turn`, then the way he is thrown: lying poses put the head in
	# front, so the head stays on the side he flew to.
	"tip":0.0, "pivot":45.0, "turn":.75,
	"flash":.65, "flash_fade":.2, "shake":14.0, "land_shake":7.0,
	"duck_db":-12.0, "duck_in":.25, "duck_out":.3,
	# Poses: hit-stop, airborne and landed. A non-empty `clip` replaces the airborne and landed
	# poses with one clip whose frames start at clip_starts (seconds since the hit).
	"hit_pose":"hurt", "air_pose":"hurt", "land_pose":"defeat", "clip":"", "clip_starts":[],
	# Hide a carried weapon while airborne (the player's `stowed`, where it has one).
	"stow_airborne":false,
	# Effects: {frames (a SpriteFrames path, loaded on use: a preload held in a catalog constant
	# outlives the scene at exit), pose, scale, squash (vertical factor), rise (screen px above the
	# feet), front (draws over Hoppy), life}.
	"hit_fx":{}, "dust_fx":{}, "fx_life":.35, "land_sound":"",
	# Stars circle `head` (lying pose, facing right, feet-relative) on an orbit of these radii.
	"head":Vector2(30,-40), "stars":3, "star_orbit":Vector2(24,7), "star_size":7.0, "star_spin":1.4,
	"star_color":Color("ffe36e"),
	"callout":"K.O.", "callout_size":96, "callout_color":Color("ffd36b"), "callout_top":215.0,
	"callout_pop":.18,
	# The pose clock slows only between these pose times; all previous keys keep their units.
	"slowmo_from":.12, "slowmo_to":.75, "slowmo_scale":.55,
	"zoom":2.0, "zoom_in":.45, "zoom_out":.25, "bars":90.0,
	"card_hold":.8, "card_title":"REVIEW FAILED", "card_line":"Every great merge takes another try."}
var tuning: Dictionary = DEFAULTS.duplicate()
var phase := ""                  # "", "hit_stop", "launch", "land", "out_cold", "card"
var clock := 0.0                 # seconds since the hit
var elapsed := 0.0               # unwarped seconds; pose clock stops at length for the card
var player: Node2D
var direction := 1.0             # world x direction of the throw, away from the hit
var start := Vector2.ZERO
var landing := Vector2.ZERO
var root: Control
var flash: ColorRect
var callout: Label
var stars: Node2D
var top_bar: ColorRect
var bottom_bar: ColorRect
var card: Control
var card_title: Label
var _camera: Camera2D
var _camera_position := Vector2.ZERO
var _camera_zoom := Vector2.ONE
var _arena: Node
var _done := Callable()
var _pose := ""
var _landed := false
var _fx: Array[Dictionary] = []
var _hud: Array[Dictionary] = []

func _init(overrides := {}) -> void:
	tuning.merge(overrides,true)

func active() -> bool:
	return phase != ""

## Starts the knockout of `owner.player`, thrown away from `source`; `done` runs at the end.
func play(owner: Node, source: Vector2, done: Callable) -> void:
	cancel()
	_arena = owner
	player = owner.player
	_done = done
	clock = 0
	elapsed = 0
	_landed = false
	_pose = ""
	var away := signf(player.position.x-source.x)
	direction = away if away != 0 else -signf(float(player.facing))
	if direction == 0: direction = -1.0
	player.facing = -direction # He takes the hit facing it and flies back from it.
	start = player.position
	if owner.has_method("knockout_hud_nodes"):
		for item in owner.knockout_hud_nodes():
			if is_instance_valid(item) and item is CanvasItem:
				_hud.append({"node":item,"visible":item.visible})
	_hide_hud()
	_camera = owner.get("camera") as Camera2D
	if is_instance_valid(_camera):
		_camera_position = _camera.position
		_camera_zoom = _camera.zoom
	landing = owner.clamp_ground(start+Vector2(direction*float(tuning.distance),0))
	var left: float = owner.room_start()+float(tuning.edge)
	landing.x = clampf(landing.x,left,maxf(left,owner.room_start()+ROOM_WIDTH-float(tuning.edge)))
	_build_ui(owner.ui_layer,owner.screen_fx)
	player.body.modulate = Color.WHITE
	stars = Node2D.new()
	stars.name = "KnockoutStars"
	stars.visible = false
	stars.draw.connect(_draw_stars.bind(stars))
	player.add_child(stars)
	owner.shake = maxf(owner.shake,float(tuning.shake))
	_spawn(tuning.hit_fx,start-Vector2(direction*14,0))
	phase = "hit_stop"
	_apply()

## Ends the knockout without calling `done`: removes its stars and effects (hidden at once, freed
## at the end of the frame), hides the flash and callout, lifts the music duck and rests the body
## on the ground, upright. Idempotent.
func cancel() -> void:
	phase = ""
	_done = Callable()
	for fx in _fx:
		if is_instance_valid(fx.node):
			fx.node.hide()
			fx.node.queue_free()
	_fx.clear()
	if is_instance_valid(stars):
		stars.hide()
		stars.queue_free()
	stars = null
	if is_instance_valid(root): root.hide()
	for item in _hud:
		if is_instance_valid(item.node): item.node.visible = item.visible
	_hud.clear()
	if is_instance_valid(_camera):
		_camera.position = _camera_position
		_camera.zoom = _camera_zoom
	_camera = null
	if is_instance_valid(player):
		player.set("stowed",false)
		player.body.rotation = 0
		player.body.position = Vector2.ZERO
	if is_instance_valid(_arena) and is_instance_valid(_arena.flow): _arena.flow.duck(0)

func tick(dt: float) -> void:
	if phase == "": return
	if not is_instance_valid(player) or not is_instance_valid(_arena):
		cancel()
		return
	if _arena.is_inside_tree() and _arena.get_tree().paused: return
	elapsed += maxf(dt,0.0)
	# Analytical mapping crosses both slow-motion boundaries correctly even on a coarse tick.
	clock = minf(_pose_time(elapsed),float(tuning.length))
	if elapsed >= duration()-1e-6:
		var done := _done
		cancel()
		if done.is_valid(): done.call()
		return
	_apply()

func _slow_bounds() -> Vector3:
	var first := clampf(float(tuning.slowmo_from),0,float(tuning.length))
	var last := clampf(float(tuning.slowmo_to),first,float(tuning.length))
	return Vector3(first,last,clampf(float(tuning.slowmo_scale),.1,1.0))

func _pose_time(seconds: float) -> float:
	var slow := _slow_bounds()
	var end := slow.x+(slow.y-slow.x)/slow.z
	if seconds <= slow.x: return seconds
	if seconds < end: return slow.x+(seconds-slow.x)*slow.z
	return slow.y+seconds-end

func _fall_duration() -> float:
	var slow := _slow_bounds()
	return float(tuning.length)+(slow.y-slow.x)*(1.0/slow.z-1.0)

## Both catalogs finish in 3.516 seconds. A hard ceiling also bounds custom tuning.
func duration() -> float:
	return minf(4.0,_fall_duration()+maxf(float(tuning.card_hold),0.0))

## Poses, places and decorates Hoppy for the current clock. Touchdown's dust, sound and shake
## fire once, on the first tick at or past launch_end.
func _apply() -> void:
	_hide_hud()
	var hit_stop := float(tuning.hit_stop)
	var launch_end := float(tuning.launch_end)
	if clock < hit_stop: phase = "hit_stop"
	elif clock < launch_end: phase = "launch"
	elif clock < float(tuning.land_end): phase = "land"
	elif elapsed < _fall_duration(): phase = "out_cold"
	else: phase = "card"
	var airborne := clock < launch_end
	var u := clampf((clock-hit_stop)/maxf(launch_end-hit_stop,.001),0,1)
	var height := 0.0
	var angle := 0.0
	if airborne:
		height = float(tuning.height)*4.0*u*(1.0-u)
		angle = float(tuning.tip)*smoothstep(0.0,1.0,u)
	else:
		if not _landed: _touchdown()
		var b := clampf((clock-launch_end)/maxf(float(tuning.bounce_time),.001),0,1)
		height = float(tuning.bounce)*sin(PI*b)
	player.position.x = lerpf(start.x,landing.x,u)
	var facing := direction if clock >= float(tuning.turn) else -direction
	if float(player.facing) != facing:
		player.facing = facing
		_pose = "" # show_pose mirrors the body (and a carry) for the new facing.
	_show_pose(airborne)
	var body: Node2D = player.body
	var pivot := Vector2(0,-float(tuning.pivot))
	body.rotation = angle*direction
	body.position = Vector2(0,-height)+pivot-pivot.rotated(body.rotation)
	var held = player.get("held")
	if held is Node2D: held.position = body.position
	_tick_fx()
	_tick_ui()
	_tick_camera()
	if is_instance_valid(stars):
		var head: Vector2 = tuning.head
		stars.position = Vector2(head.x*float(player.facing),head.y-height)
		stars.visible = phase in ["out_cold","card"]
		stars.queue_redraw()
	var duck := 0.0
	var land_end := float(tuning.land_end)
	if clock >= land_end:
		var down := clampf((clock-land_end)/maxf(float(tuning.duck_in),.001),0,1)
		var up := clampf((duration()-elapsed)/maxf(float(tuning.duck_out),.001),0,1)
		duck = float(tuning.duck_db)*minf(down,up)
	_arena.flow.duck(duck)

func _hide_hud() -> void:
	# The owner refreshes minimap/toast visibility on each physics tick, including during KO.
	for item in _hud:
		if is_instance_valid(item.node): item.node.hide()

func _tick_camera() -> void:
	if not is_instance_valid(_camera): return
	var inward := smoothstep(0.0,maxf(float(tuning.zoom_in),.001),elapsed)
	var outward := smoothstep(0.0,maxf(float(tuning.zoom_out),.001),duration()-elapsed)
	var strength := inward*outward
	_camera.zoom = _camera_zoom*lerpf(1.0,float(tuning.zoom),strength)
	# Leave offset to the owner's shake, including Code City's shake after ko.tick().
	var focus := player.global_position+Vector2(0,-80)
	if _camera.get_parent() is Node2D:
		focus = (_camera.get_parent() as Node2D).to_local(focus)
	_camera.position = _camera_position.lerp(focus,strength)
	# A throw near a door must not pan past the room art and expose the empty canvas.
	var half_view := _camera.get_viewport_rect().size.x/maxf(_camera.zoom.x,.001)*.5
	var room_left: float = _arena.room_start()
	if half_view < ROOM_WIDTH*.5:
		_camera.position.x = clampf(_camera.position.x,room_left+half_view,room_left+ROOM_WIDTH-half_view)
	var half_height := _camera.get_viewport_rect().size.y/maxf(_camera.zoom.y,.001)*.5
	if half_height < ROOM_HEIGHT*.5:
		_camera.position.y = clampf(_camera.position.y,half_height,ROOM_HEIGHT-half_height)

func _touchdown() -> void:
	_landed = true
	_spawn(tuning.dust_fx,landing)
	_arena.shake = maxf(_arena.shake,float(tuning.land_shake))
	if str(tuning.land_sound) != "": _arena.sound(str(tuning.land_sound),landing)

## The hit pose through the hit-stop, then the airborne and landed poses, or the clip's frame.
func _show_pose(airborne: bool) -> void:
	var clip := str(tuning.clip)
	var pose := clip
	if phase == "hit_stop": pose = str(tuning.hit_pose)
	elif clip == "": pose = str(tuning.air_pose) if airborne else str(tuning.land_pose)
	var body: AnimatedSprite2D = player.body
	if pose != _pose:
		_pose = pose
		player.set("stowed",airborne and bool(tuning.stow_airborne))
		if pose == clip: player.show_pose(pose,true)
		else: player.show_pose(pose)
		body.pause()
		body.frame = 0
	if pose == clip:
		var frame := 0
		var starts: Array = tuning.clip_starts
		for i in starts.size():
			if clock >= float(starts[i]): frame = i
		body.frame = mini(frame,body.sprite_frames.get_frame_count(clip)-1)

## An existing effect cel on the knockout clock: placed on the ground under its anchor so the
## stage's y-sort sees it with Hoppy (`front` draws it over him), raised by `rise`, fading out.
func _spawn(spec: Dictionary, at: Vector2) -> void:
	if spec.is_empty() or not is_instance_valid(_arena.actors): return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load(str(spec.frames))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var magnify := float(spec.get("scale",1.0))
	sprite.scale = Vector2(magnify,magnify*float(spec.get("squash",1.0)))
	sprite.position = Vector2(at.x,start.y+(1.0 if spec.get("front",false) else -1.0))
	sprite.offset = Vector2(0,-float(spec.get("rise",0.0))/maxf(sprite.scale.y,.001))
	sprite.play(spec.pose)
	_arena.actors.add_child(sprite)
	_fx.append({"node":sprite,"born":clock,"life":float(spec.get("life",tuning.fx_life))})

func _tick_fx() -> void:
	for i in range(_fx.size()-1,-1,-1):
		var fx: Dictionary = _fx[i]
		var left := 1.0-(clock-float(fx.born))/maxf(float(fx.life),.001)
		if left <= 0 or not is_instance_valid(fx.node):
			if is_instance_valid(fx.node):
				fx.node.hide()
				fx.node.queue_free()
			_fx.remove_at(i)
		else: fx.node.modulate.a = left

func _build_ui(ui_layer: CanvasLayer, screen_fx: Node) -> void:
	if not is_instance_valid(root):
		root = Control.new()
		root.name = "Knockout"
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.theme = Style.theme()
		ui_layer.add_child(root)
		flash = ColorRect.new()
		flash.color = Color(1,1,1,0)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(flash)
		callout = Style.label(str(tuning.callout),int(tuning.callout_size),tuning.callout_color)
		callout.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		callout.offset_top = float(tuning.callout_top)
		callout.offset_bottom = float(tuning.callout_top)+float(tuning.callout_size)*1.3
		callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		callout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		callout.add_theme_color_override("font_outline_color",Color(.06,.03,.05))
		callout.add_theme_constant_override("outline_size",14)
		callout.add_theme_color_override("font_shadow_color",Color(0,0,0,.6))
		callout.add_theme_constant_override("shadow_offset_x",5)
		callout.add_theme_constant_override("shadow_offset_y",5)
		callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(callout)
		for bottom in [false,true]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
			root.add_child(bar)
			if bottom: bottom_bar = bar
			else: top_bar = bar
		card = Control.new()
		card.name = "FailureCard"
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		card.offset_top = 158
		card.offset_bottom = 330
		root.add_child(card)
		var panel := ColorRect.new()
		panel.color = Color(.025,.035,.06,.94)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(panel)
		for bottom in [false,true]:
			var line := ColorRect.new()
			line.color = tuning.callout_color
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
			if bottom: line.offset_top = -3
			else: line.offset_bottom = 3
			card.add_child(line)
		card_title = _card_label(str(tuning.card_title),52,tuning.callout_color,24,90)
		_card_label(str(tuning.card_line),22,Style.CREAM,105,145)
	# Over the world and its screen effect, under the owner's HUD and menus.
	if is_instance_valid(screen_fx) and screen_fx.get_parent() == ui_layer:
		ui_layer.move_child(root,mini(screen_fx.get_index()+1,ui_layer.get_child_count()-1))
	root.show()

func _card_label(text: String, size: int, color: Color, top: float, bottom: float) -> Label:
	var label := Style.label(text,size,color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.offset_bottom = bottom
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(label)
	return label

func _tick_ui() -> void:
	flash.color.a = float(tuning.flash)*clampf(1.0-clock/maxf(float(tuning.flash_fade),.001),0,1)
	var shown := clock-float(tuning.land_end)
	callout.visible = shown >= 0 and phase != "card"
	if callout.visible:
		var pop := clampf(shown/maxf(float(tuning.callout_pop),.001),0,1)
		callout.modulate.a = pop
		callout.pivot_offset = callout.size*.5
		callout.scale = Vector2.ONE*lerpf(1.8,1.0,1.0-pow(1.0-pop,3))
	# Fully letterboxed by the first airborne frame, held through the failure card.
	var bars_in := smoothstep(0.0,maxf(float(tuning.hit_stop),.001),elapsed)
	top_bar.offset_bottom = float(tuning.bars)*bars_in
	bottom_bar.offset_top = -float(tuning.bars)*bars_in
	card.visible = phase == "card"
	card.modulate.a = clampf((elapsed-_fall_duration())/.12,0,1)

## Stars circling the lying head, larger and brighter on the near side of the orbit.
func _draw_stars(canvas: Node2D) -> void:
	var count := int(tuning.stars)
	var orbit: Vector2 = tuning.star_orbit
	var seen := clock-float(tuning.land_end)+maxf(0.0,elapsed-_fall_duration())
	var fade := clampf(seen/.15,0,1)
	for i in count:
		var a := TAU*(float(tuning.star_spin)*seen+float(i)/count)
		var near := .5+.5*sin(a)
		var size := float(tuning.star_size)*(.75+.4*near)
		var center := Vector2(cos(a)*orbit.x,sin(a)*orbit.y)
		var color: Color = tuning.star_color
		color.a = fade*(.65+.35*near)
		canvas.draw_colored_polygon(_star(center,size*1.45,a*2.0),Color(.07,.04,.06,color.a))
		canvas.draw_colored_polygon(_star(center,size,a*2.0),color)

static func _star(center: Vector2, radius: float, spin: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 10:
		var r := radius if k%2 == 0 else radius*.45
		var t := spin+TAU*k/10.0-PI*.5
		points.append(center+Vector2(cos(t),sin(t))*r)
	return points
