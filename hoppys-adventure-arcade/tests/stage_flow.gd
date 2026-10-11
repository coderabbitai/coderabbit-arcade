extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const DT := 1.0/60.0
const ENCOUNTER := "ENCOUNTER 1 / 3 — clear the blockers"
var failures := 0
var game
var encounter_overlap := false
var ticks_since_clear := -1
var shown_after := -1
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func tick(n: int) -> void:
	for i in n: game._physics_process(DT)
func near(got: float, want: float) -> bool:
	return absf(got-want) <= DT+1e-4
func encounter_showing() -> bool:
	return game.toast_label.visible and game.toast_label.text==ENCOUNTER
## Combat under a live title banner must not paint the encounter line. Once the banner
## clock hits zero, the held line is due on that same physics tick.
func note_encounter_banner() -> void:
	if game.flow.banner_panel.visible and encounter_showing(): encounter_overlap = true
	if game.state=="combat" and game.stage_index==1 and game.flow.phase=="" and not game.flow.banner_active():
		if ticks_since_clear < 0: ticks_since_clear = 0
		else: ticks_since_clear += 1
		if shown_after < 0 and encounter_showing(): shown_after = ticks_since_clear
func freeze() -> void:
	game.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)
		game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
func clear_enemies() -> void:
	for e in game.enemies:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.queue_free()
	game.enemies.clear()
## Room 3 of districts 1 and 2 has no walk-out: its cleared wave calls in the district boss,
## whose defeat runs the victory hop and then the exit. Drops the boss in, past its entrance,
## and lands the killing blow; play stops in boss_victory. Without a district boss it fails the
## suite and returns false, so no caller waits on an exit that cannot come.
func defeat_district_boss() -> bool:
	var boss = game.boss
	if not is_instance_valid(boss) or not game.has_mini_boss():
		check(false, "Room 3 of district %d has its district boss to defeat" % (game.stage_index+1))
		quit(1)
		return false
	boss.set_physics_process(false)
	var guard := 0
	while boss.state=="intro" and guard<200:
		boss.tick(DT)
		guard += 1
	boss.take_hit(999, 0, game.player.position)
	return true
## Right edge sits at room_start()+1280, so exit_x is room_start()+1340 on any viewport.
func frame_room() -> void:
	var width: float = game.get_viewport().get_visible_rect().size.x
	game.camera.zoom = Vector2.ONE
	game.camera.position = Vector2(game.room_start()+1280.0-width*0.5, 360)
	game.camera.reset_physics_interpolation()
func pause_frozen(detail: String, return_state: String, via_event: bool) -> void:
	var clock: float = game.flow.clock
	var alpha: float = game.flow.veil.color.a
	var volume: float = game.music.volume_db
	if via_event:
		var event := InputEventAction.new()
		event.action = "pause"
		event.pressed = true
		game._unhandled_input(event)
	else: game.pause(detail)
	check(game.state=="paused" and game.pause_return_state==return_state, "Pause from %s" % return_state)
	game._physics_process(DT)
	game.flow.tick(0.5, game.player)
	check(is_equal_approx(game.flow.clock, clock) and is_equal_approx(game.flow.veil.color.a, alpha) and is_equal_approx(game.music.volume_db, volume), "Pause freezes the %s fade" % return_state)
	game.resume()
	check(game.state==return_state, "Resume restores %s" % return_state)
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused = false
	if game.state=="paused": game.resume()
	freeze()
	check(is_equal_approx(game.flow.base_db, -13.0), "Music envelope is relative to the -13 dB base")
	check_intro()
	check_retry()
	check_exit()
	check_boss_dip()
	check_cancel()
	check(game.completion_count==0, "Transitions do not count as a completion")
	await check_terminal_paths()
	await check_armed_overlays()
	print("Stage flow failures: ", failures)
	if is_instance_valid(current_scene): current_scene.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
