extends MultiMeshInstance3D
## Seven socket bursts, one draw. Progress drives every shard, including a seek across beats.
const BEATS := [0.08, 0.15, 0.225, 0.30, 0.385, 0.465, 0.54]
const SHARDS := 15
const LIFETIME := 0.20
var origins: Array[Vector3] = []
var accent := Color("ff8546")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	name = "DefeatExplosions"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.radius = 0.5
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = BEATS.size() * SHARDS
	multimesh.custom_aabb = AABB(Vector3(-8, -8, -40), Vector3(16, 20, 80))
	for i in BEATS.size(): origins.append(Vector3.ZERO)
	clear()

func clear() -> void:
	visible = false
	if multimesh != null: multimesh.visible_instance_count = 0

func sample(progress: float) -> void:
	var count := 0
	for burst in BEATS.size():
		var t := (progress - float(BEATS[burst])) / LIFETIME
		if t < 0 or t >= 1: continue
		for shard in SHARDS:
			var angle := TAU * float(shard) / SHARDS + burst * 1.7
			var direction := Vector3(cos(angle), sin(angle), sin(angle * 2.7) * 0.6).normalized()
			var radius := (0.5 + t * 2.5) * (0.75 + float(shard % 3) * 0.12)
			var size := lerpf(0.42, 0.04, t) if shard > 0 else lerpf(1.6, 0.0, t)
			var point := origins[burst] + direction * radius if shard > 0 else origins[burst]
			multimesh.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), point))
			# White-hot ignition gives way to the boss accent within the first fifth.
			var color := Color.WHITE.lerp(accent, smoothstep(0.05 if shard == 0 else 0.0, 0.20, t))
			color.a = 1.0 - smoothstep(0.30, 1.0, t)
			multimesh.set_instance_color(count, color)
			count += 1
	multimesh.visible_instance_count = count
	visible = count > 0
