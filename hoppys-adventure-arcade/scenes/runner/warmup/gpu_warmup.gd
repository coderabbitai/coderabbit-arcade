extends Node3D
## One-shot GPU warm-up. gl_compatibility compiles each shader variant on its first draw, and an
## object first lit by an omni light compiles another variant, so a pickup, hazard or boss used to
## compile the moment it came into view, reached Hoppy's KeyLight or was lit by a boss light: the
## "grab an item, freeze, catch up" hitch. run() mounts every runtime visual in small batches, one
## copy where Hoppy stands (inside the play lights) and one far down the corridor (outside every
## light), and draws each batch with RenderingServer.force_draw(false) under the live lights, then
## again with a corridor-wide omni light: same viewport, environment, scaling and scene as play,
## but the frames are never presented. It runs from _ready() while the route veil is opaque, once
## in the runner menu and once in the first game (the menu's lights and Hoppy are not the game's),
## so nothing flashes even on a directly launched scene. Only public scene paths and visual hooks
## (contract §5, §11.5-§11.8) are used, the way the backend mounts them.
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Burst = preload("res://scenes/runner/powerups/visuals/hifi/collect_burst.gd")
const Telegraph = preload("res://scenes/runner/boss/telegraph.tscn")
const Tracer = preload("res://scenes/runner/boss/tool_tracer.gd")
const Number = preload("res://scenes/runner/boss/damage_number.gd")
const POWER_UP_DIR := "res://scenes/runner/powerups/visuals/"
const HAZARD_DIR := "res://scenes/runner/hazards/visuals/"
const BOSS_DIR := "res://scenes/runner/boss/visuals/"
const PURSUER_PATH := "res://scenes/runner/pursuer/pursuer_visual.tscn"
const HOPPY_PATH := "res://scenes/runner/player/hoppy_runner_visual.tscn"
const Vignette = preload("res://scenes/runner/shaders/vignette.gdshader")
const Scanline = preload("res://scenes/runner/shaders/scanline_portrait.gdshader")
const PostGrade = preload("res://scenes/runner/shaders/post_grade.gdshader")
## Frame 1 compiles draw and particle-process shaders, frame 2 draws particles that emitted.
const FRAMES := 2
## Copies of each batch sit at these distances down the track from Hoppy, so every light
## combination an item meets on its way in (key light, deck bounce, neither) is drawn. The last is
## outside every in-play light range, like a pickup spawned down the corridor.
const TRACK_DEPTHS: Array[float] = [0.0, 9.0, 55.0]
## Covers the whole visible corridor too: a boss or pursuer light later reaches walls and racks
## the KeyLight never touches.
const LIT_RANGE := 150.0

## Process-lifetime state lives on the Engine singleton: nothing else references this script once
## the runner menu is freed, and an unloaded script would drop its statics (the guard and the
## retained materials) before the game's first frame.
const STATE_KEY := &"runner_gpu_warmup"
## True once the game context has been warmed (the one that matters for play).
static var done: bool:
	get: return _state().ran.has(&"game")
	set(value):
		if value:
			_state().ran[&"game"] = true
			_state().ran[&"menu"] = true
		else: _state().ran.clear()
## Last run: stage build and forced-draw wall time, and what was mounted.
static var build_ms := 0.0
static var draw_ms := 0.0
static var census: Dictionary = {}
## Process-lifetime references to every material the warm-up drew. BaseMaterial3D,
## ParticleProcessMaterial and code-built shaders free their compiled program with their last
## user, so a warmed program would otherwise be recompiled by the next pickup, pit or burst
## (measured: a new spark system cost 75 ms again once every earlier one was freed).
static var retained: Dictionary:
	get: return _state().retained

static func _state() -> Dictionary:
	if not Engine.has_meta(STATE_KEY): Engine.set_meta(STATE_KEY, {"ran": {}, "retained": {}})
	return Engine.get_meta(STATE_KEY)

var _group: Node3D
var _near: Node3D
var _light: OmniLight3D
var _focus := Vector3.ZERO
var _slots := {}

