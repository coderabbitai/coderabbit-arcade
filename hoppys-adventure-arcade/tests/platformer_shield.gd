## The Approve Shield shows as a bubble around Hoppy, not as a tint on the sprite.
##
## Runs headless against Bay Area Blitz, the shared platformer level. Covers: the bubble is
## hidden on spawn, appears when the shield is gained, replaces the old green tint, pops when
## the shield absorbs a hit (and the hit still costs no health), hides once the pop finishes,
## reopens for a second pickup, and clears instantly on death.
extends SceneTree
var failures := 0
var level
var player


func _initialize() -> void: call_deferred("run")


func frames(count: int) -> void:
	for i in count: await physics_frame


func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1


func run() -> void:
	change_scene_to_file("res://scenes/platformer/bay_area_blitz.tscn")
	await frames(12)
	level = current_scene
	player = level.player
	await process_frame
	level._resume()
	var bubble: Node2D = player.bubble
	check(bubble != null and bubble.get_parent() == player, "The player owns a shield bubble child")
	check(bubble.get_index() > player.sprite.get_index() and bubble.z_index >= player.sprite.z_index,
		"The bubble draws in front of Hoppy's sprite")
	check(not bubble.visible and not bubble.active, "The bubble is hidden before any pickup")
	player.boost = 0
	player.invulnerable = 0
	player.shield = true
	check(bubble.visible and bubble.active, "Gaining the shield raises the bubble")
	await frames(3)
	check(player.sprite.modulate == Color.WHITE, "The shield no longer tints Hoppy green")
	check(bubble.visible and bubble.active, "The bubble stays while the shield holds")
	player.hp = 3
	player.damage(0)
	check(player.hp == 3 and not player.shield, "The shield still absorbs one hit without health loss")
	check(not bubble.active, "Absorbing a hit pops the bubble")
	await frames(30)
	check(not bubble.visible, "The popped bubble is hidden once its pop animation ends")
	# The blink and boost tints survive the change.
	check(player.invulnerable > 0, "Absorbing a hit still grants invulnerability")
	player.boost = 5
	await frames(2)
	check(player.sprite.modulate.r < 1.0, "The LGTM boost tint still shows")
	player.boost = 0
	player.invulnerable = 0
	# A second pickup reopens the bubble even if it was still popping.
	player.shield = true
	player.shield = false
	player.shield = true
	check(bubble.visible and bubble.active and bubble.modulate.a == 1.0,
		"A new shield reopens a popping bubble at full strength")
	player.shield = true
	check(bubble.active, "Setting an already-held shield is a no-op")
	# The level's real pickup path raises it too.
	player.shield = false
	await frames(30)
	var shield_item: Dictionary = {}
	for item in level.pickups:
		if item.kind == "approve_shield": shield_item = item
	check(not shield_item.is_empty(), "Bay Area still has an Approve Shield pickup")
	if not shield_item.is_empty():
		player.invulnerable = 999
		player.position = shield_item.origin
		player.velocity = Vector2.ZERO
		await frames(4)
		check(player.shield and bubble.visible and bubble.active,
			"Collecting the pickup raises the bubble")
	# Death clears it without waiting on an animation.
	player.invulnerable = 0
	player.hp = 1
	player.shield = true
	player.shield = false
	player.damage(0)
	check(player.hp == 0 and not bubble.visible and not bubble.active,
		"Death clears the bubble at once")
	print("Shield bubble suite finished with %d failure(s)" % failures)
	await process_frame
	quit(1 if failures > 0 else 0)
