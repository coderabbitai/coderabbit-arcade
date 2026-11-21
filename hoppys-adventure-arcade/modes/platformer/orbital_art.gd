extends RefCounted
const ROOT := "res://Assets/orbital-ops-assets-only/orbital_ops/"
const Art = preload("res://modes/platformer/art.gd")
## End caps of the station-kit terrain clips, in texels (left, right); see Art.run. The one-way
## platform's and the scaffold's interiors are cut to whole repeats of their painted pattern
## (two thruster humps, three lattice bays) so the repeat joins on the pattern.
const TRIMS := {
	"floor_slab": Vector2i(4, 4), "hull_panel": Vector2i(2, 3), "wall_block": Vector2i(1, 1),
	"one_way_platform": Vector2i(9, 31), "scaffold_horizontal": Vector2i(12, 5),
}
static var crops := {}
static var manifest: Dictionary = {}

static func sprite(sheet: String, clip: String, pos := Vector2.ZERO) -> AnimatedSprite2D:
	var result := AnimatedSprite2D.new()
	result.sprite_frames = load(ROOT + sheet + ".tres")
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.position = pos
	result.play(clip)
	return result

static func crop(sheet: String, clip: String) -> AtlasTexture:
	var key := sheet + "/" + clip
	if not crops.has(key):
		if manifest.is_empty():
			manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		var spec: Dictionary = manifest.atlases[sheet]
		for animation in spec.clips:
			if animation.name != clip: continue
			var frame: Dictionary = spec.frames[int(animation.frames[0])]
			var b: Array = frame.visible_bounds
			var texture := AtlasTexture.new()
			texture.atlas = load(ROOT + sheet + ".png")
			texture.region = Rect2(frame.rect[0] + b[0], frame.rect[1] + b[1], b[2] - b[0], b[3] - b[1])
			texture.filter_clip = true
			crops[key] = texture
	return crops[key]

static func prop(clip: String, pos: Vector2, size: Vector2) -> Sprite2D:
	var result := Sprite2D.new()
	result.texture = crop("station_kit", clip)
	result.centered = false
	result.position = pos
	result.scale = size / result.texture.get_size()
	return result

## `clip` laid seamlessly across `size`, at the texel scale one crop has stretched to `tile`.
static func run(clip: String, pos: Vector2, size: Vector2, tile: Vector2) -> Node2D:
	return Art.run(crop("station_kit", clip), pos, size, tile, TRIMS.get(clip, Vector2i.ZERO))
