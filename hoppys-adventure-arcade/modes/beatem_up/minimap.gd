extends Control
## The top-right minimap shared by both beat'em ups. The top row is the whole game: every room of
## every stage as a tile, grouped by stage (cleared filled, the current one pulsing, the rest dim,
## boss rooms marked). Under it is the current room: Hoppy, the enemies and any boss as dots over
## the depth band, and the room's gate.
##
## Clock-driven, no Tweens: the host calls tick(dt, snapshot) from its _physics_process, so a
## paused tree freezes it (pulse included) and headless tests can step it. Everything is drawn in
## _draw from the last snapshot; the geometry helpers are public so tests can check the layout.
##
## snapshot = {stage, room, cleared, gate_open, room_left, player: Vector2,
##             enemies: PackedVector2Array, bosses: PackedVector2Array}, all in world pixels.

const Style = preload("res://scenes/main_menu/menu_style.gd")
const SIZE := Vector2(236,92)
## Gap to the window's right edge and below the host's HUD bar.
const MARGIN := Vector2(20,10)
const PAD := 8.0
const STRIP_HEIGHT := 14.0
const STRIP_GAP := 8.0
const GROUP_GAP := 10.0
const TILE_GAP := 3.0
const LABEL_WIDTH := 12.0
## A room in world pixels: 1280 wide, Hoppy and the enemies walk the 455..650 depth band.
const ROOM_WIDTH := 1280.0
const DEPTH_TOP := 455.0
const DEPTH_BOTTOM := 650.0
## Where the encounter gate stands in its room (both modes put it about here).
const GATE_X := 1205.0
const PULSE_RATE := 1.2
const PANEL := Color(.02,.035,.06,.82)
const AHEAD := Color(1,1,1,.12)
const ENEMY := Color("ff6b6b")
const BOSS := Color("ffc66c")
const GATE_CLOSED := Color("ff8888")

var stage_count := 3
var rooms_per_stage := 3
var boss_rooms: Array[Vector2i] = []
var accent := Style.MINT
var stage := 0
var room := 0
var cleared := false
var gate_open := false
## Dots in 0..1 room space (x along the room, y down the depth band).
var player_dot := Vector2.ZERO
var enemy_dots := PackedVector2Array()
var boss_dots := PackedVector2Array()
var pulse := 0.0

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE

## Stage and room counts, the boss rooms as Vector2i(stage, room), and the mode's accent.
func setup(stages: int, rooms: int, bosses: Array[Vector2i], color: Color) -> void:
	stage_count = maxi(stages,1)
	rooms_per_stage = maxi(rooms,1)
	boss_rooms = bosses.duplicate()
	accent = color
	queue_redraw()

## Pins the minimap to the top-right corner, `below` pixels from the top (the HUD bar's bottom).
func dock(below: float) -> void:
	set_anchors_preset(PRESET_TOP_RIGHT)
	offset_left = -SIZE.x-MARGIN.x
	offset_right = -MARGIN.x
	offset_top = below+MARGIN.y
	offset_bottom = below+MARGIN.y+SIZE.y

func tick(dt: float, snapshot: Dictionary) -> void:
	pulse += dt
	stage = clampi(int(snapshot.get("stage",0)),0,stage_count-1)
	room = clampi(int(snapshot.get("room",0)),0,rooms_per_stage-1)
	cleared = bool(snapshot.get("cleared",false))
	gate_open = bool(snapshot.get("gate_open",false))
	var left: float = snapshot.get("room_left",room*ROOM_WIDTH)
	player_dot = map_point(snapshot.get("player",Vector2.ZERO),left)
	enemy_dots = _map_all(snapshot.get("enemies",PackedVector2Array()),left)
	boss_dots = _map_all(snapshot.get("bosses",PackedVector2Array()),left)
	queue_redraw()

## A world position as 0..1 room space, clamped into the room (Hoppy runs in from off-screen
## and out past the gate).
static func map_point(world: Vector2, room_left: float) -> Vector2:
	return Vector2(clampf((world.x-room_left)/ROOM_WIDTH,0,1),clampf((world.y-DEPTH_TOP)/(DEPTH_BOTTOM-DEPTH_TOP),0,1))

