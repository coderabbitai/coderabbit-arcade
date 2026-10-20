extends CanvasLayer
const BoothLog := preload("res://app/booth_log.gd")
const BoothHeartbeat := preload("res://app/booth_heartbeat.gd")
const NextPlayerCard := preload("res://app/next_player_card.gd")
const BoothSoak := preload("res://app/booth_soak.gd")
const BoothQrOverlay := preload("res://app/booth_qr_overlay.gd")
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
	"beatem_up": "res://scenes/beatem_up/beatem_menu.tscn",
	"credits": "res://scenes/credits/credits.tscn"
}
## Packaged-build check (`<game> --headless -- --smoke-routes`): load every route, then quit
## nonzero on the first failure. tools/build/export_game.py runs it against each export.
const SMOKE_FLAG := "--smoke-routes"
const SMOKE_FRAMES := 30
## Booth mode (`<game> -- --booth`) is for unattended kiosks: the game runs fullscreen, the menu's
## Quit does nothing, and after IDLE_SECONDS without input any route returns to the attract route
## (the hub, whose rotating previews are the attract screen, unless --attract names another).
## `--route=<name>` opens a route at launch, with or without --booth. Both are off unless passed.
const BOOTH_FLAG := "--booth"
const ROUTE_PREFIX := "--route="
const IDLE_SECONDS := 90.0
const STICK_DEADZONE := 0.4
## Booth analytics (app/booth_log.gd): with --booth, each game session's start and end go to a file
## for this run in the SESSION_LOG_DEFAULT folder. `--session-log=<folder>` (absolute or user://)
## picks another folder and also works without --booth, for playtests. Nothing is logged unless one
## of them is passed.
const SESSION_LOG_PREFIX := "--session-log="
const SESSION_LOG_DEFAULT := "user://booth"
## Watchdog support (app/booth_heartbeat.gd): `--heartbeat=<path>` keeps that file updated with the
## time every two seconds, so tools/booth/watchdog.sh can restart a game that hangs. Off unless
## passed; the watchdog passes it.
const HEARTBEAT_PREFIX := "--heartbeat="
## Booth game over: games call booth_game_over() when the player loses. A booth player gets
## `--retries=<n>` retries (default 0); after that the router lays NextPlayerCard over the game
## and, NEXT_PLAYER_SECONDS later, opens the attract route for the next player. `--attract=<name>`
## picks the attract route for this and the idle return, from ATTRACT_ROUTES. Outside booth mode
## games are unchanged.
const ATTRACT_PREFIX := "--attract="
## Menus that can wait for the next player: each starts its own music (the hub through
## AudioService). Game routes would start playing by themselves, and the platformer menu would be
## silent after a beat 'em up stops the shared music.
const ATTRACT_ROUTES: Array[String] = ["hub", "beatem_up", "runner"]
const RETRIES_PREFIX := "--retries="
const NEXT_PLAYER_SECONDS := 6.0
var busy := false
var veil: ColorRect
var booth := false
var idle_limit := IDLE_SECONDS
var idle_seconds := 0.0
var session_log: BoothLog
var heartbeat: BoothHeartbeat
var attract := "hub"
var retry_limit := 0
## Game overs since the attract route last opened: one player's, as far as a booth can tell.
var game_overs := 0
var next_player: NextPlayerCard
var next_player_left := 0.0
## The soak test (app/booth_soak.gd), when the game was launched with `--soak=<minutes>`.
var soak: BoothSoak
var booth_qr: Control
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
	booth_qr = BoothQrOverlay.new()
	booth_qr.visible = false
	add_child(booth_qr)
	add_child(veil)
	var args := OS.get_cmdline_user_args()
	if SMOKE_FLAG in args:
		smoke_routes.call_deferred()
		return
	attract = attract_route(args)
	retry_limit = retry_count(args)
	set_booth(BOOTH_FLAG in args)
	if booth:
		print("AppRouter: booth attract route %s, %d retries per player" % [attract, retry_limit])
	var beat_path := heartbeat_path(args)
	if beat_path != "":
		heartbeat = BoothHeartbeat.new(beat_path)
		add_child(heartbeat)
		print("AppRouter: heartbeat at %s" % ProjectSettings.globalize_path(beat_path))
	var soak_minutes := BoothSoak.minutes_from(args)
	if soak_minutes > 0.0:
		# The soak changes routes itself: no idle return, no launch route, no next-player card,
		# and no session log, so its visits never count as booth sessions.
		idle_limit = INF
		soak = BoothSoak.new(soak_minutes, args)
		add_child(soak)
		return
	var log_path := session_log_path(args, booth)
	if log_path != "":
		start_session_log(log_path)
	var start := launch_route(args)
	if start != "":
		_launch.call_deferred(start)
## `reason` is how a game session in progress ends, for the session log: "menu" unless the router
## itself is leaving the game (booth mode's idle return passes "idle").
## Returns true once the route's scene has opened, false when the change was refused or failed;
## callers that don't need to know can ignore it.
func go(route: String, reason := "menu") -> bool:
	if busy or not ROUTES.has(route) or not ResourceLoader.exists(ROUTES[route]):
		return false
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
		if session_log:
			session_log.route_changed(route, reason)
		if route == attract:
			game_overs = 0
		if next_player:
			next_player.hide()
		if route == "hub":
			AudioService.play_default_music()
	await create_tween().tween_property(veil, "modulate:a", 0.0, 0.25).finished
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
	return error == OK
