extends Node3D
## CPU-owned instance poses make the animation and its bounds testable headlessly.
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Forge = preload("res://scenes/runner/boss/hifi/forge.gd")
const ArcMetal = preload("res://scenes/runner/boss/hifi/arc_metal.gdshader")
const Screen = preload("res://scenes/runner/boss/hifi/screen.gdshader")
var batches: Array[Dictionary] = []
var state := &"idle"
var phase := 1
var health := 1.0
var clock := 0.0
var age := 0.0
var duration := 0.0
var aim := 0.0
var boss_kind := &""
var core: MeshInstance3D
var ring: MeshInstance3D
var tag: Label3D
var heads: Array[Node3D] = []
var eyes: MultiMeshInstance3D
var faces: MultiMeshInstance3D
const NECK_SEGMENTS := 7
const FACE_POSITION := Vector3(0, 0.83, 0.54)
const FACE_SIZE := Vector3(0.68, 0.42, 0.015)
const EYE_POSITION := Vector3(0, 1.32, 0.62)
const EYE_SIZE := Vector3(0.76, 0.10, 0.035)
var shader_materials: Array[ShaderMaterial] = []
var flashes: Array[StandardMaterial3D] = []
var rest_poses: Dictionary = {}
var motes: GPUParticles3D
static var PLATING := Palette.SLATE.lerp(Palette.CREAM, 0.32)
## Contract 2.4 signature reactions. `mode` is the signature the current telegraph belongs to
## (&"wall", &"quake", &"debris" for the Monolith, &"" otherwise), `wall_mask` its lanes;
## `commit_age` counts from a flaky commit (-1 before one); `head_recoil` holds each Hydra head's
## seconds since its recoil started (negative while staggered, >= HEAD_RECOIL when at rest).
var mode: StringName = &""
var wall_mask := 0
var commit_age := -1.0
var head_recoil := PackedFloat32Array([9.0, 9.0, 9.0, 9.0])
const HEAD_RECOIL := 0.38
const SIGNATURE_MODES := {&"slab": &"wall", &"quake": &"quake", &"debris": &"debris"}
const WALL_PUSH := 0.5
const QUAKE_RISE := 0.22

