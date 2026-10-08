extends Node
## Hands-free stage transitions shared by the beat'em up modes: Hoppy runs out of the cleared
## stage, the screen dips to black while the next one is built, and he runs back in under a
## title banner. Clock-driven from the owner's _physics_process (no Tweens), so tests step it
## with tick(); a paused tree freezes it because the owner stops ticking.
##
## Owner contract: setup() once; tick(dt, player) every unpaused physics frame, combat included
## (banners and music swaps advance there); spawn each stage's player at enter_from_x before
## play_enter(); start combat when phase_changed reports "". From setup() on the director owns
## the music player's volume_db, as an envelope over the volume it had then.
signal phase_changed(phase: String)

const Style = preload("res://scenes/main_menu/menu_style.gd")
## Every key a mode's FLOW may override. Seconds, world px, px/s and dB.
const DEFAULTS := {
	"run_speed":300.0, "exit_min":.6, "exit_max":1.6, "exit_margin":60.0,
	"fade_out":.35, "fade_in":.35, "music_floor_db":-40.0,
	"enter_from_x":-60.0, "enter_to_x":180.0, "enter_max":1.6,
	"stage_banner":2.8, "banner_slide":.3, "banner_fade":.6}
const EXITING := ["exit_run","fade_out","fade_in"]
var phase := ""                  # "", "exit_run", "fade_out", "fade_in", "enter_run"
var clock := 0.0                 # seconds into the current phase
var tuning: Dictionary = DEFAULTS.duplicate()
var music: AudioStreamPlayer
var base_db := 0.0
var music_db := 0.0              # envelope applied on top of base_db
var exit_x := INF                # world x Hoppy must pass before the fade (just off-screen right)
var veil: ColorRect
var banner_panel: Control
var banner_text: Control
var banner_title: Label
var banner_subtitle: Label
var banner_clock := 0.0
var banner_length := 0.0
var _on_black := Callable()
var _serial := 0
var _enter_queued := false
var _enter_title := ""
var _enter_story := ""
var _exit_runner := 0
var _enter_runner := 0
var _fade_db := 0.0
var _swap_db := 0.0
var _swap_stream: AudioStream
var _swap_clock := 0.0
var _swap_length := 0.0
var _swapped := false

func setup(ui_layer: CanvasLayer, music_player: AudioStreamPlayer, overrides := {}) -> void:
	tuning = DEFAULTS.duplicate()
	tuning.merge(overrides,true)
	music = music_player
	base_db = music.volume_db if is_instance_valid(music) else 0.0
	var root := Control.new()
	root.name = "StageFlow"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.theme()
	ui_layer.add_child(root)
	# Beneath the owner's HUD and menus, so pause and game over stay readable mid-fade.
	ui_layer.move_child(root,0)
	banner_panel = Control.new()
	banner_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_panel.offset_top = 196
	banner_panel.offset_bottom = 306
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.hide()
	root.add_child(banner_panel)
	var strip := ColorRect.new()
	strip.color = Color(.02,.035,.06,.8)
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.add_child(strip)
	for edge in [Control.PRESET_TOP_WIDE,Control.PRESET_BOTTOM_WIDE]:
		var line := ColorRect.new()
		line.color = Style.MINT
		line.set_anchors_and_offsets_preset(edge)
		if edge==Control.PRESET_TOP_WIDE: line.offset_bottom = 3
		else: line.offset_top = -3
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner_panel.add_child(line)
	banner_text = Control.new()
	banner_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.add_child(banner_text)
	banner_title = _banner_label(38,Color("ffe6a6"),12,60)
	banner_subtitle = _banner_label(18,Style.CREAM,66,94)
	veil = ColorRect.new()
	veil.color = Color(0,0,0,0)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.hide()
	root.add_child(veil)

func _banner_label(font_size: int, color: Color, top: float, bottom: float) -> Label:
	var label := Style.label("",font_size,color)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.offset_bottom = bottom
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	banner_text.add_child(label)
	return label

