extends RefCounted
const Forge = preload("res://scenes/runner/environment/hifi/mesh_forge.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const DARK := Color(Palette.NAVY_2, 0)
const METAL := Color(Palette.SLATE, 0)
const LIGHT := Color(Palette.MATRIX, 0.65)
const SCREEN_X := 4.20
const FRAME_FACE_X := 3.80
static func mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		# Solid backing at 4.38; the display at 4.20 sits 0.40 m behind the front bezel.
		Forge.box(st, Vector3(side * 4.48, 3.0, 0), Vector3(0.20, 6.0, 7.9), 0.07, DARK)
		for y in [0.45, 5.35]:
			Forge.box(st, Vector3(side * 4.10, y, 0), Vector3(0.60, 0.85, 7.9), 0.09, METAL)
		for z in [-3.65, 3.65]:
			Forge.box(st, Vector3(side * 4.10, 2.90, z), Vector3(0.60, 4.5, 0.50), 0.09, METAL)
			Forge.box(st, Vector3(side * 3.77, 3.05, z), Vector3(0.045, 2.5, 0.065), 0.016, LIGHT)
		# Deep inner lip surrounds the inset display, not the whole wall plane.
		for y in [0.95, 4.85]:
			Forge.box(st, Vector3(side * 4.09, y, 0), Vector3(0.35, 0.12, 6.85), 0.04, DARK)
		for y in [0.45, 5.35]:
			for z in [-2.7, -0.9, 0.9, 2.7]:
				Forge.box(st, Vector3(side * 3.78, y, z), Vector3(0.09, 0.18, 1.25), 0.035, DARK)
				Forge.box(st, Vector3(side * 3.72, y, z), Vector3(0.04, 0.035, 1.05), 0.012, METAL)
		for z in [-3.65, 3.65]:
			for y in [0.45, 5.35]:
				Forge.box(st, Vector3(side * 3.74, y, z), Vector3(0.12, 0.16, 0.16), 0.045, METAL)
		# Every overhead vertex is above the full-height boss envelope (y <= 6.1).
		Forge.box(st, Vector3(side * 2.8, 6.40, 0), Vector3(0.7, 0.18, 7.9), 0.055, DARK)
		for x in [2.58, 3.02]:
			Forge.box(st, Vector3(side * x, 6.26, 0), Vector3(0.055, 0.065, 7.9), 0.02, METAL)
		Forge.box(st, Vector3(side * 2.8, 6.29, 0), Vector3(0.16, 0.04, 4.8), 0.015, LIGHT)
		for z in [-3.0, 0.0, 3.0]:
			Forge.box(st, Vector3(side * 2.8, 6.24, z), Vector3(0.8, 0.055, 0.09), 0.02, METAL)
	st.generate_tangents()
	return st.commit()

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