static func shape(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return shape(parent, Forge.bevel_box(size, 0.09), pos, Forge.metal(color))

static func sphere(parent: Node3D, pos: Vector3, diameter: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	mesh.radial_segments = 32
	mesh.rings = 32
	return shape(parent, mesh, pos, Forge.metal(color))

static func torus(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.92
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 12
	var node := shape(parent, mesh, Vector3(0, 0.55, 0), Materials.additive(color, 0.55))
	node.rotation.x = PI / 2
	return node

static func label(parent: Node3D, words: String, pos: Vector3, pixels: float = 0.006) -> Label3D:
	var node := Materials.label(parent, words, 44, Palette.CREAM)
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.pixel_size = pixels
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	node.outline_size = 10
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.position = pos
	return node

func _init() -> void:
	# Cosmetic transforms are animated on render frames, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_mode = Node.PROCESS_MODE_PAUSABLE

func batch(poses: Array[Transform3D], color: Color) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh := Forge.bevel_box(Vector3.ONE)
	multi.mesh = mesh
	multi.instance_count = poses.size()
	node.multimesh = multi
	var material := Forge.metal(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	node.material_override = material
	flashes.append(material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	batches.append({"node": node, "rest": poses.duplicate(), "poses": poses.duplicate(), "color": color, "colors": []})
	for i in poses.size():
		multi.set_instance_transform(i, poses[i])
		multi.set_instance_color(i, color)
		batches.back().colors.append(color)
	return node

static func pose(pos: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)

func screen(parent: Node3D, pos: Vector3, size: Vector2, accent: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := ShaderMaterial.new()
	material.shader = Screen
	material.set_shader_parameter("accent", accent)
	shader_materials.append(material)
	return shape(parent, mesh, pos, material)

func build(value: StringName) -> void:
	if core != null: return
	boss_kind = value
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var poses: Array[Transform3D] = []
	match value:
		&"flaky_test_swarm":
			for i in 24:
				poses.append(pose(swarm_origin(i, 1, 0.0), Vector3(0.72, 0.64, 0.26)))
			batch(poses, PLATING)
			var screens: Array[Transform3D] = []
			for item in poses:
				var front := item
				front.origin.z += 0.145
				front.basis = Basis.from_scale(Vector3(0.30, 0.25, 0.02))
				screens.append(front)
			var panels := batch(screens, Palette.DANGER)
			var panel_material := ShaderMaterial.new()
			panel_material.shader = Screen
			panel_material.set_shader_parameter("accent", Palette.DANGER)
			panel_material.set_shader_parameter("instance_accent", true)
			panel_material.set_shader_parameter("symbol", 1)
			panels.material_override = panel_material
			shader_materials.append(panel_material)
			var arc_poses: Array[Transform3D] = []
			for i in 24: arc_poses.append(swarm_arc_pose(i, 1, 0.0))
			var arcs := batch(arc_poses, PLATING)
			arcs.name = "SwarmMetalArcs"
			arcs.multimesh.mesh = Forge.recessed_arc_segment()
			var arc_material := ShaderMaterial.new()
			arc_material.shader = ArcMetal
			arc_material.set_shader_parameter("base_color", PLATING)
			arc_material.set_shader_parameter("accent", Palette.MATRIX)
			for key in Forge.textures(): arc_material.set_shader_parameter(key + "_map", Forge.textures()[key])
			arcs.material_override = arc_material
			shader_materials.append(arc_material)
			core = shape(self, Forge.reactor_housing(), Vector3(0,0.85,0), Forge.metal(PLATING))
			core.name = "ReactorHousing"
			var bands := SurfaceTool.new()
			bands.begin(Mesh.PRIMITIVE_TRIANGLES)
			for depth in [-0.20, 0.24]:
				bands.append_from(Forge.forged_band(0.84,0.12,0.14),0,Transform3D(Basis.IDENTITY,Vector3(0,0,depth)))
			shape(core,bands.commit(),Vector3.ZERO,Forge.metal(PLATING)).name = "ContainmentBands"
			shape(core,Forge.reactor_vents(),Vector3.ZERO,luminous(Palette.MATRIX)).name = "RecessedVents"
			var heart_material := ShaderMaterial.new()
			heart_material.shader = preload("res://scenes/runner/boss/hifi/reactor.gdshader")
			heart_material.set_shader_parameter("accent",Palette.MATRIX)
			shader_materials.append(heart_material)
			shape(core,Forge.reactor_heart(),Vector3.ZERO,heart_material).name = "ReactorHeart"
		&"merge_conflict_hydra":
			for head in 4:
				poses.append_array(neck_chain(head))
			batch(poses, PLATING)
			var torso := box(self, Vector3(0, -0.12, -0.35), Vector3(5.95, 1.15, 1.25), PLATING)
			torso.name = "Torso"
			var eye_poses: Array[Transform3D] = []
			var face_poses: Array[Transform3D] = []
			for i in 4:
				var pivot := Node3D.new()
				pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				pivot.process_mode = Node.PROCESS_MODE_PAUSABLE
				add_child(pivot)
				pivot.position = Vector3((i - 1.5) * 1.65, 1.65, 0.28)
				heads.append(pivot)
				shape(pivot, Forge.hydra_head(), Vector3(0, 0.93, 0), Forge.metal(PLATING))
				var jaw := box(pivot, Vector3(0, 0.48, 0.08), Vector3(1.05, 0.24, 0.93), Palette.NAVY_2)
				jaw.name = "Jaw"
				var face := Node3D.new()
				face.name = "Face"
				face.process_mode = Node.PROCESS_MODE_PAUSABLE
				face.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				face.position = FACE_POSITION
				pivot.add_child(face)
				eye_poses.append(pose(pivot.position + EYE_POSITION, EYE_SIZE))
				face_poses.append(pose(pivot.position + FACE_POSITION, FACE_SIZE))
			eyes = batch(eye_poses, Palette.LILAC)
			eyes.material_override = luminous(Palette.LILAC)
			faces = batch(face_poses, Palette.LILAC)
			var face_quad := QuadMesh.new()
			face_quad.size = Vector2.ONE
			faces.multimesh.mesh = face_quad
			var face_material := luminous(Palette.LILAC)
			face_material.set_shader_parameter("symbol", 2)
			faces.material_override = face_material
			var sleeves: Array[Transform3D] = []
			for head in 4:
				var chain := neck_chain(head)
				for i in range(NECK_SEGMENTS - 1):
					var rotation := chain[i].basis.orthonormalized().slerp(chain[i + 1].basis.orthonormalized(), 0.5)
					var size := chain[i].basis.get_scale().lerp(chain[i + 1].basis.get_scale(), 0.5)
					sleeves.append(Transform3D(rotation.scaled_local(Vector3(size.x * 1.04, 0.13, size.z * 1.04)), chain[i].origin.lerp(chain[i + 1].origin, 0.5)))
			# Dormant right socket and mirrored left shoulder vent share the sleeve draw.
			var stump := neck_chain(3)[1]
			stump.origin += stump.basis.y.normalized() * 0.16
			stump.basis = stump.basis.orthonormalized().scaled_local(Vector3(0.72,0.15,0.67))
			sleeves.append(stump)
			sleeves.append(pose(Vector3(-stump.origin.x,0.48,stump.origin.z),Vector3(0.72,0.15,0.67)))
			var joints := batch(sleeves, Palette.NAVY_2)
			joints.name = "NeckSleeves"
			joints.multimesh.mesh = Forge.sleeve()
			var seam: Array[Vector3] = []
			for i in 13:
				var x := lerpf(-2.475, 2.475, i / 12.0)
				seam.append(Vector3(x, 0.42 + 0.22 * cos(x * PI / 4.95), 0.34))
			core = shape(self, Forge.bevelled_path(seam, Vector2(0.07, 0.06)), Vector3.ZERO, luminous(Palette.LILAC))
			core.name = "InterNeckSeam"
			var channel_surface := SurfaceTool.new()
			channel_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for offset in [Vector3(0,0,-0.07),Vector3(0,0.075,0),Vector3(0,-0.075,0)]:
				var path: Array[Vector3] = []
				for point in seam: path.append(point+offset)
				channel_surface.append_from(Forge.bevelled_path(path,Vector2(0.18,0.04) if offset.z < 0 else Vector2(0.045,0.13)),0,Transform3D.IDENTITY)
			shape(core,channel_surface.commit(),Vector3.ZERO,Forge.metal(Palette.NAVY_BG)).name = "SeamChannel"
		&"legacy_monolith":
			for row in 3:
				for col in 3:
					for half in [-1, 1]:
						poses.append(pose(Vector3((col - 1) * 1.98 + half * 0.48, (row - 1) * 1.32 + 1.02, 0), Vector3(0.92, 1.29, 1.65)))
			var slabs := batch(poses, PLATING)
			slabs.multimesh.mesh = Forge.unit_bevel_box(Vector3(0.92, 1.29, 1.65), 0.035)
			var cracks: Array[Transform3D] = []
			for col in 3:
				# Continuous recessed channels, no isolated glyph fragments.
				cracks.append(pose(Vector3((col - 1) * 1.98, 1.02, 0.72), Vector3(0.02, 3.93, 0.015)))
			var fissures := batch(cracks, Palette.ORANGE)
			fissures.material_override = luminous(Palette.ORANGE)
			var vents: Array[Transform3D] = []
			for side in [-1, 1]:
				for i in 9:
					vents.append(pose(Vector3(side * 2.4, 0.12 + i * 0.16, 0.86), Vector3(0.45, 0.065, 0.13)))
				var pipe := CylinderMesh.new()
				pipe.top_radius = 0.1
				pipe.bottom_radius = 0.1
				pipe.height = 3.55
				pipe.radial_segments = 24
				shape(self, pipe, Vector3(side * 3.0, 1.02, 0.3), Forge.metal(PLATING))
			batch(vents, Palette.NAVY_BG)
			var channels: Array[Transform3D] = []
			for col in 3: channels.append(pose(Vector3((col - 1) * 1.98, 1.02, 0.69), Vector3(0.12, 3.93, 0.20)))
			var cavities := batch(channels, Palette.NAVY_BG)
			cavities.name = "FissureCavities"
			cavities.multimesh.mesh = Forge.channel()
			box(self, Vector3(0, 1.32, 0.91), Vector3(2.78, 1.65, 0.16), Palette.NAVY_BG)
			var face := screen(self, Vector3(0, 1.32, 1.0), Vector2(2.55, 1.43), Palette.ORANGE)
			face.material_override.set_shader_parameter("symbol", 3)
			var vent := shape(self, Forge.channel(), Vector3(0, 0.29, 0.91), Forge.metal(Palette.NAVY_BG))
			vent.name = "CoreVent"
			vent.scale = Vector3(0.52, 0.34, 0.18)
			core = box(self, Vector3(0, 0.29, 0.90), Vector3(0.26, 0.12, 0.018), Palette.ORANGE)
			core.material_override = luminous(Palette.ORANGE)
	add_accent_light()
	add_motes(Palette.LILAC if value == &"merge_conflict_hydra" else (Palette.ORANGE if value == &"legacy_monolith" else Palette.DANGER))
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.material_override is StandardMaterial3D: flashes.append(node.material_override)
	ring = shape(self, Forge.forged_band(0.65,0.12,0.12), Vector3.ZERO, luminous(Palette.MATRIX)) if value == &"flaky_test_swarm" else torus(self, 0.65, Palette.DANGER)
	tag = label(self, "", Vector3(0, 3.15, 0), 0.005)
	tag.font_size = 40
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	for node: Node3D in get_children():
		rest_poses[node] = node.transform
	reset()

func reset() -> void:
	state = &"idle"
	mode = &""
	wall_mask = 0
	commit_age = -1.0
	head_recoil.fill(9.0)
	phase = 1
	health = 1.0
	clock = 0.0
	age = 0.0
	show()
	transform = Transform3D.IDENTITY
	if motes != null: motes.restart()
	advance(0.0)

func react(value: StringName, seconds: float) -> void:
	if state in [&"defeated", &"retreat"]: return
	state = value
	age = 0.0
	duration = maxf(seconds, 0.001)

## play_telegraph with the variant: the Monolith reads its signature from it (slab = the legacy
## wall, quake, debris); every boss aims at the lanes' centre.
func signature_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	aim = mask_center(lane_mask)
	wall_mask = lane_mask
	commit_age = -1.0
	mode = SIGNATURE_MODES.get(projectile_kind, &"")
	react(&"telegraph", seconds)

## A flaky telegraph settled on `lane_mask`: the Swarm's tiles converge on it until the shot.
func signature_commit(lane_mask: int, seconds: float) -> void:
	aim = mask_center(lane_mask)
	if state != &"telegraph":
		react(&"telegraph", seconds)
	else:
		duration = age + maxf(seconds, 0.001)
	commit_age = 0.0

## At fire: the Monolith slams its body for a quake; every other attack is the short recoil.
func signature_attack(projectile_kind: StringName) -> void:
	commit_age = -1.0
	if mode == &"quake" and projectile_kind == &"quake": react(&"slam", 0.34)
	else: react(&"attack", 0.12)

## Hydra: head `index` snaps back after `delay` seconds (heads recoil one after another).
func recoil_head(index: int, delay: float) -> void:
	if index >= 0 and index < head_recoil.size(): head_recoil[index] = -maxf(delay, 0.0)

## The visible Hydra head nearest to lane x `x` that is not already recoiling (else the nearest).
func head_for_x(x: float) -> int:
	var best := -1
	var fallback := -1
	for i in heads.size():
		if not (i < 3 or phase >= 2): continue
		var distance := absf((i - 1.5) * 1.65 - x)
		if fallback < 0 or distance < absf((fallback - 1.5) * 1.65 - x): fallback = i
		if head_recoil[i] < HEAD_RECOIL: continue
		if best < 0 or distance < absf((best - 1.5) * 1.65 - x): best = i
	return best if best >= 0 else fallback

static func mask_center(lane_mask: int) -> float:
	var total := 0.0
	var count := 0
	for lane in 3:
		if lane_mask & (1 << lane):
			total += (lane - 1) * 2.0
			count += 1
	return total / maxi(count, 1)

func flash(resisted: bool = false) -> void:
	react(&"resist" if resisted else &"hurt", 0.25)

func shatter() -> void:
	react(&"defeated", 0.95)

func advance(delta: float) -> void:
	clock += delta
	age += delta
	if commit_age >= 0.0: commit_age += delta
	for i in head_recoil.size():
		if head_recoil[i] < HEAD_RECOIL: head_recoil[i] += delta
	# Entrance root transforms never leak into idle, hit, or defeat poses.
	position = Vector3.ZERO
	if age >= duration and state not in [&"idle", &"defeated", &"retreat"]: state = &"idle"
	var u := clampf(age / maxf(duration, 0.001), 0, 1)
	for node: Node3D in rest_poses:
		node.transform = rest_poses[node]
	var charge := u if state == &"telegraph" else 0.0
	var converge := 0.5 * smoothstep(0.0, 0.12, commit_age) if boss_kind == &"flaky_test_swarm" and state == &"telegraph" and commit_age >= 0.0 else 0.0
	var wall_push := 0.0
	if boss_kind == &"legacy_monolith" and mode == &"wall":
		wall_push = WALL_PUSH * (charge if state == &"telegraph" else (1.0 - u if state == &"attack" else 0.0))
	var debris_shake := charge if boss_kind == &"legacy_monolith" and mode == &"debris" else 0.0
	if boss_kind != &"merge_conflict_hydra":
		core.scale = Vector3.ONE * (1 + 0.6 * charge)
		core.rotation.y = sin(clock * 0.5) * 0.08
		core.position.x += aim * 0.12 * charge
	if state == &"attack": core.position.z -= 0.12 * sin(u * PI)
	if state == &"hurt": core.position.x += sin(age * 90) * 0.06
	ring.visible = boss_kind != &"merge_conflict_hydra" and state in [&"phase_change", &"attack", &"defeated", &"slam"]
	ring.scale = Vector3.ONE * (1 + minf(u * 1.5, 1.5))
	# Lift expanding geometry to keep its bottom above the contract floor.
	ring.position.y = 1.2
	for material in flashes:
		material.emission_enabled = state == &"hurt" and age < 0.12
		material.emission_energy_multiplier = 2.2
		material.emission = Palette.CREAM
	for shader in shader_materials:
		shader.set_shader_parameter("clock", clock)
		shader.set_shader_parameter("intensity", 1.0 if state != &"hurt" else 1.1)
	for b in batches.size():
		var entry := batches[b]
		var multi: MultiMesh = entry.node.multimesh
		for i in entry.rest.size():
			var current: Transform3D = entry.rest[i]
			var color: Color = entry.color
			if boss_kind == &"flaky_test_swarm":
				if b <= 1:
					current.origin = _swarm_point(i, converge) + Vector3(0, 0, 0.145 if b == 1 else 0.0)
					color = PLATING if b == 0 else (Palette.DANGER if converge > 0.0 else tile_accent(i, clock))
				elif converge > 0.0:
					current = swarm_arc_between(_swarm_point(i, converge), _swarm_point((i + 1) % 24, converge)) if not (phase >= 2 and i % 8 == 7) else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
				else:
					current = swarm_arc_pose(i, phase, clock)
			if boss_kind == &"merge_conflict_hydra":
				var per_neck := NECK_SEGMENTS - 1 if b == 3 else NECK_SEGMENTS
				current.origin.x += sin(clock * 2 + float(i / per_neck)) * 0.025
				if phase < 2 and ((b == 0 and i >= NECK_SEGMENTS * 3 + 2) or (b in [1, 2] and i == 3) or (b == 3 and i >= (NECK_SEGMENTS - 1) * 3 + 1 and i < 24)):
					current.basis = Basis.from_scale(Vector3.ZERO)
			if boss_kind == &"legacy_monolith" and b == 0:
				current.origin.x += (-1.0 if i % 2 == 0 else 1.0) * (phase - 1) * 0.016
				# Legacy wall: the bottom-row slabs of the blocked lanes push out toward the player.
				if i < 6 and wall_mask & (1 << ((i % 6) / 2)): current.origin.z += wall_push
				# Debris: the top row shakes loose while the shadows grow.
				if i >= 12 and debris_shake > 0.0: current.origin += Vector3(sin(clock * 55.0 + i), cos(clock * 47.0 + i), 0) * 0.025 * debris_shake
			if boss_kind == &"legacy_monolith" and b == 1:
				current.basis = current.basis.scaled_local(Vector3(1 + phase * 0.35 + (1 - health), 1, 1))
			if state == &"intro" and boss_kind == &"flaky_test_swarm":
				current.origin.z -= 8.0 * (1.0 - smoothstep(0.0, 0.9, u))
			if state == &"defeated":
				current.origin += Vector3(sin(i * 2.3) * u * 0.3, 1.0 * u - 0.6 * u * u, cos(i * 1.7) * u * 0.12)
				current.basis = current.basis.scaled_local(Vector3.ONE * (1 - u))
				color = color.lerp(Palette.NAVY_BG, u)
			entry.colors[i] = color
			entry.poses[i] = current
			multi.set_instance_transform(i, current)
			multi.set_instance_color(i, color)
	for i in heads.size():
		heads[i].visible = i < 3 or phase >= 2
		heads[i].rotation.y = aim * charge * 0.08
		heads[i].position.x += sin(clock * 2 + i) * 0.025
		if head_recoil[i] >= 0.0 and head_recoil[i] < HEAD_RECOIL:
			var kick := sin(PI * head_recoil[i] / HEAD_RECOIL)
			heads[i].position.z -= 0.34 * kick
			heads[i].rotation.x = -0.4 * kick
		if state == &"intro": heads[i].scale = Vector3.ONE * lerpf(0.86, 1.0, smoothstep(0.1, 0.9, u))
		var jaw := heads[i].get_node("Jaw") as Node3D
		jaw.rotation.x = 0.05 + charge * 0.7 + (sin(u * PI) * 0.9 if state == &"attack" else 0.0)
		jaw.position.y = 0.48 - charge * 0.18 - (0.22 * sin(u * PI) if state == &"attack" else 0.0)
		var eye_pose := heads[i].transform * pose(EYE_POSITION, EYE_SIZE)
		if not heads[i].visible: eye_pose.basis = Basis.from_scale(Vector3.ZERO)
		eyes.multimesh.set_instance_transform(i, eye_pose)
		batches[1].poses[i] = eye_pose
		var face_pose := heads[i].transform * pose(FACE_POSITION, FACE_SIZE)
		if not heads[i].visible: face_pose.basis = Basis.from_scale(Vector3.ZERO)
		faces.multimesh.set_instance_transform(i, face_pose)
		batches[2].poses[i] = face_pose
	if state == &"intro":
		position.z = -55.0 * (1.0 - smoothstep(0.0, 0.92, u))
	# Collapse around the torso centre, keeping the floor clearance during exit.
	if state == &"hurt": position.z -= 0.16 * sin(u * PI)
	if state in [&"defeated", &"retreat"]:
		var shrink := maxf(1.0 - u, 0.001)
		scale = Vector3.ONE * shrink
		position.y = 0.8 * (1.0 - shrink)
		motes.emitting = false
		if u >= 1: hide()
	else:
		scale = Vector3.ONE
		motes.emitting = true
	# Monolith quake: the body rises through the charge and slams down at fire.
	if boss_kind == &"legacy_monolith":
		if state == &"telegraph" and mode == &"quake": position.y += QUAKE_RISE * charge
		elif state == &"slam":
			position.y += QUAKE_RISE * (1.0 - smoothstep(0.0, 0.3, u))
			var squash := sin(PI * clampf((u - 0.25) / 0.75, 0.0, 1.0))
			scale = Vector3(1.0, 1.0 - 0.04 * squash, 1.0 + 0.04 * squash)

static func tile_accent(index: int, seconds: float) -> Color:
	return Palette.MATRIX if (index + int(floor(seconds * 3.0))) % 3 != 0 else Palette.DANGER

static func neck_pose(head: int, t: float) -> Transform3D:
	var center := Vector3((head - 1.5) * 1.65 + sin(t * TAU) * 0.26, 0.2 + t * 2.3, -0.55 + t * 0.83 + sin(t * TAU) * 0.22)
	var tangent := Vector3(cos(t * TAU) * TAU * 0.26, 2.3, 0.83 + cos(t * TAU) * TAU * 0.22).normalized()
	var rotation := Basis(Quaternion(Vector3.UP, tangent))
	return Transform3D(rotation.scaled_local(Vector3(lerpf(0.78, 0.46, t), 0.23, lerpf(0.70, 0.42, t))), center)

func luminous(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Screen
	material.set_shader_parameter("accent", color)
	material.set_shader_parameter("symbol", 4)
	material.set_shader_parameter("accent_path", true)
	material.set_shader_parameter("accent_gain", 0.55)
	shader_materials.append(material)
	return material

func add_motes(color: Color) -> void:
	motes = GPUParticles3D.new()
	motes.name = "GlyphMotes"
	motes.process_mode = Node.PROCESS_MODE_PAUSABLE
	motes.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	motes.position = Vector3(2.25, 2.5, 1.0) if boss_kind == &"legacy_monolith" else Vector3(0, 1.6, 0.7)
	motes.amount = 16
	motes.lifetime = 0.8
	motes.local_coords = true
	motes.visibility_aabb = AABB(Vector3(-0.4, -0.4, -0.4), Vector3.ONE * 0.8)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.18
	motion.gravity = Vector3.ZERO
	motion.direction = Vector3.UP
	motion.initial_velocity_min = 0.08
	motion.initial_velocity_max = 0.12
	motion.scale_min = 0.6
	motion.scale_max = 1.0
	motion.anim_offset_max = 1.0
	motes.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.albedo_texture = Forge.glyph_atlas()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 4
	quad.material = material
	motes.draw_pass_1 = quad
	add_child(motes)

static func neck_chain(head: int) -> Array[Transform3D]:
	# Equal arc-length sampling with eight percent axial overlap and monotone taper.
	var distances: Array[float] = [0.0]
	for sample in range(1, 257):
		distances.append(distances.back() + neck_pose(head, sample / 256.0).origin.distance_to(neck_pose(head, (sample - 1) / 256.0).origin))
	var result: Array[Transform3D] = []
	for segment in NECK_SEGMENTS:
		var target: float = distances.back() * float(segment) / (NECK_SEGMENTS - 1)
		var index := 1
		while index < 256 and distances[index] < target: index += 1
		var t := (index - 1 + inverse_lerp(distances[index - 1], distances[index], target)) / 256.0
		result.append(neck_pose(head, t))
	for segment in NECK_SEGMENTS:
		var previous := result[maxi(segment - 1, 0)].origin
		var next := result[mini(segment + 1, NECK_SEGMENTS - 1)].origin
		var spacing := (result[segment].origin.distance_to(previous) + result[segment].origin.distance_to(next)) / (1.0 if segment in [0, NECK_SEGMENTS - 1] else 2.0)
		var size := result[segment].basis.get_scale()
		# Preserve monotone cross-sections; only the axial length follows spacing.
		result[segment].basis = result[segment].basis.orthonormalized().scaled_local(Vector3(size.x * 0.85, spacing * 1.08, size.z * 0.85))
	return result

static func projected_radius(transform_value: Transform3D, axis: Vector3) -> float:
	return (absf(axis.dot(transform_value.basis.x)) + absf(axis.dot(transform_value.basis.y)) + absf(axis.dot(transform_value.basis.z))) * 0.5

static func swarm_origin(index: int, current_phase: int, seconds: float) -> Vector3:
	var angle := TAU * index / 24.0
	if current_phase >= 2:
		angle = seconds * 0.35 + float(index / 8) * TAU / 3.0 + lerpf(deg_to_rad(-50), deg_to_rad(50), float(index % 8) / 7.0)
	return Vector3(cos(angle) * 2.68 + sin(seconds * 2 + index) * 0.025, 1.05 + sin(angle) * 1.64 + sin(seconds * 3 + index) * 0.025, sin(angle * 3) * 0.25)

static func swarm_arc_pose(index: int, current_phase: int, seconds: float) -> Transform3D:
	if current_phase >= 2 and index % 8 == 7: return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	return swarm_arc_between(swarm_origin(index, current_phase, seconds), swarm_origin((index + 1) % 24, current_phase, seconds))

## Swarm tile `index` pulled `amount` of the way toward the committed lane's focus point.
func _swarm_point(index: int, amount: float) -> Vector3:
	var origin := swarm_origin(index, phase, clock)
	if amount <= 0.0: return origin
	return origin.lerp(Vector3(aim * 0.35, 1.05, 0.3), amount)

static func swarm_arc_between(a: Vector3, b: Vector3) -> Transform3D:
	var tangent := (b - a).normalized()
	var side := tangent.cross(Vector3.BACK).normalized()
	var depth := side.cross(tangent).normalized()
	var center := a.lerp(b, 0.5) + Vector3(0, 0, -0.19)
	return Transform3D(Basis(side, tangent, depth).scaled_local(Vector3(0.14, a.distance_to(b) * 1.02, 0.22)), center)

func add_accent_light() -> void:
	var light := OmniLight3D.new()
	light.name = "BossAccentLight"
	light.process_mode = Node.PROCESS_MODE_PAUSABLE
	light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	light.position = Vector3(0, 1.2, 0)
	light.light_color = Palette.LILAC if boss_kind == &"merge_conflict_hydra" else (Palette.ORANGE if boss_kind == &"legacy_monolith" else Palette.MATRIX)
	light.light_energy = 1.3
	# Light influence is included by the shared contract envelope validator.
	light.omni_range = 1.25
	light.shadow_enabled = false
	add_child(light)
