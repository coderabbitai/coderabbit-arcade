extends Control
## The little looping scenes on how-to-play pages (app/how_to_play.gd), acted out with each game's
## own sprite sheets: Hoppy beating the boss and pressing MERGE, swiping a bug, floating in zero-G.
## Each scene is one looping Tween bound to this node, so it runs while the game under the card is
## paused and stops when the page is freed.
##
## A scene is a scaled-down window onto the game's own screen, so it reads like the game: `world`
## takes game coordinates (the floor at y = FLOOR_Y, as in every level and arena), each actor keeps
## its game scale and its sheet's foot pivot, and the backdrop sits where the game draws it. The
## platformers get their sky, mid layer and ground tiles; the beat 'em ups get their room panorama,
## whose painted floor is where the actors walk. WORLDS holds each game's layers and how far the
## window zooms out (`zoom`).
##
## A page's `scene` dictionary picks the scene by `id` and the game by `world`:
## - platformer_goal: world (bay, orbital, forest), boss (SpriteFrames with idle and defeat clips)
##   and boss_scale (its in-game scale)
## - blitz_tips (bay), zero_g and orbital_tips (orbital), enchanted_tips (forest), brawl_goal and
##   brawl_tips (city), heroes_goal and heroes_review (heroes)
## - slideshow: images (screenshots, panned and cross-faded; the runner is 3D, so it has no sheets)
##
## `icon()` makes the small animated Hoppy beside a control row from a game's `poses` entry.

const Data := preload("res://app/how_to_play_data.gd")
const OrbitalArt := preload("res://modes/platformer/orbital_art.gd")
const ForestArt := preload("res://modes/platformer/enchanted_art.gd")

const SIZE := Vector2(820, 260)
## Where the game's floor line lands on the stage.
const GROUND := 236.0
## The floor line in game coordinates: platformer ground tops and the beat 'em ups' front lane.
const FLOOR_Y := 600.0
const SCENES := ["platformer_goal", "blitz_tips", "zero_g", "orbital_tips", "enchanted_tips",
	"slideshow", "brawl_goal", "brawl_tips", "heroes_goal", "heroes_review"]
const ICON_SIZE := Vector2(52, 40)
const CAPTION := Color("fff4d6")
const REVIEW_TINT := preload("res://modes/beatem_up/reinvent/player.gd").REVIEW_TINT
const STUNNED := preload("res://modes/beatem_up/reinvent/enemy.gd").STUNNED_TINT
const HOPPY_GLOW := preload("res://modes/beatem_up/reinvent/player.gd").REVIEW_GLOW
## Each game's backdrop, as its level script draws it (scenes/platformer/*.gd, the beat 'em ups'
## room setup). `zoom` is stage pixels per game pixel.
const WORLDS := {
	"bay": {"zoom": 0.8, "sky": Data.BAY + "backdrop.png", "shade": Color(0.03, 0.09, 0.15, 0.24),
		"fill": Color("223c48"), "slab": "sidewalk"},
	"orbital": {"zoom": 0.8, "sky": Data.ORBIT + "starfield.png", "shade": Color(0.02, 0.035, 0.09, 0.3),
		"fill": Color("101d35"), "slab": "floor_slab"},
	"forest": {"zoom": 0.8, "sky": Data.FOREST + "sky.png", "shade": Color(0.025, 0.05, 0.06, 0.35),
		"fill": Color("252f35"), "slab": "ground_slab"},
	"city": {"zoom": 0.45, "room": Data.CITY + "district_background.png"},
	"heroes": {"zoom": 0.55, "room": Data.HEROES + "generation_floor.png"},
}
## Foot offsets the games set by hand rather than from a sheet manifest.
const FOOT := {
	"platformer.tres": -40.0, "combat.tres": -38.0, "hazards.tres:orbital": -54.0, "interactives.tres": -51.0,
}

var spec: Dictionary
var world: Node2D
var caption: Label
var loop: Tween
var zoom := 1.0
static var manifests := {}


## A scene for a page's `scene` entry.
static func build(scene: Dictionary) -> Control:
	var demo: Control = load("res://app/how_to_play_demo.gd").new()
	demo.spec = scene
	return demo


