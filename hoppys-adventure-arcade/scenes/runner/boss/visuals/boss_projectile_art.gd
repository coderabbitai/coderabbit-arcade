extends Node3D
## Per-boss projectile looks for the contract 2.4 signature attacks (§11.6). projectile_visual.gd
## opts into the real variant (`signature_variants`) and hands the shots a boss fires here; any
## other shot keeps hazard_art.gd's base look.
##
## Every mesh and material is built once into a static cache (warm() does it at arena load, from
## boss_fx.gd) and shared by every spawn, so firing a shot allocates nodes only, never resources,
## and no part ever mutates a shared resource. Nothing here reads TIME: advance(age) poses the
## parts from the shot's own `age` (seconds since fire, projectile.gd), so a paused tree freezes
## every look and a scatter half splits on the exact frame its motion does.
##
## Bounds: every part stays inside 110 % of the hitbox, measured from hitbox_offset, except the
## parts tagged with the `ground_projection` meta (floor shadows and skirts), which are exempt on y
## only, as in contract §5.2.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Forge = preload("res://scenes/runner/boss/hifi/forge.gd")
const MeshForge = preload("res://scenes/runner/hazards/visuals/hifi/mesh_forge.gd")
const Screen = preload("res://scenes/runner/boss/hifi/screen.gdshader")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")

## Look ids, one per signature projectile. Swarm orbs (plain or flaky) are test-screen tiles and
## Hydra orbs (plain or branching) are jawed head bolts.
const SWARM_TILE: StringName = &"swarm_tile"
const SWARM_SCATTER: StringName = &"swarm_scatter"
const HYDRA_HEAD: StringName = &"hydra_head"
const HYDRA_SWEEP: StringName = &"hydra_sweep"
const HYDRA_FORCE_PUSH: StringName = &"hydra_force_push"
const MONOLITH_SLAB: StringName = &"monolith_slab"
const MONOLITH_QUAKE: StringName = &"monolith_quake"
const MONOLITH_DEBRIS: StringName = &"monolith_debris"
## Every look with the [boss_kind, variant, signature] that selects it, for tests and warm-up.
const LOOKS := {
	SWARM_TILE: [&"flaky_test_swarm", &"orb", &"flaky"],
	SWARM_SCATTER: [&"flaky_test_swarm", &"scatter", &"scatter"],
	HYDRA_HEAD: [&"merge_conflict_hydra", &"orb", &"branching"],
	HYDRA_SWEEP: [&"merge_conflict_hydra", &"sweep", &"sweep"],
	HYDRA_FORCE_PUSH: [&"merge_conflict_hydra", &"force_push", &"force_push"],
	MONOLITH_SLAB: [&"legacy_monolith", &"slab", &"legacy_wall"],
	MONOLITH_QUAKE: [&"legacy_monolith", &"quake", &"quake"],
	MONOLITH_DEBRIS: [&"legacy_monolith", &"debris", &"debris"],
}
## Seconds per glitch step of a flaky tile (reads as a stutter, not a strobe).
const GLITCH_STEP := 1.0 / 11.0
## Floor-projection height: above the telegraph inset (0.025) is not needed, these move with the
## shot, and stay under the hazard markers' 0.02 / 0.03 planes only in the shot's own footprint.
const GROUND_Y := 0.022
## Art review r1: every projectile is DANGER (art bible). Bodies use the danger_* metals and the
## DANGER glows; MATRIX / LILAC / ORANGE survive only as glyphs and thin accents (<= 25 % of the lit
## area, a5_check "C4 projectile palette").
const MATERIAL_KEYS := ["danger_body", "danger_dark", "danger_stone", "dark", "screen_tile", "screen_merge",
	"glow_matrix", "glow_danger", "glow_lilac", "glow_orange", "glow_cream",
	"add_danger", "add_danger_strong"]
## Palette role of each material key for the lit-area share check: DANGER body/glow, accent
## (MATRIX / LILAC / ORANGE / CREAM), or neither (unlit navy; screens, whose glyph is mostly dark).
const DANGER_KEYS := ["danger_body", "danger_dark", "danger_stone", "glow_danger", "add_danger", "add_danger_strong"]
const ACCENT_KEYS := ["glow_matrix", "glow_lilac", "glow_orange", "glow_cream"]
## Fraction of its box a crack mesh (five thin strokes) actually covers, for the area share.
const CRACK_COVERAGE := 0.14
const MESH_KEYS := ["box", "sphere", "wedge", "shard", "quad", "floor", "tile_check", "tile_cross",
	"crack", "quake_crest", "quake_glow", "quake_ripple"]

