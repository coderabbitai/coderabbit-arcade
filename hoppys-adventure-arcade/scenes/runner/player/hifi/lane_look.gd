extends SkeletonModifier3D
## Applied after imported animation evaluation; SkeletonModifier restores base poses.
var direction := 0.0

func _process_modification() -> void:
	var skeleton := get_skeleton()
	var head := skeleton.find_bone("head")
	if head >= 0:
		var pose := skeleton.get_bone_pose_rotation(head)
		skeleton.set_bone_pose_rotation(head, pose * Quaternion(Vector3.UP, -direction * 0.09))
