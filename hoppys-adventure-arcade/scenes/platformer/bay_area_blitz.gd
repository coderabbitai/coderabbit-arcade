extends "res://modes/platformer/level.gd"
const Boss = preload("res://modes/platformer/merge_monster.gd")
const Projectile = preload("res://modes/platformer/branch_projectile.gd")
const LEVEL_MUSIC = preload("res://Assets/Audio/Platformer/Bay Area Blitz/bay_area_blitz_level.ogg")
const MUSIC = preload("res://Assets/Audio/Platformer/Bay Area Blitz/bay_area_blitz_boss.ogg")
var terrain_crops := {}

func _init() -> void:
	level_title = "Bay Area Blitz"
	level_route = "bay_area_blitz"
	boss_title = "MERGE CONFLICT MONSTER"
	intro_caption = "Resolve the branches. Ship the build."
	approach_objective = "Reach the bridge. Resolve the Merge Conflict Monster."
	fight_objective = "Resolve the conflict! Jump the slam; dodge the branch volley."
	level_track = LEVEL_MUSIC
	boss_track = MUSIC

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background()
	# Art has transparent padding: solids use the visible surface, never the atlas cell.
	for segment in [Vector3(0, 1060, 600), Vector3(1200, 1200, 600), Vector3(2530, 2770, 600)]:
		platform(Vector2(segment.x, segment.z), Vector2(segment.y, 160), "sidewalk")
	platform(Vector2(-50, 0), Vector2(50, 900), "brick_block")
	platform(Vector2(5300, 0), Vector2(50, 900), "brick_block")
	for p in [Vector2(470, 485), Vector2(730, 385), Vector2(1450, 475), Vector2(1770, 370), Vector2(2070, 450), Vector2(2800, 480), Vector2(3070, 380), Vector2(3430, 465)]:
		platform(p, Vector2(170, 24), "steel_platform")
	for x in [180, 900, 1390, 2620, 3520, 4100, 5020]:
		var lamp := Art.sprite("street_kit", "street_lamp", Vector2(x, 513))
		lamp.scale = Vector2(1.6, 1.6)
		add_child(lamp)
	_car(Vector2(1680, 531), Vector2(420, -55))
	_car(Vector2(3020, 531), Vector2(360, -55))
	_create_player()
	for data in [[800, "glitch_critter"], [1530, "request_reviewer"], [2220, "glitch_critter"], [2820, "glitch_critter"], [3550, "request_reviewer"]]:
		_enemy(float(data[0]), data[1])
	boss = _enemy(4630, "merge_monster")
	boss.fired.connect(_spawn_projectile)
	_build_arena()
	for x in [350, 550, 620, 770, 850, 1030, 1250, 1510, 1640, 1820, 1890, 2130, 2370, 2580, 2850, 2930, 3110, 3180, 3470, 3710, 3950, 4170]:
		var y := 540.0
		for p in [Vector2(470, 485), Vector2(730, 385), Vector2(1450, 475), Vector2(1770, 370), Vector2(2070, 450), Vector2(2800, 480), Vector2(3070, 380), Vector2(3430, 465)]:
			if x >= p.x and x <= p.x + 170: y = p.y - 45
		_pickup("commit_token", Vector2(x, y))
	_pickup("approve_shield", Vector2(650, 548))
	_pickup("coffee", Vector2(1970, 548))
	_pickup("lgtm_boost", Vector2(3150, 335))
	_pickup("auto_fix", Vector2(3470, 420))
	_pickup("full_review", Vector2(4250, 550))
	for x in [1320, 2680, 3800]:
		_hazard("pipeline", Vector2(x, 600))
	_hazard("conflict_zone", Vector2(3300, 560))
	exit_sprite = Art.sprite("interactives", "exit_ready", Vector2(5090, 600))
	exit_sprite.offset.y = -51
	exit_sprite.modulate = Color(0.45, 0.45, 0.45)
	add_child(exit_sprite)
	var exit_top := StaticBody2D.new()
	exit_top.position = Vector2(5090, EXIT_TOP)
	var exit_shape := Art.shape(Vector2(64, 12), Vector2(0, 6))
	exit_shape.one_way_collision = true
	exit_top.add_child(exit_shape)
	add_child(exit_top)
	_sign("BAY AREA BLITZ", "01 / THE EMBARCADERO", Vector2(120, 270))
	_sign("CATCH A CABLE CAR", "JUMP ON THE ROOF • RIDE TO THE NEXT PLATFORM", Vector2(1660, 180))
	_sign("BRANCH CONFLICT", "03 / JUMP OVER THE SLAM", Vector2(4350, 230))
	_setup_session()