## Once per process per context (runner menu, runner game). `host` owns the transient stage;
## `camera` defaults to the viewport camera. Returns false when skipped (already warmed, or the
## headless dummy renderer compiles nothing).
static func run(host: Node, camera: Camera3D = null) -> bool:
	if host == null or not host.is_inside_tree(): return false
	var context := &"game" if host.has_method(&"start_run") else &"menu"
	if _state().ran.has(context): return false
	_state().ran[context] = true
	if DisplayServer.get_name() == "headless": return false
	if camera == null: camera = host.get_viewport().get_camera_3d()
	if camera == null: return false
	build_ms = 0.0
	draw_ms = 0.0
	census.clear()
	# Retained programs must go before the RenderingServer does at exit.
	var root := host.get_tree().root
	if not root.tree_exiting.is_connected(release): root.tree_exiting.connect(release)
	# The menu's own corridor and Hoppy are freed on Play; keep their programs for the game.
	retain(host)
	_drop_doomed(host)
	var corridor := _corridor(host)
	# One process tick puts the corridor and starship lights (DeckBounce, key light) where play has them.
	if corridor != null: corridor.notification(Node.NOTIFICATION_PROCESS)
	var hoppy := _hoppy(host)
	var stage = stage_for(host, camera, hoppy.global_position if hoppy != null else Vector3.INF)
	# Label3D builds its mesh in a deferred call, so every label the batches mount draws empty
	# here. Copies wait on this stage for the deferred pass below (measured: the first pickup tag
	# of a run compiled for ~8 ms, 20-45 ms under load).
	var labels = stage_for(host, camera, stage._focus)
	labels.name = "GpuWarmupLabels"
	labels._copy_labels(host, [stage, labels])
	# Batches keep the shared instance-uniform buffer (4096 slots) well inside its limit.
	for batch in batches():
		var started := Time.get_ticks_usec()
		stage.build(batch)
		build_ms += (Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		# The corridor's turn corner, chevron and streaks only show mid-turn.
		var turn: bool = corridor != null and batch == &"canvas"
		if turn: _pose_turn(corridor, 0.5)
		# The live Hoppy's auras and shield, under its own lights (restored below; a run opens bare).
		if hoppy != null and batch == &"characters": _dress(hoppy, true)
		_sync_transforms(host)
		for lit in [false, true]:
			stage._light.visible = lit
			for i in FRAMES: RenderingServer.force_draw(false, 1.0 / 60.0)
		if hoppy != null and batch == &"characters": _dress(hoppy, false)
		if turn: _pose_turn(corridor, 0.0)
		draw_ms += (Time.get_ticks_usec() - started) / 1000.0
		retain(stage)
		labels._copy_labels(stage._group, [])
		stage.clear()
	stage.free()
	# Queued after every copy's own mesh update, so it runs once they are built, in the same
	# message-queue flush and so before the next frame is drawn.
	_draw_labels.call_deferred(labels)
	return true

## One copy of each distinct Label3D setup under `root` (outside `skip`), at the same place.
## The shader depends on the draw flags, the atlas texture on font and size.
func _copy_labels(root: Node, skip: Array) -> void:
	for node in root.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if skip.any(func(s): return s != root and s.is_ancestor_of(label)): continue
		var key := [label.font, label.font_size, label.outline_size > 0, label.billboard, label.shaded,
			label.double_sided, label.no_depth_test, label.fixed_size, label.alpha_cut, label.texture_filter,
			label.alpha_antialiasing_mode, label.render_priority, label.outline_render_priority,
			roundi(label.global_position.distance_to(_focus) / 5.0)]
		if _slots.has(key): continue
		_slots[key] = true
		var copy := label.duplicate(0) as Label3D
		copy.visible = true
		# Placed before it enters the tree: a later move only reaches the renderer with the
		# next transform flush, after the deferred draw.
		copy.transform = global_transform.affine_inverse() * label.global_transform
		add_child(copy)

## The deferred half of run(): draws the label copies under the live and the warm light.
static func _draw_labels(labels: Node3D) -> void:
	if not is_instance_valid(labels): return
	if labels.is_inside_tree():
		var started := Time.get_ticks_usec()
		for lit in [false, true]:
			labels._light.visible = lit
			for i in FRAMES: RenderingServer.force_draw(false, 1.0 / 60.0)
		draw_ms += (Time.get_ticks_usec() - started) / 1000.0
		census["label"] = labels.get_child_count() - 1
	labels.free()

## A Node3D moved inside the tree reaches the renderer only at the frame's transform flush, which
## never runs between these forced draws: anything a hook placed after mounting (hazard parts,
## boss FX, the posed corridor, Hoppy's shells) would draw at a stale spot, often off-screen.
static func _sync_transforms(root: Node) -> void:
	for node in root.find_children("*", "Node3D", true, false):
		(node as Node3D).force_update_transform()

## RunnerGame queue_free()s its graybox environment once the corridor mounts, but it lives until
## the end of this frame: its WorldEnvironment (no fog, no glow, linear tonemap) and second Sun
## would make every warm draw compile variants play never uses. Already doomed, so detach it now.
static func _drop_doomed(host: Node) -> void:
	for node in host.find_children("*", "Node", true, false):
		if is_instance_valid(node) and node.is_queued_for_deletion() and node.is_inside_tree():
			node.get_parent().remove_child(node)

## Application exit: drop the retained materials while the RenderingServer still exists.
static func release() -> void:
	retained.clear()

## Collects every material (and so its shader) under `node` into `retained`.
static func retain(node: Node) -> void:
	var materials: Array[Material] = []
	if node is GeometryInstance3D:
		materials.append_array([node.material_override, node.material_overlay])
		var meshes: Array[Mesh] = []
		if node is MeshInstance3D:
			meshes.append(node.mesh)
			for i in node.get_surface_override_material_count(): materials.append(node.get_surface_override_material(i))
		elif node is MultiMeshInstance3D and node.multimesh != null:
			meshes.append(node.multimesh.mesh)
		elif node is GPUParticles3D:
			materials.append(node.process_material)
			for i in node.draw_passes: meshes.append(node.get_draw_pass_mesh(i))
		for mesh in meshes:
			if mesh == null: continue
			for i in mesh.get_surface_count(): materials.append(mesh.surface_get_material(i))
	elif node is CanvasItem:
		materials.append(node.material)
	for material in materials:
		while material != null and not retained.has(material):
			retained[material] = true
			material = material.next_pass
	for child in node.get_children(): retain(child)

## The scene's Hoppy visual (game player or menu backdrop), found by its visual hooks.
static func _hoppy(host: Node) -> Node3D:
	for node in host.find_children("*", "Node3D", true, false):
		if node.has_method(&"show_shield") and node.has_method(&"show_aura") and not node.get_parent() is Camera3D:
			return node
	return null

static func _dress(hoppy: Node3D, on: bool) -> void:
	for aura: StringName in [&"lgtm", &"nitro", &"code_review"]:
		hoppy.call(&"show_aura", aura, on)
	hoppy.call(&"show_shield", on)
	# The orbit glyphs follow the aura from the visual's next _process; apply it now, as play would.
	hoppy.notification(Node.NOTIFICATION_PROCESS)

## The mounted corridor, found by its public turn hook rather than by path.
static func _corridor(host: Node) -> Node:
	for node in host.find_children("*", "Node3D", true, false):
		if node.has_method(&"set_turn") and node.has_method(&"set_boss_arena"): return node
	return null

## set_turn() is the StageManager's public hook; one process notification applies the pose the
## way the next frame would. Progress 0 restores the straight corridor.
static func _pose_turn(corridor: Node, progress: float) -> void:
	corridor.call(&"set_turn", progress, 1 if progress > 0.0 else 0)
	corridor.notification(Node.NOTIFICATION_PROCESS)

## Builds an empty stage under `host`, oriented like `camera`, with the (hidden) warm omni light.
## `focus` is where Hoppy stands; without one the near copy goes 6 m ahead of the camera.
static func stage_for(host: Node, camera: Camera3D, focus := Vector3.INF) -> Node3D:
	var stage = new()
	stage.name = "GpuWarmup"
	host.add_child(stage)
	stage.global_transform = camera.global_transform
	if focus == Vector3.INF: focus = camera.global_transform * Vector3(0, 0, -6)
	stage._focus = focus
	var local: Vector3 = camera.global_transform.affine_inverse() * focus
	stage._light = OmniLight3D.new()
	stage._light.name = "WarmOmni"
	stage._light.visible = false
	stage._light.position = local + Vector3(0, 1.5, 0)
	stage._light.light_color = Palette.MINT
	stage._light.light_energy = 0.65
	stage._light.omni_range = LIT_RANGE
	stage._light.shadow_enabled = false
	stage.add_child(stage._light)
	return stage

func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## Hazard visuals are instance-uniform heavy, so each kind gets its own batch.
static func batches() -> Array[StringName]:
	var result: Array[StringName] = [&"pickups"]
	for kind: StringName in HazardDefs.kinds(): result.append(kind)
	result.append_array([&"characters", &"canvas"])
	return result

## Mounts one copy of the batch at each track depth, in world space along the corridor (-Z).
func build(batch: StringName) -> void:
	_group = Node3D.new()
	_group.name = "Batch"
	add_child(_group)
	_slots.clear()
	for depth in TRACK_DEPTHS:
		var copy := Node3D.new()
		copy.name = "Depth%d" % depth
		_group.add_child(copy)
		copy.global_position = _focus + Vector3(0, 0, -depth)
		if depth == 0.0: _near = copy
		_build_into(copy, batch)

func _build_into(copy: Node3D, batch: StringName) -> void:
	_target = copy
	match batch:
		&"pickups":
			for kind: StringName in PowerUpDefs.kinds() + ToolDefs.kinds():
				_pickup(kind, false)
				_pickup(kind, true)
			for accent: Color in [Palette.MINT, Palette.ORANGE]:
				var burst := Burst.new()
				_place(burst, "burst")
				burst.start(accent)
		&"characters":
			for kind: StringName in _boss_kinds():
				_boss(kind, false)
				_boss(kind, true)
			_boss_fx()
			_pursuer()
			_hoppies()
		&"canvas":
			_canvas()
		_:
			# One hazard kind: every variant, plus hit and clear FX on one variant each.
			var variants := _variants(batch)
			for variant: StringName in variants:
				_hazard(batch, variant, &"")
			_hazard(batch, variants[variants.size() - 1], &"hit")
			_hazard(batch, variants[0], &"cleared")

func clear() -> void:
	if is_instance_valid(_group): _group.free()

var _target: Node3D

## A tight grid around the copy's origin, so every item shares the lights at that depth.
func _place(node: Node, category: String) -> void:
	var index := int(_slots.get(_target, 0))
	_slots[_target] = index + 1
	if node is Node3D:
		node.position = Vector3(float(index % 5 - 2), float(index / 5 % 3) + 0.5, -float(index / 15)) * 0.6
	_target.add_child(node)
	census[category] = int(census.get(category, 0)) + 1

func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var scene := load(path) as PackedScene
	if scene == null: return null
	var node := scene.instantiate()
	if node is Node3D: return node
	if node != null: node.free()
	return null

func _pickup(kind: StringName, collected: bool) -> void:
	var visual := _instance(POWER_UP_DIR + String(kind) + "_visual.tscn")
	if visual == null: return
	if &"kind" in visual: visual.set(&"kind", kind)
	_place(visual, "pickup")
	_hook(visual, &"on_spawned")
	if collected: _hook(visual, &"on_collected")

## Visual hooks are optional per the contract; a missing one is skipped, never an error.
func _hook(node: Object, method: StringName, args: Array = []) -> void:
	if node.has_method(method): node.callv(method, args)

func _variants(kind: StringName) -> Array:
	var variants: Dictionary = HazardDefs.DEFS[kind].get("variants", {})
	return variants.keys() if not variants.is_empty() else [&""]

func _hazard(kind: StringName, variant: StringName, state: StringName) -> void:
	var visual := _instance(HAZARD_DIR + String(kind) + "_visual.tscn")
	if visual == null: return
	var def := HazardDefs.get_def(kind, variant)
	var size: Vector3 = def.get("size", Vector3.ONE)
	var values := {
		&"kind": kind, &"variant": variant, &"hitbox_size": size,
		&"hitbox_offset": Vector3(0, HazardDefs.center_y(def), 0),
		&"lanes_mask": 7 if size.x > 5.0 else (3 if size.x > 3.0 else 2),
		&"dodge_hint": def.get("dodge_hint", &""),
		&"closing_speed": 12.0 if HazardDefs.is_projectile(kind) else 0.0,
	}
	for key: StringName in values:
		if key in visual: visual.set(key, values[key])
	_place(visual, "hazard")
	_hook(visual, &"on_spawned")
	if HazardDefs.is_timed(def):
		_hook(visual, &"set_laser_state", [&"high" if state == &"hit" else &"ground"])
		_hook(visual, &"set_telegraph", [0.5])
	if state == &"hit": _hook(visual, &"on_hit_player")
	elif state == &"cleared": _hook(visual, &"on_cleared")

func _boss_kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for slot: Dictionary in BossDefs.SLOTS:
		var kind: StringName = slot.get("kind", &"")
		if kind != &"" and kind not in kinds: kinds.append(kind)
	return kinds

func _boss(kind: StringName, defeated: bool) -> void:
	var visual := _instance(BOSS_DIR + String(kind) + "_visual.tscn")
	if visual == null: return
	var values := {&"kind": kind, &"boss_name": String(kind), &"max_hp": 10, &"phase_count": BossDefs.PHASE_COUNT,
		&"hover_z": 0.0, &"sway_amplitude": 0.0, &"sway_period": 1.0}
	for key: StringName in values:
		if key in visual: visual.set(key, values[key])
	_place(visual, "boss")
	_hook(visual, &"on_spawned")
	_hook(visual, &"set_phase", [BossDefs.PHASE_COUNT if defeated else 1])
	_hook(visual, &"set_health", [3 if defeated else 10, 10])
	_hook(visual, &"play_telegraph", [BossDefs.LANE_ALL, HazardDefs.PROJECTILE_KIND, 1.0])
	_hook(visual, &"play_attack", [HazardDefs.PROJECTILE_KIND])
	if defeated:
		_hook(visual, &"play_resist", [&"lint_rule"])
		_hook(visual, &"play_defeat")
	else:
		_hook(visual, &"play_hit", [&"unit_test", 1])

func _boss_fx() -> void:
	var telegraph := Telegraph.instantiate() as Node3D
	_place(telegraph, "boss_fx")
	_hook(telegraph, &"start", [1, &"orb", 1.0])
	for tool: StringName in [&"unit_test", &"lint_rule"]:
		var tracer: Node3D = Tracer.new()
		_place(tracer, "boss_fx")
		_hook(tracer, &"fire", [tracer.position, tracer.position + Vector3(0.5, 0.5, 0), tool, 1])
	for damage in [2, 0]:
		var number: Node3D = Number.new()
		_place(number, "boss_fx")
		_hook(number, &"start", [number.position, damage, Palette.MATRIX, 0.0])

func _pursuer() -> void:
	for threat in [0.2, 1.0]:
		var visual := _instance(PURSUER_PATH)
		if visual == null: return
		_place(visual, "pursuer")
		_hook(visual, &"set_threat", [threat])

## Roll, hurt sparks, every aura and the shield on Hoppy; the idle run pose is drawn by the scene.
func _hoppies() -> void:
	for state: StringName in [&"roll", &"hurt"]:
		var hoppy := _instance(HOPPY_PATH)
		if hoppy == null: return
		_place(hoppy, "hoppy")
		_hook(hoppy, &"set_anim_state", [state])
		if state == &"hurt":
			_hook(hoppy, &"on_hit")
			_hook(hoppy, &"show_shield", [true])
			for aura: StringName in [&"lgtm", &"nitro", &"code_review"]:
				_hook(hoppy, &"show_aura", [aura, true])
			hoppy.notification(Node.NOTIFICATION_PROCESS)

## The HUD's canvas shaders (vignette, scanline portrait, screen-reading grade) compile on first
## draw too; the boss HUD and pursuit alert only draw them once their event fires.
func _canvas() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -128
	var swatch := GradientTexture2D.new()
	swatch.width = 8
	swatch.height = 8
	for shader: Shader in [Vignette, Scanline, PostGrade]:
		for textured in [false, true]:
			var rect: Control = TextureRect.new() if textured else ColorRect.new()
			if textured: rect.set(&"texture", swatch)
			var material := ShaderMaterial.new()
			material.shader = shader
			rect.material = material
			rect.size = Vector2(64, 64)
			layer.add_child(rect)
	_place(layer, "canvas")
