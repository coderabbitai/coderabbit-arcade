extends RefCounted
## Clock-owned Code City finale. Owner stops combat and ticks this while unpaused, then done
## opens the ending pages. The flow's music player owns the victory loop after the party ends.
## cancel() on stage rebuild or leave also stops that loop, but never a newer stage track.
## Owner: player (body, show_pose), ui_layer, flow (StageFlow). camera and player.held are optional.
## Optional knockout_hud_nodes() returns gameplay chrome, excluding pause, story and results UI.
## Tick after the owner's HUD refreshes. Visibility is restored before done or on cancel.

const Style = preload("res://scenes/main_menu/menu_style.gd")
const AUDIO := "res://Assets/Audio/Beat'em Up/"
const JINGLE_PATH := AUDIO+"code_city_victory_jingle.wav"
const LOOP_PATH := AUDIO+"code_city_victory_loop.wav"
const LENGTH := 5.2
const JINGLE_AT := .3
const LOOP_AT := 3.8
const COLORS := [Color("79e0c4"),Color("ffd36b"),Color("ff884d"),Color("a0bcff"),Color("fff0cb")]

var clock := 0.0
var phase := ""
var root: Control
var banner: Label
var confetti: Control
var jingle: AudioStreamPlayer
var player: Node2D
var _arena: Node
var _flow: Node
var _done := Callable()
var _jingle_started := false
var _loop_started := false
var _loop_stream: AudioStream
var _camera: Camera2D
var _camera_position := Vector2.ZERO
var _camera_zoom := Vector2.ONE
var _body_position := Vector2.ZERO
var _body_rotation := 0.0
var _held_visible := false
var _hud: Array[Dictionary] = []

func active() -> bool:
	return phase != ""

func play(owner: Node, done: Callable) -> void:
	cancel()
	_arena = owner
	_flow = owner.flow
	player = owner.player
	_done = done
	clock = 0.0
	phase = "celebration"
	_jingle_started = false
	_loop_started = false
	if owner.has_method("knockout_hud_nodes"):
		for item in owner.knockout_hud_nodes():
			if is_instance_valid(item) and item is CanvasItem:
				_hud.append({"node":item,"visible":item.visible})
	_hide_hud()
	_body_position = player.body.position
	_body_rotation = player.body.rotation
	player.body.rotation = 0.0
	player.body.modulate = Color.WHITE
	var held = player.get("held")
	_held_visible = is_instance_valid(held) and held is CanvasItem and held.visible
	if held is CanvasItem: held.hide()
	player.show_pose("victory")
	player.body.pause()
	_camera = owner.get("camera") as Camera2D
	if is_instance_valid(_camera):
		_camera_position = _camera.position
		_camera_zoom = _camera.zoom
	_build_ui(owner.ui_layer)
	_flow.duck(-18.0)
	_apply()

func tick(dt: float) -> void:
	if not active(): return
	if not is_instance_valid(_arena) or not is_instance_valid(player) or not is_instance_valid(_flow):
		cancel()
		return
	if _arena.is_inside_tree() and _arena.get_tree().paused: return
	clock = minf(clock+maxf(dt,0.0),LENGTH)
	if clock >= JINGLE_AT and not _jingle_started:
		_jingle_started = true
		jingle = AudioStreamPlayer.new()
		jingle.name = "VictoryJingle"
		jingle.process_mode = Node.PROCESS_MODE_PAUSABLE
		jingle.stream = load(JINGLE_PATH)
		jingle.volume_db = _flow.base_db
		if is_instance_valid(_flow.music): jingle.bus = _flow.music.bus
		_arena.add_child(jingle)
		jingle.play(minf(clock-JINGLE_AT,jingle.stream.get_length()))
	if clock >= LOOP_AT and not _loop_started:
		_loop_started = true
		_stop_jingle()
		var source: AudioStream = load(LOOP_PATH)
		# Duplicate before setting loop properties, so the imported shared resource stays immutable.
		var loop := source.duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = roundi(loop.get_length()*loop.mix_rate)
		_loop_stream = loop
		_flow.play_music(loop,source)
		_flow.duck(0.0)
	_apply()
	if clock >= LENGTH-1e-6:
		var done := _done
		_done = Callable()
		phase = ""
		_clear_visuals()
		player = null
		if done.is_valid(): done.call()

## Explicit cancellation suppresses done and clears every owned transient. Completion leaves
## the loop playing; this method ends it only if the flow still holds our exact stream instance.
func cancel() -> void:
	phase = ""
	_done = Callable()
	_stop_jingle()
	_clear_visuals()
	if is_instance_valid(_flow):
		_flow.duck(0.0)
		if _loop_stream != null and is_instance_valid(_flow.music) and _flow.music.stream == _loop_stream:
			_flow.music.stop()
			_flow.music.stream = null
			_flow.music_track = null
	_loop_stream = null
	_flow = null
	_arena = null
	player = null

