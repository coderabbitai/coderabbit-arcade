extends Control
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Heroes = preload("res://modes/beatem_up/reinvent/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const HeroArt = preload("res://modes/beatem_up/reinvent/art.gd")
var backdrop: TextureRect
var caption: Label
var description: Label
var clock := 0.0
var preview_index := 0
var selected_mode := 0
var started := false
var local_music: AudioStreamPlayer
var fade: Tween

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
	var play := Style.button("Play Code City Brawl  →",54)
	play.name="CodeCityButton"
	column.add_child(play)
	play.pressed.connect(func(): launch("code_city_brawl"))
	play.mouse_entered.connect(func(): focus_mode(0))
	play.focus_entered.connect(func(): focus_mode(0))
	var heroes := Style.button("Play Heroes vs. Villains  →",54)
	heroes.name="HeroesButton"
	column.add_child(heroes)
	heroes.pressed.connect(func(): launch("heroes_vs_villains"))
	heroes.mouse_entered.connect(func(): focus_mode(1))
	heroes.focus_entered.connect(func(): focus_mode(1))
	var back := Style.button("Return to Main Menu",48)
	column.add_child(back)
	back.pressed.connect(func(): AppRouter.go("hub"))
	var quit := Style.button("Quit Game",48)
	column.add_child(quit)
	quit.pressed.connect(func(): AppRouter.quit_game())
	column.add_child(Style.label("WASD / stick: move · Space / A: jump · J or X / X: combo\nE / Y: pick up weapon · Esc / Start: pause\nHeroes: hold Q / LB to charge REVIEW after unlocking it",14))
	caption=Style.label("",16,Color("ffb366"))
	column.add_child(caption)
	local_music=AudioStreamPlayer.new()
	local_music.bus="Music";local_music.volume_db=-16
	add_child(local_music)
	AudioService.music.stop()
	focus_mode(0,true)
	play.grab_focus()

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