## Accumulated 1/60 steps land one ulp under 4.5, so the page turns on the next tick.
func cross_intro(page: int) -> void:
	var hold: float = Catalog.FLOW.intro_hold
	var guard := 0
	while game.intro_clock+DT<hold and game.state=="intro" and game.intro_page==page and guard<400:
		game._physics_process(DT)
		guard += 1
	check(game.state=="intro" and game.intro_page==page and game.intro_clock<hold, "Intro page %d holds at 4.5s - ε" % [page+1])
	var extra := 0
	while game.state=="intro" and game.intro_page==page and extra<3:
		game._physics_process(DT)
		extra += 1
	if page<2: check(extra<=2 and game.state=="intro" and game.intro_page==page+1, "Intro page %d advances by 4.5s + ε" % [page+1])
	else: check(extra<=2 and game.state=="stage_enter" and game.stage_index==0 and not game.playing, "Third page leads into the stage entrance by 4.5s + ε")
func check_intro() -> void:
	check(game.state=="intro" and game.intro_page==0 and not game.playing, "Opening sequence precedes combat")
	check(not game.toast_label.visible and game.held_toast=="", "Intro page 0 hides the encounter toast")
	tick(60)
	check(game.state=="intro" and game.intro_page==0 and not game.toast_label.visible and game.held_toast=="", "Intro page 0 still hides the encounter toast after ~1s")
	cross_intro(0)
	tick(30)
	var page: int = game.intro_page
	var clock: float = game.intro_clock
	game.pause("x")
	game._physics_process(1.0)
	check(game.state=="paused" and game.pause_return_state=="intro" and game.intro_page==page and is_equal_approx(game.intro_clock, clock), "Pause freezes the intro page and its clock")
	game.resume()
	check(game.state=="intro" and game.intro_page==page and is_equal_approx(game.intro_clock, clock), "Resume keeps the intro page and its clock")
	cross_intro(1)
	cross_intro(2)
	var guard := 0
	while game.state=="stage_enter" and guard<120:
		game._physics_process(DT)
		guard += 1
	check(game.state=="combat" and game.playing and game.stage_index==0, "Entrance reaches combat with no input")
	check(is_equal_approx(game.player.position.x, Catalog.FLOW.enter_to_x), "Intro entrance stops Hoppy at x=180")
func check_retry() -> void:
	var p = game.player
	p.hp = 1
	p.invulnerable = 0
	p.shield = false
	p.weapon = ""
	p.height = 0
	p.take_hit(p.position+Vector2(-40, 0))
	check(game.state=="knockout", "A last hit starts the knockout")
	var ko_guard := 0
	while game.state=="knockout" and ko_guard<400:
		game._physics_process(DT)
		ko_guard += 1
	check(game.state=="game_over", "A last hit opens the retry overlay")
	game.retry_stage()
	freeze()
	check(game.state=="stage_enter" and not game.overlay.visible, "Retry plays the stage entrance with the overlay hidden")
	check(is_equal_approx(game.player.position.x, Catalog.FLOW.enter_from_x), "Retry spawns Hoppy at x=-60")
	var guard := 0
	while game.state=="stage_enter" and guard<120:
		game._physics_process(DT)
		guard += 1
	check(game.state=="combat" and game.playing and not game.flow.active(), "Retry entrance reaches combat with no input")
	check(is_equal_approx(game.player.position.x, Catalog.FLOW.enter_to_x), "Retry entrance stops Hoppy at x=180")
	var armed := 0
	var grace := true
	for e in game.enemies:
		if not is_instance_valid(e) or e.dead: continue
		armed += 1
		if e.cooldown < Catalog.FLOW.enemy_grace: grace = false
	check(game.room==0 and armed>0 and grace, "Every room-0 enemy has telegraph grace at begin_play")
