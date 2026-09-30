extends Area2D
const Art = preload("res://modes/platformer/art.gd")
var velocity := Vector2.ZERO
var lifetime := 0.0
func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	add_child(Art.shape(Vector2(20, 20)))
	var sprite := Art.sprite("interactives", "conflict_zone")
	sprite.scale = Vector2.ONE * 0.32
	add_child(sprite)
	body_entered.connect(_hit)
func _physics_process(dt: float) -> void:
	lifetime += dt
	var next := position + velocity * dt
	# Sweep the flight segment as well as overlap detection to avoid tunnelling.
	var query := PhysicsRayQueryParameters2D.create(global_position, get_parent().to_global(next), 3)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_hit(hit.collider)
	position = next
	if lifetime > 4 or position.x < 4160 or position.x > 4990 or position.y < 80 or position.y > 620:
		queue_free()
func _hit(body: Node) -> void:
	if is_queued_for_deletion(): return
	if body.has_method("damage"):
		body.damage(global_position.x)
	queue_free()