static var _cache: Dictionary = {}

var look: StringName = &""
var signature: StringName = &""
var motion := {}
var age := 0.0
var parts: Dictionary = {}
var _rest: Dictionary = {}
var _size := Vector3.ONE
var _offset := Vector3.ZERO
var _twin := false
var _split_at := -1.0
var _land_at := 0.0
var _slide_dir := 0.0
var _shift_at := -1.0
var _shift_end := -1.0
var _sweep_dir := 0.0
var _sweep_end := 0.0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## The look a (variant, boss) shot is drawn with, &"" for hazard_art's base look.
static func look_for(variant: StringName, boss_kind: StringName) -> StringName:
	match variant:
		&"scatter": return SWARM_SCATTER
		&"sweep": return HYDRA_SWEEP
		&"force_push": return HYDRA_FORCE_PUSH
		&"slab": return MONOLITH_SLAB
		&"quake": return MONOLITH_QUAKE
		&"debris": return MONOLITH_DEBRIS
		&"orb":
			if boss_kind == &"flaky_test_swarm": return SWARM_TILE
			if boss_kind == &"merge_conflict_hydra": return HYDRA_HEAD
	return &""

# --- shared resources ---

## Builds every shared mesh and material (idempotent) and returns the cache, so a warm-up can hold
## and draw them. boss_fx.gd calls this when the arena mounts, before any shot is fired.
static func warm() -> Dictionary:
	for key: String in MATERIAL_KEYS: material(key)
	for key: String in MESH_KEYS: mesh(key)
	return _cache

static func release_caches() -> void:
	_cache.clear()

static func _tint(name: String) -> Color:
	match name:
		"matrix": return Palette.MATRIX
		"danger": return Palette.DANGER
		"lilac": return Palette.LILAC
		"orange": return Palette.ORANGE
	return Palette.CREAM

static func material(key: String) -> Material:
	var id := "mat:" + key
	if _cache.has(id): return _cache[id]
	var result: Material
	match key:
		# DANGER metals with a self-glow, so every shot reads as a hazard against the corridor.
		"danger_body": result = _lifted(Forge.metal(Palette.DANGER.lerp(Palette.NAVY_2, 0.3)), Palette.DANGER, 0.55)
		"danger_dark": result = _lifted(Forge.metal(Palette.DANGER.lerp(Palette.NAVY_2, 0.58)), Palette.DANGER, 0.3)
		"danger_stone": result = _lifted(Forge.metal(Palette.DANGER.lerp(Palette.SLATE, 0.45)), Palette.DANGER, 0.4)
		"dark": result = Forge.metal(Palette.NAVY_2)
		"screen_tile", "screen_merge":
			var screen := ShaderMaterial.new()
			screen.shader = Screen
			screen.set_shader_parameter("accent", Palette.DANGER if key == "screen_tile" else Palette.LILAC)
			screen.set_shader_parameter("instance_accent", key == "screen_tile")
			screen.set_shader_parameter("symbol", 1 if key == "screen_tile" else 2)
			result = screen
		_:
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.cull_mode = BaseMaterial3D.CULL_DISABLED
			glow.albedo_color = _tint(key.get_slice("_", 1))
			if key.begins_with("add_"):
				glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				glow.albedo_color.a = 0.75 if key.ends_with("_strong") else 0.38
			result = glow
	_cache[id] = result
	return result

static func _lifted(metal: StandardMaterial3D, glow: Color, energy: float) -> StandardMaterial3D:
	metal.emission_enabled = true
	metal.emission = glow
	metal.emission_energy_multiplier = energy
	return metal