func check_exit() -> void:
	game.enter_room(2)
	freeze()
	clear_enemies()
	game._physics_process(DT)
	check(game.room==2 and not game.gate_open and game.has_mini_boss() and game.state=="combat", "Clearing room 3 calls in the district boss instead of opening the gate")
	frame_room()
	game.player.position = Vector2(game.room_start()+1210, 580)
	if not defeat_district_boss(): return
	check(game.state=="boss_victory" and not game.playing, "The district boss's defeat starts the victory hop")
	game.score = 480
	var volume_ok := true
	var spent := {}
	var order: Array[String] = []
	var stage_changes := 0
	var black_veil := -1.0
	var black_db := 0.0
	var exit_banner := false
	var exit_cleared := false
	var enter_banner := false
	var banner_at_combat := false
	var fade_out_prev := 0.0
	var fade_out_rose := false
	var fade_out_seen := false
	var fade_in_prev := float(Catalog.FLOW.music_floor_db)
	var fade_in_rose := false
	var fade_in_fell := false
	var fade_in_end := 99.0
	var exit_paused := false
	var enter_paused := false
	var enter_tick := -1
	var toast_ticks := 0
	var toast_mid := false
	var toast_hidden := false
	var driven := 0
	var near_exit_speed := -1.0
	var encounter_held := false
	encounter_overlap = false
	ticks_since_clear = -1
	shown_after = -1
	var hop := 0
	while game.state=="boss_victory" and hop<200:
		game._physics_process(DT)
		hop += 1
	check(game.state=="stage_exit" and game.flow.phase=="exit_run" and absi(hop-int(round(Catalog.FLOW.boss_victory/DT)))<=1, "The victory hop starts the exit run after %ss with no input (%d ticks)" % [Catalog.FLOW.boss_victory, hop])
	if order.is_empty() or order.back()!=game.flow.phase: order.append(game.flow.phase)
	game.toast("x", 1.0)
	var guard := 0
	while guard<600:
		guard += 1
		var phase_before: String = game.flow.phase
		var stage_before: int = game.stage_index
		if not exit_paused and phase_before=="fade_out" and game.flow.clock>0.12 and game.flow.clock<0.22:
			pause_frozen("x", "stage_exit", false)
			exit_paused = true
			continue
		if not enter_paused and game.state=="stage_enter" and phase_before=="fade_in" and game.flow.clock>0.12 and game.flow.clock<0.22:
			pause_frozen("x", "stage_enter", true)
			enter_paused = true
			continue
		game._physics_process(DT)
		driven += 1
		toast_ticks += 1
		if not is_equal_approx(game.music.volume_db, game.flow.base_db+game.flow.music_db): volume_ok = false
		spent[phase_before] = float(spent.get(phase_before, 0.0))+DT
		if order.is_empty() or order.back()!=game.flow.phase: order.append(game.flow.phase)
		if phase_before=="exit_run" and game.flow.banner_panel.visible and game.flow.banner_title.text=="DISTRICT SECURED" and game.flow.banner_panel.modulate.a>0.0:
			exit_banner = true
		if phase_before=="fade_out":
			fade_out_seen = true
			if game.flow.music_db > fade_out_prev+0.05: fade_out_rose = true
			fade_out_prev = game.flow.music_db
		if phase_before=="fade_in":
			if game.flow.music_db > fade_in_prev+0.05: fade_in_rose = true
			if game.flow.music_db < fade_in_prev-0.05: fade_in_fell = true
			fade_in_prev = game.flow.music_db
			fade_in_end = game.flow.music_db
		if game.stage_index!=stage_before:
			stage_changes += 1
			black_veil = game.flow.veil.color.a
			black_db = game.flow.music_db
			exit_cleared = not game.flow.banner_panel.visible
			freeze()
		if game.flow.phase=="enter_run" and enter_tick<0: enter_tick = driven
		if phase_before=="enter_run" and game.flow.banner_panel.visible and game.flow.banner_title.text=="02 / SECURITY SECTOR" and game.flow.banner_subtitle.text==Catalog.STORIES[1]:
			enter_banner = true
		if phase_before=="exit_run": near_exit_speed = game.flow.exit_speed
		if phase_before=="enter_run" and game.flow.phase=="":
			banner_at_combat = game.state=="combat" and game.flow.banner_panel.visible and game.flow.banner_panel.modulate.a>0.9
			encounter_held = game.state=="combat" and game.flow.banner_active() and game.held_toast==ENCOUNTER and not encounter_showing()
		note_encounter_banner()
		if toast_ticks==30: toast_mid = game.state=="stage_exit" and game.toast_label.visible and near(game.toast_left, 0.5)
		if toast_ticks>=60 and not game.toast_label.visible: toast_hidden = true
		if game.state=="combat" and game.stage_index==1 and game.flow.phase=="": break
	var banner_hide := -1
	var after := 0
	while game.flow.banner_panel.visible and after<180:
		game._physics_process(DT)
		driven += 1
		after += 1
		if not is_equal_approx(game.music.volume_db, game.flow.base_db+game.flow.music_db): volume_ok = false
		note_encounter_banner()
		if not game.flow.banner_panel.visible: banner_hide = driven
	var sequence := ""
	for phase in order: sequence += "/" + phase
	check(sequence=="/exit_run/fade_out/fade_in/enter_run/", "Phase order is exit_run → fade_out → fade_in → enter_run → done (got %s)" % sequence)
	check(near(float(spent.get("exit_run", -1)), 0.6), "exit_run lasts 0.6s (got %s)" % spent.get("exit_run"))
	check(near(float(spent.get("fade_out", -1)), 0.35), "fade_out lasts 0.35s (got %s)" % spent.get("fade_out"))
	check(near(float(spent.get("fade_in", -1)), 0.35), "fade_in lasts 0.35s (got %s)" % spent.get("fade_in"))
	check(near(float(spent.get("enter_run", -1)), 0.8), "enter_run lasts 0.8s (got %s)" % spent.get("enter_run"))
	check(game.state=="combat" and game.stage_index==1 and game.playing, "Exit returns through stage_enter into the next stage's combat")
	check(is_equal_approx(game.player.position.x, Catalog.FLOW.enter_to_x), "The new stage's Hoppy ends at x=180")
	check(game.checkpoint_score==480, "The exit saves the checkpoint score")
	check(stage_changes==1 and is_equal_approx(black_veil, 1.0) and is_equal_approx(black_db, float(Catalog.FLOW.music_floor_db)), "on_black runs once, on a black veil, with music at the floor")
	check(volume_ok, "music.volume_db == base_db + music_db throughout")
	check(fade_out_seen and not fade_out_rose and is_equal_approx(black_db, -40.0), "Music never rises during fade_out and reaches -40 at black")
	check(fade_in_rose and not fade_in_fell and is_equal_approx(fade_in_end, 0.0), "Music rises during fade_in and ends at 0")
	check(exit_paused and enter_paused, "Pause was exercised during the exit fade and the next entrance")
	check(exit_banner and exit_cleared, "DISTRICT SECURED shows during the exit run and clears at black")
	check(enter_banner, "The entrance banner names 02 / SECURITY SECTOR and its story")
	check(banner_at_combat, "The entrance banner is still up when combat starts")
	check(game.state=="combat" and banner_hide>enter_tick and near(float(banner_hide-enter_tick)*DT, Catalog.FLOW.stage_banner), "The entrance banner hides 2.8s after enter_run began")
	check(toast_mid and toast_hidden, "A 1s toast shown during the exit counts down while play is stopped")
	check(is_equal_approx(near_exit_speed, float(Catalog.FLOW.run_speed)), "A near gate exit keeps run_speed (got %s)" % near_exit_speed)
	check(encounter_held, "The encounter toast is held, not shown, while the entrance banner is up")
	check(not encounter_overlap, "The encounter toast is never visible while the entrance banner is")
	check(shown_after>=0 and shown_after<=1, "The encounter toast appears within 1 tick of the banner clearing (delay %s)" % shown_after)
	check_far_exit()
	check_toast_probe()
