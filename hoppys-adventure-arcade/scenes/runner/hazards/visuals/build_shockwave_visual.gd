extends "res://scenes/runner/hazards/hazard_visual_base.gd"
const Rig = preload("res://scenes/runner/hazards/visuals/hazard_art.gd")
var _art: Rig

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()

func _build() -> void:
	# Backend mounts before supplying the base vars. Spawn completes this build.
	if hitbox_size == Vector3.ZERO:
		return
	if _art != null:
		# Retire safely even when a pooled spawn occurs during processing.
		_art.name = "RetiredArtwork"
		_art.hide()
		_art.queue_free()
	_art = Rig.new()
	add_child(_art)
	_art.build(&"build_shockwave", variant, hitbox_size, hitbox_offset)

func _process(delta: float) -> void:
	if _art != null:
		_art.advance(delta)

func on_spawned() -> void:
	_build()

func on_hit_player() -> void:
	if _art != null:
		_art.react(false)

func on_cleared() -> void:
	if _art != null:
		_art.react(true)

func set_telegraph(t: float) -> void:
	if _art != null:
		_art.telegraph(t)

func set_laser_state(state: StringName) -> void:
	if _art != null:
		_art.laser_state(state)
