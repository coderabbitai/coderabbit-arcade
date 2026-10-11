extends SceneTree
## Last-life knockout in Code City and Heroes vs Villains. Both games are frozen and
## stepped with _physics_process, the same way as stage_flow.gd. The live-path checks
## kill Hoppy through a bullet, a ground warning, an enemy and the boss.
const DT := 1.0/60.0
## Frames to wait for the last autoload before giving up, so a stuck start fails instead of hanging.
const READY_FRAMES := 600
const LENGTH := 2.2
## Wall-time contract: .12 s at full speed, .63 s of pose clock at .55x, the rest at full speed,
## then the card for .8 s. 0.12+0.63/0.55+(2.2-0.75)+0.8 = 3.515 s, under the 4 s budget.
const SLOWMO_FROM := .12
const SLOWMO_TO := .75
const SLOWMO_SCALE := .55
const CARD_HOLD := .8
const WALL_TOTAL := .12+(.75-.12)/.55+(2.2-.75)+.8
const WALL_BUDGET := 4.0
const SLACK := .05
const ZOOM := 2.0
const BARS := 90.0
## Rendered frames go here, not into docs/previews, until the preview owner adopts them.
const CAPTURE_DIR := "/tmp/s3-captures"
const DISTANCE := 140.0
var failures := 0
var passes := 0
var game
var heroes := false
var scene_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if ok: passes += 1
	else: failures += 1
func mode() -> String:
	return "HvV" if heroes else "Code City"
func tag(message: String) -> String:
	return "%s: %s" % [mode(), message]
func step() -> void:
	game._physics_process(DT)
func advance_to(seconds: float) -> void:
	var guard := 0
	while game.state=="knockout" and game.ko.clock<seconds and guard<600:
		step()
		guard += 1
func freeze() -> void:
	game.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)
		game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
	if "bosses" in game:
		for b in game.bosses:
			if is_instance_valid(b): b.set_physics_process(false)
func free_entries(entries: Array) -> void:
	for entry in entries:
		var node: Object = entry.node if entry is Dictionary else entry
		if node is Node and is_instance_valid(node): node.free()
	entries.clear()
## Enemies, props and pickups would hit Hoppy or leave sprites that later checks would count.
func sweep() -> void:
	for e in game.enemies.duplicate():
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.free()
	game.enemies.clear()
	for prop in game.props.duplicate():
		if is_instance_valid(prop.node): prop.node.free()
	game.props.clear()
	for item in game.pickups.duplicate():
		if is_instance_valid(item.node): item.node.free()
	game.pickups.clear()
	free_entries(game.bullets)
	free_entries(game.warnings)
	free_entries(game.allies)
	if "bosses" in game:
		for b in game.bosses.duplicate():
			if is_instance_valid(b): b.free()
		game.bosses.clear()
	if is_instance_valid(game.boss):
		game.boss.free()
		game.boss = null
	for child in game.actors.get_children():
		if child==game.player: continue
		child.free()
	if is_instance_valid(game.player):
		var stars = game.player.get_node_or_null("KnockoutStars")
		if stars: stars.free()
func ready_combat() -> void:
	game.test_mode = true
	paused = false
	game.start_stage(0)
	freeze()
	var guard := 0
	while game.state!="combat" and guard<240:
		step()
		guard += 1
	freeze()
	sweep()
	var p = game.player
	p.hp = 3
	p.invulnerable = 0.0
	p.shield = false
	p.height = 0.0
	p.rise = 0.0
	p.knock = Vector2.ZERO
	p.stagger = 0.0
	p.weapon = ""
	p.facing = 1.0
	if "stowed" in p: p.stowed = false
	p.position = Vector2(game.room_start()+640.0, 580.0)
	p.held.hide()
	game.gate_open = false
	game.prompt.text = ""
	game.playing = true
	check(game.state=="combat", tag("stage entrance reaches combat"))
func strike(from_left: bool) -> bool:
	var p = game.player
	p.hp = 1
	p.invulnerable = 0.0
	p.shield = false
	p.height = 0.0
	p.rise = 0.0
	var source = p.position+Vector2(-80.0 if from_left else 80.0, 0.0)
	return p.take_hit(source)
func stars_visible() -> bool:
	if not is_instance_valid(game.player): return false
	var stars = game.player.get_node_or_null("KnockoutStars")
	return stars!=null and stars.visible and not stars.is_queued_for_deletion()
## A knockout effect still on screen: visible, and not already queued to leave.
func knockout_sprites() -> int:
	var count := 0
	for child in game.actors.get_children():
		if child==game.player: continue
		if child.visible and not child.is_queued_for_deletion(): count += 1
	return count
func loose_sprites() -> int:
	var count := 0
	for child in game.actors.get_children():
		if child is AnimatedSprite2D and child.visible and not child.is_queued_for_deletion():
			count += 1
	return count
func has_pose(pose: String) -> bool:
	for child in game.actors.get_children():
		if child is AnimatedSprite2D and child.visible and not child.is_queued_for_deletion():
			if String(child.animation)==pose: return true
	return false
func do_pause() -> void:
	if heroes:
		var event := InputEventAction.new()
		event.action = "pause"
		event.pressed = true
		game._unhandled_input(event)
	else: game.pause("x")
func tap_space() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		root.push_input(key, true)
func advance_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	return key
func accept_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event
func run() -> void:
	# Rendered, SaveService's window-mode call pumps the loop inside its _ready and fires the deferred
	# run() before the autoloads finish, so wait for the last one.
	var waited := 0
	while not (root.has_node("ControllerService") and root.get_node("ControllerService").is_node_ready()) and waited < READY_FRAMES:
		await process_frame
		waited += 1
	if not (root.has_node("ControllerService") and root.get_node("ControllerService").is_node_ready()):
		check(false, "ControllerService is ready within %d frames" % READY_FRAMES)
		quit(1)
		return
	await process_frame
	await settle_window()
	await run_mode("res://scenes/beatem_up/code_city_brawl.tscn", false)
	await run_mode("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn", true)
	print("Knockout passes: ", passes, " failures: ", failures)
	if is_instance_valid(current_scene): current_scene.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
func boot(path: String) -> void:
	scene_path = path
	change_scene_to_file(path)
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	# A covered window can focus-pause before test_mode is set. Physics is re-enabled at ready.
	paused = false
	if game.state=="paused": game.resume()
	freeze()
func run_mode(path: String, is_heroes: bool) -> void:
	heroes = is_heroes
	await boot(path)
	print("--- ", mode(), " ---")
	check_timeline()
	check_arc(true)
	check_arc(false)
	check_clamp()
	check_poses()
	check_weapon()
	check_effects()
	check_pause()
	check_double()
	check_flow()
	check_live()
	check_cinematic()
	check_card()
	check_camera()
	check_no_camera()
	check_hud_proxy()
	check_hud_real()
	check_done_once()
	check_retry_cleanup()
	await check_menu()
	await check_cancel()
	await check_preview()
	await check_card_preview()
