extends SceneTree
## Re-bakes Hoppy's roll from the imported Blender clip (headless is fine):
## Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/player/dev/bake_hoppy_roll.gd
## Since recipe revision 8 the Blender roll is a full-scale baseball slide that the builder already seats
## on the floor under 0.885 m, so the scale factor is 1 (no shrink). This step only re-grounds every key
## against Godot's own skinning (skinned bounds inside [FLOOR_GAP, CEILING] m, under the 0.9 m roll
## hitbox) and fails if the slide pokes above CEILING. Output: res://scenes/runner/player/hifi/hoppy_roll.tres.
const OUTPUT := "res://scenes/runner/player/hifi/hoppy_roll.tres"
const SOURCE_SCALE := 1.0
const TARGET_SCALE := 1.0
const FLOOR_GAP := 0.012
const CEILING := 0.885

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var hoppy = (load("res://scenes/runner/player/hoppy_runner_visual.tscn") as PackedScene).instantiate()
	hoppy.set("use_baked_roll", false)
	root.add_child(hoppy)
	await process_frame
	var player: AnimationPlayer = hoppy.animation_player
	player.playback_default_blend_time = 0.0
	var clip: Animation = player.get_animation(&"roll")
	var scale_track := -1
	var position_track := -1
	for track in clip.get_track_count():
		if String(clip.track_get_path(track)).ends_with(":root"):
			if clip.track_get_type(track) == Animation.TYPE_SCALE_3D: scale_track = track
			if clip.track_get_type(track) == Animation.TYPE_POSITION_3D: position_track = track
	if scale_track < 0 or position_track < 0 or clip.track_get_key_count(scale_track) != clip.track_get_key_count(position_track):
		push_error("BAKE ROLL: unexpected root tracks")
		quit(1)
		return
	var factor := TARGET_SCALE / SOURCE_SCALE
	for key in clip.track_get_key_count(scale_track):
		clip.track_set_key_value(scale_track, key, clip.track_get_key_value(scale_track, key) * factor)
	# Skeleton-space metres per world metre on the vertical axis.
	var skeleton: Skeleton3D = hoppy.skeleton
	var up_scale := skeleton.global_basis.y.length()
	player.play(&"roll")
	var high := -INF
	# Two passes: the first grounds each key, the second removes the residual left by bone blending.
	for pass_index in 2:
		for key in clip.track_get_key_count(position_track):
			player.seek(clip.track_get_key_time(position_track, key), true)
			hoppy._process(0.0)
			var bounds := skin_bounds(hoppy)
			var value: Vector3 = clip.track_get_key_value(position_track, key)
			value.y -= (bounds.position.y - FLOOR_GAP) / up_scale
			clip.track_set_key_value(position_track, key, value)
	var low := INF
	for sample in 61:
		player.seek(clip.length * sample / 60.0, true)
		hoppy._process(0.0)
		var bounds := skin_bounds(hoppy)
		low = minf(low, bounds.position.y)
		high = maxf(high, bounds.end.y)
	print("BAKE ROLL: scale %.2f -> %.2f, skinned y %.3f..%.3f over 61 samples" % [SOURCE_SCALE, TARGET_SCALE, low, high])
	if low < 0.0 or high > CEILING:
		push_error("BAKE ROLL: envelope %.3f..%.3f outside 0..%.3f; lower the slide in build_hoppy.py" % [low, high, CEILING])
		quit(1)
		return
	var error := ResourceSaver.save(clip, OUTPUT)
	print("BAKE ROLL: saved ", OUTPUT, " error=", error)
	quit(error)

# Skinned-vertex bounds (imported Mesh AABBs are rest bounds); same evaluation as tests/assets/a1_check.gd.
func skin_bounds(hoppy: Node3D) -> AABB:
	var sk: Skeleton3D = hoppy.skeleton
	sk.force_update_all_bone_transforms()
	var first := true
	var result := AABB()
	for mesh: MeshInstance3D in hoppy._meshes:
		var skin := mesh.skin
		var transforms: Array[Transform3D] = []
		for bind in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(bind))
			transforms.append(sk.global_transform * sk.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for i in vertices.size():
				var point := Vector3.ZERO
				for j in stride:
					var weight := weights[i * stride + j]
					if weight > 0:
						point += (transforms[bones[i * stride + j]] * vertices[i]) * weight
				result = AABB(point, Vector3.ZERO) if first else result.expand(point)
				first = false
	return result
