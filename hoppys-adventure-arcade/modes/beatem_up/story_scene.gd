extends Control
## Cinematic story scene shared by both beat'em up openings. A full-bleed illustration pans and
## zooms slowly (Ken Burns) under letterbox bars. A kicker titles the scene in the top bar, and the
## caption types out letter by letter in the bottom bar, which also holds the drain bar, the skip
## hint and any host actions. Each scene dips in from black and back out to black at its end.
##
## Clock-driven, no Tweens: the host calls advance(seconds, hold) from its _physics_process with
## the scene's own clock, so a paused tree freezes the scene and headless tests can step it. Every
## frame is a function of (scene, seconds, hold, visible rect); _process only redoes the layout at
## the current clock when the window or the parent transform changes.
##
## It fills the visible viewport wherever it is parented, so it stays full-bleed at any aspect
## under stretch/aspect=expand, including inside HvV's centred 1280x720 card host.
##
## Data comes from a catalog script: STORY[i] = {image, fallback, kicker, caption, from, to}, plus
## STORY_ACCENT and STORY_SERIES. The final-boss epilogue uses the same page shape under ENDING. image is the painted scene (T8); while it is not imported, the
## stage art in fallback stands in, so dropping the paintings in needs no code change. from/to
## frame the move as Vector3(focus x, focus y, zoom). The focus is in 0..1 image space and is held
## at the middle of the picture between the bars where the image allows. Zoom is over a cover fit
## of the viewport and stays within 1..1.25, which the paintings are composed for: 1.0 shows the
## whole frame, 1.25 shows 1600x900 art at 1:1 on a 1280x720 view.

const Style = preload("res://scenes/main_menu/menu_style.gd")
const TOP_BAR := 72.0
const BOTTOM_BAR := 136.0
## The bars slide in over this at the first scene; later scenes open with them in place.
const BAR_SLIDE := .45
## Dip in from black over the first DIP seconds and out to black over the last DIP seconds.
const DIP := .3
## The caption starts once the dip-in is done and types TYPE_RATE letters a second. A long
## caption types faster so it is complete by TYPE_SHARE of the hold.
const TYPE_DELAY := .35
const TYPE_RATE := 40.0
const TYPE_SHARE := .55
## Text column: inset from the view edges, centred and capped on wide windows.
const MARGIN := 64.0
const COLUMN := 1152.0
const BAR_COLOR := Color(.012,.012,.02,1)
const TRACK_COLOR := Color("142735")

## A presentation .tscn names its scene here: catalog.<pages>[story_index] (the HvV opening and
## ending cards).
@export var catalog: Script
@export var story_index := 0
@export var pages := "STORY"
var scene: Dictionary = {}
var index := 0
var seconds := 0.0
var hold := 4.5
var picture: TextureRect
var dip: ColorRect
var top_bar: ColorRect
var bottom_bar: ColorRect
var kicker: Label
var series: Label
var caption: Label
var drain: ProgressBar
var hint: Label
var actions: HBoxContainer
var _driven := false
var _laid_out := Transform2D()
var _laid_view := Vector2.ZERO

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(picture)
	dip = _rect(Color.BLACK)
	top_bar = _rect(BAR_COLOR)
	bottom_bar = _rect(BAR_COLOR)
	kicker = _label(26)
	series = _label(13,Color(Style.CREAM,.6))
	series.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption = _label(22)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_constant_override("line_spacing",6)
	hint = _label(13,Color(Style.CREAM,.72))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drain = ProgressBar.new()
	drain.show_percentage = false
	drain.max_value = 1.0
	drain.step = 0.0
	drain.value = 1.0
	drain.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(drain)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation",12)
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(actions)
	_paint_drain(Style.MINT)

func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect

