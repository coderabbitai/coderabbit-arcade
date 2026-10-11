extends "res://scenes/runner/environment/corridor.gd"
## Visual-only replacement retaining the existing corridor lifecycle and facade.
const Starship = preload("res://scenes/runner/environment/starship/starship_world.gd")
var starship: Node3D

func _ready() -> void:
	retro_scale = 0.85
	super._ready()
	# Keep the original corridor implementation available for legacy fixtures.
	# Its old geometry is hidden, never layered over the starship or drawn.
	for child in get_children():
		if child is GeometryInstance3D:
			child.visible = false
		if child is GPUParticles3D:
			child.emitting = false
	starship = Node3D.new()
	starship.set_script(Starship)
	add_child(starship)
	_environment.background_color = Color("08111f")
	_environment.ambient_light_color = Color("94abc3")
	_environment.ambient_light_energy = 0.34
	_environment.fog_depth_begin = 24.0
	_environment.fog_depth_end = 96.0
	_environment.adjustment_saturation = 0.95
	_sun.light_energy = 0.68
	_sun.rotation_degrees = Vector3(-48,-28,0)
	# The legacy KeyLight keeps its palette tuning for the legacy fixtures and is switched off; the
	# starship's own key sits in the same place, so the lit result is unchanged.
	var legacy_key := get_node("KeyLight") as OmniLight3D
	legacy_key.visible = false
	var key := OmniLight3D.new()
	key.name = "StarshipKeyLight"
	key.position = legacy_key.position
	key.light_color = Color("e9edf5")
	key.light_energy = 0.35
	key.omni_range = 5.0
	key.shadow_enabled = false
	key.process_mode = Node.PROCESS_MODE_PAUSABLE
	key.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(key)
	set_pursuit(_pursuit)
	starship.sync(_offset,_clock,global_transform,boss_arena,0.0)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(starship):
		starship.sync(_offset,_clock,global_transform,boss_arena,delta)

## The starship keeps the legacy glyph rain and speed streaks hidden; only a visible emitter is
## touched, so a frame that finds them already off writes nothing.
func _refresh_dressing() -> void:
	super._refresh_dressing()
	if is_instance_valid(_rain) and (_rain.visible or _rain.emitting):
		_rain.visible = false
		_rain.emitting = false
	if is_instance_valid(_speed_lines) and (_speed_lines.visible or _speed_lines.emitting):
		_speed_lines.visible = false
		_speed_lines.emitting = false

func set_pursuit(t: float) -> void:
	super.set_pursuit(t)
	if _environment != null:
		_environment.fog_light_color = Color("102236").lerp(Color("422b29"),_pursuit*0.6)
		_sun.light_color = Color("c4d6e8").lerp(Color("edb19a"),_pursuit*0.45)
