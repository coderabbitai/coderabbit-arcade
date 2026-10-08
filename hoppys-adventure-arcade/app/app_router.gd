extends CanvasLayer
const ROUTES := {
	"heroes_vs_villains": "res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn",
	"code_city_brawl": "res://scenes/beatem_up/code_city_brawl.tscn",
	"enchanted_repo": "res://scenes/platformer/enchanted_repo.tscn",
	"orbital_ops": "res://scenes/platformer/orbital_ops.tscn",
	"bay_area_blitz": "res://scenes/platformer/bay_area_blitz.tscn",
	"hub": "res://scenes/main_menu/main_menu.tscn",
	"platformer": "res://scenes/platformer/platformer_menu.tscn",
	"runner": "res://scenes/runner/runner_menu.tscn",
	"runner_game": "res://scenes/runner/runner_game.tscn",
	"beatem_up": "res://scenes/beatem_up/beatem_menu.tscn"
}
## Packaged-build check (`<game> --headless -- --smoke-routes`): load every route, then quit
## nonzero on the first failure. tools/build/export_game.py runs it against each export.
const SMOKE_FLAG := "--smoke-routes"
const SMOKE_FRAMES := 30
var busy := false
var veil: ColorRect
func _ready() -> void:
	# The veil tween must keep running while a microgame has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	layer = 100
	veil = ColorRect.new()
	veil.color = Color.BLACK
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.modulate.a = 0
	add_child(veil)
	if SMOKE_FLAG in OS.get_cmdline_user_args():
		smoke_routes.call_deferred()
func go(route: String) -> void:
	if busy or not ROUTES.has(route) or not ResourceLoader.exists(ROUTES[route]):
		return
	busy = true
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioService.play_ui(2)
	await create_tween().tween_property(veil, "modulate:a", 1.0, 0.25).finished
	var error := get_tree().change_scene_to_file(ROUTES[route])
	if error != OK:
		push_error("Unable to load route: " + route)
	else:
		# A microgame may have paused the tree; never hand a paused tree to the next scene.
		get_tree().paused = false
		if route == "hub":
			AudioService.play_default_music()
	await create_tween().tween_property(veil, "modulate:a", 0.0, 0.25).finished
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
func quit_game() -> void:
	if busy:
		return
	busy = true
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioService.shutdown()
	await create_tween().tween_property(veil, "modulate:a", 1.0, 1.0).finished
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func smoke_routes() -> void:
	# Let the launch scene finish its opening frames, as a player would, before switching.
	for frame in SMOKE_FRAMES:
		await get_tree().process_frame
	for route in ROUTES:
		var error := get_tree().change_scene_to_file(ROUTES[route])
		print("SMOKE %s %s" % [route, error_string(error)])
		if error != OK:
			get_tree().quit(1)
			return
		for frame in SMOKE_FRAMES:
			await get_tree().process_frame
		get_tree().paused = false
	print("SMOKE complete")
	get_tree().unload_current_scene()
	AudioService.shutdown()
	# Give freed scenes and stopped voices a moment to release before exit (as the tests do).
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()
