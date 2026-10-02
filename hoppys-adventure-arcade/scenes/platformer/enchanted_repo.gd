extends "res://modes/platformer/level.gd"
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
const ForestEnemy = preload("res://modes/platformer/enchanted_enemy.gd")
const Monolith = preload("res://modes/platformer/legacy_monolith.gd")
const Hazard = preload("res://modes/platformer/enchanted_hazard.gd")
const Branch = preload("res://modes/platformer/crumbling_branch.gd")
const Wave = preload("res://modes/platformer/enchanted_shockwave.gd")
const FOREST_MUSIC = preload("res://Assets/Audio/Platformer/The Enchanted Repo/04 - Silent Forest.mp3")
const BOSS_MUSIC = preload("res://Assets/Audio/Platformer/The Enchanted Repo/05 - Battle 1.mp3")
var forest_hazards: Array[Node2D] = []
var branches: Array[StaticBody2D] = []

func _init() -> void:
	level_title="The Enchanted Repo"
	level_route="enchanted_repo"
	boss_title="THE LEGACY MONOLITH"
	boss_max_hp=12
	intro_caption="Strip the debt. Reveal the core."
	approach_objective="Cross the rune forest. Reach the ruined castle."
	fight_objective="Jump the attacks. Strike during recovery to strip armor."
	level_track=FOREST_MUSIC
	boss_track=BOSS_MUSIC

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_physics_priority=-10
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_background()
	for segment in [Vector2(0,1100),Vector2(1260,1120),Vector2(2550,950),Vector2(3670,1630)]:
		platform(Vector2(segment.x,600),Vector2(segment.y,160),false,"arena_slab" if segment.x>=3670 else "ground_slab")
	platform(Vector2(-50,0),Vector2(50,900),false,"castle_wall")
	platform(Vector2(5300,0),Vector2(50,900),false,"castle_wall")
	for p in [Vector2(390,480),Vector2(1430,475),Vector2(1730,370),Vector2(2770,475),Vector2(3060,365),Vector2(3800,465)]:
		platform(p,Vector2(180,24),true,"root_platform")
	for p in [Vector2(730,370),Vector2(1160,515),Vector2(2110,470),Vector2(2460,515),Vector2(3575,515)]:
		var branch := Branch.new()
		branch.position=p
		add_child(branch)
		branches.append(branch)
	for x in [60,1360,2640,3750,4200,5180]:
		add_child(ForestArt.prop("rune_lantern",Vector2(x,525),Vector2(48,75)))
	for x in [1700,2980]:
		add_child(ForestArt.prop("scroll_banner",Vector2(x,200),Vector2(55,95)))
	for x in [4090,4840]:
		var arch := ForestArt.prop("castle_arch",Vector2(x,300),Vector2(210,300))
		arch.z_index=-1
		arch.modulate=Color(.6,.7,.75,.8)
		add_child(arch)
	_create_player()
	# Keep Hoppy readable when moving into the Monolith's recovery opening.
	player.z_index=5
	_build_arena()
	for data in [[680,"nitpick_gnome"],[1510,"bloat_troll"],[2020,"nitpick_gnome"],[2820,"bloat_troll"],[3330,"nitpick_gnome"],[3860,"bloat_troll"]]:
		var enemy := ForestEnemy.new()
		enemy.kind=data[1]
		enemy.position=Vector2(data[0],600)
		enemy.player=player
		enemy.defeated.connect(func(points: int):
			score+=points
			_update_hud())
		add_child(enemy)
	boss=Monolith.new()
	boss.position=Vector2(4660,600)
	boss.player=player
	boss.shockwave.connect(_spawn_wave)
	boss.defeated.connect(_boss_defeated)
	add_child(boss)
	for x in [310,460,590,800,990,1310,1600,1800,2070,2280,2610,2780,3000,3230,3430,3740,3960,4130]:
		_pickup("commit_token",Vector2(x,545))
	for p in [Vector2(470,425),Vector2(730,315),Vector2(1160,460),Vector2(1810,315),Vector2(2460,460),Vector2(3140,310),Vector2(3575,460)]:
		_pickup("commit_token",p)
	_pickup("approve_shield",Vector2(530,425))
	_pickup("coffee",Vector2(1660,545))
	_pickup("lgtm_boost",Vector2(1830,315))
	_pickup("auto_fix",Vector2(3120,310))
	_pickup("coffee",Vector2(3730,545))
	_pickup("full_review",Vector2(4230,548))
	_add_hazard("comment",Vector2(900,600),0)
	_add_hazard("vine",Vector2(1880,600),.7)
	_add_hazard("comment",Vector2(2250,600),1.4)
	_add_hazard("vine",Vector2(3180,600),2.1,1)
	_add_hazard("comment",Vector2(4050,600),.5)
	exit_sprite=Art.sprite("interactives","exit_ready",Vector2(5090,600))
	exit_sprite.offset.y=-51
	exit_sprite.modulate=Color(.45,.45,.45)
	add_child(exit_sprite)
	var exit_top := StaticBody2D.new()
	exit_top.position=Vector2(5090,EXIT_TOP)
	var shape := Art.shape(Vector2(64,12),Vector2(0,6))
	shape.one_way_collision=true
	exit_top.add_child(shape)
	add_child(exit_top)
	_sign("THE ENCHANTED REPO","01 / RUNEWOOD TRAIL",Vector2(120,255))
	_sign("UNSTABLE BRANCHES","CRACKING? JUMP! THEY REGROW.",Vector2(680,220))
	_sign("ENCHANTED COMMENTS","AMBER: WARNING · VIOLET: DANGER",Vector2(1280,230))
	_sign("SPAGHETTI CODE","WAIT FOR THE WHIP. JUMP PAST THE ROOTS.",Vector2(2640,215))
	_sign("THE LEGACY MONOLITH","TWO ARMOR LAYERS. STRIKE AFTER EACH ATTACK.",Vector2(4330,235))
	_setup_session()