## exit_run → fade_out → on_black() → fade_in. on_black runs once, under a fully black veil
## with the music at its floor; calling play_enter() from it runs enter_run after the fade.
func play_exit(on_black: Callable) -> void:
	_serial += 1
	_on_black = on_black
	_enter_queued = false
	_exit_runner = 0
	exit_x = INF
	_stop_swap()
	_go("exit_run")

## enter_run with the title banner; emits phase "" when Hoppy reaches enter_to_x. Queued behind
## the fade when called during play_exit, otherwise starts now.
func play_enter(title: String, story: String) -> void:
	_enter_title = title
	_enter_story = story
	_enter_runner = 0
	_stop_swap()
	if phase in EXITING: _enter_queued = true
	else:
		_fade_db = 0
		_set_veil(0)
		_go("enter_run")
	_apply_music()

## Non-blocking: slides in, holds, fades out over `seconds`, replacing any current banner.
func banner(title: String, subtitle: String, seconds: float) -> void:
	banner_title.text = title
	banner_subtitle.text = subtitle
	banner_clock = 0
	banner_length = maxf(seconds,0)
	banner_panel.visible = banner_length > 0
	_tick_banner(0)

## Dips the music to its floor, swaps in `stream` at the bottom and brings it back up over
## `seconds` in total. A stage change (play_exit / play_enter) drops a swap still in progress.
func swap_music(stream: AudioStream, seconds: float) -> void:
	_swap_stream = stream
	_swap_length = maxf(seconds,0)
	_swap_clock = 0
	_swapped = false
	_tick_swap(0)
	_apply_music()

## Abandons a running sequence without calling its on_black or emitting phase "": the owner is
## cutting straight to play. Banners and music swaps carry on.
func cancel() -> void:
	_serial += 1
	_on_black = Callable()
	_enter_queued = false
	_fade_db = 0
	_set_veil(0)
	phase = ""
	clock = 0
	_apply_music()

func active() -> bool:
	return phase != ""

## Moves the scripted player during *_run phases; `player` is the owner's current one.
func tick(dt: float, player: Node2D) -> void:
	_tick_banner(dt)
	_tick_swap(dt)
	if phase != "":
		clock += dt
		_tick_phase(dt,player if is_instance_valid(player) else null)
	_apply_music()

func _tick_phase(dt: float, player: Node2D) -> void:
	var floor_db := float(tuning.music_floor_db)
	match phase:
		"exit_run", "fade_out":
			if player:
				if player.get_instance_id() != _exit_runner:
					_exit_runner = player.get_instance_id()
					_settle(player)
					exit_x = _screen_right(player)+float(tuning.exit_margin)
				_run(player,dt)
			if phase=="exit_run":
				var out: bool = player != null and player.global_position.x >= exit_x
				if (out and clock >= float(tuning.exit_min)) or clock >= float(tuning.exit_max): _go("fade_out")
				return
			var t := _progress(tuning.fade_out)
			_set_veil(t)
			_fade_db = lerpf(0,floor_db,t)
			if t >= 1: _black()
		"fade_in":
			if player: _place_entrant(player)
			var t := _progress(tuning.fade_in)
			_set_veil(1-t)
			_fade_db = lerpf(floor_db,0,t)
			if t >= 1:
				if _enter_queued: _go("enter_run")
				else: _finish()
		"enter_run":
			var target := float(tuning.enter_to_x)
			if player:
				_place_entrant(player)
				_run(player,dt)
			var arrived: bool = player != null and player.position.x >= target
			if arrived or clock >= float(tuning.enter_max):
				if player: player.position.x = target
				_finish()

func _black() -> void:
	_set_veil(1)
	_fade_db = float(tuning.music_floor_db)
	_apply_music()
	_clear_banner()
	var serial := _serial
	var callback := _on_black
	_on_black = Callable()
	if callback.is_valid(): callback.call()
	if serial==_serial: _go("fade_in")

