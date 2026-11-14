extends Control
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Heroes = preload("res://modes/beatem_up/reinvent/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const HeroArt = preload("res://modes/beatem_up/reinvent/art.gd")
const Prompts := preload("res://app/controller_prompts.gd")
var backdrop: TextureRect
var caption: Label
var description: Label
var clock := 0.0
var preview_index := 0
var selected_mode := 0
var started := false
var local_music: AudioStreamPlayer
var fade: Tween
const TILE_MIN_HEIGHT := 240.0

func _ready() -> void:
	Heroes.install_input()
	theme=Style.theme()
	backdrop=TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(.02,.025,.04,.78)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	margin.add_child(column)
	column.add_child(Style.label("HOPPY'S ADVENTURE ARCADE",16,Color("ff9a43")))
	column.add_child(Style.label("BEAT'EM UP / MODE SELECT",38))
	description=Style.label("",17)
	column.add_child(description)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation",36)
	tiles.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(tiles)
	var play := game_tile("Code City Brawl","res://Assets/beatemup-story/code_city/hoppy_clocks_in.png")
	play.name="CodeCityButton"
	tiles.add_child(play)
	play.pressed.connect(func(): launch("code_city_brawl"))
	play.mouse_entered.connect(func(): focus_mode(0))
	play.focus_entered.connect(func(): focus_mode(0))
	var heroes := game_tile("Heroes vs. Villains","res://Assets/beatemup-story/heroes/send_in_the_rabbit.png")
	heroes.name="HeroesButton"
	tiles.add_child(heroes)
	heroes.pressed.connect(func(): launch("heroes_vs_villains"))
	heroes.mouse_entered.connect(func(): focus_mode(1))
	heroes.focus_entered.connect(func(): focus_mode(1))
	# Room for the selected card's grow, so it never covers the buttons below.
	var gap := Control.new()
	gap.custom_minimum_size.y=12
	column.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	column.add_child(row)
	var back := Style.button("Return to Main Menu",44)
	back.custom_minimum_size.x=0
	row.add_child(back)
	back.pressed.connect(func(): AppRouter.go("hub"))
	var quit := Style.button("Quit Game",44)
	quit.custom_minimum_size.x=0
	row.add_child(quit)
	quit.pressed.connect(func(): AppRouter.quit_game())
	play.focus_neighbor_bottom=play.get_path_to(back)
	heroes.focus_neighbor_bottom=heroes.get_path_to(back)
	back.focus_neighbor_top=back.get_path_to(play)
	quit.focus_neighbor_top=quit.get_path_to(heroes)
	var controls := Style.label("",14)
	Prompts.track(controls, func() -> String:
		return "%s: move · %s: jump · %s: combo\n%s: pick up weapon · %s: pause\nHeroes: hold %s to charge REVIEW after unlocking it" % [
			Prompts.keys_or_pad("WASD", Prompts.if_pad("stick")), Prompts.either("Space", &"brawl_jump"), Prompts.either("J or X", &"brawl_attack"),
			Prompts.either("E", &"brawl_pickup"), Prompts.either("Esc", &"pause"), Prompts.either("Q", &"review_burst")])
	column.add_child(controls)
	caption=Style.label("",16,Color("ffb366"))
	column.add_child(caption)
	local_music=AudioStreamPlayer.new()
	local_music.bus="Music";local_music.volume_db=-16
	add_child(local_music)
	AudioService.music.stop()
	focus_mode(0,true)
	play.grab_focus()

## A square game card: the mode's painting on top, its title underneath.
func game_tile(title: String, image: String) -> Button:
	# Each card takes half the row and all the height the column leaves it.
	var tile := Style.button("",TILE_MIN_HEIGHT)
	tile.custom_minimum_size=Vector2(0,TILE_MIN_HEIGHT)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tile.active_scale=1.025
	var card := VBoxContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right"]: card.set("offset_"+side,6 if side!="right" else -6)
	card.offset_bottom=-4
	card.add_theme_constant_override("separation",6)
	card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tile.add_child(card)
	var picture := TextureRect.new()
	picture.texture=load(image)
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.size_flags_vertical=Control.SIZE_EXPAND_FILL
	picture.clip_contents=true
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card.add_child(picture)
	var name_label := Style.label(title,26)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)
	return tile

func launch(route: String) -> void:
	if started: return
	started=true
	AppRouter.go(route)

func focus_mode(mode: int, force := false) -> void:
	if selected_mode==mode and not force: return
	selected_mode=mode;clock=0;preview_index=0
	if fade: fade.kill()
	backdrop.modulate.a=1
	_update_preview()
	description.text="MODE 1 · THREE DISTRICTS. ONE FINAL MERGE." if mode==0 else "MODE 2 · FOUR VILLAINS. REVIEW. TRIAGE. UNDERSTAND. SECURE."
	local_music.stream=Heroes.looped(Catalog.MUSIC[0] if mode==0 else Heroes.MUSIC[0])
	local_music.play()

func _process(dt: float) -> void:
	clock+=dt
	if clock>=4:
		clock=0;preview_index=(preview_index+1)%3
		if fade: fade.kill()
		fade=create_tween()
		fade.tween_property(backdrop,"modulate:a",0.0,.3)
		fade.tween_callback(_update_preview)
		fade.tween_property(backdrop,"modulate:a",1.0,.3)

func _update_preview() -> void:
	backdrop.texture=load(Art.BASE+Catalog.THEMES[preview_index]+"_background.png" if selected_mode==0 else HeroArt.BASE+Heroes.THEMES[preview_index]+".png")
	caption.text="%02d / %s" % [preview_index+1,Catalog.TITLES[preview_index] if selected_mode==0 else Heroes.TITLES[preview_index]]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): AppRouter.go("hub")
