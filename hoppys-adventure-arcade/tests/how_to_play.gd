extends SceneTree
## How-to-play cards (app/how_to_play.gd, app/how_to_play_data.gd, app/how_to_play_demo.gd): every
## game has one, a few pages long; every key and pad input a card shows is bound to the row's
## actions; every sprite clip and image a page or row icon uses exists, and every page builds; the
## keyboard and controller text reads right for each controller family; AppRouter opens the card
## once per visitor, paused; confirm/jump/attack/click turn the pages and the last one starts the
## game, left/right flip pages, pause skips, a stray early press does nothing, and each page turns
## by itself; the press that closes it never reaches the game; booth idle still counts and still returns to the
## attract route; focus loss under the card leaves the game's own pause menu working; and each
## game's pause menu reopens the card without unpausing. Run headless with
## --script res://tests/how_to_play.gd.
const HowToPlay := preload("res://app/how_to_play.gd")
const Data := preload("res://app/how_to_play_data.gd")
const HeroesCatalog := preload("res://modes/beatem_up/reinvent/catalog.gd")
const Demo := preload("res://app/how_to_play_demo.gd")
const RUNNER_SCORES := "user://test_how_to_play_leaderboard.cfg"
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
	for i in 3:
		await process_frame

func visit(route: String) -> void:
	router.go(route)
	await settle_route()

func on(route: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == router.ROUTES[route]

## The card on screen, START or PAUSE, or null.
func card() -> Node:
	for i in range(root.get_child_count() - 1, -1, -1):
		var child := root.get_child(i)
		if child.get_script() == HowToPlay and not child.is_queued_for_deletion() and child.visible:
			return child
	return null

func key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

## Sends a pointer press and then its release, so no button or touch stays held into later checks.
func press_and_release(event: InputEvent) -> void:
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEvent = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code)
	key(code, false)

## Waits for the card to finish handing the game back.
func handed_back() -> void:
	for i in 10:
		await physics_frame
	await process_frame

func run() -> void:
	router = root.get_node("AppRouter")
	HeroesCatalog.install_input()
	every_game_has_a_card()
	cards_match_the_input_map()
	art_exists()
	await every_page_builds()
	text_reads_right()
	check(not router.how_to_play_enabled, "Test suites (--script) get no cards unless they ask")
	router.how_to_play_enabled = true
	await opens_once_per_visitor()
	await pages_turn()
	await closes_on_purpose_only()
	await closes_by_itself()
	await booth_idle_still_counts()
	await focus_loss_keeps_the_pause_menu()
	await every_route_opens_its_card()
	await pause_menus_reopen_it()
	router.how_to_play_enabled = false
	await visit("hub")
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(RUNNER_SCORES + suffix):
			DirAccess.remove_absolute(RUNNER_SCORES + suffix)
	await root.get_node("AudioService").settle()
	print("How to play failures: ", failures)
	quit(1 if failures else 0)

func every_game_has_a_card() -> void:
	var gameplay: Array = root.get_node("ControllerService").GAMEPLAY_ROUTES
	for route: String in gameplay:
		check(Data.has_game(route), "Gameplay route %s has a how-to-play card" % route)
	for route: String in Data.GAMES:
		check(route in gameplay, "Card %s is for a gameplay route" % route)
		var game := Data.game(route)
		var pages := Data.pages(route)
		check(not str(game.title).is_empty() and not game.rows.is_empty() and pages.size() >= 3,
			"Card %s has a title, controls and at least three pages" % route)
		check(pages.filter(func(page: Dictionary) -> bool: return page.get("controls", false)).size() == 1,
			"Card %s has one controls page" % route)
		for page: Dictionary in pages:
			if page.get("controls", false):
				continue
			check(not str(page.get("text", "")).is_empty() and str(page.scene.id) in Demo.SCENES,
				"Card %s page %s has text and a known scene" % [route, page.heading])
		var labels: Array = game.rows.map(func(row: Dictionary) -> String: return row.label)
		check("Pause" in labels and ("Jump" in labels), "Card %s shows Jump and Pause" % route)
	var orbital: Array = Data.game("orbital_ops").rows.map(func(row: Dictionary) -> String: return row.label)
	check("Zero-G rise" in orbital and "Zero-G sink" in orbital, "Orbital Ops shows the zero-G controls")