## A row's little animated Hoppy for a `poses` entry: [sheet, clip, motion?].
static func icon(entry: Array) -> Control:
	var box := Control.new()
	box.custom_minimum_size = ICON_SIZE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frames: SpriteFrames = load(str(entry[0]))
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var clip := StringName(entry[1])
	var height := frames.get_frame_texture(clip, 0).get_size().y
	# Sheet frames carry padding around the figure, so fill a bit past the box.
	var zoom := ICON_SIZE.y * 1.35 / height
	if entry[0].ends_with("capabilities_fx.tres"):
		zoom = ICON_SIZE.y * 1.1 / height
	sprite.scale = Vector2.ONE * zoom
	sprite.position = ICON_SIZE / 2.0
	box.add_child(sprite)
	_replay(sprite, clip)
	var motion := str(entry[2]) if entry.size() > 2 else ""
	if not motion.is_empty():
		# Tweens need the tree; the row isn't in it yet.
		sprite.tree_entered.connect(_move.bind(sprite, motion, zoom), CONNECT_ONE_SHOT)
	return box


static func _move(sprite: AnimatedSprite2D, motion: String, zoom: float) -> void:
	var tween := sprite.create_tween().set_loops()
	var home := sprite.position
	match motion:
		"slide":
			tween.tween_property(sprite, "position:x", home.x - 10.0, 0.35).set_trans(Tween.TRANS_SINE)
			tween.tween_property(sprite, "position:x", home.x + 10.0, 0.7).set_trans(Tween.TRANS_SINE)
			tween.tween_property(sprite, "position:x", home.x, 0.35).set_trans(Tween.TRANS_SINE)
		"rise", "sink":
			var step := -7.0 if motion == "rise" else 7.0
			sprite.position.y = home.y - step
			tween.tween_property(sprite, "position:y", home.y + step, 0.9).set_trans(Tween.TRANS_SINE)
			tween.tween_property(sprite, "modulate:a", 0.0, 0.15)
			tween.tween_callback(func() -> void: sprite.position.y = home.y - step)
			tween.tween_property(sprite, "modulate:a", 1.0, 0.15)
		"spin":
			tween.tween_property(sprite, "rotation", TAU, 0.6).from(0.0)
			tween.tween_interval(0.5)
		"pulse":
			tween.tween_property(sprite, "scale", Vector2.ONE * zoom * 0.7, 0.45).set_trans(Tween.TRANS_SINE)
			tween.tween_property(sprite, "scale", Vector2.ONE * zoom, 0.45).set_trans(Tween.TRANS_SINE)


## Plays `clip`, and plays it again after a beat when the sheet doesn't loop it.
static func _replay(sprite: AnimatedSprite2D, clip: StringName) -> void:
	sprite.play(clip)
	if sprite.sprite_frames.get_animation_loop(clip):
		return
	sprite.animation_finished.connect(func() -> void:
		var tween := sprite.create_tween()
		tween.tween_interval(0.35)
		tween.tween_callback(func() -> void: sprite.play(clip)))


func _ready() -> void:
	custom_minimum_size = SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var images: Array = spec.get("images", [])
	if not images.is_empty():
		world = Node2D.new()
		add_child(world)
		_slideshow(images)
		return
	var setting: Dictionary = WORLDS[str(spec.world)]
	zoom = setting.zoom
	# Centre the game's 1280-wide screen on the stage, floor line on GROUND.
	var origin := Vector2((SIZE.x - 1280.0 * zoom) / 2.0, GROUND - FLOOR_Y * zoom)
	if setting.has("room"):
		_room(str(setting.room), origin)
	else:
		_sky(setting, origin)
	world = Node2D.new()
	world.position = origin
	world.scale = Vector2.ONE * zoom
	add_child(world)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_color", CAPTION)
	caption.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07))
	caption.add_theme_constant_override("outline_size", 6)
	caption.position = Vector2(16, 10)
	add_child(caption)
	loop = create_tween().set_loops()
	call(StringName("_" + str(spec.id)))


## A platformer's screen-fixed backdrop: the sky plate covering the 1280x720 screen and its shade.
func _sky(setting: Dictionary, origin: Vector2) -> void:
	var plate := TextureRect.new()
	plate.texture = load(str(setting.sky))
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plate.position = origin
	plate.size = Vector2(1280, 720) * zoom
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var shade := ColorRect.new()
	shade.color = setting.shade
	shade.size = SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