func check_timeline() -> void:
	ready_combat()
	var tune: Dictionary = game.ko.tuning
	var bounds := is_equal_approx(float(tune.hit_stop), .12)
	bounds = bounds and is_equal_approx(float(tune.launch_end), .75)
	bounds = bounds and is_equal_approx(float(tune.land_end), 1.0)
	bounds = bounds and is_equal_approx(float(tune.length), LENGTH)
	check(bounds, tag("phase boundaries are 0.12, 0.75, 1.0 and 2.2"))
	if not strike(true):
		check(false, tag("a fatal hit is accepted"))
		return
	check(game.state=="knockout" and not game.playing and not game.overlay.visible, tag("a fatal hit starts the knockout with play stopped and the menu hidden"))
	check(not ("♥" in game.hud.text), tag("the HUD shows no hearts right after the hit"))
	var order: Array[String] = []
	var at := {}
	var early := false
	var leaked := false
	var last_wall := 0.0
	var wall_total := 0.0
	note_phase(order, at)
	var guard := 0
	while game.state=="knockout" and guard<600:
		if game.ko.clock>=LENGTH and game.ko.phase!="card": early = true
		if game.overlay.visible or game.playing: leaked = true
		step()
		note_phase(order, at)
		last_wall = wall()
		guard += 1
	wall_total = last_wall
	var want: Array[String] = ["hit_stop", "launch", "land", "out_cold", "card", "game_over"]
	check(order==want, tag("phases run in order, got %s" % str(order)))
	# The pose clock still marks the phases. Slow-mo only changes how fast it runs in wall time,
	# so a tick that crosses a boundary may overshoot it by up to one (slowed) tick.
	check(near_at(at, "launch", .12), tag("launch starts at pose clock 0.12 s (clock %s)" % str(at.get("launch", "?"))))
	check(near_at(at, "land", .75), tag("land starts at pose clock 0.75 s (clock %s)" % str(at.get("land", "?"))))
	check(near_at(at, "out_cold", 1.0), tag("out_cold starts at pose clock 1.0 s (clock %s)" % str(at.get("out_cold", "?"))))
	var carded: float = float(at.get("card", -1.0))
	check(carded>=LENGTH-0.001 and carded<=LENGTH+DT+0.001 and not early, tag("the card starts when the pose clock reaches 2.2 s (clock %.4f)" % carded))
	check(wall_ok(wall_total), tag("game over lands at about 3.515 s of wall time, within 4 s (%.4f)" % wall_total))
	check(not leaked, tag("play stays stopped and the menu stays hidden through the knockout"))
	var focused = game.state=="game_over" and game.overlay.visible and game.primary.has_focus()
	check(focused, tag("game over shows the overlay with Retry focused"))
## Wall seconds since the hit. The knockout adds `elapsed` beside the pose `clock`.
func wall() -> float:
	return float(game.ko.elapsed)
func wall_ok(seconds: float) -> bool:
	return absf(seconds-WALL_TOTAL)<=DT*2.0+SLACK and seconds<=WALL_BUDGET
func note_phase(order: Array[String], at: Dictionary) -> void:
	var name = "game_over" if game.state=="game_over" else game.ko.phase
	if order.is_empty() or order.back()!=name:
		order.append(name)
		at[name] = game.ko.clock
func near_at(at: Dictionary, key: String, want: float) -> bool:
	if not at.has(key): return false
	return absf(float(at[key])-want)<=DT+0.001
func check_arc(from_left: bool) -> void:
	ready_combat()
	var p = game.player
	var ground_y := 580.0
	p.position = Vector2(game.room_start()+640.0, ground_y)
	var side := "left" if from_left else "right"
	if not strike(from_left):
		check(false, tag("a hit from the %s is accepted" % side))
		return
	var direction := float(game.ko.direction)
	var want := 1.0 if from_left else -1.0
	check(is_equal_approx(direction, want), tag("a hit from the %s throws the other way" % side))
	var landed: float = game.ko.start.x+direction*DISTANCE
	check(is_equal_approx(game.ko.landing.x, landed), tag("landing x is 140 px from the start (%s)" % side))
	check(is_equal_approx(game.ko.landing.y, ground_y), tag("landing keeps the ground y (%s)" % side))
	var nearest := 100.0
	var peak_y := 0.0
	var peak_clock := 0.0
	var y_held := true
	var above := false
	var guard := 0
	while game.state=="knockout" and game.ko.clock<0.95 and guard<200:
		if absf(p.position.y-ground_y)>0.01: y_held = false
		var c: float = game.ko.clock
		if c>0.2 and c<0.7 and p.body.position.y<-20.0: above = true
		var gap := absf(c-0.435)
		if gap<nearest:
			nearest = gap
			peak_y = p.body.position.y
			peak_clock = c
		step()
		guard += 1
	if absf(p.position.y-ground_y)>0.01: y_held = false
	check(y_held, tag("ground y does not change (%s)" % side))
	var peaked := above and nearest<=DT and absf(peak_y+70.0)<=15.0
	check(peaked, tag("the body peaks near -70 around 0.435 s (%s, y %.1f at %.3f)" % [side, peak_y, peak_clock]))
	var settled = p.body.position.is_equal_approx(Vector2.ZERO) and is_zero_approx(p.body.rotation)
	check(game.ko.clock+0.001>=0.95 and settled, tag("after the bounce the body rests on the shadow (%s)" % side))
	check(is_equal_approx(p.position.x, game.ko.landing.x), tag("ground x ends at the landing (%s)" % side))
	check(is_equal_approx(float(p.facing), direction), tag("facing ends on the throw direction (%s)" % side))
func check_clamp() -> void:
	ready_combat()
	var edge := float(game.ko.tuning.edge)
	var p = game.player
	p.position = Vector2(game.room_start()+edge+20.0, 580.0)
	if not strike(false):
		check(false, tag("a hit toward the left edge is accepted"))
		return
	var min_x = game.room_start()+edge
	var full = game.ko.start.x+float(game.ko.direction)*DISTANCE
	var clamped = game.ko.landing.x+0.01>=min_x and game.ko.landing.x>full
	check(is_equal_approx(float(game.ko.direction), -1.0) and clamped, tag("a left throw lands at the edge or further right (%.1f, edge %.1f)" % [game.ko.landing.x, min_x]))
	advance_to(0.95)
	var ended = is_equal_approx(p.position.x, game.ko.landing.x) and p.position.x+0.01>=min_x
	check(ended, tag("Hoppy stops on that clamped landing (%.1f)" % p.position.x))
func check_poses() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for poses"))
		return
	var direction := float(game.ko.direction)
	var turn := float(game.ko.tuning.turn)
	var pose_bad := ""
	var face_bad := ""
	var frame_bad := ""
	var saw_frame := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		var c: float = game.ko.clock
		var anim := String(p.body.animation)
		var want_face := direction if c>=turn else -direction
		if not is_equal_approx(float(p.facing), want_face) and face_bad=="":
			face_bad = "clock %.3f facing %.0f want %.0f" % [c, p.facing, want_face]
		if heroes:
			var want := "hurt" if c<0.75 else "defeat"
			if anim!=want and pose_bad=="": pose_bad = "clock %.3f anim %s" % [c, anim]
		else:
			var want_pose := "hurt" if c<0.12 else "death"
			if anim!=want_pose and pose_bad=="": pose_bad = "clock %.3f anim %s" % [c, anim]
			if c>=0.93:
				if int(p.body.frame)==5: saw_frame = true
				elif frame_bad=="": frame_bad = "clock %.3f frame %s" % [c, str(p.body.frame)]
		step()
		guard += 1
	check(face_bad=="", tag("he faces the hit, then the throw (%s)" % face_bad))
	if heroes: check(pose_bad=="", tag("hurt before 0.75 s, then defeat (%s)" % pose_bad))
	else:
		check(pose_bad=="", tag("hurt during the hit-stop, then death (%s)" % pose_bad))
		check(saw_frame and frame_bad=="", tag("death stays on frame 5 from 0.93 s (%s)" % frame_bad))
	check(is_equal_approx(float(p.facing), direction), tag("facing ends equal to the throw direction"))