## Hoppy starts deep in the room. exit_run must carry him past exit_x before exit_max, faster than a walk.
func check_far_exit() -> void:
	frame_room()
	game.player.position = Vector2(game.room_start()+100.0, 580)
	game.exit_stage()
	check(game.state=="stage_exit" and game.flow.phase=="exit_run", "A far Hoppy still starts the exit run")
	var spent := 0.0
	var guard := 0
	while game.flow.phase!="fade_out" and guard<400:
		var phase_before: String = game.flow.phase
		game._physics_process(DT)
		if phase_before=="exit_run": spent += DT
		guard += 1
	var run_speed := float(Catalog.FLOW.run_speed)
	check(game.flow.phase=="fade_out", "Far exit reaches fade_out (phase %s after %ss)" % [game.flow.phase, spent])
	check(game.player.global_position.x>=game.flow.exit_x, "Far exit clears exit_x before fade_out (x %s, exit_x %s)" % [game.player.global_position.x, game.flow.exit_x])
	check(spent>0.0 and spent<=float(Catalog.FLOW.exit_max), "Far exit_run stays within exit_max (spent %s)" % spent)
	check(game.flow.exit_speed>run_speed, "Far exit runs faster than run_speed (got %s)" % game.flow.exit_speed)
	check(is_equal_approx(game.player.body.speed_scale, game.flow.exit_speed/run_speed), "Far exit matches stride to exit_speed (scale %s vs %s)" % [game.player.body.speed_scale, game.flow.exit_speed/run_speed])
	if game.flow.active(): game.flow.cancel()
	game.state = "combat"
	game.playing = true
	freeze()