## A beat 'em up room: its panorama at 1:1 game scale, repeated the way the arena lays rooms side
## by side. Its painted floor band (y 455-650) is where the actors walk.
func _room(path: String, origin: Vector2) -> void:
	var texture: Texture2D = load(path)
	for index in range(-1, 2):
		var room := Sprite2D.new()
		room.texture = texture
		room.centered = false
		room.position = origin + Vector2(index * 1280.0 * zoom, 0)
		room.scale = Vector2.ONE * zoom
		add_child(room)


## A stretch of the level's ground from `from_x` to `to_x`: the dark fill plus the top tiles, the
## way each platformer's platform() draws it.
func ground(from_x: float, to_x: float) -> void:
	var setting: Dictionary = WORLDS[str(spec.world)]
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2(from_x, FLOOR_Y), Vector2(to_x, FLOOR_Y), Vector2(to_x, FLOOR_Y + 160), Vector2(from_x, FLOOR_Y + 160)])
	fill.color = setting.fill
	world.add_child(fill)
	var slab := str(setting.slab)
	var tile: Texture2D
	var tile_size: Vector2
	match str(spec.world):
		"bay":
			var whole := load("res://Assets/bay-area-blitz-assets-only/individual/street_kit/" + slab + ".png") as Texture2D
			var crop := AtlasTexture.new()
			crop.atlas = whole
			crop.region = whole.get_image().get_used_rect()
			tile = crop
			tile_size = Vector2(96, 32)
		"orbital":
			tile = OrbitalArt.crop("station_kit", slab)
			tile_size = Vector2(128, 40)
		_:
			tile = ForestArt.crop("forest_kit", slab)
			tile_size = Vector2(128, 68)
	var x := from_x
	while x < to_x:
		var piece := Sprite2D.new()
		piece.texture = tile
		piece.centered = false
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.position = Vector2(x, FLOOR_Y)
		var width := minf(tile_size.x, to_x - x)
		piece.scale = Vector2(width, tile_size.y) / tile.get_size()
		world.add_child(piece)
		x += tile_size.x


## A sprite at game position `at` and game scale `size`, anchored at its feet the way the game
## anchors it (FOOT, else the sheet manifest's pivot, else 40% of the frame above centre). Sheets
## face the way they're drawn: Hoppy right, every enemy and boss left (the games flip an enemy only
## to face right); `mirror` flips it.
func actor(sheet: String, clip: String, at: Vector2, size := 1.0, mirror := false) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * size
	sprite.flip_h = mirror
	sprite.position = at
	world.add_child(sprite)
	_wear(sprite, sheet, clip)
	return sprite


func _wear(sprite: AnimatedSprite2D, sheet: String, clip: String) -> void:
	sprite.sprite_frames = load(sheet)
	sprite.offset = foot(sheet, sprite.sprite_frames.get_frame_texture(clip, 0).get_size())
	sprite.play(clip)


## The offset that puts a frame's feet on the sprite's position.
static func foot(sheet: String, frame: Vector2) -> Vector2:
	var file := sheet.get_file()
	var key := file + (":orbital" if sheet.contains("orbital") else "")
	if FOOT.has(key):
		return Vector2(0, FOOT[key])
	var folder := sheet.get_base_dir() + "/manifest.json"
	if not manifests.has(folder):
		manifests[folder] = JSON.parse_string(FileAccess.get_file_as_string(folder)) if FileAccess.file_exists(folder) else {}
	var atlases: Dictionary = manifests[folder].get("atlases", {}) if manifests[folder] is Dictionary else {}
	var entry: Dictionary = atlases.get(file.get_basename(), {})
	if entry.has("pivot"):
		var cell: Array = entry.get("cell", [frame.x, frame.y])
		return Vector2(float(cell[0]) / 2.0 - float(entry.pivot[0]), float(cell[1]) / 2.0 - float(entry.pivot[1]))
	return Vector2(0, -frame.y * 0.4)


# -- Steps on the scene's loop ---------------------------------------------------------------------

func play(sprite: AnimatedSprite2D, clip: String) -> void:
	loop.tween_callback(func() -> void: sprite.play(clip))


func pose(sprite: AnimatedSprite2D, sheet: String, clip: String) -> void:
	loop.tween_callback(_wear.bind(sprite, sheet, clip))


func move(sprite: Node2D, to: Vector2, seconds: float) -> PropertyTweener:
	return loop.tween_property(sprite, "position", to, seconds)


