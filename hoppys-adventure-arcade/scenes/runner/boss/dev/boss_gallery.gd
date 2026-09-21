extends Node3D
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const FX = preload("res://scenes/runner/boss/boss_fx.tscn")
const HUD = preload("res://scenes/runner/ui/boss_hud.tscn")
const Projectile = preload("res://scenes/runner/hazards/visuals/projectile_visual.tscn")
const KINDS := [&"flaky_test_swarm", &"merge_conflict_hydra", &"legacy_monolith"]
const NAMES := ["FLAKY TEST SWARM", "MERGE CONFLICT HYDRA", "Legacy Monolith"]
const VARIANTS := [&"orb", &"high", &"wide"]
const SIZES := [Vector3(1.6, 0.9, 1.2), Vector3(5.6, 0.4, 1.2), Vector3(3.6, 1, 1.2)]
@export_range(0, 2) var fixture := 0
var camera: Camera3D
var encounter: Node3D
var overlay: Control
var selected := 0
var animate := true
var clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var corridor := Corridor.instantiate()
	add_child(corridor)
	corridor.set_scroll_speed(0.0)
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.position = Vector3(0, 4, 8)
	camera.look_at(Vector3(0, 1, -8))
	camera.fov = 60
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	overlay = HUD.instantiate()
	canvas.add_child(overlay)
	capture_boss(fixture)

func get_boss_info() -> Dictionary:
	return {"kind": KINDS[selected], "name": NAMES[selected], "hp": 60, "max_hp": 100, "phase": 2, "phase_count": 3, "pending_attacks": []}

func capture_boss(index: int) -> void:
	selected = clampi(index, 0, 2)
	if encounter != null:
		remove_child(encounter)
		encounter.free()
	encounter = Node3D.new()
	add_child(encounter)
	var mount := Node3D.new()
	mount.position = Vector3(0, 2.6, -14)
	encounter.add_child(mount)
	var visual := (load("res://scenes/runner/boss/visuals/%s_visual.tscn" % KINDS[selected]) as PackedScene).instantiate() as Node3D
	mount.add_child(visual)
	visual.kind = KINDS[selected]
	visual.boss_name = NAMES[selected]
	visual.max_hp = 100
	visual.phase_count = 3
	visual.hover_z = -14
	visual.sway_amplitude = 0.0
	visual.sway_period = 3.2
	visual.on_spawned()
	visual.set_health(60, 100)
	visual.set_phase(2)
	visual.play_telegraph(2, VARIANTS[selected], 10.0)
	visual._process(0.6)
	visual.set_process(false)
	var fx := FX.instantiate()
	encounter.add_child(fx)
	fx.bind(self)
	fx.telegraphs[1].start(1, VARIANTS[selected], 10.0)
	fx.telegraphs[1]._process(3.5)
	fx.telegraphs[1].set_process(false)
	var projectile := Projectile.instantiate()
	encounter.add_child(projectile)
	projectile.position = Vector3(0, 0, -6)
	projectile.variant = VARIANTS[selected]
	projectile.hitbox_size = SIZES[selected]
	projectile.hitbox_offset = Vector3(0, 1.3 if selected == 1 else SIZES[selected].y * 0.5, 0)
	projectile.closing_speed = 30
	projectile.on_spawned()
	projectile._process(0.2)
	for i in 2:
		var tool_kind: String = ["lint_rule", "unit_test"][i]
		var tool := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % tool_kind) as PackedScene).instantiate() as Node3D
		encounter.add_child(tool)
		tool.position = Vector3(-2 if i == 0 else 2, 1.1, -3 - i * 2)
		tool.on_spawned()
	overlay.bind(self)
	# Capture deterministic settled UI, independent of the host's capture delay.
	for tween in [overlay.slide, overlay.fill, overlay.drain, overlay.pip_flash]:
		if tween != null: tween.kill()
	overlay.panel.position.y = 0
	overlay.panel.modulate = Color.WHITE
	overlay.hp.value = 0.6
	overlay.chip.value = 0.74

func _process(delta: float) -> void:
	if not animate: return
	clock += delta
	if clock >= 6.0:
		clock = 0.0
		capture_boss((selected + 1) % 3)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		animate = not animate