func _label(font_size: int, color := Style.CREAM) -> Label:
	var label := Style.label("",font_size,color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _paint_drain(fill: Color) -> void:
	for part in ["background","fill"]:
		var box := StyleBoxFlat.new()
		box.bg_color = TRACK_COLOR if part=="background" else fill
		drain.add_theme_stylebox_override(part,box)

func _ready() -> void:
	# A presentation scene shows its own catalog entry. Until a host drives it (an asset preview,
	# say), it rests on its poster frame: bars in, caption complete, no dip.
	if scene.is_empty() and catalog != null: show_scene(catalog,story_index,pages)
	if not _driven:
		seconds = type_end()+.2
		_render()

## Shows scene `at` of the `list` pages of `source` (a catalog script with STORY or ENDING,
## STORY_ACCENT and STORY_SERIES), clamped to the scenes it has. The clock is left alone: the
## host's next advance() places the scene in time.
func show_scene(source: Variant, at: int, list := "STORY") -> void:
	var entries := page_list(source,list)
	if entries.is_empty(): return
	index = clampi(at,0,entries.size()-1)
	scene = entries[index]
	picture.texture = texture_for(scene)
	kicker.text = scene.kicker
	kicker.add_theme_color_override("font_color",source.STORY_ACCENT)
	caption.text = scene.caption
	series.text = source.STORY_SERIES
	_paint_drain(source.STORY_ACCENT)
	_render()

## The `list` pages of a catalog script (STORY, ENDING), or none when it has no such constant.
static func page_list(source: Variant, list := "STORY") -> Array:
	var constants: Dictionary = source.get_script_constant_map() if source is Script else {}
	return constants.get(list,[])

## The painted scene once it is imported, otherwise the stage art standing in for it (also when
## the painting is listed but fails to load, e.g. a stale import cache).
static func texture_for(entry: Dictionary) -> Texture2D:
	for key in ["image","fallback"]:
		var path: String = entry.get(key,"")
		if path=="" or not ResourceLoader.exists(path): continue
		var texture := load(path) as Texture2D
		if texture!=null: return texture
	return null

## Places the scene `at` seconds into a hold of `hold_seconds`. The host's clock is the only clock.
func advance(at: float, hold_seconds: float) -> void:
	_driven = true
	seconds = at
	hold = maxf(hold_seconds,.001)
	_render()

## Seconds into the scene at which the caption is fully typed.
func type_end() -> float:
	return TYPE_DELAY+minf(caption.text.length()/TYPE_RATE,hold*TYPE_SHARE)

## Share of the caption typed so far, in whole letters: 0 before typing starts, 1 once complete.
func typed_ratio() -> float:
	var total := caption.text.length()
	if total==0: return 1.0
	var span := type_end()-TYPE_DELAY
	var t := clampf((seconds-TYPE_DELAY)/span,0,1) if span>0 else 1.0
	return floorf(t*total)/total

## How far the letterbox bars have slid in, 0..1, eased out.
func bars_shown() -> float:
	if index>0: return 1.0
	var t := clampf(seconds/BAR_SLIDE,0,1)
	return 1.0-(1.0-t)*(1.0-t)

## Opacity of the black dip over the picture and text.
func dip_alpha() -> float:
	var fade_in := 1.0-clampf(seconds/DIP,0,1)
	var fade_out := clampf((seconds-(hold-DIP))/DIP,0,1)
	return maxf(fade_in,fade_out)

## The Ken Burns framing now: from → to over the whole hold, eased in and out.
func framing() -> Vector3:
	var from: Vector3 = scene.get("from",Vector3(.5,.5,1.0))
	var to: Vector3 = scene.get("to",from)
	var t := clampf(seconds/hold,0,1)
	return from.lerp(to,.5-.5*cos(PI*t))

## The visible viewport in this Control's own coordinates.
func view_rect() -> Rect2:
	if not is_inside_tree(): return Rect2(Vector2.ZERO,Vector2(1280,720))
	return get_global_transform_with_canvas().affine_inverse()*Rect2(Vector2.ZERO,get_viewport_rect().size)

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	if get_global_transform_with_canvas()!=_laid_out or get_viewport_rect().size!=_laid_view: _render()

func _render() -> void:
	if is_inside_tree():
		_laid_out = get_global_transform_with_canvas()
		_laid_view = get_viewport_rect().size
	var view := view_rect()
	var shown := bars_shown()
	var top := TOP_BAR*shown
	var bottom := BOTTOM_BAR*shown
	_frame_picture(view)
	dip.position = view.position
	dip.size = view.size
	dip.color.a = dip_alpha()
	top_bar.position = view.position
	top_bar.size = Vector2(view.size.x,top)
	bottom_bar.position = Vector2(view.position.x,view.end.y-bottom)
	bottom_bar.size = Vector2(view.size.x,bottom)
	var width := minf(view.size.x-MARGIN*2,COLUMN)
	var left := view.position.x+(view.size.x-width)*.5
	# Text rides on the bars: it slides in with them and sits at the same place once they are in.
	var top_edge := view.position.y+top-TOP_BAR
	kicker.position = Vector2(left,top_edge+18)
	kicker.size = Vector2(width,36)
	series.position = Vector2(left,top_edge+28)
	series.size = Vector2(width,20)
	var bottom_edge := view.end.y-bottom
	drain.position = Vector2(left,bottom_edge+12)
	drain.size = Vector2(width,4)
	caption.position = Vector2(left,bottom_edge+24)
	caption.size = Vector2(width,62)
	hint.position = Vector2(left,bottom_edge+BOTTOM_BAR-42)
	hint.size = Vector2(width*.5,32)
	actions.position = Vector2(left,bottom_edge+BOTTOM_BAR-42)
	actions.size = Vector2(width,32)
	# Picture and words dip together; the bars, hint, timer and actions stay put.
	var text_alpha := 1.0-dip_alpha()
	kicker.modulate.a = text_alpha
	series.modulate.a = text_alpha
	caption.modulate.a = text_alpha
	var typed := typed_ratio()
	caption.visible_characters = -1 if typed>=1.0 else roundi(typed*caption.text.length())
	drain.value = clampf(1.0-seconds/hold,0,1)

## Cover-fits the picture to the view at the current zoom, with the focus centred between the
## final bars as far as the picture's edges allow. Whole pixels, so nearest sampling stays crisp.
func _frame_picture(view: Rect2) -> void:
	var texture := picture.texture
	if texture==null: return
	var source := texture.get_size()
	var frame := framing()
	var drawn := source*maxf(view.size.x/source.x,view.size.y/source.y)*maxf(1.0,frame.z)
	var middle := Vector2(view.position.x+view.size.x*.5,view.position.y+TOP_BAR+(view.size.y-TOP_BAR-BOTTOM_BAR)*.5)
	var at := middle-Vector2(frame.x,frame.y)*drawn
	at.x = clampf(at.x,view.end.x-drawn.x,view.position.x)
	at.y = clampf(at.y,view.end.y-drawn.y,view.position.y)
	picture.position = at.floor()
	picture.size = (drawn+Vector2.ONE).ceil()
