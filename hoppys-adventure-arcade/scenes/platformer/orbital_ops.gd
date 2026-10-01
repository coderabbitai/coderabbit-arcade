extends "res://modes/platformer/level.gd"
const OrbitalArt = preload("res://modes/platformer/orbital_art.gd")
const OrbitalEnemy = preload("res://modes/platformer/orbital_enemy.gd")
const DeprecatedAPI = preload("res://modes/platformer/deprecated_api.gd")
const Plasma = preload("res://modes/platformer/orbital_projectile.gd")
const Hazard = preload("res://modes/platformer/orbital_hazard.gd")
const ORBITAL_LEVEL_MUSIC = preload("res://Assets/Audio/Platformer/Obital Ops/tipa16.mp3")
const ORBITAL_BOSS_MUSIC = preload("res://Assets/Audio/Platformer/Obital Ops/Valor of Heroes.mp3")
const ZERO_G := Rect2(2280, 140, 950, 520)
var orbital_hazards: Array[Node2D] = []
var rings: Array[Sprite2D] = []
var gravity_label: Label

func _init() -> void:
	level_title = "Orbital Ops"
	level_route = "orbital_ops"
	boss_title = "THE DEPRECATED API"
	boss_max_hp = 10
	intro_caption = "Broken routines. One final migration."
	approach_objective = "Cross the station. Shut down the Deprecated API."
	fight_objective = "Watch the warnings. Jump the slam and dash; punish recovery."
	level_track = ORBITAL_LEVEL_MUSIC
	boss_track = ORBITAL_BOSS_MUSIC

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background()
	for segment in [Vector3(0,1060,600),Vector3(1190,1410,600),Vector3(2820,2480,600)]:
		platform(Vector2(segment.x,segment.z),Vector2(segment.y,150))
	platform(Vector2(-50,0),Vector2(50,900),false,"wall_block")
	platform(Vector2(5300,0),Vector2(50,900),false,"wall_block")
	for p in [Vector2(430,480),Vector2(710,375),Vector2(1520,480),Vector2(1800,370),Vector2(2070,460),Vector2(2350,420),Vector2(2790,330),Vector2(3070,450),Vector2(3450,480),Vector2(3730,375)]:
		platform(p,Vector2(180,24),true,"one_way_platform")
	# A ceiling keeps assisted zero-g motion inside the visible bay.
	platform(Vector2(2280,110),Vector2(950,30),false,"scaffold_horizontal")
	for x in [80,1340,1970,3350,4070,5160]:
		add_child(OrbitalArt.prop("terminal",Vector2(x,510),Vector2(68,90)))
	for x in [350,1700,3600]:
		add_child(OrbitalArt.prop("solar_array",Vector2(x,160),Vector2(145,135)))
	_shuttle(Vector2(1840,530),Vector2(360,-65))
	_create_player()
	_build_arena()
	for data in [[730,600,"rogue_ai"],[1600,600,"rogue_ai"],[2010,340,"security_drone"],[2980,300,"security_drone"],[3530,600,"rogue_ai"],[3890,350,"security_drone"]]:
		_spawn_enemy(Vector2(data[0],data[1]),data[2])
	boss = DeprecatedAPI.new()
	boss.position = Vector2(4670,600)
	boss.player = player
	boss.fired.connect(_spawn_projectile)
	boss.defeated.connect(func(points: int):
		score += points
		boss_down = true
		_end_encounter()
		exit_sprite.modulate = Color.WHITE
		_update_hud())
	add_child(boss)
	for x in [320,470,570,750,840,1020,1260,1470,1580,1710,1880,2120,2310,2470,2650,2820,2990,3160,3380,3500,3690,3880,4100]:
		var y := 540.0
		if x>2350 and x<3170: y=340
		_pickup("commit_token",Vector2(x,y))
	_pickup("approve_shield",Vector2(550,435))
	_pickup("coffee",Vector2(1730,545))
	_pickup("lgtm_boost",Vector2(1850,325))
	_pickup("auto_fix",Vector2(3110,390))
	_pickup("coffee",Vector2(3650,545))
	_pickup("full_review",Vector2(4220,548))
	_add_hazard("laser",Vector2(1390,600),0)
	_add_hazard("laser",Vector2(3350,600),1.3)
	_add_hazard("laser",Vector2(3980,600),2.1)
	_add_hazard("vent",Vector2(840,600),.5)
	_add_hazard("vent",Vector2(2170,600),1.4)
	_add_hazard("vent",Vector2(3630,600),2.3)
	for x in [2290,3220]:
		var beacon := OrbitalArt.sprite("hazards","zero_g_beacon",Vector2(x,600))
		beacon.offset.y=-54
		add_child(beacon)
	exit_sprite = Art.sprite("interactives","exit_ready",Vector2(5090,600))
	exit_sprite.offset.y=-51
	exit_sprite.modulate=Color(.45,.45,.45)
	add_child(exit_sprite)
	var exit_top := StaticBody2D.new()
	exit_top.position=Vector2(5090,EXIT_TOP)
	var shape := Art.shape(Vector2(64,12),Vector2(0,6))
	shape.one_way_collision=true
	exit_top.add_child(shape)
	add_child(exit_top)
	_sign("ORBITAL OPS", "01 / SATELLITE SCAFFOLDS",Vector2(120,255))
	_sign("VACUUM VENTS", "AMBER: OPENING • CYAN: SUCTION",Vector2(780,245))
	_sign("CI CHECKPOINT", "AMBER: WARNING   RED: WAIT   DARK: CROSS",Vector2(1250,235))
	_sign("SERVICE SHUTTLE", "JUMP ON • RIDE TO THE UPPER DECK",Vector2(1780,185))
	_sign("ZERO-G BAY", "HOLD JUMP / UP: RISE • DOWN: DESCEND • RELEASE: BRAKE",Vector2(2320,185))
	_sign("GRAVITY RESTORED", "03 / LEGACY SYSTEMS",Vector2(3300,205))
	_sign("THE DEPRECATED API", "WATCH THE WARNINGS. ATTACK DURING RECOVERY.",Vector2(4340,230))
	_setup_session()
	gravity_label = Style.label("",17,Color("7aebff"))
	gravity_label.position=Vector2(24,107)
	score_label.get_parent().get_parent().add_child(gravity_label)
	queue_redraw()

