extends MultiMeshInstance3D
## The per-boss accent layer drawn over the DANGER lane telegraphs (boss_fx.gd): glitch tiles,
## branch lines, sweep paths, chevrons, fissures, the quake ring and debris shadows are all floor
## quads of ONE MultiMesh, so every signature mode together costs a single draw call. Instances are
## rewritten from the attack records every frame (boss_fx.gd), from a preallocated buffer: nothing
## is allocated after _init(). Additive and depth-write free, so overlapping marks never z-fight.
const CAPACITY := 256
## Above the telegraph inset (0.025) and the hazard footprint planes (0.02 / 0.03).
const FLOOR_Y := 0.036
var used := 0
## CPU mirrors of the written instances (the dummy renderer returns nothing for tests).
var origins := PackedVector3Array()
var sizes := PackedVector2Array()
var colors := PackedColorArray()

func _init() -> void:
	name = "SignatureMarks"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = plane
	multi.instance_count = CAPACITY
	multi.visible_instance_count = 0
	# The whole corridor in arena space: no per-frame AABB recompute.
	multi.custom_aabb = AABB(Vector3(-6, -0.1, -32), Vector3(12, 0.4, 36))
	multimesh = multi
	origins.resize(CAPACITY)
	sizes.resize(CAPACITY)
	colors.resize(CAPACITY)
	visible = false

func begin() -> void:
	used = 0

## A floor quad centred at (x, z), `width` across and `length` along its yaw (0 = along the lane).
func add(x: float, z: float, width: float, length: float, yaw: float, color: Color) -> void:
	if used >= CAPACITY or color.a <= 0.004 or width <= 0.0 or length <= 0.0: return
	var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(width, 1.0, length))
	multimesh.set_instance_transform(used, Transform3D(basis, Vector3(x, FLOOR_Y, z)))
	multimesh.set_instance_color(used, color)
	origins[used] = Vector3(x, FLOOR_Y, z)
	sizes[used] = Vector2(width, length)
	colors[used] = color
	used += 1

## A strip from floor point a to floor point b (x, z).
func segment(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var d := b - a
	if d.length() < 0.001: return
	add((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, width, d.length(), atan2(d.x, d.y), color)

## A square turned 45 degrees: a node on a branch graph.
func diamond(x: float, z: float, size: float, color: Color) -> void:
	add(x, z, size, size, PI / 4, color)

func finish() -> void:
	multimesh.visible_instance_count = used
	visible = used > 0

func clear() -> void:
	used = 0
	finish()