func _background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var image := TextureRect.new()
	image.texture = load(Art.ROOT + "backdrop.png")
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.add_child(image)
	var tint := ColorRect.new()
	tint.color = Color(0.03, 0.09, 0.15, 0.24)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(tint)
	var near := Parallax2D.new()
	near.scroll_scale = Vector2(0.65, 0)
	near.repeat_size = Vector2(900, 0)
	near.z_index = -1
	add_child(near)
	for x in [100, 480, 780]:
		var building := Art.sprite("street_kit", "bay_window", Vector2(x, 470))
		building.scale = Vector2(2.8, 2.8)
		building.modulate = Color(0.5, 0.65, 0.7, 0.45)
		near.add_child(building)
	var fog := Parallax2D.new()
	fog.scroll_scale = Vector2(0.85, 0)
	fog.autoscroll = Vector2(15, 0)
	fog.repeat_size = Vector2(800, 0)
	fog.z_index = 3
	add_child(fog)
	var curl := Art.sprite("street_kit", "fog", Vector2(400, 615))
	curl.scale = Vector2(7, 2)
	curl.modulate.a = 0.18
	fog.add_child(curl)
func platform(pos: Vector2, size: Vector2, art: String) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var solid := Art.shape(size, size / 2)
	solid.one_way_collision = art == "steel_platform"
	body.add_child(solid)
	add_child(body)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	fill.color = Color("223c48")
	body.add_child(fill)
	var cropped := _terrain_crop(art)
	var bounds := cropped.region
	for x in range(0, int(size.x), 96):
		var piece := Sprite2D.new()
		piece.texture = cropped
		piece.centered = false
		piece.position.x = x
		piece.scale = Vector2(minf(96, size.x - x) / bounds.size.x, minf(size.y, 32) / bounds.size.y)
		body.add_child(piece)
# get_image() is a GPU readback on this renderer: crop each street-kit texture once.
func _terrain_crop(art: String) -> AtlasTexture:
	if not terrain_crops.has(art):
		var texture := load("res://Assets/bay-area-blitz-assets-only/individual/street_kit/" + art + ".png") as Texture2D
		var cropped := AtlasTexture.new()
		cropped.atlas = texture
		cropped.region = texture.get_image().get_used_rect()
		terrain_crops[art] = cropped
	return terrain_crops[art]
func _car(pos: Vector2, travel: Vector2) -> void:
	var body := AnimatableBody2D.new()
	body.position = pos
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := Art.shape(Vector2(92, 12), Vector2(0, -45))
	shape.one_way_collision = true
	shape.one_way_collision_margin = 12
	body.add_child(shape)
	var sprite := Art.sprite("interactives", "cable_car")
	sprite.offset.y = -51
	body.add_child(sprite)
	add_child(body)
	cars.append({"body": body, "origin": pos, "travel": travel})
func _enemy(x: float, kind: String) -> Node2D:
	var enemy = Boss.new() if kind == "merge_monster" else Enemy.new()
	enemy.kind = kind
	enemy.position = Vector2(x, 600)
	enemy.player = player
	if kind == "merge_monster":
		enemy.defeated.connect(_boss_defeated)
	else:
		enemy.defeated.connect(func(points: int):
			score += points
			_update_hud())
	add_child(enemy)
	return enemy
func _hazard(kind: String, pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2
	area.add_child(Art.shape(Vector2(46, 45), Vector2(0, -24)))
	var sprite := Art.sprite("interactives", kind)
	sprite.offset.y = -51
	area.add_child(sprite)
	add_child(area)
	hazards.append({"node": area, "kind": kind, "origin": pos})
func _spawn_projectile(start: Vector2, direction: Vector2) -> void:
	if encounter != "fight" or finished: return
	var projectile := Projectile.new()
	projectile.position = start
	projectile.velocity = direction * 320
	projectiles.add_child(projectile)
	projectile.reset_physics_interpolation()
