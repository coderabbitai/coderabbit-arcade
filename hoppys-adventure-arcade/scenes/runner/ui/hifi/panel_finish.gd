extends Node2D
## Single translucent interior with a vector vignette and bevel. No grain/scanline overdraw.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const STATIC_COMMANDS := 4
var accent := Palette.MINT
var _last_accent := Color.TRANSPARENT
var _last_alpha := -1.0
var _cached_bracket := Rect2()
var _bracket_dirty := true
var occupancy_scans := 0
var invalidations := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_watch(get_parent())

func surface_alpha() -> float:
	return (get_parent().get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a

func corner_cut() -> float:
	return float((get_parent().get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left)

func _process(_delta: float) -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if "game" in ancestor and is_instance_valid(ancestor.get("game")):
			if ancestor.get("game").get("paused") == true: return
			break
		ancestor = ancestor.get_parent()
	if not is_visible_in_tree(): return
	var box := get_parent().get_theme_stylebox("panel") as StyleBoxFlat
	accent = box.border_color
	if accent != _last_accent or surface_alpha() != _last_alpha:
		_last_accent = accent
		_last_alpha = surface_alpha()
		_invalidate()

func _invalidate() -> void:
	invalidations += 1
	queue_redraw()

func _layout_changed(_child: Node = null) -> void:
	_bracket_dirty = true
	_invalidate()

func _watch(node: Node) -> void:
	if node == self: return
	if not node.child_entered_tree.is_connected(_watch):
		node.child_entered_tree.connect(_watch)
		node.child_exiting_tree.connect(_layout_changed)
		if node is CanvasItem:
			node.visibility_changed.connect(_layout_changed)
			node.item_rect_changed.connect(_layout_changed)
	for child in node.get_children(): _watch(child)
	_layout_changed()

func bracket_rect() -> Rect2:
	if not _bracket_dirty: return _cached_bracket
	_bracket_dirty = false
	occupancy_scans += 1
	_cached_bracket = _available_bracket()
	return _cached_bracket

func _available_bracket() -> Rect2:
	var panel := get_parent() as Control
	var extent := panel.size
	if extent.y < 56: return Rect2()
	var candidate := Rect2(extent.x-30, extent.y-30, 8, 10)
	# Include layout containers, rules, bars, icons and text. Unknown custom
	# CanvasItems conservatively suppress decoration because they expose no rect.
	for item in panel.find_children("*", "CanvasItem", true, false):
		if item == self or not item.is_visible_in_tree(): continue
		if not item is Control: return Rect2()
		var transform: Transform2D = panel.get_global_transform().affine_inverse() * item.get_global_transform()
		var bounds: Rect2 = transform * Rect2(Vector2.ZERO, item.size)
		var padding: float = item.get_theme_constant("outline_size") if item is Label else 2.0
		if candidate.intersects(bounds.grow(padding)): return Rect2()
	return candidate

func _draw() -> void:
	var extent: Vector2 = get_parent().size
	if extent.x < 20 or extent.y < 20: return
	var box := get_parent().get_theme_stylebox("panel") as StyleBoxFlat
	accent = box.border_color
	var w := extent.x
	var h := extent.y
	var cut := minf(corner_cut(), minf(w, h) * 0.5)
	var points := PackedVector2Array([Vector2(cut, 2), Vector2(w-cut, 2), Vector2(w-2, cut), Vector2(w-2, h-cut), Vector2(w-cut, h-2), Vector2(cut, h-2), Vector2(2, h-cut), Vector2(2, cut)])
	if h >= 40:
		var vertices := points.duplicate()
		vertices.append(extent * Vector2(0.5, 0.38))
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for i in 8:
			colors.append(Color(Palette.NAVY_BG.lerp(Palette.NAVY_2, 0.3 if i < 3 else 0.0), surface_alpha()))
			indices.append_array(PackedInt32Array([8, i, (i+1)%8]))
		colors.append(Color(Palette.NAVY_2, surface_alpha()))
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, vertices, colors)
	else:
		draw_colored_polygon(points, Color(Palette.NAVY_BG, surface_alpha()))
	# Continuous bevels, aligned to the parent chamfer, then a thin inset stroke.
	var bevel := points.duplicate()
	bevel.append(bevel[0])
	var bevel_colors := PackedColorArray([Color(Palette.CREAM,0.3),Color(Palette.CREAM,0.3),Color(Palette.CREAM,0.2),Color(Palette.NAVY_BG,0.8),Color(Palette.NAVY_BG,0.8),Color(Palette.NAVY_BG,0.8),Color(Palette.NAVY_BG,0.8),Color(Palette.CREAM,0.2),Color(Palette.CREAM,0.3)])
	draw_polyline_colors(bevel, bevel_colors, 2, true)
	var inner := PackedVector2Array()
	for point in points: inner.append(point.move_toward(extent * 0.5, 4))
	inner.append(inner[0])
	draw_polyline(inner, Color(accent, 0.22), 1, true)
	var bracket := bracket_rect()
	if bracket.has_area():
		draw_polyline(PackedVector2Array([bracket.position, Vector2(bracket.end.x,bracket.position.y), bracket.end]), Color(accent,0.45), 2, true)