func with(sprite: Node2D, to: Vector2, seconds: float) -> void:
	loop.parallel().tween_property(sprite, "position", to, seconds)


func hop(sprite: Node2D, from: Vector2, to: Vector2, seconds: float, height: float) -> void:
	loop.tween_method(func(t: float) -> void:
		sprite.position = from.lerp(to, t) + Vector2(0, -height * 4.0 * t * (1.0 - t)), 0.0, 1.0, seconds)


func pause_for(seconds: float) -> void:
	loop.tween_interval(seconds)


func fade(sprite: CanvasItem, to: float, seconds: float) -> void:
	loop.tween_property(sprite, "modulate:a", to, seconds)


func fade_with(sprite: CanvasItem, to: float, seconds: float) -> void:
	loop.parallel().tween_property(sprite, "modulate:a", to, seconds)


## A white flash on a hit.
func flash(sprite: CanvasItem) -> void:
	loop.tween_callback(func() -> void:
		sprite.modulate = Color(2.4, 2.4, 2.4, sprite.modulate.a)
		sprite.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, sprite.modulate.a), 0.22))


## A pickup popping: it swells and fades.
func pop(sprite: Node2D) -> void:
	loop.tween_callback(func() -> void:
		var base := sprite.scale
		var tween := sprite.create_tween()
		tween.tween_property(sprite, "scale", base * 1.6, 0.2)
		tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func() -> void: sprite.scale = base))


func say(text: String) -> void:
	loop.tween_callback(func() -> void: caption.text = text)


func reset(each: Callable) -> void:
	loop.tween_callback(each)


## A bob that runs on its own, for pickups hanging in the air.
func bob(sprite: Node2D) -> void:
	var tween := sprite.create_tween().set_loops()
	var y := sprite.position.y
	tween.tween_property(sprite, "position:y", y - 6.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, "position:y", y, 0.5).set_trans(Tween.TRANS_SINE)


# -- Scenes (game coordinates; the floor is FLOOR_Y) ------------------------------------------------

## Hoppy runs in and swipes the boss down; the dim MERGE button lights up and he lands on it.
func _platformer_goal() -> void:
	ground(-200, 1500)
	var start := Vector2(220, FLOOR_Y)
	var hoppy := actor(Data.PLATFORMER_HOPPY, "run", start)
	var boss := actor(str(spec.boss), "idle", Vector2(830, FLOOR_Y), float(spec.get("boss_scale", 1.0)))
	var merge := actor(Data.BAY + "interactives.tres", "exit_ready", Vector2(1070, FLOOR_Y))
	var swipe_at := Vector2(700, FLOOR_Y)
	var button_top := Vector2(1070, 540.0)  # level.gd EXIT_TOP
	var locked := Color(0.45, 0.45, 0.45)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		hoppy.play("run")
		boss.modulate = Color.WHITE
		boss.play("idle")
		merge.modulate = locked
		merge.play("exit_ready"))
	say("Reach the boss")
	move(hoppy, swipe_at, 1.4)
	say("Swipe it down")
	for hit in 3:
		play(hoppy, "attack")
		flash(boss)
		pause_for(0.45)
	play(boss, "defeat")
	play(hoppy, "idle")
	pause_for(0.5)
	fade(boss, 0.0, 0.5)
	say("Then land on MERGE")
	loop.tween_property(merge, "modulate", Color.WHITE, 0.3)
	play(hoppy, "run")
	move(hoppy, Vector2(930, FLOOR_Y), 0.5)
	play(hoppy, "jump")
	hop(hoppy, Vector2(930, FLOOR_Y), button_top, 0.55, 110.0)
	play(merge, "exit_pressed")
	play(hoppy, "idle")
	pause_for(0.35)
	play(merge, "exit_complete")
	say("Level complete!")
	pause_for(1.4)
	fade(hoppy, 0.0, 0.3)