## True when `action` has a binding for pad entry `pad` (a JoyButton or a Data.STICK* value).
func pad_bound(action: String, pad: int) -> bool:
	for event in InputMap.action_get_events(action):
		if pad >= 0 and event is InputEventJoypadButton and event.button_index == pad:
			return true
		if pad < 0 and event is InputEventJoypadMotion:
			var vertical: bool = event.axis == JOY_AXIS_LEFT_Y
			if pad == Data.STICK and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
				return true
			if pad == Data.STICK_UP and vertical and event.axis_value < 0:
				return true
			if pad == Data.STICK_DOWN and vertical and event.axis_value > 0:
				return true
	return false

func key_bound(action: String, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.physical_keycode == code or event.keycode == code):
			return true
	return false

func cards_match_the_input_map() -> void:
	for route: String in Data.GAMES:
		for row: Dictionary in Data.game(route).rows:
			var where := "%s / %s" % [route, row.label]
			for action: String in row.actions:
				check(InputMap.has_action(action), "%s: action %s exists" % [where, action])
			for code: int in row.keys:
				check(row.actions.any(func(action: String) -> bool: return InputMap.has_action(action) and key_bound(action, code)),
					"%s: key %s is bound to %s" % [where, OS.get_keycode_string(code), row.actions])
			for pad: int in row.pad:
				check(row.actions.any(func(action: String) -> bool: return InputMap.has_action(action) and pad_bound(action, pad)),
					"%s: pad input %d is bound to %s" % [where, pad, row.actions])
	# The card closes on these, so each must exist in some game.
	for action in [&"ui_accept", &"jump", &"attack", &"pause", &"brawl_jump", &"brawl_attack"]:
		check(InputMap.has_action(action), "Dismiss action %s exists" % action)

func clip_exists(sheet: String, clip: String) -> bool:
	var frames := load(sheet) as SpriteFrames
	return frames != null and frames.has_animation(clip)

## Every sheet, clip and image the pages and row icons name is there.
func art_exists() -> void:
	for name: String in Demo.WORLDS:
		var setting: Dictionary = Demo.WORLDS[name]
		var image: String = setting.get("room", setting.get("sky", ""))
		check(load(image) is Texture2D, "World %s backdrop %s loads" % [name, image])
	for route: String in Data.GAMES:
		var poses: Dictionary = Data.game(route).get("poses", {})
		for row: Dictionary in Data.game(route).rows:
			if row.has("icon"):
				check(poses.has(row.icon), "%s / %s: icon %s has a pose" % [route, row.label, row.icon])
		for name: String in poses:
			check(clip_exists(poses[name][0], poses[name][1]), "%s: pose %s's clip %s exists" % [route, name, poses[name][1]])
		for page: Dictionary in Data.pages(route):
			var scene: Dictionary = page.get("scene", {})
			if scene.has("world"):
				check(Demo.WORLDS.has(scene.world), "%s: scene world %s is known" % [route, scene.world])
			for image in scene.get("images", []):
				check(load(image) is Texture2D, "%s: image %s loads" % [route, image])
			if scene.has("boss"):
				check(clip_exists(scene.boss, "idle") and clip_exists(scene.boss, "defeat"), "%s: boss %s has idle and defeat" % [route, scene.boss])

## Opens every card on every page outside any game and checks it has something on it; scenes
## that name a missing clip print an error here.
func every_page_builds() -> void:
	for route: String in Data.GAMES:
		var shown: Node = HowToPlay.open(self, route, HowToPlay.Mode.PAUSE)
		for index in Data.pages(route).size():
			shown.show_page(index)
			for i in 20:
				await process_frame
			var body: Node = shown._body
			var filled: bool = body.get_child_count() > 0
			if Data.pages(route)[index].get("controls", false):
				filled = shown._controls != null and shown._controls.get_child_count() >= 4 * (Data.game(route).rows.size() + 1)
			else:
				var demo: Node = body.get_child(0)
				filled = demo is Control and demo.loop != null and demo.loop.is_running() and \
					(demo.world.get_child_count() > 0 or str(demo.spec.id) == "slideshow")
			check(filled, "%s page %d builds and plays" % [route, index + 1])
			if filled and not Data.pages(route)[index].get("controls", false) and str(shown._body.get_child(0).spec.id) != "slideshow":
				enemies_face_hoppy(shown._body.get_child(0), "%s page %d" % [route, index + 1])
		shown.close()
		await process_frame

