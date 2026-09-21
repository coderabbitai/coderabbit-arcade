extends RefCounted
## Fixture-only teardown; does not change runtime corridor or audio-service ownership.
static func release(tree: SceneTree, nodes: Array[Node]) -> void:
	for node in nodes:
		if is_instance_valid(node): node.free()
	var audio := tree.root.get_node_or_null("AudioService")
	if audio != null:
		audio._stop_duck()
		for player in [audio.music, audio.sfx]:
			player.stop()
			player.stream = null
		audio.default_track = null
	# Allow the mixer to consume stop commands and release its playback references.
	await tree.create_timer(0.15, true, false, true).timeout