## Hoppy grabs a token, swipes a glitch critter (Bay Area Blitz has no stomping), grabs another.
func _blitz_tips() -> void:
	ground(-200, 1500)
	var hearts := Node2D.new()
	hearts.position = Vector2(SIZE.x - 120, 26)
	add_child(hearts)
	for index in 3:
		var heart := Sprite2D.new()
		heart.texture = load("res://Assets/bay-area-blitz-assets-only/individual/hud/heart_full.png")
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.position = Vector2(index * 36, 0)
		hearts.add_child(heart)
	var start := Vector2(220, FLOOR_Y)
	var hoppy := actor(Data.PLATFORMER_HOPPY, "run", start)
	var critter := actor(Data.BAY + "glitch_critter.tres", "scuttle", Vector2(1150, FLOOR_Y))
	var first := actor(Data.BAY + "pickups.tres", "commit_token", Vector2(440, 470))
	var second := actor(Data.BAY + "pickups.tres", "commit_token", Vector2(960, 530))
	bob(first)
	bob(second)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		hoppy.play("run")
		critter.position = Vector2(1150, FLOOR_Y)
		critter.modulate = Color.WHITE
		critter.play("scuttle")
		for token in [first, second]:
			token.modulate = Color.WHITE)
	say("Grab tokens")
	move(hoppy, Vector2(330, FLOOR_Y), 0.6)
	with(critter, Vector2(900, FLOOR_Y), 0.6)
	play(hoppy, "jump")
	hop(hoppy, Vector2(330, FLOOR_Y), Vector2(540, FLOOR_Y), 0.6, 150.0)
	with(critter, Vector2(700, FLOOR_Y), 0.6)
	pop(first)
	play(hoppy, "idle")
	say("Swipe bugs")
	move(critter, Vector2(620, FLOOR_Y), 0.4)
	play(critter, "idle")
	for hit in 2:
		play(hoppy, "attack")
		flash(critter)
		pause_for(0.4)
	play(critter, "defeat")
	fade(critter, 0.0, 0.5)
	play(hoppy, "run")
	move(hoppy, Vector2(960, FLOOR_Y), 0.8)
	pop(second)
	play(hoppy, "idle")
	pause_for(1.3)
	fade(hoppy, 0.0, 0.3)


## Hoppy floats in the zero-gravity bay: rise, let go to brake, sink.
func _zero_g() -> void:
	ground(-200, 1500)
	var bay := Bay.new()
	bay.area = Rect2(390, 140, 500, 460)
	world.add_child(bay)
	actor(Data.ORBIT + "hazards.tres", "zero_g_beacon", Vector2(400, FLOOR_Y))
	actor(Data.ORBIT + "hazards.tres", "zero_g_beacon", Vector2(880, FLOOR_Y))
	var low := Vector2(640, FLOOR_Y)
	var high := Vector2(640, 410)
	var hoppy := actor(Data.PLATFORMER_HOPPY, "jump_apex", low)
	reset(func() -> void:
		hoppy.position = low
		hoppy.play("jump_apex"))
	say("Hold Space / A to rise")
	play(hoppy, "jump_rise")
	move(hoppy, high, 1.3).set_trans(Tween.TRANS_SINE)
	say("Let go to brake")
	play(hoppy, "jump_apex")
	move(hoppy, high + Vector2(0, -10), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	say("Hold S / Stick ↓ to sink")
	play(hoppy, "jump_fall")
	move(hoppy, low, 1.3).set_trans(Tween.TRANS_SINE)
	say("Let go to brake")
	play(hoppy, "jump_apex")
	pause_for(0.9)


## A laser cycles; Hoppy waits for it to switch off, crosses, then hops a vent before it vents.
func _orbital_tips() -> void:
	ground(-200, 1500)
	# The game draws the beam itself (orbital_hazard.gd); the sheet only has the emitter.
	var beam := Beam.new()
	beam.position = Vector2(700, FLOOR_Y)
	world.add_child(beam)
	var laser := actor(Data.ORBIT + "hazards.tres", "laser_active", Vector2(700, FLOOR_Y))
	var vent := actor(Data.ORBIT + "hazards.tres", "vent_closed", Vector2(960, FLOOR_Y))
	var start := Vector2(250, FLOOR_Y)
	var hoppy := actor(Data.PLATFORMER_HOPPY, "idle", start)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		hoppy.play("idle")
		laser.play("laser_active")
		beam.show_state("active")
		vent.play("vent_closed"))
	say("Laser on: wait")
	pause_for(1.2)
	play(laser, "laser_cooldown")
	loop.tween_callback(beam.show_state.bind("cooldown"))
	pause_for(0.35)
	play(laser, "laser_off")
	loop.tween_callback(beam.show_state.bind("off"))
	say("Off: go!")
	play(hoppy, "run")
	move(hoppy, Vector2(830, FLOOR_Y), 0.9)
	play(laser, "laser_warning")
	loop.tween_callback(beam.show_state.bind("warning"))
	play(vent, "vent_warning")
	say("Amber = about to fire")
	play(hoppy, "jump")
	hop(hoppy, Vector2(830, FLOOR_Y), Vector2(1100, FLOOR_Y), 0.6, 140.0)
	play(vent, "vent_active")
	play(laser, "laser_active")
	loop.tween_callback(beam.show_state.bind("active"))
	play(hoppy, "idle")
	pause_for(1.2)
	fade(hoppy, 0.0, 0.3)


