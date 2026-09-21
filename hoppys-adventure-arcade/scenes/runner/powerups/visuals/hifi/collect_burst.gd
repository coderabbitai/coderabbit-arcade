extends GPUParticles3D
## Detached because tool_pickup frees its entire branch during collect().
const Textures = preload("res://scenes/runner/powerups/visuals/hifi/texture_forge.gd")
var age := 0.0

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

func start(color: Color) -> void:
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
	draw_pass_1 = shape
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 180.0
	motion.initial_velocity_min = 0.3
	motion.initial_velocity_max = 1.1
	motion.gravity = Vector3(0,-0.25,0)
	motion.scale_min = 0.4
	motion.scale_max = 1.0
	process_material = motion
	restart()
	emitting = true

func _process(delta: float) -> void:
	age += delta
	if age >= 0.5: queue_free()