## Enemy and boss sheets are drawn facing left, Hoppy's facing right (the games flip an enemy only to
## face right): on the stage, every enemy faces Hoppy.
func enemies_face_hoppy(demo: Node, where: String) -> void:
	var hoppy: AnimatedSprite2D = null
	var others: Array[AnimatedSprite2D] = []
	for child in demo.world.get_children():
		if not child is AnimatedSprite2D:
			continue
		var file: String = child.sprite_frames.resource_path.get_file()
		if file in ["platformer.tres", "combat.tres", "hoppy.tres", "hoppy_locomotion.tres"]:
			hoppy = child
		elif not file in ["pickups.tres", "interactives.tres", "hazards.tres", "items_allies.tres", "weapons.tres", "capabilities_fx.tres"]:
			others.append(child)
	if hoppy == null:
		return
	for enemy in others:
		var toward_left: bool = enemy.position.x > hoppy.position.x
		check(enemy.flip_h != toward_left, "%s: %s faces Hoppy" % [where, enemy.sprite_frames.resource_path.get_file()])

func text_reads_right() -> void:
	check(HowToPlay.keys_text([KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]) == "A / D / ← →", "Platformer move keys read A / D / ← →")
	check(HowToPlay.keys_text([KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]) == "WASD / Arrows", "Brawler move keys read WASD / Arrows")
	check(HowToPlay.keys_text([KEY_SPACE, KEY_W, KEY_UP]) == "Space / W / ↑", "Jump keys read Space / W / ↑")
	check(HowToPlay.keys_text([KEY_ESCAPE, KEY_P]) == "Esc / P", "Pause keys read Esc / P")
	check(HowToPlay.keys_text([KEY_S, KEY_CTRL, KEY_DOWN]) == "S / Ctrl / ↓", "Roll keys read S / Ctrl / ↓")
	check(HowToPlay.pad_text([JOY_BUTTON_A], "") == "A / Cross", "No controller: A reads A / Cross")
	check(HowToPlay.pad_text([JOY_BUTTON_X], "playstation") == "Square", "PlayStation: X reads Square")
	check(HowToPlay.pad_text([JOY_BUTTON_A], "nintendo") == "B", "Nintendo: the bottom button reads B")
	check(HowToPlay.pad_text([JOY_BUTTON_START], "") == "Start", "No controller: Start reads Start")
	check(HowToPlay.pad_text([JOY_BUTTON_LEFT_SHOULDER], "") == "LB / L1", "No controller: LB reads LB / L1")
	check(HowToPlay.pad_text([Data.STICK, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT], "xbox") == "Left stick / D-pad",
		"Movement reads Left stick / D-pad")
	check(HowToPlay.pad_text([Data.STICK_DOWN, JOY_BUTTON_DPAD_DOWN], "xbox") == "Stick ↓ / D-pad ↓",
		"Zero-G sink reads Stick ↓ / D-pad ↓")
	check(HowToPlay.face_button([Data.STICK, JOY_BUTTON_Y]) == JOY_BUTTON_Y and HowToPlay.face_button([JOY_BUTTON_START]) == -1,
		"Rows with a face button get its glyph")

func opens_once_per_visitor() -> void:
	await visit("hub")
	check(card() == null, "The hub has no card")
	await visit("bay_area_blitz")
	var shown := card()
	check(shown != null and shown.route == "bay_area_blitz" and shown.mode == HowToPlay.Mode.START,
		"Entering Bay Area Blitz opens its card")
	check(paused, "The card holds the game paused")
	check(shown != null and shown.get_index() == root.get_child_count() - 1, "The card is the root's last child (first to see input)")
	await close_with(KEY_ESCAPE)
	check(card() == null and not paused, "Esc skips the card and the game plays")
	await visit("bay_area_blitz")
	check(card() == null, "A retry skips the card")
	await visit("platformer")
	await visit("bay_area_blitz")
	check(card() == null, "Coming back from the platformer menu skips the card")
	await visit("hub")
	await visit("bay_area_blitz")
	check(card() != null, "A new visitor (the hub opened) sees the card again")
	await close_with(KEY_ESCAPE)

## Wait past the arming delay, then press `code` (Esc skips the card).
func close_with(code: Key) -> void:
	var shown := card()
	if shown:
		shown.age = HowToPlay.ARM_SECONDS
	tap(code)
	await handed_back()