## Hoppy hops across branches over a gap; each cracks under him and falls once he leaves.
func _enchanted_tips() -> void:
	ground(-200, 400)
	ground(900, 1500)
	var spots := [Vector2(520, 520), Vector2(760, 460)]
	var branches: Array[Sprite2D] = []
	for spot: Vector2 in spots:
		var branch := Sprite2D.new()
		branch.centered = false
		branch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		world.add_child(branch)
		branches.append(branch)
	# crumbling_branch.gd: a 180x48 crop whose top edge is the surface Hoppy stands on.
	var show := func(branch: Sprite2D, spot: Vector2, clip: String) -> void:
		branch.texture = ForestArt.crop("hazards", clip)
		branch.position = spot - Vector2(90, 0)
		branch.scale = Vector2(180, 48) / branch.texture.get_size()
	var start := Vector2(200, FLOOR_Y)
	var hoppy := actor(Data.PLATFORMER_HOPPY, "run", start)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		hoppy.play("run")
		for index in branches.size():
			show.call(branches[index], spots[index], "branch_intact")
			branches[index].modulate = Color.WHITE)
	say("Branches crumble under you")
	move(hoppy, Vector2(340, FLOOR_Y), 0.4)
	var from := Vector2(340, FLOOR_Y)
	for index in branches.size():
		play(hoppy, "jump")
		hop(hoppy, from, spots[index], 0.5, 80.0)
		play(hoppy, "idle")
		loop.tween_callback(show.bind(branches[index], spots[index], "branch_warning"))
		if index > 0:
			loop.tween_callback(show.bind(branches[index - 1], spots[index - 1], "branch_fall"))
			loop.tween_property(branches[index - 1], "position:y", 900.0, 0.5).set_ease(Tween.EASE_IN)
		else:
			pause_for(0.35)
		from = spots[index]
	say("Keep moving!")
	play(hoppy, "jump")
	hop(hoppy, from, Vector2(1040, FLOOR_Y), 0.55, 70.0)
	loop.tween_callback(show.bind(branches[-1], spots[-1], "branch_fall"))
	loop.tween_property(branches[-1], "position:y", 900.0, 0.5).set_ease(Tween.EASE_IN)
	play(hoppy, "idle")
	pause_for(1.2)
	fade(hoppy, 0.0, 0.3)


## Hoppy walks in, combos a soldier down, and the Grand Merge Conflict looms at the room's end.
func _brawl_goal() -> void:
	var start := Vector2(160, FLOOR_Y)
	# Walking sideways, the game plays the base sheet's run (beatem_up/player.gd); walk_up and
	# walk_down are only for changing lanes.
	var hoppy := actor(Data.PLATFORMER_HOPPY, "run", start, 1.55)
	var soldier := actor(Data.CITY + "merge_conflict_soldier.tres", "walk", Vector2(1250, FLOOR_Y), 1.7)
	# beatem_up/game.gd: the boss stands at room x 965, y 565, at 2.6x.
	var boss := actor(Data.CITY + "conflict_spawner.tres", "idle", Vector2(1080, 565), 2.6)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		_wear(hoppy, Data.PLATFORMER_HOPPY, "run")
		soldier.position = Vector2(1250, FLOOR_Y)
		soldier.modulate = Color.WHITE
		soldier.play("walk")
		boss.modulate.a = 0.0)
	say("Beat every bug")
	move(hoppy, Vector2(470, FLOOR_Y), 1.2)
	with(soldier, Vector2(610, FLOOR_Y), 1.2)
	play(soldier, "idle")
	say("Jab, jab, kick!")
	for clip in ["jab", "jab", "kick"]:
		pose(hoppy, Data.BRAWL_HOPPY, clip)
		flash(soldier)
		pause_for(0.32)
	play(soldier, "defeat")
	loop.tween_property(soldier, "position:x", 760.0, 0.35)
	fade_with(soldier, 0.0, 0.5)
	pose(hoppy, Data.BRAWL_HOPPY, "idle")
	say("Then the Grand Merge Conflict")
	fade(boss, 1.0, 0.5)
	pause_for(1.6)
	fade(hoppy, 0.0, 0.3)
	fade_with(boss, 0.0, 0.3)


