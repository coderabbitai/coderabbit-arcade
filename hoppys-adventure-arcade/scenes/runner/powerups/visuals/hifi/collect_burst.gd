extends GPUParticles3D
## Detached because tool_pickup frees its entire branch during collect().
## Pooled: after LIFETIME a burst goes idle under its host instead of freeing, and the next collect
## restarts it. Draw passes are static and shared, so a repeat collect never builds a material (a
## new material variant used to compile its shader on the grab frame).
const Textures = preload("res://scenes/runner/powerups/visuals/hifi/texture_forge.gd")
const LIFETIME := 0.5
const GROUP := &"a4_collect_burst"
static var _draws: Dictionary = {}
static var _motion: ParticleProcessMaterial
var age := 0.0
## True while a collect (or warm-up) is playing; idle bursts are free for reuse.
var busy := false

func _init() -> void:
	name = "A4CollectBurst"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	emitting = false
	amount = 24
	lifetime = 0.32
	one_shot = true
	explosiveness = 1.0
	visibility_aabb = AABB(Vector3.ONE*-0.8,Vector3.ONE*1.6)
	set_process(false)
	add_to_group(GROUP)

## Process-material prototype; each pooled burst takes one copy of it.
static func motion() -> ParticleProcessMaterial:
	if _motion == null:
		_motion = ParticleProcessMaterial.new()
		_motion.direction = Vector3.UP
		_motion.spread = 180.0
		_motion.initial_velocity_min = 0.3
		_motion.initial_velocity_max = 1.1
		_motion.gravity = Vector3(0,-0.25,0)
		_motion.scale_min = 0.4
		_motion.scale_max = 1.0
	return _motion

## One shared draw pass per accent; every accent shares one shader variant.
static func draw_mesh(color: Color) -> QuadMesh:
	var key := color.to_html()
	if not _draws.has(key):
		var shape := QuadMesh.new()
		shape.size = Vector2(0.025,0.045)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_color = color
		material.albedo_texture = Textures.maps().glyph
		shape.material = material
		_draws[key] = shape
	return _draws[key]

## Shared resources for warm-up callers: the process material plus one draw mesh per accent.
static func warm_resources(colors: Array = []) -> Array[Resource]:
	var result: Array[Resource] = [motion()]
	for color: Color in colors: result.append(draw_mesh(color))
	return result

## Static on purpose: gl_compatibility frees a material variant's shader with its last material,
## so a warm-up burst freed before play would otherwise leave the grab to recompile it.
## Tests release them before quitting (engine shader maps finalise before script statics).
static func release_caches() -> void:
	_draws.clear()
	_motion = null

## An idle pooled burst directly under `host`, or a new one added there.
static func acquire(host: Node) -> GPUParticles3D:
	for child in host.get_children():
		if child.is_in_group(GROUP) and not child.busy and not child.is_queued_for_deletion():
			return child
	var burst = new()
	host.add_child(burst)
	return burst

## One invisible emission (amount_ratio 0: nothing is drawn on screen) mid-corridor under `host`.
## The GPU warm-up's off-screen stage leaves one burst variant for its first in-corridor draw
## (measured about 10 ms on the first grab); this pays it while the run is being set up. The burst
## then idles in the host's pool and serves the first grab.
static func prewarm(host: Node, at: Vector3) -> void:
	if host == null or not host.is_inside_tree(): return
	var burst := acquire(host)
	burst.global_position = at
	burst.start(Color.WHITE)
	burst.amount_ratio = 0.0

func start(color: Color) -> void:
	amount_ratio = 1.0
	draw_pass_1 = draw_mesh(color)
	# A pooled burst keeps its own copy for life; the static prototype keeps the process shader
	# variant compiled between bursts (sharing the one instance across emitters leaked at exit).
	if process_material == null: process_material = motion().duplicate()
	age = 0.0
	busy = true
	show()
	restart()
	emitting = true
	set_process(true)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		emitting = false
		busy = false
		set_process(false)
