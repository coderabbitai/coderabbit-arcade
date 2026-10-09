@static_unload
extends RefCounted
const BASE := "res://Assets/code-city-brawl-assets-only/code_city/"
const ARMED := "res://Assets/hoppy-armed/code_city/"
## The armed pack's cell and foot pivot (Assets/hoppy-armed/README.md).
const ARMED_CELL := Vector2(192, 128)
const ARMED_PIVOT := Vector2(72, 118)
static var manifest: Dictionary = {}
static var resources: Dictionary = {}
static var armed_manifest: Dictionary = {}
static var armed_sheets: Dictionary = {}
static var carry_icons: Dictionary = {}
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
## Manifest entry (cell, pivot, clips, anchors) of a weapon's armed sheet; empty without one.
static func armed_spec(weapon: String) -> Dictionary:
	if armed_manifest.is_empty() and FileAccess.file_exists(ARMED + "manifest.json"):
		armed_manifest = JSON.parse_string(FileAccess.get_file_as_string(ARMED + "manifest.json"))
	return armed_manifest.get("weapons", {}).get(weapon, {})
## Hoppy holding the weapon, or null while the weapon has no baked sheet yet (legacy rig).
## Loaded on first use, so a sheet is picked up as soon as its resource and manifest entry exist.
static func armed(weapon: String) -> SpriteFrames:
	if not armed_sheets.has(weapon):
		var path := ARMED + weapon + ".tres"
		var spec := armed_spec(weapon)
		armed_sheets[weapon] = load(path) as SpriteFrames if spec.has("anchors") and ResourceLoader.exists(path) else null
	return armed_sheets[weapon]
## Foot-pivot offset of a facing-right armed sheet, so it stands where the unarmed body does.
## A weapon with no manifest entry uses the pack's contract cell and pivot.
static func armed_offset(weapon: String) -> Vector2:
	var spec := armed_spec(weapon)
	var cell: Vector2 = Vector2(spec.cell[0], spec.cell[1]) if spec.has("cell") else ARMED_CELL
	var pivot: Vector2 = Vector2(spec.pivot[0], spec.pivot[1]) if spec.has("pivot") else ARMED_PIVOT
	return Vector2(cell.x * 0.5 - pivot.x, cell.y * 0.5 - pivot.y)
## The weapon cel downsampled to one texel per body texel, for poses with no armed frame.
static func carry(weapon: String) -> Texture2D:
	if not carry_icons.has(weapon): carry_icons[weapon] = load(ARMED + "carry/" + weapon + ".png")
	return carry_icons[weapon]
## Icon texel the paw holds when the builder reoriented the carry; null keeps the cel grip.
static func carry_grip(weapon: String) -> Variant:
	armed_spec(weapon)
	var grip: Variant = armed_manifest.get("carry_calibration", {}).get("weapons", {}).get(weapon, {}).get("grip")
	return Vector2(grip[0], grip[1]) if grip is Array and grip.size() == 2 else null
static func shadow(radius := 27.0) -> Polygon2D:
	var p := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24: points.append(Vector2(cos(TAU*i/24.0)*radius,sin(TAU*i/24.0)*radius*.3))
	p.polygon = points
	p.color = Color(0.01,0.02,0.04,.6)
	return p
