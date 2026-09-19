extends Control

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.text = "BAY AREA BLITZ — Asset animation gallery"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var note := Label.new()
	note.text = "Select an animation on each card. One-shot animations repeat here for inspection. No gameplay logic."
	column.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 4
	column.add_child(grid)
	for asset in ["glitch_critter", "request_reviewer", "merge_monster", "interactives", "pickups", "street_kit", "hud", "hoppy/platformer"]:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(300, 300)
		grid.add_child(card)
		var label := Label.new()
		label.text = asset.replace("_", " ")
		card.add_child(label)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(280, 210)
		card.add_child(holder)
		var sprite := AnimatedSprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.sprite_frames = load("res://bay_area/" + asset + ".tres")
		sprite.position = Vector2(140, 105)
		sprite.scale = Vector2.ONE * (1.0 if asset == "merge_monster" else 1.5)
		holder.add_child(sprite)
		var picker := OptionButton.new()
		var names := sprite.sprite_frames.get_animation_names()
		for animation_name in names:
			picker.add_item(animation_name)
		card.add_child(picker)
		picker.item_selected.connect(func(index: int): sprite.play(names[index]))
		sprite.animation_finished.connect(func(): sprite.frame = 0; sprite.play())
		sprite.play(names[0])