func check_weapon() -> void:
	ready_combat()
	var p = game.player
	var kind := "review_stamp" if heroes else "debug_stick"
	p.equip(kind)
	p.pickup_time = 0.0
	p.tick(0.0)
	check(p.held.visible, tag("%s is drawn before the fatal hit" % kind))
	p.position = Vector2(game.room_start()+500.0, 580.0)
	if not strike(true):
		check(false, tag("an armed fatal hit is accepted"))
		return
	var hidden_bad := ""
	var air_bad := ""
	var carry_bad := ""
	var saw_air := false
	var saw_carry := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		var c: float = game.ko.clock
		if heroes and c<0.75:
			saw_air = true
			var sheet_ok: bool = p.body.sprite_frames==p.COMBAT_FRAMES
			if p.held.visible or not sheet_ok:
				if air_bad=="": air_bad = "clock %.3f held %s combat %s" % [c, p.held.visible, sheet_ok]
		elif heroes and c>=0.75:
			var carry: bool = p.held.visible and p.held.carry.visible
			if carry: saw_carry = true
			elif carry_bad=="": carry_bad = "clock %.3f held %s carry %s" % [c, p.held.visible, p.held.carry.visible]
		elif p.held.visible and hidden_bad=="": hidden_bad = "clock %.3f" % c
		step()
		guard += 1
	if heroes:
		check(saw_air and air_bad=="", tag("the stamp is hidden and the body is unarmed while airborne (%s)" % air_bad))
		check(saw_carry and carry_bad=="", tag("the stamp and its carry return after touchdown (%s)" % carry_bad))
	else:
		check(hidden_bad=="" and not p.held.visible, tag("the debug stick stays hidden (%s)" % hidden_bad))
func check_effects() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for effects"))
		return
	var dust := str(game.ko.tuning.dust_fx.pose)
	var saw_dust := false
	var stars_ok := false
	var duck_ok := false
	var duck_at := 0.0
	var guard := 0
	while game.state=="knockout" and guard<600:
		var c: float = game.ko.clock
		if c+0.001>=0.75 and c<0.9 and has_pose(dust): saw_dust = true
		if c>=1.05 and c<=1.7:
			var stars = p.get_node_or_null("KnockoutStars")
			if stars!=null and stars.visible: stars_ok = true
			if game.flow.music_db<0.0:
				duck_ok = true
				duck_at = game.flow.music_db
		step()
		guard += 1
	check(saw_dust, tag("a dust sprite is in actors right after touchdown"))
	check(stars_ok, tag("stars are visible during out_cold"))
	check(duck_ok, tag("music ducks during out_cold (db %.2f)" % duck_at))
	check(knockout_sprites()==0, tag("no knockout sprite is left visible in actors (%d)" % knockout_sprites()))
	check(not stars_visible(), tag("no visible KnockoutStars after game over"))
	var ui_hidden = is_instance_valid(game.ko.root) and not game.ko.root.visible
	check(ui_hidden, tag("the knockout UI is hidden after game over"))
	check(is_equal_approx(game.flow.music_db, 0.0), tag("the music duck is lifted after game over"))
	check(not game.ko.active(), tag("the knockout is inactive after game over"))
func check_pause() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for pause"))
		return
	advance_to(0.4)
	check(game.ko.phase=="launch", tag("the pause sample is mid-launch (%s)" % game.ko.phase))
	var clock: float = game.ko.clock
	var pos = p.position
	do_pause()
	var paused_ko = game.state=="paused" and game.pause_return_state=="knockout"
	check(paused_ko, tag("pause during a knockout remembers knockout"))
	game._physics_process(1.0)
	var frozen = is_equal_approx(game.ko.clock, clock) and p.position.is_equal_approx(pos)
	check(frozen, tag("a paused physics step advances neither the clock nor Hoppy"))
	game.resume()
	check(game.state=="knockout", tag("resume returns to the knockout"))
	game.test_mode = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var focus = game.state=="paused" and game.pause_return_state=="knockout"
	check(focus, tag("losing focus pauses a knockout"))
	game.test_mode = true
	game.resume()
	var guard := 0
	var early := false
	while game.state=="knockout" and guard<600:
		if game.ko.clock>=LENGTH and game.ko.phase!="card": early = true
		step()
		guard += 1
	var ended: float = wall()
	var on_time = game.state=="game_over" and not early and wall_ok(ended)
	check(on_time, tag("game over still lands at about 3.515 s of unpaused wall time (%.4f)" % ended))
func same_knockout(clock: float, phase: String, direction: float, landing: Vector2) -> bool:
	return is_equal_approx(game.ko.clock, clock) and game.ko.phase==phase and is_equal_approx(float(game.ko.direction), direction) and game.ko.landing.is_equal_approx(landing)
func check_double() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the double-knockout check"))
		return
	var clock: float = game.ko.clock
	var phase = game.ko.phase
	var direction := float(game.ko.direction)
	var landing: Vector2 = game.ko.landing
	var pos = p.position
	var hp: int = p.hp
	var again: bool = p.take_hit(p.position+Vector2(50, 0))
	var unchanged = same_knockout(clock, phase, direction, landing) and p.position.is_equal_approx(pos) and p.hp==hp
	check(not again and unchanged, tag("a second hit returns false and changes nothing"))
	game.knockout(p.position+Vector2(-200, 10))
	check(same_knockout(clock, phase, direction, landing), tag("knockout() during a knockout leaves clock, phase, direction and landing"))
	var guard := 0
	while game.state=="knockout" and guard<600:
		step()
		guard += 1
	game.knockout(Vector2.ZERO)
	check(game.state=="game_over" and not game.ko.active(), tag("knockout() after game over stays on game over"))
func check_flow() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	game.flow.banner("", "", 0)
	game.toast("SHOULD HIDE", 4.0)
	game.prompt.text = "E / Y · PICK UP"
	game.flow.play_enter("TITLE", "story")
	game.held_toast = "HELD"
	check(game.flow.active(), tag("the flow is running just before the fatal hit"))
	if not strike(true):
		check(false, tag("a fatal hit is accepted while the flow is running"))
		return
	var cleared = not game.flow.active() and not game.toast_label.visible and game.held_toast==""
	cleared = cleared and game.prompt.text=="" and not game.flow.banner_panel.visible
	check(cleared, tag("the hit stops the flow and clears the toast, the prompt and the banner"))
	# HvV's edge keeps a natural arc inside x=1175, short of the 1205 gate line, so the arc is
	# placed past the line. The knockout tick writes that x before the room check can see it.
	game.gate_open = true
	var past = game.room_start()+1260.0
	game.ko.start.x = past
	game.ko.landing.x = past
	p.position.x = past
	var room: int = game.room
	var stage: int = game.stage_index
	var moved := false
	var chatter := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		step()
		if game.flow.active() or game.room!=room or game.stage_index!=stage: moved = true
		if game.toast_label.visible or game.held_toast!="" or game.prompt.text!="": chatter = true
		if game.flow.banner_panel.visible: chatter = true
		guard += 1
	check(not moved and game.room==room, tag("the flow stays idle and the room does not change past the gate"))
	check(not chatter, tag("toasts, the prompt and the stage banner stay hidden"))