static func _map_all(points: Variant, room_left: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points: out.append(map_point(point,room_left))
	return out

func is_boss_room(at_stage: int, at_room: int) -> bool:
	return Vector2i(at_stage,at_room) in boss_rooms

## "cleared", "current" or "ahead" for one tile of the game strip.
func tile_state(at_stage: int, at_room: int) -> String:
	if at_stage<stage or (at_stage==stage and at_room<room): return "cleared"
	if at_stage==stage and at_room==room: return "current"
	return "ahead"

func group_width() -> float:
	return (SIZE.x-PAD*2-GROUP_GAP*(stage_count-1))/stage_count

func tile_rect(at_stage: int, at_room: int) -> Rect2:
	var group_left := PAD+at_stage*(group_width()+GROUP_GAP)
	var tile_width := (group_width()-LABEL_WIDTH-TILE_GAP*(rooms_per_stage-1))/rooms_per_stage
	return Rect2(group_left+LABEL_WIDTH+at_room*(tile_width+TILE_GAP),PAD,tile_width,STRIP_HEIGHT)

func room_rect() -> Rect2:
	var top := PAD+STRIP_HEIGHT+STRIP_GAP
	return Rect2(PAD,top,SIZE.x-PAD*2,SIZE.y-top-PAD)

## A 0..1 room-space dot in this Control's coordinates.
func dot_position(dot: Vector2) -> Vector2:
	var area := room_rect().grow(-4)
	return area.position+dot*area.size

## 0.6..1 brightness of the current tile, on the minimap's own clock.
func pulse_level() -> float:
	return .8+.2*sin(pulse*TAU*PULSE_RATE)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),PANEL)
	draw_rect(Rect2(Vector2.ZERO,SIZE),Color(accent,.45),false,1.0)
	var font := get_theme_font("font","Label")
	for s in stage_count:
		var first := tile_rect(s,0)
		if font != null:
			var label_color := accent if s==stage else Color(Style.CREAM,.55)
			draw_string(font,Vector2(first.position.x-LABEL_WIDTH,first.end.y-2),str(s+1),HORIZONTAL_ALIGNMENT_LEFT,LABEL_WIDTH,11,label_color)
		for r in rooms_per_stage: _draw_tile(s,r)
	_draw_room()

func _draw_tile(at_stage: int, at_room: int) -> void:
	var rect := tile_rect(at_stage,at_room)
	match tile_state(at_stage,at_room):
		"cleared": draw_rect(rect,Color(accent,.85))
		"current":
			draw_rect(rect,Color(accent,(.85 if cleared else .35)*pulse_level()))
			draw_rect(rect.grow(1),Color(Style.CREAM,pulse_level()),false,1.5)
		_: draw_rect(rect,AHEAD)
	if is_boss_room(at_stage,at_room):
		var done := tile_state(at_stage,at_room)=="cleared"
		_draw_diamond(rect.get_center(),3.5,Color(BOSS,.45) if done else BOSS)

func _draw_room() -> void:
	var rect := room_rect()
	draw_rect(rect,Color(1,1,1,.05))
	draw_rect(rect,Color(accent,.35),false,1.0)
	var gate_x := dot_position(Vector2(GATE_X/ROOM_WIDTH,0)).x
	if gate_open: draw_dashed_line(Vector2(gate_x,rect.position.y+2),Vector2(gate_x,rect.end.y-2),Color(accent,.7),1.5,3.0)
	else: draw_line(Vector2(gate_x,rect.position.y+2),Vector2(gate_x,rect.end.y-2),GATE_CLOSED,2.0)
	for dot in enemy_dots: draw_circle(dot_position(dot),2.4,ENEMY)
	for dot in boss_dots: _draw_diamond(dot_position(dot),5.0,BOSS)
	var hoppy := dot_position(player_dot)
	draw_circle(hoppy,4.6,Color(accent,.45))
	draw_circle(hoppy,3.2,Style.CREAM)

func _draw_diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius,0),at+Vector2(0,radius),at+Vector2(-radius,0)]),color)
