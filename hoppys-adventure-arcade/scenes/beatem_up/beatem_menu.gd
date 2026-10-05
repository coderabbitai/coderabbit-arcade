extends Control
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
var backdrop: TextureRect
var caption: Label
var clock := 0.0
var preview_index := 0
var started := false
var local_music: AudioStreamPlayer
func _ready() -> void:
	Catalog.install_input()
	theme = Style.theme()
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(.015,.025,.05,.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,48)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",17)
	margin.add_child(column)
	column.add_child(Style.label("HOPPY'S ADVENTURE ARCADE / BEAT'EM UP",16,Style.MINT))
	column.add_child(Style.label("CODE CITY BRAWL",48))
	column.add_child(Style.label("MODE 1 · THREE DISTRICTS. ONE FINAL MERGE.",18,Color("ffc66c")))
	column.add_child(Style.label("Rogue Code is on the loose. Review it with your fists.",18))
	var play := Style.button("Play Code City Brawl  →")
	column.add_child(play)
	play.pressed.connect(func():
		if started: return
		started = true
		AppRouter.go("code_city_brawl"))
	var back := Style.button("Return to Main Menu")
	column.add_child(back)
	back.pressed.connect(func(): AppRouter.go("hub"))
	var quit := Style.button("Quit Game")
	column.add_child(quit)
	quit.pressed.connect(func(): AppRouter.quit_game())
	var instructions := Style.label("WASD / stick: move in 8 directions\nSpace / A: jump   ·   J or X / X: attack\nChain 3 attacks: jab → swing → spinning kick\nE / Y: pick up a weapon   ·   Esc / Start: pause",16)
	column.add_child(instructions)
	caption = Style.label("",16,Style.MINT)
	column.add_child(caption)
	column.add_child(Style.label("Heroes vs. Villains — coming later",13))
	_update_preview()
	local_music = AudioStreamPlayer.new()
	local_music.bus = "Music"
	local_music.volume_db = -16
	local_music.stream = Catalog.looped(Catalog.MUSIC[0])
	add_child(local_music)
	AudioService.music.stop()
	local_music.play()
	play.grab_focus()
func _process(dt: float) -> void:
	clock += dt
	backdrop.scale = Vector2.ONE*(1.03+sin(clock*.15)*.015)
	if clock>=5:
		clock = 0
		preview_index = (preview_index+1)%3
		var fade := create_tween()
		fade.tween_property(backdrop,"modulate:a",0.0,.4)
		fade.tween_callback(_update_preview)
		fade.tween_property(backdrop,"modulate:a",1.0,.6)
func _update_preview() -> void:
	backdrop.texture = load(Art.BASE+Catalog.THEMES[preview_index]+"_background.png")
	caption.text = "%02d / %s" % [preview_index+1,Catalog.TITLES[preview_index]]
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): AppRouter.go("hub")
