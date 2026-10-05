@static_unload
extends RefCounted
const BASE := "res://Assets/code-city-brawl-assets-only/code_city/"
static var manifest: Dictionary = {}
static var resources: Dictionary = {}
static func frames(key: String) -> SpriteFrames:
	if not resources.has(key): resources[key] = load(BASE + key + ".tres")
	return resources[key]
static func sprite(key: String, pose: String, scale_factor := 1.0, foot := true) -> AnimatedSprite2D:
	if manifest.is_empty(): manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE + "manifest.json"))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(key)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * scale_factor
	if foot:
		var spec: Dictionary = manifest.atlases[key]
		s.offset = Vector2(spec.cell[0] * 0.5 - spec.pivot[0], spec.cell[1] * 0.5 - spec.pivot[1])
	s.play(pose)
	return s
static func shadow(radius := 27.0) -> Polygon2D:
	var p := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24: points.append(Vector2(cos(TAU*i/24.0)*radius,sin(TAU*i/24.0)*radius*.3))
	p.polygon = points
	p.color = Color(0.01,0.02,0.04,.6)
	return p