static func mesh(key: String) -> Mesh:
	var id := "mesh:" + key
	if _cache.has(id): return _cache[id]
	var result: Mesh
	match key:
		"box": result = MeshForge.bevel_box()
		"sphere": result = MeshForge.sphere()
		"wedge": result = MeshForge.wedge()
		"shard": result = MeshForge.shard()
		"quad":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			result = quad
		"floor":
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE
			result = plane
		"tile_check", "tile_cross": result = _tile_quad(Palette.MATRIX if key == "tile_check" else Palette.DANGER)
		"crack": result = _crack()
		"quake_crest": result = _arc(0.42, 0.16, 0.0)
		"quake_glow": result = _arc(0.1, 0.05, 0.13)
		"quake_ripple": result = _arc(0.0, 0.2, -0.12)
	_cache[id] = result
	return result

## A unit quad whose vertex colour picks the screen shader's check (MATRIX) or cross (DANGER).
static func _tile_quad(tint: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	for index: int in [0, 2, 1, 0, 3, 2]:
		var p: Vector2 = corners[index]
		st.set_color(tint)
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(p.x + 0.5, 0.5 - p.y))
		st.add_vertex(Vector3(p.x, p.y, 0))
	return st.commit()

## A zigzag fissure across a unit front face: five bevelled strokes in one surface.
static func _crack() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector2(-0.12, 0.5), Vector2(0.1, 0.24), Vector2(-0.08, 0.02), Vector2(0.16, -0.2), Vector2(-0.04, -0.34), Vector2(0.06, -0.5)]
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var direction := b - a
		var stroke := Basis(Vector3.BACK, atan2(-direction.x, direction.y)).scaled_local(Vector3(0.07, direction.length() * 1.12, 0.06))
		st.append_from(MeshForge.bevel_box(), 0, Transform3D(stroke, Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0)))
	return st.commit()

## The quake crest: a band along a circle of radius 4.9 m centred 4.4 m behind the shot, so it
## spans x ±2.9 m (inside the 5.6 m hitbox) and bulges 0.5 m toward the player at the middle.
## `height` 0 builds a flat floor ribbon instead of a wave wall.
static func _arc(height: float, thickness: float, radial_offset: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 4.9 + radial_offset
	var reach := asin(2.9 / 4.9)
	var segments := 40
	var half := thickness * 0.5
	for i in segments:
		var a0 := lerpf(-reach, reach, float(i) / segments)
		var a1 := lerpf(-reach, reach, float(i + 1) / segments)
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var c0 := d0 * radius + Vector3(0, 0, -4.4)
		var c1 := d1 * radius + Vector3(0, 0, -4.4)
		if height <= 0.0:
			_quad(st, c0 - d0 * half, c1 - d1 * half, c1 + d1 * half, c0 + d0 * half, Vector3.UP)
			continue
		# A wave profile: steep front face, longer back slope.
		var top := Vector3(0, height, 0)
		var f0 := c0 + d0 * half
		var f1 := c1 + d1 * half
		var b0 := c0 - d0 * half * 1.8
		var b1 := c1 - d1 * half * 1.8
		var k0 := c0 + d0 * half * 0.3 + top
		var k1 := c1 + d1 * half * 0.3 + top
		_quad(st, f0, f1, k1, k0, (d0 + d1).normalized() + Vector3.UP * 0.2)
		_quad(st, k0, k1, b1, b0, -(d0 + d1).normalized() + Vector3.UP)
		if i == 0: _tri(st, f0, k0, b0, Vector3(-cos(a0), 0, sin(a0)))
		if i == segments - 1: _tri(st, f1, b1, k1, Vector3(cos(a1), 0, -sin(a1)))
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(st, a, b, c, outward)
	_tri(st, a, c, d, outward)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# Godot fronts are clockwise seen from outside.
	var points := [a, b, c]
	if (b - a).cross(c - a).dot(outward) > 0.0: points = [a, c, b]
	for p: Vector3 in points:
		st.set_uv(Vector2(p.x * 0.5, p.z + p.y))
		st.add_vertex(p)

static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)

# --- build ---

