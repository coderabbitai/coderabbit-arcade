extends Control
## Honest navigation endpoint until each microgame is implemented.
const Style = preload("res://scenes/main_menu/menu_style.gd")
@export var mode_title := "Platformer Game"
@export var description := "Bay Area Blitz · Orbital Ops · Enchanted Repo"
func _ready() -> void:
	theme = Style.theme()
	var background := ColorRect.new()
	background.color = Color("101d2d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 25)
	center.add_child(column)
	column.add_child(Style.label("NEXT ADVENTURE", 16, Style.MINT))
	column.add_child(Style.label(mode_title.to_upper(), 42))
	column.add_child(Style.label(description, 17))
	column.add_child(Style.label("Coming soon — this mode is not playable yet.", 17, Color("afbdc9")))
	var back := Style.button("Return to Main Menu")
	column.add_child(back)
	back.pressed.connect(func(): AppRouter.go("hub"))
	back.grab_focus()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AppRouter.go("hub")
		get_viewport().set_input_as_handled()
