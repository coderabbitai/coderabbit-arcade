extends "res://scenes/runner/player/runner_visual_base.gd"
## Imported Blender mascot. Cosmetic transforms never drive player physics.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Glass = preload("res://scenes/runner/player/hifi/hoppy_glass.gdshader")
const Surface = preload("res://scenes/runner/player/hifi/hoppy_surface.gdshader")
const Hologram = preload("res://scenes/runner/player/hifi/energy.gdshader")
const LaneLook = preload("res://scenes/runner/player/hifi/lane_look.gd")
const FaceRig = preload("res://scenes/runner/player/hifi/face_rig.gd")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead",
	&"lane_dash_left", &"lane_dash_right", &"land", &"shield_brace", &"powerup_react", &"victory"]
## Backend-owned locomotion; one-shots return to the last of these.
const LOCOMOTION: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll"]
## Grounded one-shots authored on the run gait (Blender RUN_GAIT). Each ends on a run pose, so
## returning to run is seamless; re-requesting their return state does not cut them short.
const GAIT_ONE_SHOTS: Array[StringName] = [&"lane_dash_left", &"lane_dash_right", &"land",
	&"shield_brace", &"powerup_react", &"victory"]
## Clips that keep the run cadence, so set_run_speed scales them like run.
const PACED: Array[StringName] = [&"run", &"lane_dash_left", &"lane_dash_right", &"shield_brace",
	&"powerup_react", &"victory"]
## Run phase (fraction of the run clip) each gait one-shot ends on; hoppy.build.json run_exit.
const GAIT_EXIT := {&"lane_dash_left": 0.5}
const GROUNDED_BASE: Array[StringName] = [&"idle", &"run"]
const AIRBORNE: Array[StringName] = [&"jump", &"fall"]
const ONE_SHOT_BLEND := 0.08
const LAND_BLEND := 0.05
## Face weights per state: x focused, y wide-eyed, z wince, w grin. Hoppy is a friendly mascot:
## locomotion reads as focused-but-smiling, never a scowl (face_rig.gd also caps the brow drop).
const RUN_FACE := Vector4(0.3, 0.1, 0, 0.35)
const EXPRESSIONS := {
	&"idle": Vector4(0, 0, 0, 0.45), &"run": RUN_FACE, &"jump": Vector4(0, 1, 0, 0),
	&"fall": Vector4(0.2, 0.8, 0, 0), &"roll": Vector4(0.3, 0.4, 0, 0.3), &"hurt": Vector4(0, 0, 1, 0),
	&"dead": Vector4(0, 0, 0.8, 0), &"lane_dash_left": RUN_FACE,
	&"lane_dash_right": RUN_FACE, &"land": Vector4(0.4, 0, 0.3, 0.1),
	&"shield_brace": Vector4(0.4, 0, 0.7, 0), &"powerup_react": Vector4(0, 0.3, 0, 1),
	&"victory": Vector4(0, 0.2, 0, 1)}
const FACE_RATE := 14.0
## Neutral front fill for surfaces facing forward (hoppy_surface.gdshaderinc `front_fill`); tuned
## so the face fur reads cream (luma 0.65..0.85, saturation <= 0.20) in the corridor (art review r1).
const FRONT_FILL := 0.22
## Half-white cream ambient: a full CREAM tint squared the fur toward tan (saturation ~0.30 on the
## ambient term); the lighter tint keeps the warm cast with a hue closer to each albedo.
const AMBIENT_FILL := Color(1.0, 0.972549, 0.913725)
const BLINK_PERIOD := 3.4
## Power-up kinds that light the backpack LED strip (colours in _led_colors, same order).
const LED_KINDS: Array[StringName] = [&"nitro", &"lgtm", &"code_review", &"super_jump", &"auto_fix",
	&"approve_shield"]