func check_menu() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+480.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the menu"))
		return
	var guard := 0
	while game.state=="knockout" and guard<600:
		step()
		guard += 1
	check(game.state=="game_over" and game.overlay.visible and game.primary.has_focus(), tag("game over focuses Retry"))
	await process_frame
	if heroes:
		check(is_zero_approx(game.terminal_overlay_clock), tag("the game-over clock starts at 0"))
		game._input(advance_key())
		game._input(accept_event())
		check(game.state=="game_over" and game.overlay.visible, tag("the first-frame press does not retry"))
		step()
		game._input(advance_key())
		game._input(accept_event())
		check(game.state=="game_over" and game.overlay.visible, tag("a press one frame later still does not retry"))
		game._physics_process(0.6)
		game._input(advance_key())
	else:
		check(is_zero_approx(game.overlay_clock), tag("the game-over clock starts at 0"))
		tap_space()
		check(game.state=="game_over" and game.overlay.visible, tag("the first-frame press does not retry"))
		var arm := int(ceili(game.OVERLAY_ARM/DT))+1
		for _i in arm: step()
		tap_space()
	check(game.state=="stage_enter" and not game.overlay.visible, tag("Retry after 0.5 s enters the stage"))
	freeze()
	guard = 0
	while game.state!="combat" and guard<240:
		step()
		guard += 1
	var back = game.state=="combat" and game.playing and game.player.hp==3 and not game.ko.active()
	check(back, tag("retry reaches combat with 3 hp and the knockout inactive"))
	freeze()