## A second entrance: two combat lines raised under the banner, and only the later one plays, at its own duration.
func check_toast_probe() -> void:
	clear_enemies()
	game.gate_open = true
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	game.enter_stage()
	var guard := 0
	while not (game.state=="combat" and game.flow.phase=="") and guard<400:
		game._physics_process(DT)
		guard += 1
	check(game.state=="combat" and game.flow.banner_active(), "Probe entrance is in combat with the title banner still up")
	check(game.held_toast==ENCOUNTER and not game.toast_label.visible, "Probe entrance holds the encounter line")
	game.toast("earlier", 0.8)
	check(game.held_toast=="earlier" and is_equal_approx(game.held_toast_seconds, 0.8) and not game.toast_label.visible, "A combat toast raised during the banner is held")
	game.toast("probe", 1.5)
	check(game.held_toast=="probe" and is_equal_approx(game.held_toast_seconds, 1.5) and not game.toast_label.visible, "A later combat toast replaces the one still held")
	var overlap := false
	var left := -1.0
	var shown := false
	guard = 0
	while game.flow.banner_active() and guard<400:
		game._physics_process(DT)
		guard += 1
		var painting: bool = game.toast_label.visible and game.toast_label.text=="probe"
		if game.flow.banner_panel.visible and painting: overlap = true
		if not game.flow.banner_active() and not shown:
			shown = painting
			left = game.toast_left
	check(shown and not overlap and is_equal_approx(left, 1.5), "Held probe appears at 1.5s once the banner clears (left %s, overlap %s)" % [left, overlap])
func check_boss_dip() -> void:
	game.start_stage(2)
	freeze()
	var guard := 0
	while game.state!="combat" and guard<120:
		game._physics_process(DT)
		guard += 1
	check(game.state=="combat" and game.stage_index==2, "Stage 3 entrance reaches combat")
	var before = game.music.stream
	game.enter_room(2)
	freeze()
	var unchanged := true
	var mid_db := 99.0
	var swapped := false
	var back := 99.0
	for i in 40:
		var elapsed := float(i+1)*DT
		game._physics_process(DT)
		if not is_equal_approx(game.music.volume_db, game.flow.base_db+game.flow.music_db): unchanged = false
		if elapsed < 0.3-DT*0.5 and game.music.stream!=before: unchanged = false
		if not swapped and game.music.stream!=before:
			swapped = true
			mid_db = game.flow.music_db
			check(near(elapsed, 0.3), "Boss stream swaps at the midpoint (at %s s)" % snappedf(elapsed, 0.001))
		if elapsed>=0.6-1e-4 and back>90.0: back = game.flow.music_db
	check(unchanged, "Boss stream is unchanged before 0.3s and the envelope tracks volume_db")
	check(swapped and is_equal_approx(mid_db, float(Catalog.FLOW.music_floor_db)), "Boss dip reaches about -40 dB as the stream swaps")
	# The player holds a looping copy (no resource_path); the director names its source track.
	check(game.flow.music_track==Catalog.BOSS_MUSIC and game.music.stream!=Catalog.BOSS_MUSIC and game.music.stream.loop and not Catalog.BOSS_MUSIC.loop, "Swapped stream is a looping copy of Catalog.BOSS_MUSIC (got '%s')" % (game.flow.music_track.resource_path if game.flow.music_track else ""))
	check(is_equal_approx(back, 0.0) and is_equal_approx(game.flow.music_db, 0.0), "Boss dip is back to 0 dB by 0.6s")