const LED_FLASH_SECONDS := 0.5
## The full-size slide re-grounded against Godot skinning by dev/bake_hoppy_roll.gd (scale 1, no shrink).
const BAKED_ROLL := "res://scenes/runner/player/hifi/hoppy_roll.tres"
## The roll starts on its first baked frame: any blend from the upright pose would poke above the 0.9 m
## roll envelope (the barrier clearance). Leaving the roll blends so Hoppy uncurls instead of popping.
const ROLL_BLEND_IN := 0.0
const ROLL_BLEND_OUT := 0.1
## The roll is a full-size low slide (hips on the floor, lead leg reaching down the lane), so the
## aura/shield shells flatten into a long, low ellipsoid that hugs it, still inside the 0.9 m
## envelope (0.9 m aura radius * 0.49 about y = 0.455). The glyph orbit follows the same footprint.
const SLIDE_SHELL_CENTER := Vector3(0, 0.455, 0)
const SLIDE_SHELL_SCALE := Vector3(0.8, 0.49, 1.1)
const SLIDE_ORBIT := Vector2(0.66, 0.9)
## The bake tool reads the imported clip, so it switches the baked one off.
var use_baked_roll := true
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var anim_state: StringName = &"idle"
var _return_state: StringName = &"idle"
var _speed := 0.0
var _lean := 0.0
var _contact_shadow: MeshInstance3D
var _look: SkeletonModifier3D
var _meshes: Array[MeshInstance3D] = []
var _auras: Dictionary = {}
var _aura: MeshInstance3D
var _aura_material: ShaderMaterial
var _shield: MeshInstance3D
var _shield_requested := false
var _sparks: GPUParticles3D
var _sparkles: GPUParticles3D
var _glyph_material: ShaderMaterial
var _glyph_trail_material: ShaderMaterial
var _glyphs: MultiMeshInstance3D
var _trail: MultiMeshInstance3D
var _flash_remaining := 0.0
var _clock := 0.0
var _face: SkeletonModifier3D
## Smoothed face weights (focused, wide, wince, grin).
var _expression := Vector4.ZERO
## A victory requested mid-air or mid-roll plays on the next grounded return.
var _victory_pending := false
## LED strip: private accessory material copies with the COLOR_0 mask, and per-kind timers.
var _led_materials: Array[ShaderMaterial] = []
var _led_colors: Array[Color] = []
var _led_remaining := PackedFloat32Array()
var _led_duration := PackedFloat32Array()
var _led_kind := -1
var _led_flash := 0.0
var _led_state := Vector3.ZERO

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	var model := get_node("Root/Model")
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	# Keep the public player path while preserving imported track paths relative to Model.
	animation_player.reparent(self)
	animation_player.root_node = NodePath("../Root/Model")
	var library := AnimationLibrary.new()
	for state in STATES:
		var clip := animation_player.get_animation(state).duplicate(true) as Animation
		if state == &"roll" and use_baked_roll and ResourceLoader.exists(BAKED_ROLL):
			clip = (load(BAKED_ROLL) as Animation).duplicate(true)
		clip.loop_mode = Animation.LOOP_LINEAR if state in [&"idle", &"run", &"fall"] else Animation.LOOP_NONE
		if state == &"hurt":
			var track := clip.add_track(Animation.TYPE_METHOD)
			clip.track_set_path(track, NodePath("../.."))
			for time in [0.001, 0.12, 0.24]:
				clip.track_insert_key(track, time, {"method": &"flash", "args": []})
		library.add_animation(state, clip)
	for key in animation_player.get_animation_library_list():
		animation_player.remove_animation_library(key)
	animation_player.add_animation_library(&"", library)
	animation_player.playback_default_blend_time = 0.08
	animation_player.animation_finished.connect(_animation_finished)
	# Materials are shared by the imported PackedScene; only private duplicates mutate.
	var copies: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_meshes.append(mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index)
			if not copies.has(source):
				copies[source] = _surface_material(source as BaseMaterial3D)
				var opaque := (source as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				if opaque and mesh.mesh.surface_get_format(index) & Mesh.ARRAY_FORMAT_COLOR:
					(copies[source] as ShaderMaterial).set_shader_parameter("has_led_mask", true)
					_led_materials.append(copies[source])
			mesh.set_surface_override_material(index, copies[source])
	_look = LaneLook.new()
	_look.name = "LaneLook"
	skeleton.add_child(_look)
	_face = FaceRig.new()
	_face.name = "FaceRig"
	skeleton.add_child(_face)
	_face.bind(skeleton)
	_led_colors = [Palette.ORANGE, Palette.MINT, Palette.MATRIX, Palette.CREAM, Palette.MATRIX, Palette.MINT]
	_led_remaining.resize(LED_KINDS.size())
	_led_duration.resize(LED_KINDS.size())
	_build_contact_shadow()
	_build_effects()
	_configure_cosmetics(self)
	animation_player.play(anim_state, 0.0)
	animation_player.advance(0.0)
	set_lane_lean(_lean)
	set_run_speed(_speed)
	_update_aura()
	show_shield(_shield_requested)
	_process(0.0)

func _build_contact_shadow() -> void:
	_contact_shadow = MeshInstance3D.new()
	_contact_shadow.name = "ContactShadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.90,0.75)
	_contact_shadow.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://scenes/runner/player/hifi/contact_shadow.gdshader")
	_contact_shadow.material_override = material
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact_shadow)

