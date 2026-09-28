extends Node2D
const Art = preload("res://modes/platformer/art.gd")
const Player = preload("res://modes/platformer/player.gd")
const Enemy = preload("res://modes/platformer/enemy.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
# Preloaded so nothing is read from disk mid-run (a freed one-shot player used to drop its stream,
# so every jump reloaded the WAV).
const SFX := {
	"jump": preload("res://Assets/Backgrounds/Sunny-land-forest-files/demo/assets/sound/wavs/jump.wav"),
	"hurt": preload("res://Assets/Backgrounds/Sunny-land-forest-files/demo/assets/sound/wavs/hurt.wav")
}
const HEART_FULL = preload("res://Assets/bay-area-blitz-assets-only/individual/hud/heart_full.png")
const HEART_EMPTY = preload("res://Assets/bay-area-blitz-assets-only/individual/hud/heart_empty.png")
const MUSIC = preload("res://Assets/Audio/Platformer/Bay Area Blitz/c64_uptempo_chiptune.ogg")
var player: CharacterBody2D
var camera: Camera2D
var score := 0
var elapsed := 0.0
var finished := false
var boss_down := false
var boss: Node2D
var pickups: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var cars: Array[Dictionary] = []
var hearts: Array[TextureRect] = []
var score_label: Label
var objective: Label
var boss_label: Label
var overlay: ColorRect
var overlay_title: Label
var overlay_detail: Label
var resume_button: Button
var exit_sprite: AnimatedSprite2D
var music: AudioStreamPlayer
var sfx_players := {}
var terrain_crops := {}
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
	player = Player.new()
	player.position = Vector2(150, 590)
	add_child(player)
	camera = Camera2D.new()
	camera.position = Vector2(0, -245)
	camera.limit_left = 0
	camera.limit_right = 5300
	camera.limit_top = 0
	camera.limit_bottom = 720
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6
	player.add_child(camera)
	for data in [[800, "glitch_critter"], [1530, "request_reviewer"], [2220, "glitch_critter"], [2820, "glitch_critter"], [3550, "request_reviewer"]]:
		_enemy(float(data[0]), data[1])
	boss = _enemy(4630, "merge_monster")
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
	_sign("BAY AREA BLITZ", "01 / THE EMBARCADERO", Vector2(120, 270))
	_sign("CATCH A CABLE CAR", "JUMP ON THE ROOF • RIDE TO THE NEXT PLATFORM", Vector2(1660, 180))
	_sign("BRANCH CONFLICT", "03 / JUMP OVER THE SLAM", Vector2(4350, 230))
	_hud()
	player.health_changed.connect(_update_hud)
	player.died.connect(func(): _finish(false))
	player.jumped.connect(func(): _sound("jump"))
	player.hurt.connect(func(): _sound("hurt"))
	player.swiped.connect(func(): AudioService.play_ui(2))
	_update_hud()
	AudioService.music.stream_paused = true
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	var track := MUSIC.duplicate() as AudioStreamOggVorbis
	track.loop = true
	music.stream = track
	music.volume_db = -13
	add_child(music)
	music.play()
	for clip in SFX:
		var sound := AudioStreamPlayer.new()
		sound.stream = SFX[clip]
		sound.bus = "SFX"
		sound.volume_db = -12
		add_child(sound)
		sfx_players[clip] = sound
	for child in get_children():
		if not child is CanvasLayer: child.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Everything above was placed, not moved: start interpolation from those positions.
	reset_physics_interpolation()
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
	var enemy := Enemy.new()
	enemy.kind = kind
	enemy.position = Vector2(x, 600)
	enemy.player = player
	enemy.defeated.connect(func(points: int):
		score += points
		if kind == "merge_monster":
			boss_down = true
			exit_sprite.modulate = Color.WHITE
		_update_hud())
	add_child(enemy)
	return enemy
func _pickup(kind: String, pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2
	area.add_child(Art.shape(Vector2(38, 42)))
	area.add_child(Art.sprite("pickups", kind))
	add_child(area)
	pickups.append({"node": area, "kind": kind, "origin": pos})
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
func _sign(title: String, subtitle: String, pos: Vector2) -> void:
	var l := Style.label(title + "\n" + subtitle, 19)
	l.position = pos
	l.add_theme_color_override("font_shadow_color", Color("101d2d"))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	add_child(l)
func _physics_process(dt: float) -> void:
	if finished or get_tree().paused: return
	elapsed += dt
	for car in cars:
		car.body.position = car.origin + car.travel * _car_progress(elapsed)
	for i in range(pickups.size() - 1, -1, -1):
		var item: Dictionary = pickups[i]
		var area: Area2D = item.node
		area.position.y = item.origin.y + sin(elapsed * 3 + item.origin.x) * 5
		if area.overlaps_body(player):
			match item.kind:
				"commit_token": score += 25
				"coffee": player.heal(1)
				"full_review": player.heal(3)
				"approve_shield": player.shield = true
				"lgtm_boost": player.boost = 5
				"auto_fix":
					for enemy in get_children():
						if enemy is Enemy and enemy.kind != "merge_monster" and enemy.position.distance_to(player.position) < 350:
							enemy.hp = 1
							enemy.take_hit()
			pickups.remove_at(i)
			area.queue_free()
			AudioService.play_ui(1)
			_update_hud()
	for hazard in hazards:
		if hazard.kind == "conflict_zone":
			hazard.node.position.x = hazard.origin.x + sin(elapsed) * 115
		if hazard.node.overlaps_body(player): player.damage(hazard.node.position.x)
	if boss_down and absf(player.position.x - 5090) < 85 and player.position.y > 510 and player.attack_time > 0:
		exit_sprite.play("exit_complete")
		_finish(true)
	if is_instance_valid(boss) and not boss_down and player.position.x > 4080:
		boss_label.text = "MERGE CONFLICT MONSTER   " + "●".repeat(boss.hp) + "○".repeat(8 - boss.hp)
	else: boss_label.text = ""
func _hud() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.theme = Style.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var bar := ColorRect.new()
	bar.color = Color(0.04, 0.10, 0.15, 0.92)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 90
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.position = Vector2(28, 24)
	bar.add_child(row)
	for i in 3:
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(38, 38)
		row.add_child(heart)
		hearts.append(heart)
	score_label = Style.label("", 19)
	score_label.position = Vector2(175, 18)
	bar.add_child(score_label)
	objective = Style.label("", 15, Style.MINT)
	objective.position = Vector2(175, 49)
	bar.add_child(objective)
	var pause := Button.new()
	pause.text = "Ⅱ  PAUSE"
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-180, 22)
	pause.size = Vector2(150, 45)
	pause.pressed.connect(_pause)
	bar.add_child(pause)
	boss_label = Style.label("", 18, Color("ffbd7c"))
	boss_label.position = Vector2(330, 107)
	root.add_child(boss_label)
	var controls := Style.label("A/D or ←/→  MOVE     SPACE  JUMP     J / X  SWIPE     ESC  PAUSE", 14)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(24, -32)
	root.add_child(controls)
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.06, 0.1, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	overlay_title = Style.label("", 40)
	col.add_child(overlay_title)
	overlay_detail = Style.label("", 18, Style.MINT)
	col.add_child(overlay_detail)
	resume_button = Style.button("Resume")
	col.add_child(resume_button)
	resume_button.pressed.connect(_resume)
	for entry in [["Retry Bay Area Blitz", "bay_area_blitz"], ["Return to Platformer Menu", "platformer"], ["Return to Arcade", "hub"]]:
		var button := Style.button(entry[0])
		col.add_child(button)
		button.pressed.connect(func():
			get_tree().paused = false
			AppRouter.go(entry[1]))
	overlay.hide()
func _update_hud() -> void:
	for i in hearts.size():
		hearts[i].texture = HEART_FULL if i < player.hp else HEART_EMPTY
	score_label.text = "BAY AREA BLITZ   /   %06d" % score
	objective.text = "Smash the MERGE button with J / X!" if boss_down else "Reach the bridge. Resolve the Merge Conflict Monster."
	if player.shield: objective.text += "   [SHIELD]"
func _pause() -> void:
	if finished: return
	get_tree().paused = true
	overlay_title.text = "TAKE A BREATHER"
	overlay_detail.text = "Your commits can wait."
	resume_button.show()
	overlay.show()
	resume_button.grab_focus()
func _resume() -> void:
	player.input_lock = 0.15
	player.buffer = 0
	player.attack_time = 0
	get_tree().paused = false
	overlay.hide()
func _finish(won: bool) -> void:
	if finished: return
	finished = true
	player.set_physics_process(false)
	set_physics_process(false)
	get_tree().paused = true
	overlay_title.text = "MERGE SUCCESSFUL!" if won else "BUILD FAILED"
	overlay_detail.text = "%06d POINTS   /   %02d:%02d\n%s" % [score, int(elapsed) / 60, int(elapsed) % 60, "Bay Area Blitz complete." if won else "Fresh branch. Another try."]
	resume_button.hide()
	overlay.show()
	resume_button.get_parent().get_child(3).grab_focus()
func _input(event: InputEvent) -> void:
	# Once a route change has started, the level is leaving: never re-pause it under the veil.
	if AppRouter.busy:
		return
	if event.is_action_pressed("pause") and not finished:
		if get_tree().paused: _resume()
		else: _pause()
		get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(overlay) and not finished and not AppRouter.busy:
		_pause()
func _exit_tree() -> void:
	get_tree().paused = false
	AudioService.music.stream_paused = false

func _sound(clip: String) -> void:
	sfx_players[clip].play()

# Ten-second round trip with a one-second boarding stop at each end.
func _car_progress(time: float) -> float:
	var phase := fmod(time, 10.0)
	if phase < 1.0: return 0.0
	if phase < 5.0: return smoothstep(0.0, 1.0, (phase - 1.0) / 4.0)
	if phase < 6.0: return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (phase - 6.0) / 4.0)