func check_cancel() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+420.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted before start_stage"))
		return
	advance_to(0.4)
	check(game.ko.active(), tag("the knockout is active before start_stage"))
	game.start_stage(1)
	freeze()
	var cleared = not game.ko.active() and not stars_visible() and game.ko._fx.is_empty() and loose_sprites()==0
	check(cleared, tag("start_stage cancels the knockout, its stars and its sprites"))
	var guard := 0
	while game.state!="combat" and guard<240:
		step()
		guard += 1
	var ran = game.state=="combat" and game.playing and game.stage_index==1 and game.player.hp==3 and not game.ko.active()
	check(ran, tag("the new stage runs after a cancelled knockout"))
	ready_combat()
	p = game.player
	p.position = Vector2(game.room_start()+420.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted before leave"))
		return
	advance_to(0.3)
	game.leave()
	check(game.state=="leaving" and not game.ko.active(), tag("leave during a knockout cancels it and starts leaving"))
	await reload_scene()
func reload_scene() -> void:
	var deadline := Time.get_ticks_msec()+5000
	while root.get_node("AppRouter").busy:
		if Time.get_ticks_msec()>deadline:
			check(false, tag("AppRouter finishes routing within 5 s"))
			return
		await process_frame
	check(current_scene.name=="BeatemMenu", tag("leave still routes to the Beat'em Up menu"))
	change_scene_to_file(scene_path)
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	paused = false
	if game.state=="paused": game.resume()
	freeze()
## One hp, no shield, no i-frames, on the ground, with the incidental clocks held back.
func prepare() -> void:
	ready_combat()
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	arm()
func arm() -> void:
	var p = game.player
	p.hp = 1
	p.invulnerable = 0.0
	p.shield = false
	p.height = 0.0
	p.rise = 0.0
	p.knock = Vector2.ZERO
	p.weapon = ""
	p.position = Vector2(game.room_start()+640.0, 580.0)
	game.playing = true
	game.gate_open = false
	game.toast_left = 0.0
	game.held_toast = ""
	game.toast_label.hide()
	game.prompt.text = ""
func toast_hidden() -> bool:
	return not game.toast_label.visible and game.held_toast==""
func check_live() -> void:
	check_bullet()
	check_warning()
	check_enemy()
	check_boss()
	check_fatal_frame()
## A shot aimed at Hoppy, plus one aimed away. Bullets advance only while playing.
func check_bullet() -> void:
	prepare()
	var p = game.player
	game.projectile(p.position+Vector2(-40, 0), Vector2(1500, 0))
	game.projectile(p.position+Vector2(240, 0), Vector2(300, 0))
	if game.bullets.size()!=2:
		check(false, tag("a hitting bullet and a bullet aimed away are both live"))
		return
	var shot = game.bullets[0].node
	var away = game.bullets[1].node
	var spawned = away.position
	var guard := 0
	while game.state=="combat" and guard<12:
		step()
		guard += 1
	if game.state!="knockout":
		check(false, tag("the bullet knocks Hoppy out"))
		return
	var gone = shot.is_queued_for_deletion()
	for b in game.bullets:
		if b.node==shot: gone = false
	var kept := false
	for b in game.bullets:
		if b.node==away: kept = true
	check(not game.playing and gone and kept and game.bullets.size()==1, tag("the hitting bullet is gone and the other one remains"))
	var advanced = away.position.distance_to(spawned)>1.0
	check(advanced, tag("the other bullet advanced on the frame play was still running"))
	var parked = away.position
	var drifted := false
	for _i in 8:
		step()
		if not is_instance_valid(away) or not away.position.is_equal_approx(parked): drifted = true
	check(not drifted, tag("the bullet aimed away does not move once play has stopped"))
## Code City bomb, HvV code dump. After it fires, its clock stops with play.
func check_warning() -> void:
	prepare()
	var p = game.player
	# An empty room opens the gate and clears threats. One frozen enemy keeps the warning up.
	var keeper = game.spawn_enemy("slop_sprite" if heroes else "cli_gremlin", Vector2(game.room_start()+180.0, 500.0))
	if keeper==null:
		check(false, tag("the ground warning has a room to fire in"))
		return
	keeper.set_physics_process(false)
	var kind := "bomb"
	var radius := Vector2(80, 38)
	if heroes:
		kind = "code_dump"
		radius = Vector2(90, 42)
	game.ground_warning(p.position, radius, DT*2, 0.5, kind)
	if game.warnings.size()!=1:
		check(false, tag("the ground warning is live"))
		return
	var guard := 0
	while game.state=="combat" and guard<12:
		step()
		guard += 1
	if game.state!="knockout" or game.warnings.is_empty():
		check(false, tag("the ground warning knocks Hoppy out"))
		return
	var fired: bool = game.warnings[0].fired
	var left = game.warnings[0].left
	var stopped := true
	for _i in 8:
		step()
		if game.warnings.is_empty() or not is_equal_approx(float(game.warnings[0].left), float(left)):
			stopped = false
	check(not game.playing and fired and stopped, tag("the warning fires, then its clock stops"))
## The enemy's own tick lands the hit. Its _physics_process is gated on playing,
## so later arena steps leave the attack where it was.
func check_enemy() -> void:
	prepare()
	var p = game.player
	var kind := "cli_gremlin"
	if heroes: kind = "slop_sprite"
	var enemy = game.spawn_enemy(kind, p.position+Vector2(40, 0))
	if enemy==null:
		check(false, tag("an enemy spawns for the contact hit"))
		return
	enemy.set_physics_process(false)
	enemy.position = p.position+Vector2(40, 0)
	enemy.state = "attack"
	enemy.timer = 0.5
	enemy.facing = -1.0
	enemy.cooldown = 10.0
	var guard := 0
	while game.state=="combat" and guard<8:
		enemy.tick(DT)
		guard += 1
	if game.state!="knockout" or guard>4:
		check(false, tag("the enemy's tick knocks Hoppy out within a few ticks (%d)" % guard))
		return
	var at = enemy.position
	var timer = enemy.timer
	var moved := false
	for _i in 8:
		step()
		enemy._physics_process(DT)
		if not enemy.position.is_equal_approx(at) or not is_equal_approx(float(enemy.timer), float(timer)):
			moved = true
	check(not game.playing and not moved, tag("the enemy stays put once play has stopped"))
func check_boss() -> void:
	if heroes: check_boss_heroes()
	else: check_boss_city()
## Room 3 of stage 3. The boss has no body hit; telegraph() plants the slam that
## reaches Hoppy, and real ticks run it out. Cycle 2 is that first slam.
func check_boss_city() -> void:
	prepare()
	game.stage_index = 2
	game.enter_room(2)
	arm()
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	if game.stage_index!=2 or game.room!=2 or not is_instance_valid(game.boss):
		check(false, tag("the boss is in room 3 of stage 3"))
		return
	var p = game.player
	var boss = game.boss
	boss.set_physics_process(false)
	boss.phase = 1
	boss.cycle = 1
	boss.state = "idle"
	boss.timer = 0.0
	boss.tick(DT)
	var planted = game.warnings.size()==1 and game.warnings[0].owner==boss and game.warnings[0].kind=="slam"
	if planted: planted = game.warnings[0].pos.distance_to(p.position)<1.0
	if not planted:
		check(false, tag("the boss plants its slam on Hoppy"))
		return
	var guard := 0
	while game.state=="combat" and guard<150:
		step()
		guard += 1
	if game.state!="knockout":
		check(false, tag("the boss slam knocks Hoppy out"))
		return
	check(not game.playing, tag("the boss slam stops play"))
	defy_victory()
## A dash already committed, closing on Hoppy over a few of the boss's own ticks.
func check_boss_heroes() -> void:
	prepare()
	var p = game.player
	var boss = game.spawn_boss("ai_augmented_hacker", p.position+Vector2(-100, 0))
	if boss==null:
		check(false, tag("a boss spawns for the dash"))
		return
	boss.set_physics_process(false)
	boss.phase = 1
	boss.state = "attack"
	boss.action = "dash"
	boss.timer = 0.5
	boss.dash_direction = Vector2(1, 0)
	boss.aim = p.position
	var guard := 0
	while game.state=="combat" and guard<12:
		boss.tick(DT)
		guard += 1
	if game.state!="knockout" or guard>6:
		check(false, tag("the hacker's dash knocks Hoppy out within a few ticks (%d)" % guard))
		return
	check(not game.playing, tag("the hacker's dash stops play"))
	defy_victory()
## boss_defeated() during the knockout must not start a win, and the knockout still ends.
func defy_victory() -> void:
	game.boss_defeated()
	var ignored = game.state=="knockout" and toast_hidden()
	if heroes: ignored = ignored and not game.boss_rewarded
	else: ignored = ignored and not is_instance_valid(game.merge_button)
	check(ignored, tag("boss_defeated during the knockout does not start a finisher or a victory"))
	var guard := 0
	var won := false
	while game.state=="knockout" and guard<600:
		step()
		if game.state=="finisher" or game.state=="boss_victory" or game.state=="won": won = true
		guard += 1
	var ended: float = wall()
	var over = game.state=="game_over" and not won and wall_ok(ended)
	check(over, tag("the knockout still ends in game over (state %s, clock %.4f)" % [game.state, ended]))
## The bullet connects on the step an ally is due. Threats run first, so no ally and no toast.
func check_fatal_frame() -> void:
	prepare()
	var p = game.player
	game.allies.clear()
	game.gate_open = false
	game.ally_clock = DT
	game.hazard_clock = 30.0
	game.projectile(p.position+Vector2(-40, 0), Vector2(1500, 0))
	if not (game.ally_clock<=DT and game.allies.is_empty() and not game.gate_open and game.bullets.size()==1):
		check(false, tag("an ally is due on the bullet's frame"))
		return
	step()
	var quiet = game.state=="knockout" and not game.playing and game.allies.is_empty() and toast_hidden()
	quiet = quiet and game.ally_clock<=DT
	if not quiet:
		check(false, tag("the fatal bullet knocks Hoppy out with no ally and no toast"))
		return
	check(true, tag("the fatal bullet knocks Hoppy out with no ally and no toast"))
	var leaked := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		step()
		if not toast_hidden() or not game.allies.is_empty(): leaked = true
		guard += 1
	if not toast_hidden() or not game.allies.is_empty(): leaked = true
	check(not leaked, tag("the toast stays hidden, and no ally appears, until game over"))
	var ended: float = wall()
	var over = game.state=="game_over" and wall_ok(ended)
	check(over, tag("that knockout still ends in game over (wall %.4f)" % ended))
## Rendered only: one out-cold frame per mode. Headless, or with the render loop off (where
## frame_post_draw never fires), it returns before any check.
func check_preview() -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	ready_combat()
	sweep()
	var p = game.player
	game.toast_left = 0.0
	game.held_toast = ""
	game.toast_label.hide()
	game.prompt.text = ""
	game.flow.banner("", "", 0)
	if heroes:
		p.equip("review_stamp")
		p.pickup_time = 0.0
		p.tick(0.0)
	else:
		p.weapon = ""
		p.held.hide()
	p.position = Vector2(game.room_start()+560.0, 580.0)
	if not strike(false):
		check(false, tag("a hit from the right is accepted for the preview"))
		return
	var guard := 0
	while game.state=="knockout" and game.ko.clock<1.6 and guard<600:
		step()
		guard += 1
	# Hand steps land between engine ticks. Reset interpolation or the shot draws the previous pose.
	# The knockout's own camera push stays: the capture shows the zoomed frame as played.
	game.shake = 0.0
	game.reset_physics_interpolation()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var failed_before := failures
	var frame = game.state=="knockout" and game.ko.phase=="out_cold" and game.ko.clock+0.001>=1.6
	check(frame, tag("the preview is out cold at %.3f s" % game.ko.clock))
	var popped = game.ko.callout.visible and is_equal_approx(float(game.ko.callout.modulate.a), 1.0)
	check(popped, tag("the K.O. callout is fully popped"))
	check(stars_visible(), tag("the dizzy stars are visible"))
	var chrome = not game.overlay.visible and toast_hidden() and not game.flow.banner_panel.visible
	check(chrome, tag("the menu, the toast and the stage banner stay off the preview"))
	check(loose_sprites()==0, tag("no stray sprite is left in actors (%d)" % loose_sprites()))
	var image: Image = root.get_texture().get_image()
	# Viewport pixels, read through each item's canvas transform (camera and layer included).
	var stars = p.get_node_or_null("KnockoutStars")
	var orbit: Node2D = stars if stars else p
	var screen: Vector2 = orbit.get_global_transform_with_canvas().origin
	var zoom := float(game.camera.zoom.x)
	var star_box := Rect2(screen-Vector2(64, 40)*zoom, Vector2(128, 80)*zoom)
	var callout_xform: Transform2D = game.ko.callout.get_global_transform_with_canvas()
	var callout_rect := Rect2(callout_xform.origin, game.ko.callout.size*callout_xform.get_scale())
	var star_color: Color = game.ko.tuning.star_color
	var callout_color: Color = game.ko.tuning.callout_color
	var star_hits := count_near(image, star_box, star_color, 0.28)
	var callout_hits := count_near(image, callout_rect, callout_color, 0.28)
	# The stage itself is close to these colors. Count again with the drawings hidden.
	game.ko.callout.hide()
	if is_instance_valid(game.ko.stars): game.ko.stars.hide()
	game.reset_physics_interpolation()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var bare: Image = root.get_texture().get_image()
	var star_bare := count_near(bare, star_box, star_color, 0.28)
	var callout_bare := count_near(bare, callout_rect, callout_color, 0.28)
	var star_delta := star_hits-star_bare
	var callout_delta := callout_hits-callout_bare
	check(star_delta>=40, tag("star pixels %d drawn, %d hidden, difference %d" % [star_hits, star_bare, star_delta]))
	check(callout_delta>=200, tag("callout pixels %d drawn, %d hidden, difference %d" % [callout_hits, callout_bare, callout_delta]))
	# The rendered run refreshes the committed preview, as the smoke suites do, but only with a
	# frame that passed every check above.
	if failures==failed_before:
		check(bars_are_black(image), tag("the out-cold frame has pure black %d px bars top and bottom" % int(BARS)))
		check(hoppy_pixels(image)>=HOPPY_MIN, tag("Hoppy is drawn large under the %.1fx zoom (%d orange px)" % [ZOOM, hoppy_pixels(image)]))
		if game.has_method("knockout_hud_nodes"):
			var shown := 0
			for n in game.knockout_hud_nodes():
				if is_instance_valid(n) and n.is_visible_in_tree(): shown += 1
			check(shown==0, tag("the HUD and minimap nodes are hidden in the out-cold frame (%d visible)" % shown))
		check(edges_are_stage(image), tag("the out-cold frame shows stage, not the clear color, along the left and right edges"))
		check(save_capture(image, "knockout_out_cold"), tag("out-cold capture saved under %s" % CAPTURE_DIR))
	else: print(tag("knockout preview not saved: its frame failed a check"))
	game.ko.callout.show()
	if is_instance_valid(game.ko.stars): game.ko.stars.show()
	guard = 0
	while game.state=="knockout" and guard<600:
		step()
		guard += 1
	check(game.state=="game_over", tag("the preview knockout still ends in game over"))
func count_near(image: Image, rect: Rect2, target: Color, tol: float) -> int:
	var hits := 0
	var x0 := maxi(0, int(floor(rect.position.x)))
	var y0 := maxi(0, int(floor(rect.position.y)))
	var x1 := mini(image.get_width(), int(ceil(rect.end.x)))
	var y1 := mini(image.get_height(), int(ceil(rect.end.y)))
	var tol2 := tol*tol
	for y in range(y0, y1):
		for x in range(x0, x1):
			var px := image.get_pixel(x, y)
			var dr := px.r-target.r
			var dg := px.g-target.g
			var db := px.b-target.b
			if dr*dr+dg*dg+db*db<=tol2: hits += 1
	return hits
## Rendered only: let the window-mode change settle, then pin the viewport to 1280x720 so every
## capture has the same size. Gives up after 120 process frames and the captures refuse a wrong size.
const FRAME := Vector2i(1280, 720)
func settle_window() -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	await create_timer(.5).timeout
	DisplayServer.window_set_size(FRAME)
	root.size = FRAME
	var frames := 0
	while Vector2i(root.get_texture().get_size())!=FRAME and frames<120:
		await process_frame
		frames += 1
	print("window settled at ", root.get_texture().get_size(), " after ", frames, " frames")
func frame_ok(image: Image) -> bool:
	return Vector2i(image.get_width(), image.get_height())==FRAME
func save_capture(image: Image, name: String) -> bool:
	if not frame_ok(image):
		print(tag("capture %s refused: frame is %dx%d, not 1280x720" % [name, image.get_width(), image.get_height()]))
		return false
	var folder := "heroes-villains" if heroes else "code-city"
	var dir := "%s/%s" % [CAPTURE_DIR, folder]
	DirAccess.make_dir_recursive_absolute(dir)
	return image.save_png("%s/%s.png" % [dir, name])==OK
## The first tick, wall-measured: full speed before .12, warped at .55x between .12 and .75,
## full speed after, with Engine.time_scale untouched throughout.
func check_cinematic() -> void:
	ready_combat()
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the slow-mo check"))
		return
	var tune: Dictionary = game.ko.tuning
	var keys := is_equal_approx(float(tune.slowmo_from), SLOWMO_FROM) and is_equal_approx(float(tune.slowmo_to), SLOWMO_TO) and is_equal_approx(float(tune.slowmo_scale), SLOWMO_SCALE)
	check(keys, tag("slowmo_from .12, slowmo_to .75 and slowmo_scale .55 are the defaults"))
	check(is_equal_approx(float(tune.card_hold), CARD_HOLD) and str(tune.card_title)=="REVIEW FAILED", tag("card_hold .8 and card_title REVIEW FAILED are the defaults"))
	check(is_equal_approx(float(tune.zoom), ZOOM) and is_equal_approx(float(tune.zoom_in), .45) and is_equal_approx(float(tune.zoom_out), .25) and is_equal_approx(float(tune.bars), BARS), tag("zoom 2.0, zoom_in .45, zoom_out .25 and bars 90 are the defaults"))
	var scale_bad := ""
	var time_scale_bad := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		var before_clock: float = game.ko.clock
		var before_wall := wall()
		step()
		if not is_equal_approx(Engine.time_scale, 1.0): time_scale_bad = true
		var dc: float = game.ko.clock-before_clock
		var dw := wall()-before_wall
		if dw>0.0 and game.ko.phase!="card" and before_clock>=SLOWMO_FROM+DT and game.ko.clock<=SLOWMO_TO-DT:
			var ratio := dc/dw
			if absf(ratio-SLOWMO_SCALE)>.02 and scale_bad=="": scale_bad = "clock %.3f ratio %.3f" % [before_clock, ratio]
		elif dw>0.0 and game.ko.phase=="out_cold" and before_clock>=1.0:
			if absf(dc/dw-1.0)>.02 and scale_bad=="": scale_bad = "after slow-mo, clock %.3f ratio %.3f" % [before_clock, dc/dw]
		elif dw>0.0 and before_clock<SLOWMO_FROM-DT:
			if absf(dc/dw-1.0)>.02 and scale_bad=="": scale_bad = "before slow-mo, clock %.3f ratio %.3f" % [before_clock, dc/dw]
		guard += 1
	check(scale_bad=="", tag("the pose clock runs .55x in wall time between .12 and .75 and 1x outside it (%s)" % scale_bad))
	check(not time_scale_bad and is_equal_approx(Engine.time_scale, 1.0), tag("Engine.time_scale is never touched"))
## The card is `ko.card` (a Control) with `card_title` and `top_bar`/`bottom_bar` letterbox bars.
func card_visible() -> bool:
	return is_instance_valid(game.ko.card) and game.ko.card.is_visible_in_tree()
func card_labels() -> Array[String]:
	var found: Array[String] = []
	if not is_instance_valid(game.ko.root): return found
	var stack: Array = [game.ko.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node is Label and node.is_visible_in_tree() and node.text!="": found.append(node.text)
	return found
func check_card() -> void:
	ready_combat()
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the card check"))
		return
	var title := str(game.ko.tuning.card_title)
	var seen_early := false
	var card_start := -1.0
	var card_end := -1.0
	var saw_title := false
	var guard := 0
	while game.state=="knockout" and guard<600:
		var shown := title in card_labels()
		if game.ko.phase!="card" and shown: seen_early = true
		if game.ko.phase=="card":
			if card_start<0.0: card_start = wall()
			if shown: saw_title = true
			if game.overlay.visible: seen_early = true
		step()
		guard += 1
	card_end = wall()
	check(not seen_early, tag("the failure card and the menu stay hidden until the pose clock ends"))
	check(saw_title and card_start>0.0, tag("the card shows %s during the card phase" % title))
	check(str(game.ko.card_title.text)==title, tag("card_title carries the configured text"))
	var held := card_end-card_start
	check(absf(held-CARD_HOLD)<=DT*2.0+SLACK, tag("the card holds for .8 s of wall time (%.3f)" % held))
	check(game.state=="game_over" and game.overlay.visible and not card_visible() and not game.ko.top_bar.is_visible_in_tree(), tag("game over hides the card, the bars and shows the menu"))
func check_camera() -> void:
	ready_combat()
	var cam: Camera2D = game.camera
	var zoom0 := Vector2(1.1, 1.1)
	var pos0 := Vector2(game.room_start()+600.0, 340.0)
	cam.zoom = zoom0
	cam.position = pos0
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the camera check"))
		return
	var peak := 0.0
	var guard := 0
	var moved := false
	while game.state=="knockout" and guard<600:
		step()
		peak = maxf(peak, float(cam.zoom.x))
		if game.state=="knockout" and game.ko.phase=="card" and absf(cam.zoom.x-zoom0.x*ZOOM)<.01: moved = true
		guard += 1
	check(peak>zoom0.x+.05 and peak<=zoom0.x*ZOOM+.01, tag("the camera pushes in during the knockout, to at most ZOOMx its snapshot zoom (peak %.3f)" % peak))
	check(moved, tag("the camera holds the full zoom of its snapshot through the card"))
	check(cam.zoom.is_equal_approx(zoom0) and cam.position.is_equal_approx(pos0), tag("camera position and zoom are restored to their snapshot on completion"))
	ready_combat()
	cam.zoom = zoom0
	cam.position = pos0
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	strike(true)
	advance_to(1.5)
	check(not cam.zoom.is_equal_approx(zoom0), tag("the camera is mid-push before cancel (%.3f)" % cam.zoom.x))
	game.ko.cancel()
	check(cam.zoom.is_equal_approx(zoom0) and cam.position.is_equal_approx(pos0), tag("cancel() restores the camera position and zoom at once"))
	cam.position = pos0+Vector2(33, 0)
	game.ko.cancel()
	check(cam.position.is_equal_approx(pos0+Vector2(33, 0)), tag("a second cancel() does not re-apply the snapshot"))
	cam.position = pos0
	game.state = "combat"
## Driven straight through ko.play/tick: done fires once, never after cancel, and replay works.
func check_done_once() -> void:
	ready_combat()
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	var counter := [0]
	var done := func(): counter[0] += 1
	game.ko.play(game, p.position+Vector2(-80, 0), done)
	var wall_seen := 0.0
	for _i in 600:
		game.ko.tick(DT)
		wall_seen = float(game.ko.elapsed)
		if counter[0]>0: break
	check(counter[0]==1 and not game.ko.active(), tag("done runs once when the card ends"))
	check(wall_ok(wall_seen), tag("done runs at about 3.515 s of wall time (%.3f)" % wall_seen))
	for _i in 60: game.ko.tick(DT)
	check(counter[0]==1, tag("ticking an ended knockout never calls done again"))
	# A coarse step carries through every phase without skipping done or calling it twice.
	counter[0] = 0
	p.position = Vector2(game.room_start()+640.0, 580.0)
	game.ko.play(game, p.position+Vector2(80, 0), done)
	for _i in 20: game.ko.tick(.5)
	check(counter[0]==1 and not game.ko.active(), tag("half-second steps still call done exactly once"))
	# cancel() in each phase suppresses done.
	for cut in [.05, .4, 1.2, 2.0, 3.0]:
		counter[0] = 0
		p.position = Vector2(game.room_start()+640.0, 580.0)
		game.ko.play(game, p.position+Vector2(-80, 0), done)
		var guard := 0
		while float(game.ko.elapsed)<cut and game.ko.active() and guard<600:
			game.ko.tick(DT)
			guard += 1
		game.ko.cancel()
		for _i in 400: game.ko.tick(DT)
		check(counter[0]==0 and not game.ko.active(), tag("cancel() at %.2f s of wall time suppresses done" % cut))
	# play() over a running knockout replaces it: the first done never fires.
	var first := [0]
	var second := [0]
	game.ko.play(game, p.position+Vector2(-80, 0), func(): first[0] += 1)
	for _i in 30: game.ko.tick(DT)
	game.ko.play(game, p.position+Vector2(-80, 0), func(): second[0] += 1)
	check(is_zero_approx(game.ko.clock) and is_zero_approx(float(game.ko.elapsed)), tag("replaying restarts both clocks"))
	for _i in 600: game.ko.tick(DT)
	check(first[0]==0 and second[0]==1, tag("a replayed knockout calls only the latest done"))
## Pause mid-card, then a retry: nothing of the card, zoom or stars may carry over.
func check_retry_cleanup() -> void:
	ready_combat()
	var cam: Camera2D = game.camera
	var zoom0: Vector2 = cam.zoom
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the retry cleanup"))
		return
	var guard := 0
	while game.state=="knockout" and game.ko.phase!="card" and guard<600:
		step()
		guard += 1
	check(game.ko.phase=="card", tag("the cleanup sample is inside the card"))
	var w := wall()
	do_pause()
	game._physics_process(2.0)
	check(game.state=="paused" and is_equal_approx(wall(), w), tag("a pause inside the card freezes the wall clock"))
	game.resume()
	game.start_stage(0)
	freeze()
	var clean: bool = not game.ko.active() and not stars_visible() and not (str(game.ko.tuning.card_title) in card_labels())
	check(clean and cam.zoom.is_equal_approx(zoom0) and loose_sprites()==0, tag("start_stage during the card clears the card, the stars, the sprites and the zoom"))
	guard = 0
	while game.state!="combat" and guard<240:
		step()
		guard += 1
	freeze()
	check(game.state=="combat" and game.player.hp==3 and not game.ko.active(), tag("the retried stage reaches combat with the knockout inactive"))
## Rendered only: the failure card frame.
func check_card_preview() -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	ready_combat()
	sweep()
	var p = game.player
	game.toast_left = 0.0
	game.held_toast = ""
	game.toast_label.hide()
	game.prompt.text = ""
	game.flow.banner("", "", 0)
	p.position = Vector2(game.room_start()+560.0, 580.0)
	if not strike(false):
		check(false, tag("a hit is accepted for the card preview"))
		return
	var guard := 0
	while game.state=="knockout" and game.ko.phase!="card" and guard<600:
		step()
		guard += 1
	var target := wall()+CARD_HOLD*.5
	while game.state=="knockout" and wall()<target and guard<900:
		step()
		guard += 1
	game.shake = 0.0
	game.reset_physics_interpolation()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(game.state=="knockout" and game.ko.phase=="card", tag("the card preview is mid-card"))
	check(str(game.ko.tuning.card_title) in card_labels(), tag("the failure card text is on screen"))
	var image: Image = root.get_texture().get_image()
	var bare_ok: bool = not game.overlay.visible and toast_hidden()
	check(bare_ok, tag("the retry menu and the toast stay off the card frame"))
	check(bars_are_black(image), tag("the card frame has pure black %d px bars top and bottom" % int(BARS)))
	check(edges_are_stage(image), tag("the card frame shows stage, not the clear color, along the left and right edges"))
	check(save_capture(image, "knockout_card"), tag("card capture saved under %s" % CAPTURE_DIR))
	while game.state=="knockout" and guard<1200:
		step()
		guard += 1
	check(game.state=="game_over", tag("the card preview still ends in game over"))
## The camera's zoom must never pull the view past the room: a 12 px strip at each edge, below the
## HUD and card and above the footer, may hold at most 3% of the window's clear color.
func edges_are_stage(image: Image) -> bool:
	var clear := RenderingServer.get_default_clear_color()
	var total := 0
	var bad := 0
	for x in list_edge_columns(image.get_width()):
		for y in range(340, mini(image.get_height()-60, 690), 2):
			total += 1
			var px := image.get_pixel(x, y)
			if Vector3(px.r-clear.r, px.g-clear.g, px.b-clear.b).length()<.03: bad += 1
	print(tag("edge strips: %d of %d samples match the clear color" % [bad, total]))
	return total>0 and float(bad)/float(total)<=.03
func list_edge_columns(width: int) -> Array[int]:
	var columns: Array[int] = []
	for x in 12:
		columns.append(x)
		columns.append(width-1-x)
	return columns
## The camera is optional: with the owner's camera unset, play, tick and cancel still run.
func check_no_camera() -> void:
	ready_combat()
	var saved = game.camera
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	var counter := [0]
	game.camera = null
	game.ko.play(game, p.position+Vector2(-80, 0), func(): counter[0] += 1)
	for _i in 600:
		game.ko.tick(DT)
		if not game.ko.active(): break
	var finished: bool = counter[0]==1 and not game.ko.active()
	game.ko.play(game, p.position+Vector2(-80, 0), func(): counter[0] += 1)
	for _i in 30: game.ko.tick(DT)
	game.ko.cancel()
	var cancelled: bool = counter[0]==1 and not game.ko.active()
	game.camera = saved
	check(finished, tag("a knockout without a camera runs to done once"))
	check(cancelled, tag("cancelling a knockout without a camera is quiet"))
	check(is_instance_valid(game.camera) and game.camera==saved, tag("the owner's camera is back for the game's own ticks"))
## Hoppy's orange (1, .33, 0) pixels; 2x zoom roughly quadruples the 1x count.
const HOPPY_MIN := 1500
func hoppy_pixels(image: Image) -> int:
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var px := image.get_pixel(x, y)
			if Vector3(px.r-1.0, px.g-.33, px.b).length()<=.18: count += 4
	return count
## Both bars are solid black from the window edge in, with no HUD text or controls over them.
func bars_are_black(image: Image) -> bool:
	var h := image.get_height()
	var bad := 0
	var total := 0
	for x in range(0, image.get_width(), 4):
		for y in range(2, int(BARS)-4, 3):
			total += 2
			var top := image.get_pixel(x, y)
			var bottom := image.get_pixel(x, h-1-y)
			if top.r+top.g+top.b>.06: bad += 1
			if bottom.r+bottom.g+bottom.b>.06: bad += 1
	print(tag("bar strips: %d of %d samples are not black" % [bad, total]))
	return total>0 and bad==0
## Stands in for the game with the optional hook, so the HUD contract is tested in both modes
## even before a game implements it. Forwards everything else to the real game.
class Proxy extends Node:
	var target
	var nodes: Array[CanvasItem] = []
	func _get(property: StringName):
		return target.get(property)
	func _set(property: StringName, value) -> bool:
		if property in ["target", "nodes"]: return false
		target.set(property, value)
		return true
	func knockout_hud_nodes() -> Array[CanvasItem]: return nodes
	func sound(key: String, at: Vector2 = Vector2.ZERO) -> void: target.sound(key, at)
	func clamp_ground(at: Vector2) -> Vector2: return target.clamp_ground(at)
	func room_start() -> float: return target.room_start()
func make_proxy():
	var proxy := Proxy.new()
	proxy.target = game
	var extra := Control.new()
	game.ui_layer.add_child(extra)
	var hidden := Control.new()
	hidden.visible = false
	game.ui_layer.add_child(hidden)
	proxy.nodes = [game.hud, extra, hidden]
	return proxy
func free_proxy(proxy) -> void:
	for n in proxy.nodes:
		if is_instance_valid(n) and n!=game.hud: n.free()
	proxy.free()
func visible_states(proxy) -> Array:
	var states := []
	for n in proxy.nodes: states.append(n.visible)
	return states
func check_hud_proxy() -> void:
	ready_combat()
	var proxy = make_proxy()
	var hud_before: bool = game.hud.visible
	var p = game.player
	p.position = Vector2(game.room_start()+640.0, 580.0)
	var counter := [0]
	game.ko.play(proxy, p.position+Vector2(-80, 0), func(): counter[0] += 1)
	check(visible_states(proxy)==[false, false, false], tag("every hook node is hidden from the first frame of the knockout"))
	var leaked := false
	var guard := 0
	while game.ko.active() and guard<600:
		# The owner refreshes its HUD before every tick, as the minimap does.
		proxy.nodes[1].visible = true
		game.hud.visible = true
		game.ko.tick(DT)
		if game.ko.active() and visible_states(proxy)!=[false, false, false]: leaked = true
		guard += 1
	check(not leaked, tag("the HUD stays hidden through the throw and the card even when the owner re-shows it"))
	check(counter[0]==1 and visible_states(proxy)==[true, true, false], tag("completion restores each node's original visibility and keeps the prior-hidden one hidden (%s)" % str(visible_states(proxy))))
	# cancel() restores the same way.
	game.hud.visible = hud_before
	proxy.nodes[1].visible = true
	game.ko.play(proxy, p.position+Vector2(80, 0), func(): counter[0] += 1)
	for _i in 100: game.ko.tick(DT)
	check(visible_states(proxy)==[false, false, false], tag("the HUD is hidden mid-knockout"))
	game.ko.cancel()
	check(visible_states(proxy)==[true, true, false] and counter[0]==1, tag("cancel() restores visibility and does not call done"))
	game.ko.cancel()
	check(visible_states(proxy)==[true, true, false], tag("a second cancel() leaves visibility alone"))
	# A replay over a running knockout captures the restored state, not the hidden one.
	game.ko.play(proxy, p.position+Vector2(80, 0), func(): pass)
	for _i in 30: game.ko.tick(DT)
	game.ko.play(proxy, p.position+Vector2(80, 0), func(): pass)
	game.ko.cancel()
	check(visible_states(proxy)==[true, true, false], tag("replaying captures the original visibility, so cancel restores it"))
	# A freed node mid-knockout is skipped.
	var gone := Control.new()
	game.ui_layer.add_child(gone)
	proxy.nodes.append(gone)
	game.ko.play(proxy, p.position+Vector2(80, 0), func(): pass)
	gone.free()
	proxy.nodes.pop_back()
	for _i in 10: game.ko.tick(DT)
	game.ko.cancel()
	check(visible_states(proxy)==[true, true, false], tag("a hook node freed during the knockout does not break the restore"))
	free_proxy(proxy)
## The real game's hook, once it exists: hidden during the knockout, the pause overlay still works.
func check_hud_real() -> void:
	if not game.has_method("knockout_hud_nodes"):
		print(tag("no knockout_hud_nodes() hook yet: real-game HUD checks skipped"))
		return
	ready_combat()
	var nodes: Array = game.knockout_hud_nodes()
	check(nodes.size()>0 and game.hud in nodes, tag("the game's hook lists its HUD"))
	var minimap_listed: bool = game.minimap!=null and (game.minimap in nodes or game.minimap.get_parent() in nodes)
	check(minimap_listed, tag("the game's hook lists its minimap"))
	var before := []
	for n in nodes: before.append(n.visible)
	game.player.position = Vector2(game.room_start()+640.0, 580.0)
	if not strike(true):
		check(false, tag("a fatal hit is accepted for the real HUD check"))
		return
	var leaked := false
	var guard := 0
	while game.state=="knockout" and game.ko.phase!="card" and guard<600:
		step()
		for n in nodes:
			if n.is_visible_in_tree(): leaked = true
		guard += 1
	check(not leaked, tag("no HUD or minimap node is visible from the throw to the card"))
	do_pause()
	check(game.state=="paused" and game.overlay.visible, tag("pausing during the card still shows the pause overlay"))
	game.resume()
	check(game.state=="knockout", tag("resume returns to the knockout"))
	for n in nodes:
		if n.is_visible_in_tree(): leaked = true
	check(not leaked, tag("resuming keeps the HUD hidden"))
	guard = 0
	while game.state=="knockout" and guard<600:
		step()
		guard += 1
	var after := []
	for n in nodes: after.append(n.visible)
	check(game.state=="game_over" and after==before, tag("the game over menu follows with each HUD node's visibility restored"))
