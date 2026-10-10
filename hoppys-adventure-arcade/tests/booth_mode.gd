extends SceneTree
## Booth mode: idle routes return to the hub, input keeps a game alive, the menu can't quit
## the kiosk, and --route=<name> picks a launch route. The startup flags are checked by launching
## the game as a child process, so _ready()'s own argument handling is covered.
## Run headless with --script res://tests/booth_mode.gd.
var failures := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func settle_route() -> void:
	for i in 300:
		if not router.busy:
			break
		await process_frame
	await process_frame

## Launch the game headless with user args for two simulated seconds (fixed 60 fps, so the
## route fade always completes) and return its exit code and combined output.
func launch(user_args: Array[String]) -> Dictionary:
	var args: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--quit-after", "120", "--"]
	args.append_array(user_args)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	return {"code": code, "log": "\n".join(output)}

func on_hub() -> bool:
	return current_scene != null and current_scene.scene_file_path == router.ROUTES["hub"]

func run() -> void:
	router = root.get_node("AppRouter")
	await wait(0.3)
	check(not router.booth and not router.is_processing(), "Booth mode is off without --booth")

	var launch: String = router.launch_route(PackedStringArray(["--route=heroes_vs_villains"]))
	check(launch == "heroes_vs_villains", "--route names a launch route")
	launch = router.launch_route(PackedStringArray(["--booth"]))
	check(launch == "", "No --route means the default scene")

	var plain := launch([])
	check(plain.code == 0, "A plain launch exits cleanly")
	check(not plain.log.contains("booth mode on") and not plain.log.contains("launched route"),
		"A plain launch starts without booth mode or a launch route")
	var kiosk := launch(["--booth", "--route=heroes_vs_villains"])
	check(kiosk.code == 0, "A booth launch exits cleanly")
	check(kiosk.log.contains("AppRouter: booth mode on"), "Launching with --booth turns booth mode on")
	var opened: String = "AppRouter: launched route heroes_vs_villains (%s)" \
		% router.ROUTES["heroes_vs_villains"]
	check(kiosk.log.contains(opened), "Launching with --route opens that route's scene")

	router.go("platformer")
	await settle_route()
	await wait(0.5)
	check(not on_hub(), "Without booth mode an idle game stays put")

	router.set_booth(true)
	router.idle_limit = 0.6
	check(router.booth and router.is_processing(), "set_booth enables the idle timer")
	for i in 4:
		await wait(0.25)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_RIGHT
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
	check(not on_hub(), "Input inside the idle window keeps the game running")

	await wait(1.2)
	await settle_route()
	check(on_hub(), "An idle game returns to the hub's attract screen")

	var before: int = router.get_child_count()
	router.quit_game()
	check(not router.busy and router.get_child_count() == before,
		"The menu's Quit is ignored in booth mode")

	router.set_booth(false)
	router.idle_limit = router.IDLE_SECONDS
	await root.get_node("AudioService").settle()
	print("Booth mode failures: ", failures)
	quit(1 if failures else 0)