func platform(pos: Vector2, size: Vector2, one_way := false, clip := "floor_slab") -> void:
	var body := StaticBody2D.new()
	body.position=pos
	var shape := Art.shape(size,size/2)
	shape.one_way_collision=one_way
	body.add_child(shape)
	add_child(body)
	var fill := Polygon2D.new()
	fill.polygon=PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
	fill.color=Color("101d35")
	body.add_child(fill)
	for x in range(0,int(size.x),128):
		body.add_child(OrbitalArt.prop(clip,Vector2(x,0),Vector2(minf(128,size.x-x),minf(size.y,40))))
	if size.y>60 and size.x>60:
		for x in range(0,int(size.x),128):
			body.add_child(OrbitalArt.prop("hull_panel",Vector2(x,40),Vector2(minf(128,size.x-x),size.y-40)))

func _shuttle(pos: Vector2, travel: Vector2) -> void:
	var body := AnimatableBody2D.new()
	body.position=pos
	body.collision_layer=8
	body.collision_mask=0
	var shape := Art.shape(Vector2(130,12),Vector2(0,6))
	shape.one_way_collision=true
	shape.one_way_collision_margin=12
	body.add_child(shape)
	body.add_child(OrbitalArt.prop("service_platform",Vector2(-65,0),Vector2(130,48)))
	add_child(body)
	cars.append({"body":body,"origin":pos,"travel":travel})

func _spawn_enemy(pos: Vector2, kind: String) -> void:
	var enemy := OrbitalEnemy.new()
	enemy.kind=kind
	enemy.position=pos
	enemy.player=player
	enemy.fired.connect(_spawn_projectile)
	enemy.defeated.connect(func(points: int):
		score+=points
		_update_hud())
	add_child(enemy)

func _add_hazard(kind: String, pos: Vector2, offset: float) -> void:
	var hazard := Hazard.new()
	hazard.kind=kind
	hazard.position=pos
	hazard.clock=offset
	add_child(hazard)
	orbital_hazards.append(hazard)

func _physics_process(dt: float) -> void:
	if finished or get_tree().paused: return
	player.environmental_acceleration=Vector2.ZERO
	player.zero_gravity=ZERO_G.has_point(player.position)
	gravity_label.text="ZERO-G  •  JUMP / UP ↑   DOWN ↓" if player.zero_gravity else ""
	for hazard in orbital_hazards:
		hazard.tick(dt,player)
		if finished: return
	for ring in rings: ring.rotation+=dt*.035
	super._physics_process(dt)

func _start_encounter() -> void:
	# Traversal enemies and their shots cannot intrude on the safe cinematic or arena.
	for child in get_children():
		if child is OrbitalEnemy:
			child.set_physics_process(false)
			child.hurtbox.set_deferred("monitorable",false)
	_clear_projectiles()
	super._start_encounter()

func _spawn_projectile(start: Vector2, direction: Vector2) -> void:
	if finished or encounter=="intro" or encounter=="cleared": return
	var shot := Plasma.new()
	shot.position=start
	shot.velocity=direction*330
	projectiles.add_child(shot)
	shot.reset_physics_interpolation()

func _background() -> void:
	var layer := CanvasLayer.new()
	layer.layer=-10
	add_child(layer)
	var plate := TextureRect.new()
	plate.texture=load(OrbitalArt.ROOT+"starfield.png")
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.add_child(plate)
	var shade := ColorRect.new()
	shade.color=Color(.02,.035,.09,.3)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var mid := Parallax2D.new()
	mid.scroll_scale=Vector2(.3,0)
	mid.z_index=-5
	add_child(mid)
	for x in [0,1500]:
		var hull := Sprite2D.new()
		hull.texture=load(OrbitalArt.ROOT+"station_hull.png")
		hull.position=Vector2(x+680,440)
		hull.scale=Vector2(1.4,1.4)
		hull.modulate=Color(.6,.65,.8,.55)
		mid.add_child(hull)
		var ring := Sprite2D.new()
		ring.texture=OrbitalArt.crop("station_kit","orbital_ring")
		ring.position=Vector2(x+1000,290)
		ring.scale=Vector2(2.5,2.5)
		ring.modulate=Color(.6,.8,1,.45)
		mid.add_child(ring)
		rings.append(ring)
	var near := Parallax2D.new()
	near.scroll_scale=Vector2(.65,0)
	near.z_index=-2
	add_child(near)
	for x in range(80,4100,650):
		var strut := OrbitalArt.prop("foreground_strut",Vector2(x,200),Vector2(65,405))
		strut.modulate=Color(.6,.75,.9,.45)
		near.add_child(strut)

func _draw() -> void:
	draw_rect(ZERO_G,Color(.1,.6,.8,.065))
	for x in [ZERO_G.position.x,ZERO_G.end.x]:
		for y in range(150,600,28): draw_line(Vector2(x,y),Vector2(x,y+14),Color(.3,.9,1,.6),3)