## Change lanes to dodge a sword, drink a coffee, pick up a weapon.
func _brawl_tips() -> void:
	var back := 520.0
	var start := Vector2(330, back)
	var soldier := actor(Data.CITY + "merge_conflict_soldier.tres", "idle", Vector2(780, back), 1.7)
	# beatem_up/game.gd draws pickups at 0.65x, centred on their spot.
	var coffee := actor(Data.CITY + "items_allies.tres", "coffee", Vector2(620, FLOOR_Y - 30), 0.65)
	var stick := actor(Data.CITY + "weapons.tres", "debug_stick", Vector2(980, FLOOR_Y - 30), 0.65)
	var hoppy := actor(Data.BRAWL_HOPPY, "idle", start, 1.55)
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		_wear(hoppy, Data.BRAWL_HOPPY, "idle")
		soldier.play("idle")
		for item in [coffee, stick]:
			item.modulate = Color.WHITE)
	say("Sword coming…")
	play(soldier, "sword_warning")
	pause_for(0.6)
	say("Change lanes to dodge")
	play(hoppy, "walk_down")
	move(hoppy, Vector2(330, FLOOR_Y), 0.35)
	play(soldier, "sword")
	pause_for(0.5)
	play(soldier, "idle")
	say("Coffee heals")
	pose(hoppy, Data.PLATFORMER_HOPPY, "run")
	move(hoppy, Vector2(620, FLOOR_Y), 0.6)
	pop(coffee)
	flash(hoppy)
	say("Pick up weapons")
	move(hoppy, Vector2(960, FLOOR_Y), 0.6)
	pose(hoppy, Data.BRAWL_HOPPY, "pickup")
	pop(stick)
	pause_for(1.3)
	fade(hoppy, 0.0, 0.3)


## Hoppy runs in and combos two AI Slop sprites while the boss watches.
func _heroes_goal() -> void:
	var start := Vector2(150, FLOOR_Y)
	var hoppy := actor(Data.HERO_MOTION, "run", start, 1.65)
	# reinvent/game.gd: AI Slop stands at room x 945, y 565, at 1.6x; its minions at 1.7x.
	var boss := actor(Data.HEROES + "ai_slop.tres", "idle", Vector2(1080, 565), 1.6)
	var slops: Array[AnimatedSprite2D] = [
		actor(Data.HEROES + "slop_sprite.tres", "idle", Vector2(640, FLOOR_Y), 1.7),
		actor(Data.HEROES + "slop_sprite.tres", "idle", Vector2(820, FLOOR_Y), 1.7)]
	reset(func() -> void:
		hoppy.position = start
		hoppy.modulate = Color.WHITE
		_wear(hoppy, Data.HERO_MOTION, "run")
		boss.play("idle")
		for slop in slops:
			slop.modulate = Color.WHITE
			slop.play("idle"))
	say("Fight through each room")
	var at := start
	for index in slops.size():
		var stop := slops[index].position - Vector2(130, 0)
		pose(hoppy, Data.HERO_MOTION, "run")
		move(hoppy, stop, 0.4 + (stop.x - at.x) / 1100.0)
		at = stop
		for clip in ["jab_action", "kick_action"]:
			pose(hoppy, Data.HERO, clip)
			flash(slops[index])
			pause_for(0.35)
		play(slops[index], "defeat")
		fade(slops[index], 0.0, 0.3)
	say("Then take on the villain")
	pose(hoppy, Data.HERO, "victory")
	play(boss, "hurt")
	flash(boss)
	pause_for(1.5)
	fade(hoppy, 0.0, 0.3)


