extends "res://scenes/runner/hazards/hazard_visual_base.gd"
## Boss projectile visual (contract §11.6). A shot a boss fires with a look of its own (contract
## 2.4 signature variants, and each boss's plain orb) is drawn by boss/visuals/boss_projectile_art.gd;
## every other shot keeps hazard_art.gd's base look for the variant it maps to.
const Rig = preload("res://scenes/runner/hazards/visuals/hazard_art.gd")
const BossArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
## Contract 2.4: this visual draws the real signature variant, so projectile.gd hands it over as
## `variant` (and as `projectile_variant`) instead of the base look.
var signature_variants := true
var projectile_variant: StringName = &""
var boss_kind: StringName = &""
var signature: StringName = &""
var motion := {}
var _art: Node3D
## Seconds since fire: the host projectile's own `age` when mounted on one, else accumulated.
var _age := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	if _art != null:
		remove_child(_art)
		_art.queue_free()
		_art = null
	_age = 0.0
	var real := projectile_variant if projectile_variant != &"" else variant
	var look := BossArt.look_for(real, boss_kind)
	if look != &"":
		var art := BossArt.new()
		_art = art
		add_child(art)
		art.build(look, hitbox_size, hitbox_offset, motion, signature)
		art.advance(_host_age())
	else:
		var rig := Rig.new()
		_art = rig
		add_child(rig)
		rig.build(&"projectile", HazardDefs.projectile_look(real), hitbox_size, hitbox_offset)
	show()

func _host_age() -> float:
	var host := get_parent()
	if host != null and &"age" in host: return float(host.get(&"age"))
	return _age

func _process(delta: float) -> void:
	if _art == null: return
	if _art is BossArt:
		_age = _age + delta
		_art.advance(_host_age())
	else:
		_art.advance(delta*maxf(closing_speed/20.0,1.0))

func on_hit_player() -> void:
	hide()

func on_cleared() -> void:
	hide()
