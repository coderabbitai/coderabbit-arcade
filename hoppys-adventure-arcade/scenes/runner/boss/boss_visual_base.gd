extends Node3D
## Base for boss/visuals/<kind>_visual.tscn (contract §11.5). The backend sets every var below
## before calling on_spawned(), mounts the visual under BossArena/Boss at (0, 2.6, hover_z) and
## frees it once the fight's outro is over (the defeat cinematic, or boss_outro_seconds after a
## retreat); the visual never frees itself and never moves the Boss node.
## The boss has no hitbox: nothing here can damage the player, so the envelope is a drawing budget,
## not a collision one — <= 7 m wide x 4.5 m tall x 3 m deep, bottom edge never below y 1.6,
## <= 40 draw calls at peak. The hover sway is the visual's own job, in _process (PAUSABLE).
@warning_ignore_start("unused_parameter")

## Contract 2.6 §11.14 intro timing, shared by the visuals, the HUD and the camera: by this progress
## the visual has landed its final intro pose and the title card slams; the pose then holds frozen
## until INTRO_HOLD_UNTIL, where the camera leaves the hold (camera_rig.gd BOSS_SHOTS keys its push
## end and its hold end on exactly these values).
const INTRO_POSE_AT := {&"intro_full": 0.40, &"intro_short": 0.28}
const INTRO_HOLD_UNTIL := {&"intro_full": 0.66, &"intro_short": 0.88}

## flaky_test_swarm, merge_conflict_hydra or legacy_monolith.
var kind: StringName = &""
## Display name for a name plate, e.g. "Flaky Test Swarm".
var boss_name := ""
var max_hp := 0
## How many phases this fight has (3 today, contract §11.10 boss_phase_thresholds).
var phase_count := 3
## World z the Boss node hovers at (config.boss_z, -14 by default).
var hover_z := 0.0
## Suggested sway for the idle hover, in metres and seconds (config.boss_sway_*).
var sway_amplitude := 0.0
var sway_period := 1.0

var _cinematic_focus_point := Vector3.ZERO
var _cinematic_focus_read := false

## After the vars above are set, once per fight; reset every tween and particle.
func on_spawned() -> void:
	pass

## On boss_phase_changed: 1-based, raised at the 66 % and 33 % HP thresholds.
func set_phase(phase: int) -> void:
	pass

## On boss_health_changed, including the first one at full HP.
func set_health(hp: int, max_health: int) -> void:
	pass

## On boss_attack_telegraph, `seconds` before the projectiles are fired. `lane_mask` bit i = lane
## index i (x -2 / 0 / +2); `kind` is the projectile variant (orb, low, high, wide).
func play_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	pass

## At the end of the telegraph, once per beat however many projectiles it fired.
func play_attack(projectile_kind: StringName) -> void:
	pass

## A tool landed for `damage` points.
func play_hit(tool_kind: StringName, damage: int) -> void:
	pass

## A tool this phase resists was collected (damage 0).
func play_resist(tool_kind: StringName) -> void:
	pass

## HP reached 0. Contract 2.6 §11.14: the backend frees this node once the defeat cinematic that
## follows is over (boss_outro_seconds when that cinematic has zero length).
func play_defeat() -> void:
	pass

## The fight timed out; the backend frees this node after boss_outro_seconds.
func play_retreat() -> void:
	pass

## Optional (contract 2.6 §11.14): a cinematic of `seconds` opens — the cue to set up. `mode` is
## intro_full / intro_short (straight after on_spawned, alongside boss_intro) or defeat_full /
## defeat_short (straight after play_defeat). The poses themselves follow set_cinematic_progress().
func play_cinematic(mode: StringName, seconds: float) -> void:
	pass

## Optional (contract 2.6 §11.14): where the cinematic is, 0..1. Called with 0 right after
## play_cinematic(), on every physics tick while it runs, once straight after a skip with the jumped
## progress, and once with 1.0 when it ends. Poses, dissolve, flash and strobe are functions of
## `progress`, never of an accumulated clock, so a pause, a skip and the 6x smokes stay in step.
func set_cinematic_progress(mode: StringName, progress: float) -> void:
	pass

## Optional (contract 2.6 §11.14): the defeat's time factor, every tick of a cinematic and 1.0 when it
## ends — 0.05 through the hit-stop, then slow-mo easing back to 1. It scales only this visual's
## ambient motion (idle sway, particles), never the cinematic pose, which set_cinematic_progress()
## owns. The engine time scale is never touched.
func set_time_factor(factor: float) -> void:
	pass

## Optional (contract 2.6 §11.5): the point, in this visual's local space, the cinematic camera aims
## at. The backend reads it once, straight after on_spawned() and before any cinematic cue. The
## default, the centre of the upper third of the visual's rest bounds, is cached on that first read,
## so no later pose can move the aim. Override it to aim somewhere else (a head, a core).
func cinematic_focus() -> Vector3:
	if not _cinematic_focus_read:
		_cinematic_focus_point = rest_focus(self)
		_cinematic_focus_read = true
	return _cinematic_focus_point

## The default focus for any boss root, the backend graybox included: the centre of the upper third
## of rest_bounds(root), or the root's own origin when it carries no mesh.
static func rest_focus(root: Node3D) -> Vector3:
	var bounds := rest_bounds(root)
	if not bounds.has_volume():
		return bounds.get_center()
	return bounds.position + Vector3(bounds.size.x * 0.5, bounds.size.y * 5.0 / 6.0, bounds.size.z * 0.5)

## The combined bounds of every visible MeshInstance3D under `root`, in root's local space. Each mesh
## contributes its own mesh AABB — the rest shape, never a skinned pose — through its transform chain
## up to `root`. A root with nothing visible falls back to every mesh, then to an empty AABB.
static func rest_bounds(root: Node3D) -> AABB:
	if root == null or not is_instance_valid(root):
		return AABB()
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.push_front(root)
	var bounds := _merged_bounds(root, meshes, true)
	return bounds if bounds.has_volume() else _merged_bounds(root, meshes, false)

static func _merged_bounds(root: Node3D, meshes: Array[Node], visible_only: bool) -> AABB:
	var merged := AABB()
	var any := false
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if visible_only and not _visible_under(root, mesh_node):
			continue
		var box := _chain_to(root, mesh_node) * mesh_node.get_aabb()
		merged = box if not any else merged.merge(box)
		any = true
	return merged

## `node`'s transform in `root`'s space, multiplied up the parent chain (no tree needed).
static func _chain_to(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform

static func _visible_under(root: Node3D, node: Node3D) -> bool:
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null and not spatial.visible:
			return false
		current = current.get_parent()
	return true

@warning_ignore_restore("unused_parameter")
