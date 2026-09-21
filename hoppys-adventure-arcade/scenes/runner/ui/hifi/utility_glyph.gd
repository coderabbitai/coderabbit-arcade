extends Control
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const STROKE := 3.0
# Normalized paths are the drawing source and the headless silhouette-test source.
const GLYPHS := {
	&"approve_shield": {"lines": [[Vector2(0,-1),Vector2(0.8,-0.6),Vector2(0.6,0.4),Vector2(0,1),Vector2(-0.6,0.4),Vector2(-0.8,-0.6),Vector2(0,-1)], [Vector2(-0.4,0),Vector2(-0.1,0.35),Vector2(0.45,-0.3)]], "fills": [[Vector2(-0.35,-0.6),Vector2(0,-0.8),Vector2(0,-0.35)]]},
	&"lgtm": {"lines": [[Vector2(-0.5,-0.85),Vector2(0.5,-0.85),Vector2(0.9,-0.4),Vector2(0.9,0.4),Vector2(0.5,0.85),Vector2(-0.5,0.85),Vector2(-0.9,0.4),Vector2(-0.9,-0.4),Vector2(-0.5,-0.85)]], "fills": [[Vector2(-0.6,0),Vector2(-0.2,0.5),Vector2(0.65,-0.4),Vector2(0.4,-0.6),Vector2(-0.2,0.1),Vector2(-0.4,-0.2)]]},
	&"nitro": {"lines": [], "fills": [[Vector2(0.2,-1),Vector2(-0.75,0.15),Vector2(-0.1,0.15),Vector2(-0.2,1),Vector2(0.75,-0.15),Vector2(0.1,-0.15)]]},
	&"super_jump": {"lines": [[Vector2(-0.8,0.9),Vector2(0.8,0.9)], [Vector2(0,0.55),Vector2(0,-0.55)]], "fills": [[Vector2(0,-1),Vector2(-0.7,-0.2),Vector2(0.7,-0.2)]]},
	&"code_review": {"lines": [[Vector2(-0.35,-0.65),Vector2(-0.9,0),Vector2(-0.35,0.65)], [Vector2(0.35,-0.65),Vector2(0.9,0),Vector2(0.35,0.65)], [Vector2(0.2,-0.8),Vector2(-0.2,0.8)]], "fills": []},
	&"auto_fix": {"lines": [[Vector2(-0.9,-0.8),Vector2(-0.55,-0.45)], [Vector2(0.55,0.45),Vector2(0.9,0.8)]], "fills": [[Vector2(0,-1),Vector2(0.25,-0.25),Vector2(1,0),Vector2(0.25,0.25),Vector2(0,1),Vector2(-0.25,0.25),Vector2(-1,0),Vector2(-0.25,-0.25)]]},
	&"review_comment": {"lines": [[Vector2(-0.85,-0.75),Vector2(0.85,-0.75),Vector2(0.85,0.4),Vector2(-0.15,0.4),Vector2(-0.7,0.9),Vector2(-0.7,0.4),Vector2(-0.85,0.4),Vector2(-0.85,-0.75)], [Vector2(-0.45,-0.3),Vector2(0.45,-0.3)]], "fills": [[Vector2(-0.45,-0.05),Vector2(0.15,-0.05),Vector2(0.15,0.15),Vector2(-0.45,0.15)]]},
	&"lint_rule": {"lines": [[Vector2(-0.3,-0.65),Vector2(0.85,-0.65)], [Vector2(-0.3,0),Vector2(0.6,0)], [Vector2(-0.3,0.65),Vector2(0.35,0.65)]], "fills": [[Vector2(-0.85,-0.85),Vector2(-0.55,-0.85),Vector2(-0.55,-0.45),Vector2(-0.85,-0.45)], [Vector2(-0.85,-0.2),Vector2(-0.55,-0.2),Vector2(-0.55,0.2),Vector2(-0.85,0.2)], [Vector2(-0.85,0.45),Vector2(-0.55,0.45),Vector2(-0.55,0.85),Vector2(-0.85,0.85)]]},
	&"unit_test": {"lines": [[Vector2(-0.4,-0.9),Vector2(0.4,-0.9)], [Vector2(-0.25,-0.9),Vector2(-0.25,-0.25),Vector2(-0.75,0.7),Vector2(-0.55,0.9),Vector2(0.55,0.9),Vector2(0.75,0.7),Vector2(0.25,-0.25),Vector2(0.25,-0.9)]], "fills": [[Vector2(-0.4,0.35),Vector2(0.4,0.35),Vector2(0.6,0.7),Vector2(-0.6,0.7)]]},
	&"auto_fix_patch": {"lines": [[Vector2(0,-1),Vector2(0.9,0),Vector2(0,1),Vector2(-0.9,0),Vector2(0,-1)], [Vector2(-0.45,0),Vector2(0.45,0)], [Vector2(0,-0.45),Vector2(0,0.45)]], "fills": []},
	&"arrow": {"lines": [[Vector2(-0.8,-0.6),Vector2(-0.2,0),Vector2(-0.8,0.6)], [Vector2(0,-0.6),Vector2(0.6,0),Vector2(0,0.6)]], "fills": []},
	&"medal": {"lines": [[Vector2(-0.5,-0.8),Vector2(0.5,-0.8),Vector2(0.8,-0.2),Vector2(0.5,0.4),Vector2(-0.5,0.4),Vector2(-0.8,-0.2),Vector2(-0.5,-0.8)]], "fills": [[Vector2(-0.45,0.2),Vector2(0.45,0.2),Vector2(0.45,1),Vector2(0,0.7),Vector2(-0.45,1)]]},
	&"unknown": {"lines": [[Vector2(-0.7,-0.7),Vector2(0.7,0.7)], [Vector2(-0.7,0.7),Vector2(0.7,-0.7)]], "fills": []},
}
var kind: StringName = &"approve_shield"
var tint := Palette.MINT

static func geometry(kind_value: StringName) -> Dictionary:
	return GLYPHS.get(kind_value, GLYPHS[&"unknown"])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.36
	var shape := geometry(kind)
	draw_circle(c, r + 3, Color(Palette.NAVY_BG, 0.9))
	if kind in [&"review_comment", &"lint_rule"]:
		draw_style_box(_inset_fill(), Rect2(c-Vector2.ONE*r, Vector2.ONE*r*2))
	for path in shape.lines:
		var points := PackedVector2Array()
		for point: Vector2 in path: points.append(c + point * r)
		draw_polyline(points, tint, STROKE, true)
	for path in shape.fills:
		var points := PackedVector2Array()
		for point: Vector2 in path: points.append(c + point * r)
		draw_colored_polygon(points, tint)

func _inset_fill() -> StyleBoxFlat:
	var backing := StyleBoxFlat.new()
	backing.bg_color = Palette.NAVY_2.lerp(tint,0.2)
	backing.set_corner_radius_all(3)
	return backing