func pages_turn() -> void:
	await visit("hub")
	await visit("orbital_ops")
	var shown := card()
	var pages := Data.pages("orbital_ops").size()
	check(shown != null and shown.page == 0 and shown.page_count() == pages, "The card opens on its first page")
	shown.age = HowToPlay.ARM_SECONDS
	tap(KEY_SPACE)
	check(shown.page == 1 and shown._controls != null, "Space turns to the next page (controls)")
	tap(KEY_RIGHT)
	check(shown.page == 2, "→ turns forward")
	tap(KEY_A)
	check(shown.page == 1, "A (move left) turns back")
	tap(KEY_LEFT)
	tap(KEY_LEFT)
	check(shown.page == 0 and card() == shown, "← stops at the first page")
	for i in pages + 2:
		tap(KEY_RIGHT)
	check(shown.page == pages - 1 and card() == shown and shown.is_last_page(), "→ stops at the last page, never closes")
	check(shown._footer.text.ends_with("to play"), "The last page says how to start: %s" % shown._footer.text)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	for value in [-0.9, -1.0, -0.95]:
		stick.axis_value = value
		Input.parse_input_event(stick)
		Input.flush_buffered_events()
	check(shown.page == pages - 2, "Holding the stick left flips one page")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()
	tap(KEY_SPACE)
	check(shown.page == pages - 1 and card() == shown, "Space on the next-to-last page turns, not closes")
	var level := current_scene
	var start_y: float = level.player.global_position.y
	tap(KEY_SPACE)
	await handed_back()
	check(card() == null and not paused, "Space on the last page starts the game")
	await wait(0.3)
	check(level.player.global_position.y >= start_y - 2.0, "Hoppy didn't jump on the Space that started the game")
	# The same, with Space still held down after the game is handed back.
	await visit("hub")
	await visit("orbital_ops")
	shown = card()
	shown.age = HowToPlay.ARM_SECONDS
	shown.show_page(shown.page_count() - 1)
	level = current_scene
	start_y = level.player.global_position.y
	key(KEY_SPACE)
	await handed_back()
	check(card() == null and not paused, "A held Space on the last page starts the game")
	await wait(0.3)
	check(level.player.global_position.y >= start_y - 2.0, "Holding the Space that started the game doesn't make Hoppy jump")
	key(KEY_SPACE, false)
	await wait(0.2)