## Visitors can't quit a booth from the menu; staff close the window instead (force = true).
## A forced quit wins even mid-transition: auto_accept_quit is off, so nothing else would close.
func quit_game(force := false) -> void:
	if booth and not force:
		return
	if busy and not force:
		return
	if session_log:
		session_log.end("quit")
	if busy:
		AudioService.shutdown()
		get_tree().quit()
		return
	busy = true
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioService.shutdown()
	await create_tween().tween_property(veil, "modulate:a", 1.0, 1.0).finished
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game(true)

## The route named by `--route=<name>`, or "" when absent or unknown (with an error for typos).
static func launch_route(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(ROUTE_PREFIX):
			var route := arg.trim_prefix(ROUTE_PREFIX)
			if ROUTES.has(route):
				return route
			push_error("Unknown --route %s; expected one of %s" % [route, ", ".join(ROUTES.keys())])
	return ""

## The session-log folder these arguments ask for: `--session-log=<folder>`, else the default in
## booth mode, else "" (no logging).
static func session_log_path(args: PackedStringArray, booth_mode: bool) -> String:
	for arg in args:
		if arg.begins_with(SESSION_LOG_PREFIX) and arg.length() > SESSION_LOG_PREFIX.length():
			return arg.trim_prefix(SESSION_LOG_PREFIX)
	return SESSION_LOG_DEFAULT if booth_mode else ""

func start_session_log(folder: String) -> void:
	session_log = BoothLog.new(folder)
	print("AppRouter: session log at %s" % ProjectSettings.globalize_path(session_log.path))

## The heartbeat file named by `--heartbeat=<path>`, or "" when absent.
static func heartbeat_path(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(HEARTBEAT_PREFIX) and arg.length() > HEARTBEAT_PREFIX.length():
			return arg.trim_prefix(HEARTBEAT_PREFIX)
	return ""

## The booth's attract route from `--attract=<name>`: "hub" when absent or not one of
## ATTRACT_ROUTES (with a warning).
static func attract_route(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(ATTRACT_PREFIX):
			var route := arg.trim_prefix(ATTRACT_PREFIX)
			if route in ATTRACT_ROUTES:
				return route
			push_warning("--attract %s is not one of %s; the booth returns to the hub"
				% [route, ", ".join(ATTRACT_ROUTES)])
	return "hub"

## Retries a booth player gets, from `--retries=<n>`: 0 when absent or not a whole number.
static func retry_count(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(RETRIES_PREFIX):
			var value := arg.trim_prefix(RETRIES_PREFIX)
			if value.is_valid_int() and value.to_int() >= 0:
				return value.to_int()
			push_warning("--retries needs a whole number, not %s; using 0" % value)
	return 0

## Games call this when the player loses, before showing their own retry screen. Returns true when
## the booth takes over: the player has used their retries, so the game shows nothing and the
## router thanks them and sends the booth to the attract route. Always false outside booth mode,
## while a route change is already under way (it takes the player elsewhere anyway), and during a
## soak, which changes routes itself. The session log counts every game over, booth or not.
## `score_line` is shown on the card, in the game's own style ("SCORE 01234").
func booth_game_over(score_line := "") -> bool:
	if session_log:
		session_log.count_game_over()
	if not booth or busy or soak != null:
		return false
	game_overs += 1
	if game_overs <= retry_limit:
		return false
	if next_player == null:
		next_player = NextPlayerCard.new()
		add_child(next_player)
		move_child(next_player, 0) # Under the veil, so the route fade covers it.
	next_player_left = NEXT_PLAYER_SECONDS
	next_player.present(score_line, next_player_left)
	return true

func _launch(route: String) -> void:
	await go(route)
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene else "no scene"
	print("AppRouter: launched route %s (%s)" % [route, path])

func set_booth(enabled: bool) -> void:
	# A card counting down over a paused, finished game would strand it: hand off right away.
	var finishing := not enabled and next_player != null and next_player.visible
	booth = enabled
	if booth_qr:
		booth_qr.visible = enabled
	idle_seconds = 0.0
	AudioService.set_attract(enabled)
	game_overs = 0
	if finishing:
		go(attract, "game_over") # The route change hides the card.
	elif next_player:
		next_player.hide()
	set_process(enabled)
	set_process_input(enabled)
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("AppRouter: booth mode on (idle return after %d s)" % int(idle_limit))

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
			or event is InputEventScreenTouch \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE):
		idle_seconds = 0.0

func _process(delta: float) -> void:
	# The game-over card owns the screen until its countdown sends the booth to the attract route.
	if next_player and next_player.visible:
		next_player_left -= delta
		next_player.set_seconds(next_player_left)
		if next_player_left <= 0.0 and not busy:
			# The route change hides the card; if the attract scene fails to load, try again after
			# another countdown rather than every frame.
			next_player_left = NEXT_PLAYER_SECONDS
			go(attract, "game_over")
		return
	idle_seconds += delta
	if idle_seconds < idle_limit or busy:
		return
	idle_seconds = 0.0
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != ROUTES[attract]:
		go(attract, "idle")

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