func check_cancel() -> void:
	game.start_stage(1)
	freeze()
	check(game.state=="stage_enter" and game.flow.active(), "A direct stage start waits on the entrance")
	var index: int = game.stage_index
	game._physics_process(DT)
	game.begin_play()
	check(not game.flow.active() and is_equal_approx(game.flow.veil.color.a, 0.0), "begin_play cancels the flow and clears the veil")
	check(game.state=="combat" and game.stage_index==index, "Cancel does not run on_black")
# --- Terminal paths: game over, retry, boss defeat and leave must cancel a running sequence ---
## From a fresh stage-1 entrance, clears to the room-3 gate, runs the exit and stops 0.1 s into
## `phase`. fade_out is before black (stage 1); enter_run is after it (stage 2).
func reach(phase: String) -> void:
	game.start_stage(0)
	freeze()
	var guard := 0
	while game.state!="combat" and guard<200:
		game._physics_process(DT)
		guard += 1
	clear_enemies()
	game.enter_room(2)
	freeze()
	clear_enemies()
	game._physics_process(DT)
	frame_room()
	game.player.position = Vector2(game.room_start()+1210, 580)
	if not defeat_district_boss(): return
	guard = 0
	while not (game.flow.phase==phase and game.flow.clock>=0.1) and guard<400:
		game._physics_process(DT)
		freeze()
		guard += 1
## Ticks 3 s and checks nothing moved on: stage, track, stream, phase, veil, owner state.
func steady(label: String, want: String) -> void:
	var stage: int = game.stage_index
	var track = game.flow.music_track
	var stream = game.music.stream
	var held := true
	for i in 180:
		game._physics_process(DT)
		if game.stage_index!=stage or game.flow.music_track!=track or game.music.stream!=stream: held = false
		if game.flow.phase!="" or game.flow.veil.color.a>0.0 or game.state!=want or game.playing: held = false
		if want=="leaving" and game.music.playing: held = false
	check(held and is_equal_approx(game.flow.music_db, 0.0), label)
## Leave routes away; wait for the router, confirm the menu, then load a fresh Code City.
func reload() -> void:
	# The router fades on a clock; a stuck route must fail the suite, not hang it.
	var deadline: int = Time.get_ticks_msec()+5000
	while root.get_node("AppRouter").busy:
		if Time.get_ticks_msec() > deadline:
			check(false, "AppRouter finishes routing within 5 s")
			quit(1)
			return
		await process_frame
	check(current_scene.name=="BeatemMenu", "Leave still routes to the Beat'em Up menu")
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	paused = false
	if game.state=="paused": game.resume()
	freeze()