func _surface_material(source: BaseMaterial3D) -> ShaderMaterial:
	assert(source != null, "Hoppy expects imported PBR materials")
	assert(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "ORM occlusion must be R")
	assert(source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "ORM roughness must be G")
	assert(source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "ORM metallic must be B")
	var material := ShaderMaterial.new()
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# Godot imports this GLB's BLEND lens as alpha with a depth prepass.
		assert(source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, "Hoppy glass requires alpha depth prepass; scissor/hash are unsupported")
		# Explicit back-culled glass variant requested by the round-12 art review.
		material.shader = Glass
	else:
		assert(source.albedo_color.a == 1.0, "Opaque Hoppy imports must have full albedo alpha")
		material.shader = Surface
	material.set_shader_parameter("albedo_map", source.get_texture(BaseMaterial3D.TEXTURE_ALBEDO))
	material.set_shader_parameter("albedo_color", source.albedo_color)
	material.set_shader_parameter("orm_map", source.get_texture(BaseMaterial3D.TEXTURE_METALLIC))
	material.set_shader_parameter("roughness_factor", source.roughness)
	material.set_shader_parameter("metallic_factor", source.metallic)
	material.set_shader_parameter("normal_map", source.get_texture(BaseMaterial3D.TEXTURE_NORMAL))
	material.set_shader_parameter("normal_scale", source.normal_scale)
	material.set_shader_parameter("has_normal", source.normal_enabled)
	material.set_shader_parameter("emission_map", source.get_texture(BaseMaterial3D.TEXTURE_EMISSION))
	material.set_shader_parameter("emission_color", source.emission)
	material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	material.set_shader_parameter("has_emission", source.emission_enabled)
	material.set_shader_parameter("has_emission_map", source.get_texture(BaseMaterial3D.TEXTURE_EMISSION) != null)
	material.set_shader_parameter("chroma_lock", 1.0)
	material.set_shader_parameter("ambient_fill", AMBIENT_FILL)
	material.set_shader_parameter("ambient_energy", 0.34)
	material.set_shader_parameter("light_gain", 0.5)
	material.set_shader_parameter("front_fill", FRONT_FILL)
	material.set_shader_parameter("flash", 0.0)
	return material