func closes_on_purpose_only() -> void:
	await visit("hub")
	await visit("bay_area_blitz")
	var level := current_scene
	var start_y: float = level.player.global_position.y
	tap(KEY_SPACE)
	await handed_back()
	check(card() != null, "A press in the first half second (left over from the menu) is ignored")
	card().age = HowToPlay.ARM_SECONDS
	tap(KEY_D)
	tap(KEY_RIGHT)
	tap(KEY_RIGHT)
	tap(KEY_RIGHT)
	await handed_back()
	check(card() != null, "Movement keys don't close the card")
	tap(KEY_ESCAPE)
	await handed_back()
	check(card() == null and not paused, "Esc closes the card and the game plays")
	check(not level.overlay.visible, "The Esc that closed the card never reached the level's pause toggle")
	await wait(0.3)
	check(level.player.global_position.y >= start_y - 2.0, "Hoppy didn't jump on the closing press")
	await visit("hub")
	await visit("orbital_ops")
	var shown := card()
	shown.age = HowToPlay.ARM_SECONDS
	tap(KEY_J)
	await handed_back()
	check(card() == shown and shown.page == 1, "Attack (J) turns the page")
	shown.show_page(shown.page_count() - 1)
	tap(KEY_J)
	await handed_back()
	check(card() == null and not paused, "Attack (J) on the last page starts the game")
	await visit("hub")
	await visit("enchanted_repo")
	shown = card()
	shown.age = HowToPlay.ARM_SECONDS
	shown.show_page(shown.page_count() - 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(640, 360)
	press_and_release(click)
	await handed_back()
	check(card() == null and not paused, "A click on the last page starts the game")
	await visit("hub")
	await visit("enchanted_repo")
	shown = card()
	shown.age = HowToPlay.ARM_SECONDS
	for spec in [[MOUSE_BUTTON_WHEEL_DOWN, 0], [MOUSE_BUTTON_RIGHT, 0], [MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION]]:
		var other := InputEventMouseButton.new()
		other.button_index = spec[0]
		other.device = spec[1]
		other.pressed = true
		other.position = Vector2(640, 360)
		press_and_release(other)
	check(card() == shown and shown.page == 0, "The wheel, right-click and touch-emulated clicks don't turn pages")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(640, 360)
	press_and_release(touch)
	check(shown.page == 1, "One tap turns one page")
	await close_with(KEY_ESCAPE)

func closes_by_itself() -> void:
	await visit("hub")
	await visit("bay_area_blitz")
	var shown := card()
	check(shown != null and shown.countdown > HowToPlay.PAGE_SECONDS - 1.0,
		"Each page counts down from %d s" % int(HowToPlay.PAGE_SECONDS))
	shown.countdown = 0.2
	await wait(0.5)
	check(card() == shown and shown.page == 1 and shown.countdown > HowToPlay.PAGE_SECONDS - 1.0,
		"A page turns by itself and the next one starts its own countdown")
	check(shown.PAGE_SECONDS * shown.page_count() < router.IDLE_SECONDS / 2.0, "A whole card is well inside the booth idle reset")
	shown.show_page(shown.page_count() - 1)
	shown.countdown = 0.2
	await wait(0.5)
	await handed_back()
	check(card() == null and not paused, "The last page closes by itself and the game plays")

func booth_idle_still_counts() -> void:
	router.set_booth(true)
	await visit("hub")
	await visit("orbital_ops")
	check(card() != null, "Booth mode opens the card too")
	router.idle_seconds = 50.0
	tap(KEY_D)
	check(router.idle_seconds < 1.0, "A press the card swallows still resets the booth idle timer")
	router.idle_limit = 0.4
	await wait(0.8)
	await settle_route()
	check(on("hub") and card() == null and not paused, "Booth idle returns to the attract route from under the card")
	router.idle_limit = router.IDLE_SECONDS
	router.set_booth(false)

func focus_loss_keeps_the_pause_menu() -> void:
	await visit("hub")
	await visit("bay_area_blitz")
	var level := current_scene
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(level.is_player_paused(), "Focus loss under the card opens the level's pause menu")
	var shown := card()
	var before: float = shown.countdown
	await wait(0.3)
	check(is_equal_approx(shown.countdown, before), "The countdown waits while the window is in the background")
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait(0.3)
	check(shown.countdown < before - 0.1, "The countdown resumes once the window has focus again")
	await close_with(KEY_ESCAPE)
	check(card() == null and paused and level.is_player_paused(), "Closing the card leaves the game in its pause menu")
	level._resume()
	check(not paused, "The pause menu still resumes the level")

func every_route_opens_its_card() -> void:
	for route: String in ["bay_area_blitz", "orbital_ops", "enchanted_repo", "runner_game", "code_city_brawl", "heroes_vs_villains"]:
		await visit("hub")
		await visit(route)
		var shown := card()
		check(on(route) and shown != null and shown.route == route and paused, "%s opens its card, paused" % route)
		if shown:
			shown.age = HowToPlay.ARM_SECONDS
		tap(KEY_ESCAPE)
		await handed_back()
		check(card() == null and not paused, "%s plays once its card closes" % route)

func reopen(button: Button, route: String) -> void:
	check(button != null and button.visible, "%s's pause menu has a How to Play button" % route)
	if button == null:
		return
	button.grab_focus()
	button.pressed.emit()
	var shown := card()
	check(shown != null and shown.mode == HowToPlay.Mode.PAUSE and shown.route == route, "%s: How to Play reopens the card" % route)
	if shown == null:
		return
	check(not shown._bar_track.visible, "%s: the reopened card has no countdown" % route)
	shown.age = HowToPlay.ARM_SECONDS
	shown.countdown = -1.0
	await process_frame
	check(card() == shown and shown.page == 0, "%s: the reopened card never turns by itself" % route)
	tap(KEY_SPACE)
	check(shown.page == 1 and card() == shown, "%s: Space turns its pages" % route)
	tap(KEY_ESCAPE)
	await handed_back()
	check(card() == null and paused, "%s: Esc closes it and the game stays paused" % route)
	check(button.has_focus(), "%s: focus returns to How to Play" % route)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := find_button(child, text)
		if found:
			return found
	return null

func pause_menus_reopen_it() -> void:
	router.how_to_play_enabled = false
	await visit("bay_area_blitz")
	var level := current_scene
	level._pause()
	await reopen(level.how_to_play_button, "bay_area_blitz")
	level._resume()
	await visit("code_city_brawl")
	current_scene.pause("test")
	await process_frame
	await reopen(find_button(current_scene.panel, "How to Play"), "code_city_brawl")
	check(current_scene.is_player_paused(), "code_city_brawl: still in its pause menu")
	await visit("heroes_vs_villains")
	current_scene.state = "combat"
	tap(KEY_ESCAPE)
	await process_frame
	await reopen(find_button(current_scene.panel, "How to Play"), "heroes_vs_villains")
	check(current_scene.is_player_paused(), "heroes_vs_villains: still in its pause menu")
	current_scene.resume()
	await visit("runner_game")
	var runner := current_scene
	runner.leaderboard_path = RUNNER_SCORES
	runner.skip_run_intro()
	for i in 600:
		if runner.state == &"running" and not runner.can_skip_run_intro():
			break
		await process_frame
	await wait(0.2)
	runner.pause()
	await process_frame
	await reopen(find_button(root, "How to Play"), "runner_game")
	check(runner.is_player_paused(), "runner_game: still paused")
	runner.resume()
	router.how_to_play_enabled = true