func check_terminal_paths() -> void:
	for phase in ["fade_out", "enter_run"]:
		reach(phase)
		var at: String = "%s (stage %d)" % [phase, game.stage_index+1]
		game.game_over()
		check(game.overlay.visible and not game.flow.active(), "Game over during %s cancels the flow" % at)
		steady("Game over during %s: no rebuild, music change, veil or combat for 3 s" % at, "game_over")
		reach(phase)
		var stage: int = game.stage_index
		game.retry_stage()
		freeze()
		var held := true
		for i in 180:
			game._physics_process(DT)
			freeze()
			if game.stage_index!=stage or game.flow.music_track!=Catalog.MUSIC[stage]: held = false
		check(held and game.state=="combat" and game.flow.phase=="" and game.flow.veil.color.a==0.0, "Retry during %s re-enters the same stage; the pending exit never advances it" % at)
		check_boss_terminal(phase)
		for via_menu in [false, true]:
			reach(phase)
			at = "%s (stage %d)" % [phase, game.stage_index+1]
			if via_menu:
				game.pause("x")
				var back: Button = null
				for child in game.panel.get_children():
					if child is Button and child.text=="Return to Beat'em Up menu": back = child
				if back == null:
					check(false, "The pause menu offers Return during %s" % at)
					quit(1)
					return
				back.pressed.emit()
				check(back.disabled, "The pause menu's Return disables the menu during the router fade")
			else: game.leave()
			check(not paused and not game.flow.active() and not game.music.playing, "%s during %s cancels the flow and stops music" % ["Pause-menu Return" if via_menu else "Leave", at])
			steady("%s during %s: no rebuild, music restart, veil or combat for 3 s" % ["Pause-menu Return" if via_menu else "Leave", at], "leaving")
			await reload()
## No exit follows the boss, so drive a sequence directly in the boss room and count its black.
func check_boss_terminal(phase: String) -> void:
	game.start_stage(2)
	freeze()
	var guard := 0
	while game.state!="combat" and guard<200:
		game._physics_process(DT)
		guard += 1
	clear_enemies()
	game.enter_room(2)
	freeze()
	for i in 40: game._physics_process(DT)
	var boss = game.boss
	for damage in [12, 6]:
		boss.vulnerable = true
		boss.take_hit(damage, 0, Vector2.ZERO, true)
	freeze()
	clear_enemies()
	var blacks := [0]
	if phase=="fade_out": game.flow.play_exit(func(): blacks[0] += 1)
	else: game.flow.play_enter("x", "y")
	guard = 0
	while not (game.flow.phase==phase and game.flow.clock>=0.1) and guard<200:
		game._physics_process(DT)
		guard += 1
	check(boss.phase==3 and game.flow.phase==phase, "The boss reaches its final phase during a synthetic %s" % phase)
	boss.vulnerable = true
	boss.take_hit(6, 0, Vector2.ZERO, true) # The real defeat path: take_hit → arena.boss_defeated()
	var held := true
	for i in 180:
		game._physics_process(DT)
		if game.flow.phase!="" or game.flow.veil.color.a>0.0 or game.state!="finisher" or game.stage_index!=2: held = false
	check(held and blacks[0]==0 and game.flow.music_track==Catalog.BOSS_MUSIC and is_equal_approx(game.flow.music_db, 0.0), "Boss defeat during %s cancels the sequence and keeps the boss track" % phase)
# --- Results and game-over menus arm after OVERLAY_ARM, so a carried-over press can't skip them ---
## Everything a player can press a focused overlay button with: Space (jump and ui_accept), pad A
## (jump), a click, and a native touch, which presses buttons as well as its emulated click.
const PRESSES := ["space", "pad", "click", "touch"]
## One press or release through the viewport. Viewport coordinates: headless, the 64 px window
## is stretched, so window-space pointers miss.
func send(kind: String, pressed: bool) -> void:
	var button: Button = game.victory.action if game.state=="won" else game.primary
	var at: Vector2 = button.get_global_rect().get_center()
	var event: InputEvent
	match kind:
		"space":
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.physical_keycode = KEY_SPACE
			event = key
		"pad":
			var pad := InputEventJoypadButton.new()
			pad.button_index = JOY_BUTTON_A
			event = pad
		"click":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = at
			click.global_position = at
			event = click
		"touch":
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.position = at
			event = touch
	event.pressed = pressed
	root.push_input(event, true)
func confirm(kind: String) -> void:
	send(kind, true)
	send(kind, false)
func arm() -> void:
	for i in ceili(game.OVERLAY_ARM/DT)+1: game._physics_process(DT)