func _configure_cosmetics(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children():
		_configure_cosmetics(child)

func _shell(parent: Node3D, id: String, radius: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	node.mesh = sphere
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build_effects() -> void:
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = Hologram
	_aura_material.set_shader_parameter("sphere_radius", 0.9)
	_aura = _shell(get_node("Root"), "Aura", 0.9, _aura_material)
	var shield_material := _aura_material.duplicate() as ShaderMaterial
	shield_material.set_shader_parameter("sphere_radius", 0.88)
	shield_material.set_shader_parameter("mode", 1.0)
	_shield = _shell(self, "ShieldRing", 0.88, shield_material)
	_sparks = _particles("HitSparks", 20, true)
	_sparkles = _particles("AuraSparkles", 24, false)
	_glyph_material = ShaderMaterial.new()
	_glyph_material.shader = Hologram
	_glyph_material.set_shader_parameter("mode", 2.0)
	_glyph_material.set_shader_parameter("color", Palette.MINT)
	_glyph_trail_material = _glyph_material.duplicate()
	_glyph_trail_material.set_shader_parameter("color", Palette.MATRIX)
	_glyphs = _repeat("OrbitGlyphs", 12, _glyph_material)
	_trail = _repeat("DataTrail", 16, _glyph_trail_material)

func set_anim_state(state: StringName) -> void:
	if state not in STATES:
		return
	if state in GAIT_ONE_SHOTS:
		# Direct requests (fixtures, previews) play the one-shot from any state.
		if state != anim_state:
			_start_one_shot(state)
		return
	if state == anim_state:
		return
	if state in GROUNDED_BASE:
		if anim_state in GAIT_ONE_SHOTS and state == _return_state:
			# The backend re-asserting the state we return to (run after land) lets the one-shot finish.
			return
		if _victory_pending and anim_state != &"hurt":
			_start_one_shot(&"victory")
			_return_state = state
			return
	_play(state)

func _play(state: StringName) -> void:
	if state == &"hurt":
		if anim_state in LOCOMOTION:
			_return_state = anim_state
		elif anim_state not in GAIT_ONE_SHOTS:
			_return_state = &"run"
	if state == &"dead":
		_victory_pending = false
	var leaving_roll := anim_state == &"roll"
	anim_state = state
	if animation_player != null:
		var blend := 0.08
		if state == &"roll":
			blend = ROLL_BLEND_IN
		elif leaving_roll:
			blend = ROLL_BLEND_OUT
		animation_player.play(state, blend)
		set_run_speed(_speed)
		animation_player.advance(0.0)
		_process(0.0)

## Plays a grounded one-shot; it returns to the last locomotion state when it finishes.
func _start_one_shot(state: StringName) -> void:
	if anim_state in LOCOMOTION:
		_return_state = &"run" if anim_state in AIRBORNE else anim_state
	elif anim_state not in GAIT_ONE_SHOTS:
		_return_state = &"run"
	var restart := anim_state == state
	anim_state = state
	if state == &"victory":
		_victory_pending = false
	if animation_player != null:
		animation_player.play(state, LAND_BLEND if state == &"land" else ONE_SHOT_BLEND)
		if restart:
			animation_player.seek(0.0, true)
		set_run_speed(_speed)
		animation_player.advance(0.0)
		_process(0.0)

func _grounded() -> bool:
	return anim_state in GROUNDED_BASE or anim_state in GAIT_ONE_SHOTS

func set_run_speed(normalized: float) -> void:
	_speed = clampf(normalized, 0.0, 1.0)
	if animation_player != null:
		animation_player.speed_scale = lerpf(0.9, 1.6, _speed) if anim_state in PACED else 1.0

func set_lane_lean(direction: float) -> void:
	_lean = clampf(direction, -1.0, 1.0)
	rotation.z = -_lean * 0.12
	if _look != null:
		_look.set("direction", _lean)

func _animation_finished(state: StringName) -> void:
	# Locomotion transitions are backend-owned: jump/roll/dead hold their final pose. hurt and the
	# grounded one-shots restore the last requested locomotion state.
	if state != anim_state:
		return
	if state == &"hurt":
		_play(_return_state)
	elif state in GAIT_ONE_SHOTS:
		if _victory_pending and _return_state in GROUNDED_BASE:
			_start_one_shot(&"victory")
		else:
			_play(_return_state)
			if _return_state == &"run" and animation_player != null:
				# Resume the stride where the one-shot's gait window ended.
				animation_player.seek(animation_player.current_animation_length * float(GAIT_EXIT.get(state, 0.0)), true)

# --- Round-7 movement and reaction hooks, forwarded by runner_player.gd from RunnerGame signals ---

## player_action lane_left / lane_right / land.
func play_move(action: StringName) -> void:
	if action == &"land":
		if anim_state in AIRBORNE or _grounded():
			_start_one_shot(&"land")
	elif action == &"lane_left" or action == &"lane_right":
		if _grounded():
			_start_one_shot(&"lane_dash_left" if action == &"lane_left" else &"lane_dash_right")

## damage_blocked with the shield reason.
func on_shield_block() -> void:
	_led_flash = LED_FLASH_SECONDS
	if _grounded():
		_start_one_shot(&"shield_brace")

## power_up_collected: lights the LED meter for timed kinds and plays the reaction when grounded.
func on_power_up(kind: StringName, duration: float) -> void:
	var index := LED_KINDS.find(kind)
	if index >= 0 and _led_remaining.size() == LED_KINDS.size():
		_led_remaining[index] = maxf(duration, 0.0)
		_led_duration[index] = maxf(duration, 0.0)
		if duration > 0.0:
			_led_kind = index
	_led_flash = LED_FLASH_SECONDS
	if _grounded():
		_start_one_shot(&"powerup_react")

## power_up_expired.
func on_power_up_end(kind: StringName) -> void:
	var index := LED_KINDS.find(kind)
	if index >= 0 and _led_remaining.size() == LED_KINDS.size():
		_led_remaining[index] = 0.0

## stage_cleared / boss_defeated. Airborne or rolling, the victory waits for the next grounded return.
func celebrate() -> void:
	if anim_state == &"dead":
		return
	_led_flash = LED_FLASH_SECONDS
	if _grounded():
		if anim_state != &"victory":
			_start_one_shot(&"victory")
	else:
		_victory_pending = true

func on_hit() -> void:
	flash()
	if _sparks != null:
		_sparks.restart()

func flash() -> void:
	_flash_remaining = 0.06
	# Flash private uniforms without a full-character overlay draw pass.
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(i) as ShaderMaterial
			material.set_shader_parameter("flash", 1.0)

func _bone_point(bone_name: String, rest_point: Vector3) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	var pose := skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
	return to_local(skeleton.to_global(pose * rest_point))

func _process(delta: float) -> void:
	if is_instance_valid(_contact_shadow):
		var height := maxf(global_position.y,0.0)
		_contact_shadow.global_transform = Transform3D(Basis.from_scale(Vector3(1.0+height*0.2,1,1.0+height*0.2)),Vector3(global_position.x,0.016,global_position.z))
		_contact_shadow.material_override.set_shader_parameter("height",height)
	_clock += delta
	var rolling := anim_state == &"roll"
	var center := SLIDE_SHELL_CENTER if rolling else _bone_point("chest", Vector3(0, 0.9, 0))
	for shell in [_aura, _shield]:
		shell.position = center
		shell.scale = SLIDE_SHELL_SCALE if rolling else Vector3.ONE
		var material := shell.material_override as ShaderMaterial
		material.set_shader_parameter("clock", _clock)
		material.set_shader_parameter("hex_cell_size", 0.09 / shell.global_basis.x.length())
	_sparks.position = center
	_sparkles.position = center
	_glyph_material.set_shader_parameter("clock", _clock)
	_glyph_trail_material.set_shader_parameter("clock", _clock)
	_glyphs.visible = _aura.visible
	_trail.visible = _speed > 0.4 and anim_state == &"run"
	for i in 12:
		var a := _clock * 1.5 + i * TAU / 12.0
		var r := SLIDE_ORBIT if rolling else Vector2(0.65, 0.65)
		_instance(_glyphs, i, Transform3D(_billboard_basis(_glyphs), center + Vector3(cos(a) * r.x, sin(a * 2.0) * 0.08, sin(a) * r.y)))
	var emitter := _bone_point("chest", Vector3(0, 1.09, 0.26))
	for i in 16:
		var t := fmod(_clock * 0.8 + float(i) / 16.0, 1.0)
		_instance(_trail, i, Transform3D(_billboard_basis(_trail).scaled(Vector3.ONE * (1.0 - t)), emitter + Vector3(sin(i * 8.0) * 0.10 * t, t * 0.12, t * 0.9)))
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			for mesh in _meshes:
				for i in mesh.mesh.get_surface_count():
					var material := mesh.get_surface_override_material(i) as ShaderMaterial
					material.set_shader_parameter("flash", 0.0)
	_update_face(delta)
	_update_leds(delta)

func _update_face(delta: float) -> void:
	if _face == null:
		return
	var target: Vector4 = EXPRESSIONS.get(anim_state, Vector4.ZERO)
	_expression = _expression.lerp(target, 1.0 - exp(-FACE_RATE * delta))
	_face.focused = _expression.x
	_face.wide = _expression.y
	_face.wince = _expression.z
	_face.grin = _expression.w
	# A quick periodic blink, suppressed while wincing or dead.
	var phase := fmod(_clock, BLINK_PERIOD)
	var blink := clampf(1.0 - absf(phase - (BLINK_PERIOD - 0.09)) / 0.07, 0.0, 1.0)
	_face.blink = 0.0 if anim_state == &"dead" else blink * (1.0 - _expression.z)

## Backpack strip: the latest timed power-up shows its colour as a draining meter, a stored shield
## glows mint, and collections/blocks/celebrations sweep the strip for LED_FLASH_SECONDS.
## With nothing active, led_level is 0 and the baked MATRIX glow shows unchanged.
func _update_leds(delta: float) -> void:
	if _led_materials.is_empty() or _led_remaining.size() != LED_KINDS.size():
		return
	var best := -1
	for i in LED_KINDS.size():
		if _led_remaining[i] > 0.0:
			_led_remaining[i] = maxf(_led_remaining[i] - delta, 0.0)
			if _led_remaining[i] > 0.0 and _led_duration[i] > 0.0 and (best < 0 or i == _led_kind):
				best = i
	_led_flash = maxf(_led_flash - delta, 0.0)
	var level := 0.0
	var fill := 1.0
	var color := Palette.MINT
	if best >= 0:
		color = _led_colors[best]
		fill = _led_remaining[best] / _led_duration[best]
		level = 0.9 + 0.25 * sin(_clock * (14.0 if LED_KINDS[best] == &"nitro" else 5.0))
	elif _shield_requested:
		level = 0.8
	if _led_flash > 0.0:
		var sweep := 1.0 - _led_flash / LED_FLASH_SECONDS
		fill = maxf(fill if best >= 0 else 0.0, sweep)
		color = color.lerp(Palette.CREAM, 0.4)
		level = maxf(level, 1.4)
	if level == 0.0 and _led_state.x == 0.0:
		return
	_led_state = Vector3(level, fill, float(best))
	for material in _led_materials:
		material.set_shader_parameter("led_level", level)
		material.set_shader_parameter("led_fill", fill)
		material.set_shader_parameter("led_color", color)

## LED uniforms currently pushed to the strip: (level, fill, active kind index or -1).
func led_state() -> Vector3:
	return _led_state

func _particles(id: String, count: int, one_shot: bool) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.name = id
	node.position.y = 0.8
	node.amount = count
	node.lifetime = 0.4 if one_shot else 1.2
	node.one_shot = one_shot
	node.explosiveness = 1.0 if one_shot else 0.0
	node.emitting = false
	node.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0 if one_shot else 0.8
	process.gravity = Vector3.ZERO
	node.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.04)
	mesh.material = Materials.glow(Palette.CREAM)
	node.draw_pass_1 = mesh
	add_child(node)
	return node

func show_aura(kind: StringName, on: bool) -> void:
	if kind not in [&"lgtm", &"nitro", &"code_review"]:
		return
	if on:
		_auras[kind] = true
	else:
		_auras.erase(kind)
	if _aura != null:
		_update_aura()

func _update_aura() -> void:
	_aura.visible = not _auras.is_empty()
	_sparkles.emitting = _aura.visible
	var color := Palette.MATRIX
	color.a = 0.12
	if _auras.has(&"nitro"):
		color = Palette.ORANGE
		color.a = 0.4
	if _auras.has(&"lgtm"):
		color = Palette.MINT
		color.a = 0.55
	_aura_material.set_shader_parameter("color", color)

func show_shield(on: bool) -> void:
	_shield_requested = on
	if _shield != null:
		_shield.visible = on

func _repeat(id: String, count: int, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = id
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.055)
	node.multimesh.mesh = quad
	node.multimesh.instance_count = count
	node.material_override = material
	add_child(node)
	return node

func _instance(node: MultiMeshInstance3D, index: int, pose: Transform3D) -> void:
	# Dummy headless renderer does not retain instance transforms for readback.
	var poses: Dictionary = node.get_meta("poses", {})
	poses[index] = pose
	node.set_meta("poses", poses)
	node.multimesh.set_instance_transform(index, pose)

func _billboard_basis(node: Node3D) -> Basis:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Basis.IDENTITY
	return node.global_basis.inverse() * camera.global_basis.orthonormalized()