## Bugs close in; Hoppy holds REVIEW and the burst stuns them all.
func _heroes_review() -> void:
	var center := Vector2(640, FLOOR_Y)
	var hoppy := actor(Data.HERO, "idle", center, 1.65)
	var outer := [140.0, 310.0, 970.0, 1140.0]
	var inner := [400.0, 480.0, 800.0, 880.0]
	var slops: Array[AnimatedSprite2D] = []
	for index in outer.size():
		slops.append(actor(Data.HEROES + "slop_sprite.tres", "idle", Vector2(outer[index], FLOOR_Y), 1.7, outer[index] < center.x))
	# reinvent/game.gd review_burst: the effect at 2x on Hoppy.
	var burst := actor(Data.HEROES + "capabilities_fx.tres", "review_burst", center + Vector2(0, -60), 0.4)
	# REVIEW's colour (reinvent/game.gd REVIEW_TINT): a mint burst behind everyone, so it reads as
	# Hoppy's power and not a hit on him.
	burst.self_modulate = REVIEW_TINT
	world.move_child(burst, 0)
	reset(func() -> void:
		hoppy.play("idle")
		hoppy.modulate = Color.WHITE
		burst.modulate.a = 0.0
		burst.scale = Vector2.ONE * 0.4
		for index in slops.size():
			slops[index].position.x = outer[index]
			slops[index].modulate = Color.WHITE
			slops[index].play("idle"))
	say("Bugs close in…")
	for index in slops.size():
		loop.parallel().tween_property(slops[index], "position:x", inner[index], 1.1)
	for slop in slops:
		play(slop, "attack_warning")
	say("Hold Q / LB: REVIEW")
	play(hoppy, "scanner")
	loop.tween_property(hoppy, "modulate", HOPPY_GLOW, 0.2)
	pause_for(0.3)
	loop.tween_property(burst, "modulate:a", 1.0, 0.1)
	loop.parallel().tween_property(burst, "scale", Vector2.ONE * 2.0, 0.5)
	for index in slops.size():
		var away := 90.0 if inner[index] > center.x else -90.0
		loop.parallel().tween_property(slops[index], "position:x", inner[index] + away, 0.4)
		loop.parallel().tween_property(slops[index], "modulate", STUNNED, 0.3)
	for slop in slops:
		play(slop, "idle")
	fade(burst, 0.0, 0.3)
	loop.parallel().tween_property(hoppy, "modulate", Color.WHITE, 0.3)
	say("Stunned!")
	play(hoppy, "victory")
	pause_for(1.4)


## Screenshots, each slowly zooming, cross-faded in turn.
func _slideshow(images: Array) -> void:
	var frames: Array[TextureRect] = []
	for path in images:
		var image := TextureRect.new()
		image.texture = load(str(path))
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.size = SIZE
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.modulate.a = 0.0
		add_child(image)
		image.pivot_offset = SIZE / 2.0
		frames.append(image)
	loop = create_tween().set_loops()
	for image in frames:
		loop.tween_callback(func() -> void: image.scale = Vector2.ONE)
		loop.tween_property(image, "modulate:a", 1.0, 0.4)
		loop.parallel().tween_property(image, "scale", Vector2.ONE * 1.08, 3.2)
		loop.tween_property(image, "modulate:a", 0.0, 0.4)


## A laser beam drawn the way orbital_hazard.gd draws it: solid red when on, an amber dashed line
## as the warning, nothing when off.
class Beam extends Node2D:
	var state := "active"

	func show_state(next: String) -> void:
		state = next
		queue_redraw()

	func _draw() -> void:
		if state == "active":
			draw_line(Vector2(0, -260), Vector2(0, -28), Color(1, .17, .3, .25), 28)
			draw_line(Vector2(0, -260), Vector2(0, -28), Color("ff5369"), 14)
			draw_line(Vector2(0, -260), Vector2(0, -28), Color("fff2cf"), 4)
		elif state == "warning":
			for y in range(-260, -28, 24):
				draw_line(Vector2(0, y), Vector2(0, y + 12), Color("ffc769"), 3)


## The zero-gravity bay as orbital_ops.gd draws it: a faint cyan fill with dashed edges.
class Bay extends Node2D:
	var area := Rect2()

	func _draw() -> void:
		draw_rect(area, Color(.1, .6, .8, .065))
		for x in [area.position.x, area.end.x]:
			for y in range(int(area.position.y) + 10, int(area.end.y), 28):
				draw_line(Vector2(x, y), Vector2(x, y + 14), Color(.3, .9, 1, .6), 3)