## On its first frame the overlay ignores every press, and a press held from then and released
## after arming. Then a fresh `activate` press, once armed, is the one that counts. One process
## frame first lets the new buttons lay out, so pointers land on them; game physics is frozen
## here, so the arm clock is still 0.
func guarded(label: String, activate: String) -> void:
	await process_frame
	check(game.overlay_clock==0.0 and game.primary.get_global_rect().size.x>game.primary.custom_minimum_size.x, "%s is laid out and still unarmed" % label)
	var before: String = game.state
	for kind in PRESSES: confirm(kind)
	check(game.state==before and game.overlay.visible, "%s ignores Space, pad A, a click and a touch on its first frame" % label)
	for kind in PRESSES: send(kind, true)
	arm()
	for kind in PRESSES: send(kind, false)
	check(game.state==before and game.overlay.visible, "%s ignores a press held from its first frame and released after 0.5 s" % label)
	confirm(activate)
## The results screen: it swallows every press for 0.5 s, a press after that lands the count, and
## only once the count has landed does a press reach Return.
func guarded_results(activate: String) -> void:
	await process_frame
	var screen = game.victory
	check(screen.clock<screen.ARM and screen.action.get_global_rect().size.x>screen.action.custom_minimum_size.x, "Results are laid out and still unarmed")
	for kind in PRESSES: confirm(kind)
	check(game.state=="won" and not screen.landed, "Results ignore Space, pad A, a click and a touch on their first frame")
	for kind in PRESSES: send(kind, true)
	arm()
	for kind in PRESSES: send(kind, false)
	check(game.state=="won" and not screen.landed, "Results ignore a press held from the first frame and released after 0.5 s")
	check(screen.action.disabled, "Return is disabled until the count lands")
	confirm(activate)
	check(game.state=="won" and screen.landed and game.state!="leaving" and screen.shown_score()==screen.final_score, "A %s after 0.5 s lands the count instead of leaving" % activate)
	check(not screen.action.disabled and screen.action.has_focus(), "Return is enabled and focused once the count lands")
	confirm(activate)
	check(game.state=="leaving", "A %s once the count has landed presses Return" % activate)

func to_combat(index: int) -> void:
	game.start_stage(index)
	freeze()
	var guard := 0
	while game.state!="combat" and guard<200:
		game._physics_process(DT)
		guard += 1
func check_armed_overlays() -> void:
	# Space is both jump and ui_accept: the carried-over press. (Pad A is jump only today; the
	# guard swallows ui_accept itself, so it would cover A too if A were ever bound to it.)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	check(InputMap.event_is_action(space, "ui_accept") and InputMap.event_is_action(space, "brawl_jump"), "Space is both jump and ui_accept")
	var waited := 0
	for activate in ["space", "touch"]:
		to_combat(0)
		var p = game.player
		p.hp = 1
		p.invulnerable = 0
		p.shield = false
		p.weapon = ""
		p.take_hit(p.position+Vector2(-40, 0))
		check(game.state=="knockout", "A last hit starts the knockout before the menu")
		waited = 0
		while game.state=="knockout" and waited<400:
			game._physics_process(DT)
			waited += 1
		check(game.state=="game_over" and game.primary.has_focus(), "Game over focuses Retry")
		await guarded("Game over", activate)
		check(game.state=="stage_enter", "A %s after 0.5 s presses Retry" % activate)
	for activate in ["click", "touch"]:
		to_combat(2)
		clear_enemies()
		game.enter_room(2)
		freeze()
		var boss = game.boss
		for damage in [12, 6, 6]:
			boss.vulnerable = true
			boss.take_hit(damage, 0, Vector2.ZERO, true)
		freeze()
		var guard := 0
		while game.state in ["finisher","celebration","ending"] and guard<2000:
			game._physics_process(DT)
			guard += 1
		check(game.state=="won" and game.victory.visible and not game.victory.landed and game.victory.action.disabled, "The Force Merge hands off through the celebration and the ending to the results screen mid-count")
		await guarded_results(activate)
		await reload()
