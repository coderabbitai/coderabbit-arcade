extends Node2D
const Art = preload("res://modes/platformer/art.gd")
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
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
	area.add_child(Art.shape(Vector2(64,130) if kind == "comment" else Vector2(155,48), Vector2(0,-65) if kind == "comment" else Vector2(direction*55,-24)))
	add_child(area)
	_show("comment_dormant" if kind == "comment" else "vine_idle")

func _show(clip: String) -> void:
	if current_clip == clip: return
	current_clip = clip
	visual.texture = ForestArt.crop("hazards",clip)
	# Stable ground anchor; fit visual feedback to the actual damage band.
	visual.scale = Vector2.ONE * (1.45 if kind == "comment" else 1.6)
	visual.position = Vector2(0, -visual.texture.get_height()*visual.scale.y/2)
	visual.flip_h = kind == "vine" and direction > 0

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