func platform(pos: Vector2, size: Vector2, one_way := false, clip := "ground_slab") -> void:
	var body := StaticBody2D.new()
	body.position=pos
	var shape := Art.shape(size,size/2)
	shape.one_way_collision=one_way
	body.add_child(shape)
	add_child(body)
	var fill := Polygon2D.new()
	fill.polygon=PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
	fill.color=Color("252f35")
	body.add_child(fill)
	for x in range(0,int(size.x),128):
		body.add_child(ForestArt.prop(clip,Vector2(x,0),Vector2(minf(128,size.x-x),minf(size.y,68))))
	if size.y>70 and size.x>60:
		for x in range(0,int(size.x),128):
			body.add_child(ForestArt.prop("castle_wall",Vector2(x,68),Vector2(minf(128,size.x-x),size.y-68)))

func _add_hazard(kind: String, pos: Vector2, offset: float, direction := -1.0) -> void:
	var hazard := Hazard.new()
	hazard.kind=kind
	hazard.position=pos
	hazard.clock=offset
	hazard.direction=direction
	add_child(hazard)
	forest_hazards.append(hazard)

func _physics_process(dt: float) -> void:
	if finished or get_tree().paused: return
	# Traversal damage cannot intrude on the protected intro or cleared encounter.
	if encounter=="approach":
		for hazard in forest_hazards:
			hazard.tick(dt,player)
			if finished: return
		for branch in branches: branch.tick(dt,player)
	super._physics_process(dt)

func _start_encounter() -> void:
	for child in get_children():
		if child is ForestEnemy:
			child.set_physics_process(false)
			child.hurtbox.set_deferred("monitorable",false)
	_clear_projectiles()
	super._start_encounter()

func _spawn_wave(start: Vector2, direction: Vector2) -> void:
	if finished or encounter!="fight": return
	var wave := Wave.new()
	wave.position=start
	wave.velocity=direction*260
	projectiles.add_child(wave)
	wave.reset_physics_interpolation()

func _background() -> void:
	var layer := CanvasLayer.new()
	layer.layer=-10
	add_child(layer)
	var sky := TextureRect.new()
	sky.texture=load(ForestArt.ROOT+"sky.png")
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.add_child(sky)
	var shade := ColorRect.new()
	shade.color=Color(.025,.05,.06,.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var mid := Parallax2D.new()
	mid.scroll_scale=Vector2(.3,0)
	mid.z_index=-5
	add_child(mid)
	# Overlap finite plates at their dense tree edges; no seamless-repeat claim.
	for x in [-180,1050,2280]:
		var trees := Sprite2D.new()
		trees.texture=load(ForestArt.ROOT+"treeline.png")
		trees.centered=false
		trees.position=Vector2(x,-55)
		trees.scale=Vector2(1.5,1.3)
		trees.modulate=Color(.55,.65,.65,.62)
		mid.add_child(trees)
	var near := Parallax2D.new()
	near.scroll_scale=Vector2(.65,0)
	near.z_index=-2
	add_child(near)
	for x in range(50,4500,550):
		var tree := ForestArt.prop("rune_tree",Vector2(x,190),Vector2(260,410))
		tree.modulate=Color(.55,.65,.6,.6)
		near.add_child(tree)
	for x in range(200,5200,460):
		var flora := ForestArt.prop("foreground_flora",Vector2(x,645),Vector2(180,65))
		add_child(flora)