func _part(title: String, mesh_key: String, material_key: String, pos: Vector3, size: Vector3, rotation_value := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.mesh = mesh(mesh_key)
	node.material_override = material(material_key)
	node.set_meta("material_key", material_key)
	node.position = pos
	node.rotation = rotation_value
	node.scale = size
	(parent if parent != null else self).add_child(node)
	parts[title] = node
	_rest[title] = node.transform
	return node

## Once per spawn, after projectile_visual.gd received the contract §11.6 vars.
func build(value: StringName, size: Vector3, offset: Vector3, shot: Dictionary = {}, signature_value: StringName = &"") -> void:
	name = "BossProjectileArt"
	look = value
	signature = signature_value
	motion = shot
	_size = size
	_offset = offset
	_twin = bool(shot.get("twin", false))
	_land_at = float(shot.get("land_at", 0.0))
	var keys: PackedVector2Array = shot.get("x_keys", PackedVector2Array())
	if look == SWARM_SCATTER and keys.size() >= 2: _split_at = keys[1].x
	if look == MONOLITH_SLAB and keys.size() >= 3:
		_shift_at = keys[1].x
		_shift_end = keys[2].x
		_slide_dir = signf(keys[2].y - keys[1].y)
	if look == HYDRA_SWEEP and keys.size() >= 2:
		_sweep_dir = signf(keys[keys.size() - 1].y - keys[0].y)
		_sweep_end = keys[keys.size() - 1].x
	var c := offset
	match look:
		SWARM_TILE:
			_part("TileFrame", "box", "danger_body", c, Vector3(0.86, 0.74, 0.34))
			_part("TileScreen", "tile_cross", "screen_tile", c + Vector3(0, 0, 0.176), Vector3(0.64, 0.52, 1))
			for i in 3:
				_part("GlitchShard%d" % i, "box", "glow_matrix" if i == 1 else "glow_danger", c + Vector3((i - 1) * 0.5, 0.2 - i * 0.18, -0.1), Vector3(0.2, 0.16, 0.08))
		SWARM_SCATTER:
			for side: int in [-1, 1]:
				var half := "L" if side < 0 else "R"
				_part(half + "Half", "box", "danger_body", c + Vector3(side * 0.23, 0, 0), Vector3(0.42, 0.6, 0.42))
				_part(half + "Screen", "tile_cross" if side < 0 else "tile_check", "screen_tile", c + Vector3(side * 0.23, 0, 0.212), Vector3(0.3, 0.4, 1))
			_part("SplitSeam", "box", "glow_matrix", c, Vector3(0.04, 0.62, 0.44))
		HYDRA_HEAD:
			# Wide enough to read from the chase camera (>= 16 px at 30 m): 1.3 m of DANGER jaw.
			_part("UpperJaw", "wedge", "danger_body", c + Vector3(0, 0.1, 0.04), Vector3(1.3, 0.4, 0.9))
			_part("LowerJaw", "wedge", "dark", c + Vector3(0, -0.17, 0.02), Vector3(1.1, 0.22, 0.8), Vector3(0, 0, PI))
			_part("Maw", "quad", "glow_danger", c + Vector3(0, -0.04, 0.25), Vector3(0.92, 0.2, 1))
			_part("Eyes", "box", "glow_lilac", c + Vector3(0, 0.25, 0.12), Vector3(0.8, 0.09, 0.06))
			for i in 2:
				_part("Neck%d" % i, "box", "danger_dark", c + Vector3(0, 0.02, -0.38 - i * 0.14), Vector3(0.5 - i * 0.08, 0.32 - i * 0.05, 0.2))
		HYDRA_SWEEP:
			# The rebase serpent: five DANGER segments, 0.9 m across at the head.
			for i in 5:
				var taper := lerpf(1.0, 0.5, i / 4.0)
				_part("Segment%d" % i, "sphere", "danger_body" if i == 0 else "danger_dark", c + Vector3(0, -0.02 * i, 0.2 - i * 0.18), Vector3(0.9, 0.5, 0.44) * taper)
			_part("SerpentEyes", "box", "glow_lilac", c + Vector3(0, 0.07, 0.38), Vector3(0.5, 0.08, 0.05))
		HYDRA_FORCE_PUSH:
			_part("MergeBlock", "box", "danger_body", c + Vector3(0, 0, -0.08), Vector3(3.3, 0.86, 0.8))
			_part("ConflictFace", "box", "danger_dark", c + Vector3(0, 0, 0.33), Vector3(3.0, 0.62, 0.06))
			_part("MergeGlyph", "quad", "screen_merge", c + Vector3(0, 0, 0.365), Vector3(1.3, 0.54, 1))
			for side: int in [-1, 1]:
				_part("Seam" + ("Top" if side > 0 else "Bottom"), "box", "glow_lilac", c + Vector3(0, side * 0.4, 0.33), Vector3(3.2, 0.04, 0.05))
				_part("PushPlate%d" % side, "box", "glow_danger", c + Vector3(side * 1.7, 0, -0.08), Vector3(0.06, 0.8, 0.72))
		MONOLITH_SLAB:
			# 2.5 m of DANGER stone (>= 60 px tall from the chase camera at the boss).
			_part("StoneSlab", "box", "danger_stone", c + Vector3(0, 0.05, 0), Vector3(1.8, 2.5, 0.9))
			_part("Fissure", "crack", "glow_orange", c + Vector3(0, 0.05, 0.456), Vector3(0.9, 2.2, 1))
			for side: int in [-1, 1]:
				_part("GapEdge%d" % side, "box", "glow_orange", c + Vector3(side * 0.92, 0.05, 0.44), Vector3(0.05, 2.4, 0.05))
			var chevron := Node3D.new()
			chevron.name = "SlideChevron"
			chevron.process_mode = Node.PROCESS_MODE_PAUSABLE
			chevron.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			chevron.position = c + Vector3(0, -0.55, 0.47)
			chevron.scale.x = _slide_dir if _slide_dir != 0.0 else 1.0
			add_child(chevron)
			for arm: int in [-1, 1]:
				_part("ChevronArm%d" % arm, "box", "glow_cream", Vector3(0, arm * 0.13, 0), Vector3(0.36, 0.07, 0.03), Vector3(0, 0, -arm * 0.8), chevron)
			_rest["SlideChevron"] = chevron.transform
			parts["SlideChevron"] = chevron
			_part("FloorSkirt", "floor", "add_danger", Vector3(c.x, GROUND_Y, c.z), Vector3(1.9, 1, 1.1)).set_meta("ground_projection", true)
		MONOLITH_QUAKE:
			var floor_level := c - Vector3(0, _size.y * 0.5, 0)
			_part("QuakeCrest", "quake_crest", "danger_stone", floor_level, Vector3.ONE)
			_part("QuakeGlow", "quake_glow", "glow_orange", floor_level, Vector3.ONE)
			_part("QuakeRipple", "quake_ripple", "add_danger", floor_level + Vector3(0, GROUND_Y, 0), Vector3.ONE).set_meta("ground_projection", true)
			for i in 4:
				var angle := lerpf(-0.5, 0.5, i / 3.0)
				var point := Vector3(sin(angle) * 4.9, 0, cos(angle) * 4.9 - 4.4)
				_part("Rubble%d" % i, "shard", "danger_stone", c + Vector3(point.x, -0.1, point.z - 0.08), Vector3.ONE * 0.16, Vector3(i, i * 2.0, 0))
		MONOLITH_DEBRIS:
			_part("DebrisChunk", "box", "danger_stone", c, Vector3(0.7, 0.6, 0.7))
			_part("DebrisCrack", "crack", "glow_orange", c + Vector3(0, 0, 0.356), Vector3(0.36, 0.56, 1))
			for side: int in [-1, 1]:
				_part("DebrisShard%d" % side, "shard", "danger_stone", c + Vector3(side * 0.4, -0.18, side * 0.08), Vector3(0.26, 0.26, 0.26), Vector3(0, side, 0))
			_part("GroundShadow", "floor", "add_danger", Vector3(c.x, GROUND_Y, c.z), Vector3(0.5, 1, 0.4)).set_meta("ground_projection", true)
	advance(0.0)

## Metres the shot is lifted above its landed y range at `t` (only a falling debris slab is).
func motion_lift(t: float) -> float:
	return BossAttacks.y_offset_at(motion, t) if not motion.is_empty() else 0.0

func _pose(title: String) -> Node3D:
	var node := parts[title] as Node3D
	node.transform = _rest[title]
	return node

# --- animation ---

## Poses every part for `seconds` since fire. Allocation-free: transforms, visibility and swaps
## between cached resources only.
func advance(seconds: float) -> void:
	age = maxf(seconds, 0.0)
	match look:
		SWARM_TILE: _advance_tile()
		SWARM_SCATTER: _advance_scatter()
		HYDRA_HEAD: _advance_head()
		HYDRA_SWEEP: _advance_sweep()
		HYDRA_FORCE_PUSH: _advance_push()
		MONOLITH_SLAB: _advance_slab()
		MONOLITH_QUAKE: _advance_quake()
		MONOLITH_DEBRIS: _advance_debris()

## A flaky test: the screen flips PASS/FAIL and shards of it tear off on a stuttering step. A plain
## swarm orb is a steady FAIL tile with its shards in orbit.
func _advance_tile() -> void:
	var flaky := signature == &"flaky"
	var step := floorf(age / GLITCH_STEP)
	var frame := _pose("TileFrame")
	var screen := _pose("TileScreen") as MeshInstance3D
	if flaky:
		var tear := (_hash(step * 1.7) - 0.5) * 0.08
		frame.position.x += tear
		screen.position.x += tear * 1.6
		screen.mesh = mesh("tile_check" if _hash(step) > 0.5 else "tile_cross")
	else:
		screen.mesh = mesh("tile_cross")
	for i in 3:
		var shard := _pose("GlitchShard%d" % i) as MeshInstance3D
		if flaky:
			var h := _hash(step * 3.1 + i * 7.3)
			shard.visible = h > 0.25
			shard.position = _offset + Vector3((_hash(step + i) - 0.5) * 1.3, (_hash(step * 2.0 + i) - 0.5) * 0.7, (_hash(step * 5.0 + i) - 0.5) * 0.9)
			# Mostly DANGER; one shard in five glitches MATRIX.
			shard.material_override = material("glow_matrix" if h > 0.8 else "glow_danger")
		else:
			var angle := age * 5.0 + i * TAU / 3.0
			shard.position = _offset + Vector3(cos(angle) * 0.58, sin(angle) * 0.3, -0.1)

## One orb down the middle whose MATRIX seam widens until the split; from then on each half keeps
## its own side (the twin is hidden inside the first until then, contract §11.6).
func _advance_scatter() -> void:
	var split := _split_at >= 0.0 and age >= _split_at
	visible = split or not _twin
	var own := "R" if _twin else "L"
	var step := floorf(age / GLITCH_STEP)
	for half: String in ["L", "R"]:
		var shown := (half == own) if split else not _twin
		var body := _pose(half + "Half")
		var screen := _pose(half + "Screen") as MeshInstance3D
		body.visible = shown
		screen.visible = shown
		# A FAIL cross that glitches to PASS now and then (MATRIX stays a glyph accent).
		screen.mesh = mesh("tile_check" if _hash(step + (0.0 if half == "L" else 5.0)) > 0.82 else "tile_cross")
	var seam := _pose("SplitSeam")
	if split:
		# The torn face glows on the inside of each half while it slides out.
		var fade := clampf((age - _split_at) / (BossAttacks.SPLIT_SECONDS * 3.0), 0.0, 1.0)
		seam.position.x += 0.03 if _twin else -0.03
		seam.scale.x = lerpf(0.1, 0.03, fade)
	else:
		var build_up := clampf(age / _split_at, 0.0, 1.0) if _split_at > 0.0 else 0.0
		seam.scale.x = lerpf(0.03, 0.1, build_up * build_up)
		seam.scale.y *= 0.8 + 0.2 * _hash(step)

## A jawed head bolt: the jaws chomp and a short neck whips behind it.
func _advance_head() -> void:
	var bite := 0.5 + 0.5 * sin(age * 18.0)
	_pose("UpperJaw").rotation.x = -0.28 * bite
	var lower := _pose("LowerJaw")
	lower.rotation = Vector3(0.3 * bite, 0, PI)
	_pose("Maw").scale.y = lerpf(0.06, 0.2, bite)
	_pose("Eyes")
	for i in 2:
		_pose("Neck%d" % i).position.x += sin(age * 11.0 - i * 1.3) * 0.12 * (i + 1)

## The rebase serpent: a sine runs down the body; the head turns into the sweep until it lands.
func _advance_sweep() -> void:
	var turning := age < _sweep_end
	for i in 5:
		var segment := _pose("Segment%d" % i)
		segment.position.x += sin(age * 10.0 - i * 1.15) * (0.12 + i * 0.07)
		if i == 0 and turning: segment.rotation.y = _sweep_dir * 0.45
	var eyes := _pose("SerpentEyes")
	eyes.position.x = parts["Segment0"].position.x
	if turning: eyes.rotation.y = _sweep_dir * 0.45

## A merge block being shoved: it surges on a short stroke and its push plates flare.
func _advance_push() -> void:
	var stroke := absf(sin(age * 9.0))
	for title: String in ["MergeBlock", "ConflictFace", "MergeGlyph", "SeamTop", "SeamBottom"]:
		_pose(title).position.z += 0.07 * stroke
	for side: int in [-1, 1]:
		_pose("PushPlate%d" % side).scale.y = lerpf(0.55, 1.0, stroke)

## A wall slab; the one that slides into the old gap blinks a chevron toward it, then holds it
## solid while it slides.
func _advance_slab() -> void:
	for title: String in ["StoneSlab", "Fissure", "GapEdge-1", "GapEdge1", "FloorSkirt"]: _pose(title)
	var chevron := _pose("SlideChevron")
	chevron.visible = _slide_dir != 0.0 and age < _shift_end
	if chevron.visible:
		var sliding := age >= _shift_at
		chevron.visible = sliding or fmod(age, 0.2) < 0.13
		chevron.position.x += _slide_dir * (0.18 if sliding else 0.06 * sin(age * 20.0))

## A shockwave: the glow line pulses, the floor ripple breathes and loose rubble hops the crest.
func _advance_quake() -> void:
	_pose("QuakeCrest")
	_pose("QuakeGlow").scale.y = 0.75 + 0.25 * absf(sin(age * 16.0))
	_pose("QuakeRipple").scale.x = 1.0 + 0.05 * sin(age * 12.0)
	for i in 4:
		var rubble := _pose("Rubble%d" % i)
		rubble.position.y += absf(sin(age * 13.0 + i * 1.9)) * 0.2
		rubble.rotation += Vector3(age * 6.0, age * 4.0, 0)

## A falling chunk: it spins while its floor shadow grows beneath it, then lands and sits.
func _advance_debris() -> void:
	var falling := _land_at > 0.0 and age < _land_at
	var fall := clampf(age / _land_at, 0.0, 1.0) if _land_at > 0.0 else 1.0
	var spin_age := age if falling else _land_at
	# Spin about y (bounded by the square footprint) and rock about x (bounded height).
	var pivot := Transform3D(Basis(Vector3.UP, spin_age * 4.0) * Basis(Vector3.RIGHT, 0.25 * sin(spin_age * 7.0)), _offset) * Transform3D(Basis.IDENTITY, -_offset)
	for title: String in ["DebrisChunk", "DebrisCrack", "DebrisShard-1", "DebrisShard1"]:
		var node := _pose(title)
		node.transform = pivot * node.transform
	var shadow := _pose("GroundShadow") as MeshInstance3D
	shadow.position.y = GROUND_Y - motion_lift(age)
	var grow := lerpf(0.35, 1.0, fall * fall)
	var impact := 0.0 if falling else clampf(1.0 - (age - _land_at) / 0.25, 0.0, 1.0)
	shadow.scale = Vector3(1.5 * grow * (1.0 + 0.12 * impact), 1, 1.1 * grow * (1.0 + 0.12 * impact))
	shadow.material_override = material("add_danger_strong" if impact > 0.0 or fall > 0.8 else "add_danger")

# --- palette share (art review r1) ---

## The front (camera-facing) area of the visible parts split by palette role, as
## Vector2(DANGER area, accent area), in m². Screens and unlit navy count as neither. Used by
## a5_check to keep every look DANGER-dominant; the corridor capture measures the real pixels.
## Needs the look inside the tree.
func palette_area() -> Vector2:
	var result := Vector2.ZERO
	for title: String in parts:
		var node := parts[title] as MeshInstance3D
		if node == null or not node.is_visible_in_tree(): continue
		var key := String(node.get_meta("material_key", ""))
		if node.has_meta("ground_projection"): continue
		var box: AABB = global_transform.affine_inverse() * node.global_transform * node.get_aabb()
		var area := box.size.x * box.size.y
		if node.mesh == mesh("crack"): area *= CRACK_COVERAGE
		if DANGER_KEYS.has(key): result.x += area
		elif ACCENT_KEYS.has(key): result.y += area
	return result
