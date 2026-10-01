extends Area2D
const Art = preload("res://modes/platformer/art.gd")
const OrbitalArt = preload("res://modes/platformer/orbital_art.gd")
var velocity := Vector2.ZERO
var lifetime := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
	add_child(Art.shape(Vector2(20, 14)))
	var sprite := OrbitalArt.sprite("hazards", "plasma_bolt")
	sprite.scale = Vector2.ONE * 0.35
	# The bolt lies low in its atlas cell; keep the visual center on the collision path.
	sprite.offset = Vector2(0, -10)
	sprite.rotation = velocity.angle() - PI
	add_child(sprite)
	body_entered.connect(_hit)

func _physics_process(dt: float) -> void:
	lifetime += dt
	var target := global_position + velocity * dt
	var query := PhysicsRayQueryParameters2D.create(global_position, target, 3)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): _hit(hit.collider)
	global_position = target
	if lifetime >= 4 or global_position.x < 0 or global_position.x > 5300 or global_position.y < 30 or global_position.y > 800:
		queue_free()

func _hit(body: Node) -> void:
	if is_queued_for_deletion(): return
	if body.has_method("damage"): body.damage(global_position.x)
	queue_free()
