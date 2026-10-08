@static_unload
extends RefCounted
const BASE := "res://Assets/heroes-vs-villains-assets-only/heroes_villains/"
const PRESENTATION := "res://Assets/heroes-vs-villains-assets-only/presentation/"
const Shared = preload("res://modes/beatem_up/art.gd")
static var resources: Dictionary = {}
static var manifest: Dictionary = {}

static func frames(key: String) -> SpriteFrames:
	if not resources.has(key): resources[key] = load(BASE+key+".tres")
	return resources[key]

static func sprite(key: String, pose: String, magnify := 1.0, foot := true) -> AnimatedSprite2D:
	if manifest.is_empty(): manifest = JSON.parse_string(FileAccess.get_file_as_string(BASE+"manifest.json"))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(key)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE*magnify
	if foot:
		var spec: Dictionary = manifest.atlases[key]
		s.offset = Vector2(spec.cell[0]*.5-spec.pivot[0],spec.cell[1]*.5-spec.pivot[1])
	s.play(pose)
	return s

static func shadow(radius := 27.0) -> Polygon2D:
	return Shared.shadow(radius)

const ARMED_ROOT := "res://Assets/hoppy-armed/heroes/"
static var armed_manifest: Dictionary = {}
static var armed_manifest_loaded := false
static var armed_sheets: Dictionary = {}
static var carry_textures: Dictionary = {}

static func load_armed_manifest() -> Dictionary:
	if not armed_manifest_loaded:
		armed_manifest_loaded = true
		var path := ARMED_ROOT + "manifest.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				armed_manifest = parsed
	return armed_manifest

static func armed_spec(weapon_id: String) -> Dictionary:
	var weapons: Variant = load_armed_manifest().get("weapons", {})
	if weapons is Dictionary and weapons.has(weapon_id) and weapons[weapon_id] is Dictionary:
		return weapons[weapon_id]
	return {}

## Null when this weapon has no baked sheet yet. Missing sheets stay cached so
## a fallback weapon does not hit the filesystem on every frame.
static func armed_frames(weapon_id: String) -> SpriteFrames:
	if weapon_id == "":
		return null
	if armed_sheets.has(weapon_id):
		return armed_sheets[weapon_id]
	var spec := armed_spec(weapon_id)
	var file_name := str(spec.get("resource", weapon_id + ".tres"))
	var path := ARMED_ROOT + file_name
	var frames: SpriteFrames = null
	if ResourceLoader.exists(path):
		frames = load(path) as SpriteFrames
	armed_sheets[weapon_id] = frames
	return frames

static func carry_texture(weapon_id: String) -> Texture2D:
	if weapon_id == "":
		return null
	if carry_textures.has(weapon_id):
		return carry_textures[weapon_id]
	var path := ARMED_ROOT + "carry/" + weapon_id + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	carry_textures[weapon_id] = texture
	return texture

## Cell-pixel anchor, or null when this frame has no point of that kind.
static func sheet_anchor(weapon_id: String, kind: String, frame: int) -> Variant:
	var anchors: Variant = armed_spec(weapon_id).get("anchors", {})
	if not anchors is Dictionary:
		return null
	var table: Variant = anchors.get(kind, {})
	if not table is Dictionary:
		return null
	var point: Variant = table.get(str(frame), null)
	if point is Array and point.size() >= 2:
		return Vector2(float(point[0]), float(point[1]))
	return null
