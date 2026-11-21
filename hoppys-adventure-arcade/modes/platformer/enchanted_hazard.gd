extends Node2D
const Art = preload("res://modes/platformer/art.gd")
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
## Where each vine frame's root rocks sit (texels from the crop's left edge); the whip frame's root
## is right of centre because the tentacle lashes out to the left. Other frames stand centred.
const VINE_ROOT := {"vine_whip": 76.0}
## The whip's reach: the band the lashing tentacle covers, measured on the anchored vine_whip crop
## at this scale (about 120 px out from the root, 20 px behind it), so nothing is hit off the art.
const VINE_BAND := Rect2(-120, -48, 140, 48)
var kind := "comment"
var clock := 0.0
var state := "idle"
var direction := -1.0
var visual: Sprite2D
var area: Area2D
var current_clip := ""

func _ready() -> void:
	visual = Sprite2D.new()
	add_child(visual)
	area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	if kind == "comment":
		area.add_child(Art.shape(Vector2(64,130), Vector2(0,-65)))
	else:
		var band := VINE_BAND
		if direction > 0: band.position.x = -band.end.x
		area.add_child(Art.shape(band.size, band.get_center()))
	add_child(area)
	_show("comment_dormant" if kind == "comment" else "vine_idle")

func _show(clip: String) -> void:
	if current_clip == clip: return
	current_clip = clip
	visual.texture = ForestArt.crop("hazards",clip)
	# Every frame stands on the ground with its root at the hazard's position (a flipped vine
	# mirrors about that root), so the whip reaches out over its damage band instead of jumping.
	visual.scale = Vector2.ONE * (1.45 if kind == "comment" else 1.6)
	var width := visual.texture.get_width()
	var root: float = VINE_ROOT.get(clip, width/2.0)
	visual.flip_h = kind == "vine" and direction > 0
	var shift := direction*(root-width/2.0)*visual.scale.x if kind == "vine" else 0.0
	visual.position = Vector2(shift, -visual.texture.get_height()*visual.scale.y/2)

func tick(dt: float, player: CharacterBody2D) -> void:
	clock += dt
	var phase := fmod(clock,4.9)
	state = "idle" if phase < 2.0 else ("warning" if phase < 2.9 else ("active" if phase < 3.35 else "recover"))
	var clip: String
	if kind == "comment":
		clip = {"idle":"comment_dormant","warning":"comment_warning","active":"comment_burst","recover":"comment_spent"}[state]
	else:
		clip = {"idle":"vine_idle","warning":"vine_warning","active":"vine_whip","recover":"vine_idle"}[state]
	_show(clip)
	# The warning and burst/whip clips are the whole telegraph: no box is drawn over the art.
	if state == "active" and area.overlaps_body(player): player.damage(position.x)
