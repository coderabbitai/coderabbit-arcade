extends RefCounted
const Forge = preload("res://scenes/runner/environment/hifi/mesh_forge.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const DARK := Color(Palette.NAVY_2, 0)
const METAL := Color(Palette.SLATE, 0)
const LIGHT := Color(Palette.MATRIX, 0.65)
const SCREEN_X := 4.20
const FRAME_FACE_X := 3.80
const VARIANT_COUNT := 4
const BATCH_COUNT := 3
const BATCH_FOR_VARIANT := [0, 0, 1, 2]
# No cyclic shift shorter than the entire 96 m loop reproduces this sequence.
const PATTERN := [0, 1, 2, 0, 3, 1, 0, 2, 3, 2, 1, 3]
const WIDTHS := [6.3, 5.5, 6.1, 6.5]
const HEIGHTS := [2.35, 2.25, 2.3, 2.65]
const CENTERS := [3.0, 3.3, 2.7, 3.0]
const OFFSETS := [0.0, -0.4, 0.4, 0.0]
static func mesh(variant: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low: float = CENTERS[variant] - HEIGHTS[variant] * 0.5
	var high: float = CENTERS[variant] + HEIGHTS[variant] * 0.5
	for side in [-1.0, 1.0]:
		# Solid backing at 4.38; the display at 4.20 sits 0.40 m behind the front bezel.
		Forge.box(st, Vector3(side * 4.48, 3.0, 0), Vector3(0.20, 6.0, 7.9), 0.07, DARK)
		Forge.box(st, Vector3(side * 4.10, low * 0.5, 0), Vector3(0.60, low, 7.9), 0.09, METAL)
		Forge.box(st, Vector3(side * 4.10, (high + 6.0) * 0.5, 0), Vector3(0.60, 6.0 - high, 7.9), 0.09, METAL)
		for end in [-1.0, 1.0]:
			var edge: float = OFFSETS[variant] + end * WIDTHS[variant] * 0.5
			var outer: float = end * 3.65
			Forge.box(st, Vector3(side * 4.10, CENTERS[variant], (edge + outer) * 0.5), Vector3(0.60, HEIGHTS[variant], absf(outer - edge)), 0.035, METAL)
		for z in [-3.65, 3.65]:
			Forge.box(st, Vector3(side * 4.10, 2.90, z), Vector3(0.60, 4.5, 0.50), 0.09, METAL)
			Forge.box(st, Vector3(side * 3.77, 3.05, z), Vector3(0.045, 2.5, 0.065), 0.016, LIGHT)
		# Deep inner lip surrounds the inset display, not the whole wall plane.
		for y in [low, high]:
			Forge.box(st, Vector3(side * 4.09, y, OFFSETS[variant]), Vector3(0.35, 0.12, WIDTHS[variant]), 0.04, DARK)
		for y in [0.45, 5.35]:
			for z in [-2.7, -0.9, 0.9, 2.7]:
				Forge.box(st, Vector3(side * 3.78, y, z), Vector3(0.09, 0.18, 1.25), 0.035, DARK)
				Forge.box(st, Vector3(side * 3.72, y, z), Vector3(0.04, 0.035, 1.05), 0.012, METAL)
		for z in [-3.65, 3.65]:
			for y in [0.45, 5.35]:
				Forge.box(st, Vector3(side * 3.74, y, z), Vector3(0.12, 0.16, 0.16), 0.045, METAL)
		# Bundled cable route alternates above/below the display; dark rubber interiors.
		for cable in 3:
			var cable_y := (0.95 if variant % 2 == 0 else 5.05) + float(cable) * 0.10
			Forge.box(st, Vector3(side * 3.72, cable_y, OFFSETS[variant]), Vector3(0.10, 0.065, 5.2 - variant * 0.35), 0.025, DARK)
		# A rigid bridge crosses each rack joint, with a vertical service drop.
		var service_y := 1.20 if variant % 2 == 0 else 4.75
		Forge.box(st, Vector3(side * 3.71, service_y, 3.90), Vector3(0.12, 0.12, 0.40), 0.035, DARK)
		Forge.box(st, Vector3(side * 3.71, service_y + 0.30, 3.64), Vector3(0.12, 0.60, 0.12), 0.035, DARK)
		for led in 3:
			Forge.box(st, Vector3(side * 3.76, 1.45, -2.4 + led * 0.15), Vector3(0.04, 0.05, 0.065), 0.014, LIGHT)
		# Every overhead vertex is above the full-height boss envelope (y <= 6.1).
		Forge.box(st, Vector3(side * 2.8, 6.40, 0), Vector3(0.7, 0.18, 7.9), 0.055, DARK)
		for x in [2.58, 3.02]:
			Forge.box(st, Vector3(side * x, 6.26, 0), Vector3(0.055, 0.065, 7.9), 0.02, METAL)
		Forge.box(st, Vector3(side * 2.8, 6.29, 0), Vector3(0.16, 0.04, 4.8), 0.015, LIGHT)
		for z in [-3.0, 0.0, 3.0]:
			Forge.box(st, Vector3(side * 2.8, 6.24, z), Vector3(0.8, 0.055, 0.09), 0.02, METAL)
	st.generate_tangents()
	var original := st.commit()
	var arrays := original.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size(): colors[i].b = float(variant) / 3.0
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func pillar() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Forge.box(st, Vector3.ZERO, Vector3(0.22, 6, 0.22), 0.04, DARK)
	for y in [-2.85, 2.85]:
		Forge.box(st, Vector3(0, y, 0), Vector3(0.34, 0.24, 0.34), 0.05, METAL)
	for x in [-0.115, 0.115]:
		Forge.box(st, Vector3(x, 0, 0), Vector3(0.018, 5.2, 0.032), 0.006, LIGHT)
	st.generate_tangents()
	return st.commit()

static func instance_tag(module_index: int) -> float:
	return float(PATTERN[module_index] * 16 + module_index)

static func batch_mesh(batch_index: int) -> ArrayMesh:
	if batch_index > 0: return mesh(batch_index + 1)
	var first := mesh(0).surface_get_arrays(0)
	var second := mesh(1).surface_get_arrays(0)
	var a: PackedVector3Array = first[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = second[Mesh.ARRAY_VERTEX]
	assert(a.size() == b.size())
	var deltas := PackedFloat32Array()
	for i in a.size():
		var delta := b[i] - a[i]
		deltas.append_array(PackedFloat32Array([delta.x, delta.y, delta.z, 0.0]))
	first[Mesh.ARRAY_CUSTOM0] = deltas
	var result := ArrayMesh.new()
	var flags := Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, first, [], {}, flags)
	return result