func _go(next: String) -> void:
	phase = next
	clock = 0
	if next=="enter_run":
		_enter_queued = false
		banner(_enter_title,_enter_story,float(tuning.stage_banner))
	_apply_music()
	phase_changed.emit(next)

func _finish() -> void:
	_enter_queued = false
	_fade_db = 0
	_set_veil(0)
	phase = ""
	clock = 0
	_apply_music()
	phase_changed.emit("")

func _progress(seconds) -> float:
	return 1.0 if float(seconds) <= 0 else clampf(clock/float(seconds),0,1)

## The new stage's Hoppy starts off-screen left, settled, the first time the director sees him.
func _place_entrant(player: Node2D) -> void:
	if player.get_instance_id()==_enter_runner: return
	_enter_runner = player.get_instance_id()
	_settle(player)
	player.position.x = float(tuning.enter_from_x)
	player.reset_physics_interpolation()

func _run(player: Node2D, dt: float) -> void:
	player.position.x += float(tuning.run_speed)*dt
	player.set("facing",1.0)
	if player.has_method("show_pose"): player.show_pose("run",true)

## Lands a mid-air or mid-swing Hoppy before scripting him. Unknown properties are ignored.
func _settle(player: Node2D) -> void:
	for key in ["height","rise","swing_left"]: player.set(key,0.0)
	player.set("queued",false)
	player.set("knock",Vector2.ZERO)
	player.set("velocity",Vector2.ZERO)
	var body = player.get("body")
	if body is Node2D:
		body.position = Vector2.ZERO
		body.modulate = Color.WHITE

## The visible right edge in world x. Read from the camera itself: with physics interpolation
## the canvas transform lags a frame behind a camera the owner just placed.
func _screen_right(node: Node2D) -> float:
	var view := node.get_viewport()
	var width := view.get_visible_rect().size.x
	var camera := view.get_camera_2d()
	if camera == null: return (view.get_canvas_transform().affine_inverse()*Vector2(width,0)).x
	var span := width/camera.zoom.x
	var left := camera.global_position.x-(0.0 if camera.anchor_mode==Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT else span*.5)
	return left+span

func _set_veil(alpha: float) -> void:
	veil.color.a = alpha
	veil.visible = alpha > 0

func _tick_banner(dt: float) -> void:
	if banner_length <= 0: return
	banner_clock += dt
	if banner_clock >= banner_length:
		_clear_banner()
		return
	var slide := clampf(banner_clock/maxf(float(tuning.banner_slide),.001),0,1)
	var fade := clampf((banner_length-banner_clock)/maxf(float(tuning.banner_fade),.001),0,1)
	banner_panel.modulate.a = minf(slide,fade)
	banner_text.position.x = -140.0*pow(1.0-slide,3)

func _clear_banner() -> void:
	banner_length = 0
	banner_clock = 0
	banner_panel.hide()

func _tick_swap(dt: float) -> void:
	if _swap_stream == null: return
	_swap_clock += dt
	var floor_db := float(tuning.music_floor_db)
	var half := _swap_length*.5
	if not _swapped:
		_swap_db = lerpf(0,floor_db,clampf(_swap_clock/half,0,1)) if half > 0 else floor_db
		if _swap_clock >= half:
			_swapped = true
			if is_instance_valid(music):
				music.stream = _swap_stream
				music.play()
	if _swapped:
		_swap_db = lerpf(floor_db,0,clampf((_swap_clock-half)/half,0,1)) if half > 0 else 0.0
		if _swap_clock >= _swap_length: _stop_swap()

func _stop_swap() -> void:
	_swap_stream = null
	_swap_db = 0
	_swapped = false

func _apply_music() -> void:
	music_db = minf(_fade_db,_swap_db)
	if is_instance_valid(music): music.volume_db = base_db+music_db