func _stop_jingle() -> void:
	if is_instance_valid(jingle):
		jingle.stop()
		jingle.queue_free()
	jingle = null

func _clear_visuals() -> void:
	for item in _hud:
		if is_instance_valid(item.node): item.node.visible = item.visible
	_hud.clear()
	if is_instance_valid(root):
		root.hide()
		root.queue_free()
	root = null
	banner = null
	confetti = null
	if is_instance_valid(player):
		player.body.position = _body_position
		player.body.rotation = _body_rotation
		var held = player.get("held")
		if held is CanvasItem: held.visible = _held_visible
	if is_instance_valid(_camera):
		_camera.position = _camera_position
		_camera.zoom = _camera_zoom
	_camera = null

func _apply() -> void:
	_hide_hud()
	var pop := smoothstep(.15,.65,clock)
	var fade := smoothstep(0.0,.35,LENGTH-clock)
	root.modulate.a = fade
	banner.modulate.a = pop
	banner.pivot_offset = banner.size*.5
	banner.scale = Vector2.ONE*lerpf(1.16,1.0,pop)
	# Advance on our clock; pause must freeze the pose along with the confetti and camera.
	var body: AnimatedSprite2D = player.body
	var count := body.sprite_frames.get_frame_count(body.animation)
	if count > 0: body.frame = int(clock*5.0)%count
	body.position = Vector2(0,-maxf(0,sin(clock*TAU/1.1))*12.0)
	confetti.queue_redraw()
	if is_instance_valid(_camera):
		var push := smoothstep(0.0,2.0,clock)*fade
		_camera.zoom = _camera_zoom*lerpf(1.0,1.3,push)
		var focus := player.global_position+Vector2(0,-140)
		if _camera.get_parent() is Node2D:
			focus = (_camera.get_parent() as Node2D).to_local(focus)
		_camera.position = _camera_position.lerp(focus,push*.8)

func _hide_hud() -> void:
	# The owner may refresh minimap/toast visibility each physics tick, even outside combat.
	for item in _hud:
		if is_instance_valid(item.node): item.node.hide()

func _build_ui(layer: CanvasLayer) -> void:
	root = Control.new()
	root.name = "Celebration"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme()
	layer.add_child(root)
	# Stay beneath pause/menu controls, with the stage and its shader behind the celebration.
	var screen_fx = _arena.get("screen_fx")
	if screen_fx is Node and screen_fx.get_parent() == layer:
		layer.move_child(root,mini(screen_fx.get_index()+1,layer.get_child_count()-1))
	confetti = Control.new()
	confetti.name = "Confetti"
	confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confetti.draw.connect(_draw_confetti)
	root.add_child(confetti)
	for bottom in [false,true]:
		var bar := ColorRect.new()
		bar.color = Color("091521")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		if bottom: bar.offset_top = -45
		else: bar.offset_bottom = 45
		root.add_child(bar)
	var ribbon := ColorRect.new()
	ribbon.color = Color(.025,.07,.1,.92)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ribbon.offset_top = 151
	ribbon.offset_bottom = 308
	root.add_child(ribbon)
	for top in [151,305]:
		var line := ColorRect.new()
		line.color = COLORS[0]
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		line.offset_top = top
		line.offset_bottom = top+3
		root.add_child(line)
	_label("CODE CITY IS BACK ONLINE",18,COLORS[0],168,194)
	banner = _label("MERGE SUCCESSFUL",58,COLORS[1],194,269)
	_label("THREE DISTRICTS. ONE CLEAN HISTORY.",18,Style.CREAM,272,297)

func _label(text: String, size: int, color: Color, top: float, bottom: float) -> Label:
	var label := Style.label(text,size,color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.offset_bottom = bottom
	root.add_child(label)
	return label

## Deterministic falling ribbons. Their clock is the party clock, never an independent timer
## or particle system, so a pause or a headless step has exactly the same visual state.
func _draw_confetti() -> void:
	var view := confetti.size
	for i in 112:
		var age := clock-float(i%14)*.025
		if age < 0: continue
		var lane := float((i*47)%113)/112.0
		var speed := 115.0+float((i*31)%120)
		var x := lane*view.x+sin(age*2.0+i)*34.0
		var seed_y := float((i*97)%1009)/1009.0*(view.y+160.0)
		var y := fposmod(seed_y+age*speed,view.y+160.0)-80.0
		var width := 3.0+absf(cos(age*5.0+i))*7.0
		var height := 5.0+float(i%4)
		confetti.draw_set_transform(Vector2(x,y),age*(1.0+float(i%3)))
		confetti.draw_rect(Rect2(-width*.5,-height*.5,width,height),COLORS[i%COLORS.size()])
	confetti.draw_set_transform(Vector2.ZERO)
