extends SceneTree
## The top-right minimap of both beat'em ups: tile layout and states, point mapping, per-state
## visibility, the pause freeze, and the layout against the HUD and boss bars at two window sizes.
## The host ticks by hand; nothing here depends on a Tween.
const Minimap = preload("res://modes/beatem_up/minimap.gd")
const DT := 1.0/60.0
const SIZES := [Vector2(1280,720), Vector2(1920,1080)]
var failures := 0
var checks := 0
var game

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func freeze() -> void:
	game.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)
		game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if "bosses" in game:
		for e in game.bosses:
			if is_instance_valid(e): e.set_physics_process(false)
	elif is_instance_valid(game.boss):
		game.boss.set_physics_process(false)
func load_mode(path: String) -> void:
	change_scene_to_file(path)
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	paused = false
	if game.state == "paused": game.resume()
	freeze()
func step(until: Callable, limit := 3000) -> void:
	var guard := 0
	while not until.call() and guard < limit:
		game._physics_process(DT)
		guard += 1
func tick_once() -> void:
	game._physics_process(DT)
func shown() -> bool:
	return game.minimap.visible
func rect_of(node: Control) -> Rect2:
	return node.get_global_rect()

func run() -> void:
	check_geometry()
	await load_mode("res://scenes/beatem_up/code_city_brawl.tscn")
	await check_mode("Code City", [Vector2i(2,2)], false)
	await load_mode("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	await check_mode("HvV", [Vector2i(0,2), Vector2i(1,2), Vector2i(2,2)], true)
	print("Minimap checks: ", checks, " failures: ", failures)
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(0.4).timeout
	quit(1 if failures else 0)

## The pure helpers, on a standalone minimap.
func check_geometry() -> void:
	var map := Minimap.new()
	var bosses: Array[Vector2i] = [Vector2i(2,2)]
	map.setup(3, 3, bosses, Color.WHITE)
	var rooms := 0
	var inside := true
	var disjoint := true
	var order := true
	var all: Array[Rect2] = []
	for s in 3:
		for r in 3:
			rooms += 1
			var rect := map.tile_rect(s, r)
			if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2(Vector2.ZERO, Minimap.SIZE).encloses(rect): inside = false
			for other in all:
				if other.intersects(rect): disjoint = false
			all.append(rect)
	for s in 3:
		for r in 2:
			if map.tile_rect(s, r+1).position.x <= map.tile_rect(s, r).position.x: order = false
		if s < 2 and map.tile_rect(s+1, 0).position.x <= map.tile_rect(s, 2).end.x: order = false
	check(rooms == 9 and all.size() == 9, "The strip has nine tiles (3 stages x 3 rooms)")
	check(inside and disjoint and order, "The nine tiles are inside the panel, disjoint and left to right")
	var markers := 0
	for s in 3:
		for r in 3:
			if map.is_boss_room(s, r): markers += 1
	check(markers == 1 and map.is_boss_room(2, 2) and not map.is_boss_room(0, 2), "Code City marks only (2,2) as a boss room")
	var heroes: Array[Vector2i] = [Vector2i(0,2), Vector2i(1,2), Vector2i(2,2)]
	map.setup(3, 3, heroes, Color.WHITE)
	markers = 0
	for s in 3:
		for r in 3:
			if map.is_boss_room(s, r): markers += 1
	check(markers == 3 and map.is_boss_room(0, 2) and map.is_boss_room(1, 2) and not map.is_boss_room(1, 1), "HvV marks the last room of every stage")
	check(Minimap.SIZE.x <= 260 and Minimap.SIZE.y <= 110, "The minimap is a small panel")
	# map_point clamps into the room.
	var left := 2560.0
	var run_in := Minimap.map_point(Vector2(left-60, 550), left)
	check(is_equal_approx(run_in.x, 0.0), "The run-in from x=-60 clamps to the room's left edge")
	var out := Minimap.map_point(Vector2(left+1280+400, 550), left)
	check(is_equal_approx(out.x, 1.0), "The walk-out past the gate clamps to the right edge")
	var mid := Minimap.map_point(Vector2(left+640, (Minimap.DEPTH_TOP+Minimap.DEPTH_BOTTOM)/2.0), left)
	check(is_equal_approx(mid.x, .5) and is_equal_approx(mid.y, .5), "The room's middle maps to (.5, .5)")
	check(is_equal_approx(Minimap.map_point(Vector2(left, 0), left).y, 0.0) and is_equal_approx(Minimap.map_point(Vector2(left, 9999), left).y, 1.0), "Depth clamps to the belt band")
	# Dots always land inside room_rect, even for wild snapshots.
	map.tick(DT, {"stage":1, "room":1, "room_left":1280.0, "player":Vector2(-300, -50),
		"enemies":PackedVector2Array([Vector2(1280, 455), Vector2(9999, 9999), Vector2(2000, 550)]),
		"bosses":PackedVector2Array([Vector2(-5000, 700)])})
	var inside_room := true
	var dots := [map.player_dot]
	dots.append_array(map.enemy_dots)
	dots.append_array(map.boss_dots)
	check(map.enemy_dots.size() == 3 and map.boss_dots.size() == 1, "Every enemy and boss in the snapshot gets a dot")
	for dot in dots:
		if not map.room_rect().encloses(Rect2(map.dot_position(dot), Vector2.ZERO)): inside_room = false
	check(inside_room, "Every dot lands inside the room rect")
	# tile_state follows (stage, room).
	var ok := true
	for s in 3:
		for r in 3:
			map.tick(DT, {"stage":s, "room":r})
			for ts in 3:
				for tr in 3:
					var want := "ahead"
					if ts < s or (ts == s and tr < r): want = "cleared"
					elif ts == s and tr == r: want = "current"
					if map.tile_state(ts, tr) != want: ok = false
	check(ok, "tile_state is cleared before, current at, and ahead of (stage, room) for all 81 pairs")
	var level_ok := true
	for i in 120:
		map.tick(DT, {})
		var level := map.pulse_level()
		if level < .59 or level > 1.01: level_ok = false
	check(level_ok, "The pulse stays within .6..1")
	map.tick(DT, {"stage":9, "room":-4})
	check(map.stage == 2 and map.room == 0, "Out-of-range stage and room clamp")
	map.free()

func ui_of() -> Control:
	return game.minimap.get_parent() as Control
func hud_bar() -> Control:
	for child in ui_of().get_children():
		if child is ColorRect: return child
	return null
func child_index(node: Node) -> int:
	return node.get_index()

func check_mode(label: String, bosses: Array[Vector2i], heroes: bool) -> void:
	var map = game.minimap
	var states: Array = game.MINIMAP_STATES
	check(map != null and map.get_parent() != null, "%s has a minimap" % label)
	check(map.boss_rooms.size() == bosses.size(), "%s: %d boss markers" % [label, bosses.size()])
	for boss in bosses: check(map.is_boss_room(boss.x, boss.y), "%s: boss room %s is marked" % [label, boss])
	check(map.stage_count * map.rooms_per_stage == 9, "%s: nine tiles" % label)
	check("combat" in states and not ("intro" in states) and not ("won" in states) and not ("game_over" in states), "%s: MINIMAP_STATES holds combat and not intro, won or game over" % label)
	# --- visibility ---
	if heroes:
		check(game.state == "cards" and game.card_queue.size() == 3, "HvV opens on its cards")
		tick_once()
		check(not shown(), "HvV: hidden under the opening cards")
		game.flow.cancel()
		game.start_stage(1)
		freeze()
	else:
		game.flow.cancel()
		game.start_stage(0, true)
		freeze()
		await process_frame
		check(game.state == "intro", "Code City opens on the intro")
		tick_once()
		check(not shown(), "Code City: hidden during the intro")
		game.flow.cancel()
		game.start_stage(1)
		freeze()
	step(func(): return game.state == "stage_enter" and game.flow.banner_active(), 1200)
	check(game.flow.banner_active(), "%s: the stage title banner comes up" % label)
	check(game.state == "stage_enter" and not shown(), "%s: hidden while the stage title banner is up" % label)
	step(func(): return game.state == "combat" and not game.flow.banner_active(), 3000)
	check(game.state == "combat" and not game.flow.banner_active(), "%s: combat starts and the banner fades" % label)
	tick_once()
	check(shown(), "%s: shown in combat once the banner is gone" % label)
	await check_layout(label, heroes)
	check_order(label, heroes)
	await check_pause(label, heroes)
	# Exiting is a minimap state too.
	game.state = "stage_exit"
	tick_once()
	check(shown() or game.flow.banner_active(), "%s: stage_exit keeps the map up" % label)
	game.state = "combat"
	# --- hidden at the end screens ---
	if heroes:
		game.show_cards(Catalog_ending(), game.win)
		tick_once()
		check(game.state == "cards" and not shown(), "HvV: hidden under the ending cards")
		game.win()
		tick_once()
		check(game.state == "won" and not shown(), "HvV: hidden on the results screen")
	else:
		game.state = "finisher"
		tick_once()
		check(shown(), "Code City: shown during the finisher")
		game.start_ending()
		tick_once()
		check(game.state == "ending" and not shown(), "Code City: hidden during the ending")
		game.finish_story()
		tick_once()
		check(game.state == "won" and not shown(), "Code City: hidden on the results screen")
	game.state = "combat"
	game.playing = true
	game.victory.hide()
	game.game_over()
	tick_once()
	check(game.state == "game_over" and not shown(), "%s: hidden on game over" % label)

func Catalog_ending() -> Array:
	return load("res://modes/beatem_up/reinvent/catalog.gd").ENDING_CARDS.duplicate()

func check_layout(label: String, heroes: bool) -> void:
	var map = game.minimap
	var ui := ui_of()
	var saved := [ui.anchor_left, ui.anchor_top, ui.anchor_right, ui.anchor_bottom]
	var avoid: Array[Control] = [game.boss_bar, game.boss_text]
	if heroes: avoid.append_array([game.second_boss_bar, game.second_boss_text])
	for size: Vector2 in SIZES:
		ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ui.position = Vector2.ZERO
		ui.size = size
		await process_frame
		var rect := rect_of(map)
		var bar := hud_bar()
		check(is_equal_approx(ui.size.x, size.x) and bar != null, "%s %s: the HUD is laid out at this size" % [label, size])
		var clear := true
		for node in avoid:
			if rect.intersects(rect_of(node)): clear = false
		check(clear, "%s %s: the minimap clears the boss bars and their text" % [label, size])
		var gap: float = size.x-rect.end.x
		check(gap >= 0 and gap <= 24, "%s %s: the minimap sits within 24 px of the right edge (%.0f)" % [label, size, gap])
		check(rect.position.y >= rect_of(bar).end.y and rect.end.y <= size.y, "%s %s: the minimap sits under the HUD top bar" % [label, size])
		check(is_equal_approx(rect.size.x, Minimap.SIZE.x) and is_equal_approx(rect.size.y, Minimap.SIZE.y), "%s %s: the minimap keeps its size" % [label, size])
	ui.anchor_left = saved[0]; ui.anchor_top = saved[1]; ui.anchor_right = saved[2]; ui.anchor_bottom = saved[3]
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

func check_order(label: String, heroes: bool) -> void:
	var map = game.minimap
	var over: Array = [game.victory, game.overlay]
	over.append(game.card_host if heroes else game.story)
	var ok := true
	for node in over:
		if node.get_parent() != map.get_parent() or node.get_index() <= map.get_index(): ok = false
	check(ok, "%s: the minimap is drawn under the %s, the results and the overlay" % [label, "cards" if heroes else "story"])

func check_pause(label: String, heroes: bool) -> void:
	var map = game.minimap
	tick_once()
	var before: float = map.pulse
	tick_once()
	check(map.pulse > before, "%s: the pulse clock runs in combat" % label)
	if heroes:
		var event := InputEventAction.new()
		event.action = "pause"
		event.pressed = true
		game._unhandled_input(event)
	else:
		game.pause("x")
	var frozen: float = map.pulse
	game._physics_process(1.0)
	game._physics_process(1.0)
	for _i in 3: await process_frame
	check(game.state == "paused" and paused, "%s: the game is paused" % label)
	check(is_equal_approx(map.pulse, frozen), "%s: pausing freezes the pulse clock" % label)
	game.resume()
	paused = false
	check(game.state == "combat", "%s: resume returns to combat" % label)
	tick_once()
	check(map.pulse > frozen, "%s: the pulse runs again after resume" % label)
