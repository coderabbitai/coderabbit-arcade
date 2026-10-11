extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const MiniBoss = preload("res://modes/beatem_up/mini_boss.gd")
const DT := 1.0/60.0
const SHEET_CLIPS := ["idle", "walk", "slam_warning", "slam", "dash_warning", "dash", "recover", "hurt", "defeat"]
var failures := 0
var game
## Set by the sheet check for the boss under test. Pose names are only asserted on S2's own atlas.
var atlas_ready := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n: await process_frame
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
		if is_instance_valid(e): e.queue_free()
	game.enemies.clear()
func warnings_owned(node: Node, kind := "") -> int:
	var count := 0
	for w in game.warnings:
		if w.owner != node: continue
		if kind != "" and w.kind != kind: continue
		count += 1
	return count
func living_kind(kind: String) -> int:
	var count := 0
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead and e.kind == kind: count += 1
	return count
func boot(index: int) -> bool:
	if not is_instance_valid(game):
		check(false, "The stage is still running")
		return false
	game.start_stage(index)
	await process_frame
	await process_frame
	if not is_instance_valid(game.player) or not is_instance_valid(game.player.body) or not is_instance_valid(game.player.held):
		check(false, "The stage spawns Hoppy")
		return false
	if not is_instance_valid(game.flow):
		check(false, "The stage is still running")
		return false
	freeze()
	game.begin_play()
	game.flow.banner("", "", 0)
	game.hide_toast()
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	# Stray hazards must not open a knockout before the guard test asks for one.
	game.player.invulnerable = 30
	return true
func clear_wave() -> void:
	clear_enemies()
	game.hazard_clock = 30.0
	game.ally_clock = 30.0
	game.flow.banner("", "", 0)
	game.hide_toast()
## Rooms 1 and 2 still open the gate and walk on. Room 3 only spawns its wave.
func walk_to_last_room() -> bool:
	if not is_instance_valid(game.player):
		check(false, "Hoppy is on screen to change rooms")
		return false
	check(game.room == 0 and not game.gate_open and not game.has_mini_boss(), "District 1 starts in room 1 with the gate shut")
	if game.room != 0 or game.gate_open or game.has_mini_boss(): return false
	clear_wave()
	game._physics_process(DT)
	check(game.room == 0 and game.gate_open and is_instance_valid(game.gate) and not game.gate.visible, "Clearing room 1 opens the gate")
	if game.room != 0 or not game.gate_open: return false
	if not is_instance_valid(game.player):
		check(false, "Hoppy is on screen to change rooms")
		return false
	game.player.position = Vector2(game.room_start()+1210, 580)
	game._physics_process(DT)
	freeze()
	check(game.room == 1 and not game.gate_open and not game.has_mini_boss(), "Room 1 walks on into room 2")
	if game.room != 1 or game.gate_open or game.has_mini_boss(): return false
	clear_wave()
	game._physics_process(DT)
	check(game.room == 1 and game.gate_open and is_instance_valid(game.gate) and not game.gate.visible, "Clearing room 2 opens the gate")
	if game.room != 1 or not game.gate_open: return false
	if not is_instance_valid(game.player):
		check(false, "Hoppy is on screen to change rooms")
		return false
	game.player.position = Vector2(game.room_start()+1210, 580)
	game._physics_process(DT)
	freeze()
	check(game.room == 2 and not game.gate_open and not is_instance_valid(game.boss), "Walking into room 3 spawns its wave, not the district boss")
	return game.room == 2 and not game.gate_open and not is_instance_valid(game.boss)
func summon() -> bool:
	clear_wave()
	game._physics_process(DT)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
	var called: bool = game.has_mini_boss() and not game.gate_open
	check(called, "Clearing room 3 of district %d calls the district boss and keeps the gate shut" % [game.stage_index+1])
	return called
func expect_mini(key: String, title: String, hp: float, sheet: String, idle: String) -> bool:
	var boss = game.boss
	if not game.has_mini_boss():
		check(false, "%s spawns a mini-boss" % title)
		return false
	boss.set_physics_process(false)
	check(boss.key == key and boss.title == title, "%s uses key %s" % [title, key])
	check(is_equal_approx(boss.hp, hp) and is_equal_approx(boss.max_hp, hp) and boss.phase == 1, "%s has %d HP and stays in phase 1" % [title, int(hp)])
	check(not boss.enraged and not boss.adds_called and boss.state == "intro" and not boss.dead, "%s drops in, calm, through its intro" % title)
	check(not game.gate_open and is_instance_valid(game.gate) and game.gate.visible, "%s leaves the gate shut" % title)
	check(game.toast_label != null and game.toast_label.text == "DISTRICT BOSS · %s" % title, "%s toasts its name" % title)
	check(game.boss_text != null and game.boss_text.text == "DISTRICT BOSS · %s" % title and game.boss_bar != null and game.boss_bar.visible and is_equal_approx(game.boss_bar.max_value, hp), "%s fills the district-boss bar" % title)
	if not expect_sheet(boss, key, title, sheet, idle): return false
	return true
## S2's atlas plays each pose by name. Until it lands, the fallback sheet and its clip map draw.
func expect_sheet(boss, key: String, title: String, sheet: String, idle: String) -> bool:
	if not is_instance_valid(boss) or not is_instance_valid(boss.body):
		check(false, "%s has a body" % title)
		return false
	atlas_ready = MiniBoss.sheet_ready(key)
	if atlas_ready:
		print("SHEET: %s ready" % key)
		var scale := float(Catalog.MINI_BOSSES[key].scale)
		check(boss.clips.is_empty() and is_equal_approx(scale, 1.7) and is_equal_approx(boss.magnify, scale) and boss.body.scale.is_equal_approx(Vector2(scale, scale)), "%s uses its own sheet at scale 1.7" % title)
		check(boss.body.sprite_frames == Art.frames(key) and boss.body.animation == "idle", "%s plays idle on its own sheet" % title)
		var missing := ""
		for pose_name in SHEET_CLIPS:
			if not boss.body.sprite_frames.has_animation(pose_name): missing += pose_name + " "
		var suffix := ""
		if missing != "": suffix = " (missing %s)" % missing.strip_edges()
		check(missing == "", "%s sheet has all nine clips%s" % [title, suffix])
	else:
		print("SHEET: %s fallback (%s / %s)" % [key, sheet, idle])
		check(not MiniBoss.sheet_ready(key), "%s has no atlas yet, so the fallback sheet draws" % title)
		check(not boss.clips.is_empty() and boss.clips.get("idle", "") == idle, "%s keeps the fallback clip map" % title)
		check(boss.body.sprite_frames == Art.frames(sheet) and boss.body.animation == idle, "%s draws the %s sheet" % [title, sheet])
		check(is_equal_approx(boss.magnify, 3.4) and boss.body.scale.is_equal_approx(Vector2(3.4, 3.4)), "%s draws the fallback at scale 3.4" % title)
	return true
## On the real atlas a pose plays the clip of the same name. clip() remaps only the fallback.
func check_pose(boss, pose_name: String, when: String) -> void:
	if not atlas_ready: return
	if not is_instance_valid(boss) or not is_instance_valid(boss.body):
		check(false, "%s has a body" % when)
		return
	check(boss.body.animation == pose_name, "%s plays %s" % [when, pose_name])
func see_minimap() -> void:
	if not is_instance_valid(game.player) or not is_instance_valid(game.minimap):
		check(false, "The minimap and Hoppy are up")
		return
	# The spawn tick refreshed the minimap before the boss existed. One more tick records it.
	game.player.position = Vector2(game.room_start()+1240, 580)
	game._physics_process(DT)
	check(game.minimap.visible and game.minimap.boss_dots.size() == 1, "Combat shows the district boss on the minimap")
	check(game.room == 2 and not game.gate_open and game.has_mini_boss(), "Room 3 does not walk out while the district boss is up")
func leave_intro(boss) -> bool:
	if not is_instance_valid(boss) or not is_instance_valid(game.player):
		check(false, "The district boss and Hoppy are up for the intro")
		return false
	check(not boss.take_hit(5, 0, game.player.position) and is_equal_approx(boss.hp, boss.max_hp) and boss.state == "intro", "The drop-in intro shrugs off hits")
	var guard := 0
	while boss.state == "intro" and guard < 200:
		boss.tick(DT)
		guard += 1
	check(boss.state == "chase" and guard >= 80 and guard <= 83, "The drop-in intro ends after 1.35s (%d ticks)" % guard)
	return boss.state == "chase"
func check_tells(boss) -> void:
	if not is_instance_valid(boss):
		check(false, "The tell check still has the district boss")
		return
	game.clear_threats()
	boss.cycle = 0
	boss.telegraph()
	check(boss.move == "slam" and boss.state == "tell" and warnings_owned(boss, "slam") == 1, "An odd cycle plants one slam warning")
	check_pose(boss, "slam_warning", "A slam tell")
	game.clear_threats()
	boss.telegraph()
	check(boss.move == "dash" and boss.state == "tell" and warnings_owned(boss, "signal") == 3, "An even cycle plants three dash signals")
	check_pose(boss, "dash_warning", "A dash tell")
	game.clear_threats()
	boss._rest(0.0)
	check(boss.state == "chase" and boss.move == "", "The boss returns to the chase after a tell")
func drain_stagger(boss) -> int:
	var guard := 0
	while is_instance_valid(boss) and boss.state == "stagger" and guard < 80:
		boss.tick(DT)
		guard += 1
	return guard
func check_stagger(boss) -> void:
	if not is_instance_valid(boss) or not is_instance_valid(game.player):
		check(false, "The stagger check still has Hoppy and the boss")
		return
	game.clear_threats()
	game.ground_warning(boss.position, Vector2(40, 20), 2.0, .2, "slam", boss)
	game.ground_warning(boss.position+Vector2(80, 0), Vector2(30, 20), 2.0, .2, "signal", null)
	check(warnings_owned(boss) == 1, "A planted slam belongs to the boss")
	for i in 3:
		check(boss.take_hit(1, 0, game.player.position) and boss.state != "stagger", "Hit %d does not stagger" % [i+1])
	check(warnings_owned(boss) == 1, "The boss's warning stays up through the third hit")
	check(boss.take_hit(1, 0, game.player.position) and boss.state == "stagger" and boss.hits == 0 and is_equal_approx(boss.timer, .6), "The fourth hit staggers for 0.6s")
	check_pose(boss, "hurt", "Stagger")
	check(warnings_owned(boss) == 0 and game.warnings.size() == 1, "Stagger drops the boss's warnings and leaves the rest")
	var guard := drain_stagger(boss)
	if not is_instance_valid(boss):
		check(false, "Stagger lasts 0.6s (%d ticks)" % guard)
		return
	check(boss.state == "chase" and guard >= 36 and guard <= 37, "Stagger lasts 0.6s (%d ticks)" % guard)
## Three hits are already on the counter. The fourth connects in the air, so the reel waits for the landing.
func check_deferred(boss) -> void:
	if not is_instance_valid(boss) or not is_instance_valid(game.player):
		check(false, "The landing stagger still has Hoppy and the boss")
		return
	boss.hits = 3
	boss.leaping = true
	boss.state = "active"
	boss.move = "slam"
	boss.timer = DT
	boss.launch = boss.position
	boss.aim = boss.position
	var hp: float = boss.hp
	check(boss.take_hit(1, 0, game.player.position) and boss.leaping and boss.state == "active" and boss.hits == 4 and is_equal_approx(boss.hp, hp-1), "A fourth hit during a slam leap damages without staggering")
	boss.tick(DT)
	check(boss.state == "stagger" and not boss.leaping, "The leap staggers when it lands")
	check_pose(boss, "hurt", "The landing stagger")
	game.clear_threats()
	var guard := drain_stagger(boss)
	if not is_instance_valid(boss):
		check(false, "The landing stagger ends back in the chase")
		return
	check(boss.state == "chase" and guard >= 36 and guard <= 37, "The landing stagger ends back in the chase")
func check_enrage(boss) -> void:
	if not is_instance_valid(boss) or boss.data == null or not is_instance_valid(game.player):
		check(false, "The district boss is up to enrage")
		return
	var kind: String = str(boss.data.add)
	var before: int = game.living_enemies()
	var slam := float(boss.data.slam_tell)
	var dash := float(boss.data.dash_tell)
	check(not boss.enraged and is_equal_approx(boss.tell_time("slam"), slam), "A calm district boss tells at full length")
	var target := float(boss.max_hp)*float(boss.data.rage_at)
	check(boss.take_hit(boss.hp-target, 0, game.player.position), "The hit that crosses half health lands")
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	check(boss.enraged and boss.adds_called and game.living_enemies() == before+2 and living_kind(kind) == 2, "Crossing half health enrages and calls two %s adds" % kind)
	check(is_equal_approx(boss.tell_time("slam"), slam*float(boss.data.rage)) and is_equal_approx(boss.tell_time("dash"), dash*float(boss.data.rage)), "Enrage shortens both tells")
	var living: int = game.living_enemies()
	check(boss.take_hit(1, 0, game.player.position) and boss.adds_called and game.living_enemies() == living, "A later hit does not call more adds")
func down_and_off(from_stage: int, pause_hop: bool) -> void:
	var boss = game.boss
	if not game.has_mini_boss() or not is_instance_valid(boss) or not is_instance_valid(game.player) or not is_instance_valid(game.player.body) or not is_instance_valid(game.player.held) or not is_instance_valid(game.flow):
		check(false, "Hoppy and the district boss are up for the victory")
		return
	check(boss.phase == 1 and boss.melee_reaches(Vector2(40, 0), 1, 110, 46), "The district boss stays in phase 1 and can be hit")
	var score: int = game.score
	game.player.held.show()
	boss.take_hit(999, 0, game.player.position)
	check(boss.dead and boss.state == "defeat" and not boss.melee_reaches(Vector2(40, 0), 1, 110, 46), "Defeat removes the boss as a target")
	check_pose(boss, "defeat", "Defeat")
	check(game.state == "boss_victory" and not game.playing, "Defeat starts the victory hop")
	check(game.boss_bar != null and not game.boss_bar.visible and game.boss_text != null and not game.boss_text.visible, "Defeat hides the district-boss bar and label")
	check(game.score == score+500, "Defeat scores 500")
	check(game.gate_open and is_instance_valid(game.gate) and not game.gate.visible, "Defeat opens the gate and hides it")
	check(not game.player.held.visible, "Defeat hides what Hoppy was holding")
	var cheer: String = "victory" if game.player.COMBAT_FRAMES.has_animation("victory") else "jump"
	check(game.player.body.animation == cheer, "Hoppy cheers in the %s pose" % cheer)
	check(game.flow.banner_title.text == "DISTRICT BOSS DOWN", "The banner says DISTRICT BOSS DOWN")
	check(game.flow.banner_subtitle.text == "%s defeated · +500" % boss.title, "The banner names the fallen boss")
	game._physics_process(DT)
	var clock: float = game.victory_clock
	check(clock > 0, "The victory clock starts")
	game.boss_defeated()
	check(game.state == "boss_victory" and is_equal_approx(game.victory_clock, clock), "A repeat boss_defeated during boss_victory changes nothing")
	var min_y: float = game.player.body.position.y
	var faded: bool = boss.modulate.a < 1.0
	if pause_hop:
		var y: float = game.player.body.position.y
		game.pause("x")
		check(game.state == "paused" and game.pause_return_state == "boss_victory", "Pause from boss_victory")
		game._physics_process(0.5)
		game.flow.tick(0.5, game.player)
		check(is_equal_approx(game.victory_clock, clock) and is_equal_approx(game.player.body.position.y, y), "Pause freezes the victory hop")
		game.resume()
		check(game.state == "boss_victory" and not game.playing and is_equal_approx(game.victory_clock, clock), "Resume restores boss_victory without advancing the hop")
	var guard := 0
	while game.state == "boss_victory" and guard < 200:
		if not is_instance_valid(game.player) or not is_instance_valid(game.player.body): break
		game._physics_process(DT)
		min_y = minf(min_y, game.player.body.position.y)
		if is_instance_valid(boss) and boss.modulate.a < 1.0: faded = true
		guard += 1
	if not is_instance_valid(game.player) or not is_instance_valid(game.player.body):
		check(false, "Hoppy is on screen for the victory hop")
		return
	check(min_y < -30.0, "Hoppy hops during the victory (y %s)" % min_y)
	check(is_equal_approx(game.player.body.position.y, 0.0), "The hop returns to the ground")
	check(faded, "The district boss fades during the victory")
	var hopped_off: bool = is_instance_valid(game.flow) and game.state == "stage_exit" and game.flow.phase == "exit_run"
	check(hopped_off, "The hop runs Hoppy off with no input")
	if not hopped_off: return
	check(game.boss_bar != null and not game.boss_bar.visible and game.boss_text != null and not game.boss_text.visible, "The district-boss bar stays hidden through the run-off")
	var ran := false
	guard = 0
	var want := from_stage+1
	while is_instance_valid(game.flow) and not (game.state == "combat" and game.stage_index == want and game.flow.phase == "") and guard < 900:
		if not is_instance_valid(game.player): break
		var stage_before: int = game.stage_index
		var x_before: float = game.player.position.x
		var exiting: bool = game.state == "stage_exit" and game.flow.phase == "exit_run" and stage_before == from_stage
		game._physics_process(DT)
		if exiting and game.stage_index == from_stage and is_instance_valid(game.player) and game.player.position.x > x_before+1.0: ran = true
		guard += 1
	freeze()
	check(ran, "Hoppy's exit run moves right")
	check(game.state == "combat" and game.playing and game.stage_index == want, "District %d leads into district %d with no input" % [from_stage+1, want+1])
	if not (game.state == "combat" and game.playing and game.stage_index == want): return
	if not is_instance_valid(game.flow):
		check(false, "District %d plays its own track again" % [want+1])
		return
	check(game.flow.music_track == Catalog.MUSIC[want], "District %d plays its own track again" % [want+1])
## The boss-music dip is 0.6s. A direct tick finishes it without stepping the fight.
func finish_dip() -> void:
	if not is_instance_valid(game.flow) or not is_instance_valid(game.player):
		check(false, "The music dip has a stage to tick")
		return
	game.flow.tick(0.65, game.player)
func music_loops(track) -> bool:
	if not is_instance_valid(game.music): return false
	var stream = game.music.stream
	if stream == null or stream == track: return false
	if stream is AudioStreamMP3: return (stream as AudioStreamMP3).loop
	if stream is AudioStreamOggVorbis: return (stream as AudioStreamOggVorbis).loop
	return false
func check_fight_track(track, who: String) -> void:
	if not is_instance_valid(game.flow):
		check(false, "%s has a music player" % who)
		return
	check(game.flow.music_track == track, "%s fights to its own track" % who)
	if not is_instance_valid(game.music):
		check(false, "%s has a music player" % who)
		return
	check(music_loops(track), "%s plays a looping copy, not the shared file" % who)
func check_bar_style() -> void:
	if game.boss_bar == null:
		check(false, "The boss bar exists")
		return
	var fill: StyleBox = game.boss_bar.get_theme_stylebox("fill")
	var back: StyleBox = game.boss_bar.get_theme_stylebox("background")
	check(fill is StyleBoxFlat and (fill as StyleBoxFlat).bg_color == Color("ffc66c"), "The boss bar fill is amber")
	check(back is StyleBoxFlat, "The boss bar background is a flat style")
## Park Hoppy in reach of a boss that is already chasing, then swing with his own tick.
func arm_swing(boss, weapon: String, invulnerable: float) -> bool:
	if not is_instance_valid(boss) or not is_instance_valid(game.player) or not is_instance_valid(game.player.held):
		check(false, "Hoppy and the district boss are up for the swing")
		return false
	var p = game.player
	p.position = boss.position-Vector2(80, 0)
	p.facing = 1
	p.steer = 0
	p.knock = Vector2.ZERO
	p.velocity = Vector2.ZERO
	p.height = 0
	p.rise = 0
	p.swing_left = 0
	p.queued = false
	p.combo = 0
	p.combo_window = 0
	p.effects = {}
	p.shield = false
	p.controlled = false
	p.input_lock = 0
	p.hp = 3
	if weapon == "":
		p.weapon = ""
		p.visual_weapon = ""
		p.durability = 0
		p.held.hide()
	else:
		p.equip(weapon)
		p.pickup_time = 0
		p.held.show()
	p.invulnerable = invulnerable
	boss.hp = 1
	boss.hits = 0
	boss.state = "chase"
	game.clear_threats()
	game.playing = true
	game.state = "combat"
	return true
func swing_to(p, goal: String) -> bool:
	if not is_instance_valid(p):
		check(false, "Hoppy is up to swing")
		return false
	p.start_attack()
	var guard := 0
	while game.state != goal and is_instance_valid(p) and guard < 80:
		p.tick(DT)
		guard += 1
	if game.state != goal:
		var hp := -1.0
		if is_instance_valid(game.boss): hp = game.boss.hp
		var swing_left: float = -1.0
		var facing := 0
		if is_instance_valid(p):
			swing_left = p.swing_left
			facing = p.facing
		print("SWING stuck state=%s guard=%d playing=%s swing_left=%s facing=%s hp=%s" % [game.state, guard, game.playing, swing_left, facing, hp])
	check(game.state == goal, "A swing reaches %s after %d ticks" % [goal, guard])
	return game.state == goal
func check_cheer(p, label: String, iframes: bool) -> void:
	if not is_instance_valid(p) or not is_instance_valid(p.body) or not is_instance_valid(p.held):
		check(false, "%s still has Hoppy" % label)
		return
	check(p.body.animation == "victory", "%s leaves Hoppy in the victory pose" % label)
	check(p.body.sprite_frames == p.COMBAT_FRAMES, "%s draws the combat sheet, not an armed one" % label)
	check(not p.held.visible, "%s keeps the weapon hidden" % label)
	check(is_equal_approx(p.body.modulate.a, 1.0), "%s holds Hoppy at full opacity" % label)
	if iframes: check(p.invulnerable > 0, "%s still has i-frames, so the opacity check is real" % label)
	check(is_equal_approx(p.swing_left, 0.0) and not p.queued, "%s clears the swing and its queue" % label)
func stage_ready() -> bool:
	if is_instance_valid(game) and is_instance_valid(game.flow) and is_instance_valid(game.player): return true
	check(false, "The stage is still running")
	return false
func check_swing_kills() -> void:
	if not await boot(0): return
	game.enter_room(2)
	freeze()
	if not summon(): return
	finish_dip()
	check(Catalog.MINI_BOSS_MUSIC != Catalog.BOSS_MUSIC, "The district-boss track is not the Grand Merge Conflict's")
	check_fight_track(Catalog.MINI_BOSS_MUSIC, "Stack Overflow")
	if not stage_ready(): return
	var boss = game.boss
	game.retry_stage()
	await process_frame
	await process_frame
	freeze()
	if not stage_ready(): return
	game.begin_play()
	check(game.boss == null and game.flow.music_track == Catalog.MUSIC[0], "A mid-fight retry returns to the district track")
	game.flow.banner("", "", 0)
	game.hide_toast()
	game.enter_room(2)
	freeze()
	if not summon(): return
	boss = game.boss
	if leave_intro(boss) and arm_swing(boss, "", 0.0):
		var p = game.player
		if swing_to(p, "boss_victory"):
			check_cheer(p, "An unarmed swing kill", false)
			check(game.boss_bar != null and not game.boss_bar.visible and game.boss_text != null and not game.boss_text.visible, "A swing kill hides the district-boss bar")
			game._physics_process(DT)
			check_cheer(p, "The next victory tick", false)
	if not stage_ready(): return
	game.retry_stage()
	await process_frame
	await process_frame
	freeze()
	if not stage_ready(): return
	game.begin_play()
	game.flow.banner("", "", 0)
	game.hide_toast()
	game.enter_room(2)
	freeze()
	if not summon(): return
	boss = game.boss
	if leave_intro(boss) and arm_swing(boss, "linter_staff", 1.0):
		var p = game.player
		if swing_to(p, "boss_victory"):
			check_cheer(p, "An armed swing kill", true)
			game._physics_process(DT)
			check_cheer(p, "The armed victory's next tick", true)
func swing_grand() -> void:
	var boss = game.boss
	var grand: bool = is_instance_valid(boss) and boss.get_script() != null and str(boss.get_script().resource_path).ends_with("boss.gd")
	if not grand:
		check(false, "The Grand Merge Conflict is up for the swing")
		return
	var p = game.player
	if not is_instance_valid(p) or not is_instance_valid(p.body) or not is_instance_valid(p.held):
		check(false, "Hoppy is up for the grand swing")
		return
	boss.vulnerable = true
	boss.hp = 1
	p.position = boss.position-Vector2(70, 0)
	p.facing = 1
	p.steer = 0
	p.knock = Vector2.ZERO
	p.velocity = Vector2.ZERO
	p.height = 0
	p.rise = 0
	p.swing_left = 0
	p.queued = false
	p.combo = 0
	p.combo_window = 0
	p.effects = {}
	p.shield = false
	p.controlled = false
	p.input_lock = 0
	p.hp = 3
	p.equip("linter_staff")
	p.pickup_time = 0
	p.held.show()
	game.clear_threats()
	game.playing = true
	game.state = "combat"
	if not swing_to(p, "finisher"): return
	check(is_instance_valid(p.held) and not p.held.visible, "The finisher hides the weapon on the killing swing")
	check(game.boss_bar != null and game.boss_bar.visible, "The Grand Merge Conflict bar stays up into the finisher")
	game._physics_process(DT)
	var armed = Art.armed("linter_staff")
	var drew: bool = is_instance_valid(p.body) and is_instance_valid(p.held) and armed != null and p.body.sprite_frames != armed and not p.held.visible
	check(drew, "The finisher's next tick does not draw the armed sheet")
	if not is_instance_valid(p.body): return
	# celebrate() runs inside this frame, after the flag that decides whether the party ticks.
	game.merge_slammed = true
	game.finish_clock = 4.0-DT*0.5
	game._physics_process(DT)
	if game.party == null:
		check(false, "The celebration is loaded")
		return
	check(game.state == "celebration" and game.party.active() and is_equal_approx(game.party.clock, 0.0), "The frame that starts the celebration does not tick it")
func check_celebration_pause() -> void:
	if game.party == null or not is_instance_valid(game.player) or not is_instance_valid(game.player.body):
		check(false, "The celebration is loaded")
		return
	game.toast("still up", 2)
	game.state = "finisher"
	game.celebrate()
	check(game.state == "celebration" and game.party.active(), "celebrate() starts the celebration")
	check(is_equal_approx(game.party.clock, 0.0) and game.toast_left <= 0, "celebrate() hides the toast and waits for the next tick")
	var party_ticks := 0
	while game.state == "celebration" and game.party != null and game.party.clock < 1.0 and party_ticks < 120:
		game._physics_process(DT)
		party_ticks += 1
	if game.party == null:
		check(false, "The jingle is playing by one second")
		return
	check(game.party.clock >= 1.0 and is_instance_valid(game.party.jingle), "The jingle is playing by one second")
	if game.party.clock < 1.0 or not is_instance_valid(game.party.jingle): return
	var held_clock: float = game.party.clock
	game.pause("x")
	check(paused and game.state == "paused", "Pause from the celebration")
	game._physics_process(1.0)
	await process_frame
	await process_frame
	await process_frame
	if game.party == null:
		check(false, "Pause freezes the celebration clock")
		return
	check(is_equal_approx(game.party.clock, held_clock), "Pause freezes the celebration clock")
	check(is_instance_valid(game.party.jingle) and not game.party.jingle.can_process() and game.party.jingle.stream_paused, "Pause freezes the victory jingle")
	game.resume()
	check(game.state == "celebration", "Resume restores the celebration")
	var resumed: float = game.party.clock
	game._physics_process(DT)
	party_ticks += 1
	check(game.party.clock > resumed, "Resume advances the celebration clock")
	while game.state == "celebration" and party_ticks < 600:
		game._physics_process(DT)
		party_ticks += 1
	if game.party == null:
		check(false, "The celebration hands off to the ending (%d ticks)" % party_ticks)
		return
	check(game.state == "ending" and game.story_pages == "ENDING" and not game.party.active(), "The celebration hands off to the ending (%d ticks)" % party_ticks)
	if game.state != "ending": return
	check(absi(party_ticks-int(ceil(game.Celebration.LENGTH/DT))) <= 2, "The celebration lasts %ss" % game.Celebration.LENGTH)
func check_grand() -> void:
	if not is_instance_valid(game.flow):
		check(false, "The stage is still running")
		return
	game.flow.banner("", "", 0)
	game.hide_toast()
	game.enter_room(2)
	freeze()
	var path := ""
	if is_instance_valid(game.boss) and game.boss.get_script() != null: path = game.boss.get_script().resource_path
	check(path.ends_with("boss.gd") and not game.has_mini_boss(), "District 3 still spawns the Grand Merge Conflict")
	check(game.toast_label != null and game.toast_label.text == "THE GRAND MERGE CONFLICT", "District 3 announces the Grand Merge Conflict")
	game._update_hud()
	check(game.boss_text != null and game.boss_text.text == "GRAND MERGE CONFLICT · PHASE 1" and game.boss_bar != null and game.boss_bar.visible and is_equal_approx(game.boss_bar.max_value, 24), "The grand-boss bar reads phase 1 of 24 HP")
	check(not game.gate_open and is_instance_valid(game.gate) and game.gate.visible, "The grand boss keeps the gate shut")
	clear_wave()
	game._physics_process(DT)
	var still := ""
	if is_instance_valid(game.boss) and game.boss.get_script() != null: still = game.boss.get_script().resource_path
	check(not game.gate_open and not game.has_mini_boss() and still.ends_with("boss.gd"), "Clearing room 3 of district 3 does not call a district boss")
	finish_dip()
	check_fight_track(Catalog.BOSS_MUSIC, "The Grand Merge Conflict")
	var grand: bool = is_instance_valid(game.boss) and game.boss.get_script() != null and str(game.boss.get_script().resource_path).ends_with("boss.gd")
	if grand: swing_grand()
	else: check(false, "The Grand Merge Conflict is up for the swing")
func check_ignored(boss) -> void:
	if not is_instance_valid(boss):
		check(false, "The ignored-state guard still has the district boss")
		return
	var hp: float = boss.hp
	for blocked in ["knockout", "boss_victory", "celebration", "finisher", "ending", "won"]:
		game.state = blocked
		game.playing = false
		game.boss_defeated()
		check(game.state == blocked and not boss.dead and is_equal_approx(boss.hp, hp), "boss_defeated is ignored during %s" % blocked)
	game.state = "combat"
	game.playing = true
func check_knockout(boss) -> void:
	if not is_instance_valid(boss) or not is_instance_valid(game.player):
		check(false, "The knockout guard still has Hoppy and the boss")
		return
	var p = game.player
	p.hp = 1
	p.invulnerable = 0
	p.shield = false
	p.weapon = ""
	p.height = 0
	p.rise = 0
	var score: int = game.score
	p.take_hit(p.position+Vector2(-40, 0))
	check(game.state == "knockout", "A last hit during the district boss starts the knockout")
	boss.take_hit(999, 0, p.position)
	game.boss_defeated()
	check(game.state == "knockout" and not game.gate_open and game.score == score and is_equal_approx(game.victory_clock, 0.0), "Defeating the district boss during knockout does not start the victory")
func check_retry() -> void:
	if not await boot(0): return
	game.enter_room(2)
	freeze()
	if not summon() or not expect_mini("stack_overflow", "STACK OVERFLOW", 14, "linter_enforcer", "armored_idle"): return
	var boss = game.boss
	if not leave_intro(boss): return
	if not is_instance_valid(boss) or not is_instance_valid(game.player):
		check(false, "Hoppy and the district boss are up for the victory")
		return
	var score: int = game.score
	boss.take_hit(999, 0, game.player.position)
	check(game.state == "boss_victory" and game.score == score+500, "The retry setup reaches boss_victory")
	game._physics_process(DT)
	check(game.victory_clock > 0 and is_instance_valid(game.boss), "The victory clock is running with the boss still referenced")
	if game.state != "boss_victory": return
	if not stage_ready(): return
	game.retry_stage()
	await process_frame
	await process_frame
	freeze()
	check(game.boss == null and not game.mini_boss_called and is_equal_approx(game.victory_clock, 0.0), "Retry clears the mini-boss, the called flag and the victory clock")
	if not stage_ready(): return
	game.begin_play()
	game.flow.banner("", "", 0)
	game.hide_toast()
	game.enter_room(2)
	freeze()
	if not summon() or not expect_mini("stack_overflow", "STACK OVERFLOW", 14, "linter_enforcer", "armored_idle"): return
	boss = game.boss
	if not is_instance_valid(boss):
		check(false, "Clearing room 3 again calls the district boss at full HP")
		return
	check(is_equal_approx(boss.hp, boss.max_hp), "Clearing room 3 again calls the district boss at full HP")
	if not leave_intro(boss): return
	check_ignored(boss)
	check_knockout(boss)
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame
	await process_frame
	game = current_scene
	if not is_instance_valid(game) or not game.has_method("begin_play"):
		check(false, "Code City loads")
		print("Code City mini-boss failures: ", failures)
		await shutdown()
		quit(1)
		return
	game.test_mode = true
	paused = false
	if game.state == "paused": game.resume()
	freeze()
	check(Catalog.MINI_BOSS_STAGES == ["stack_overflow", "zero_day", ""], "Mini-boss stages are stack overflow, zero-day, then none")
	check(is_equal_approx(float(Catalog.FLOW.boss_victory), 1.4) and is_equal_approx(float(Catalog.FLOW.boss_hop), 36.0), "The victory hop is 1.4s and 36px")
	check("boss_victory" in game.PAUSABLE and "celebration" in game.PAUSABLE, "boss_victory and celebration are pausable")
	check("boss_victory" in game.MINIMAP_STATES, "boss_victory keeps the minimap state")
	check_bar_style()
	if not await boot(0):
		print("Code City mini-boss failures: ", failures)
		await shutdown()
		quit(1)
		return
	if walk_to_last_room() and summon() and expect_mini("stack_overflow", "STACK OVERFLOW", 14, "linter_enforcer", "armored_idle"):
		finish_dip()
		check_fight_track(Catalog.MINI_BOSS_MUSIC, "Stack Overflow")
		see_minimap()
		var boss = game.boss
		if leave_intro(boss):
			check_tells(boss)
			check_stagger(boss)
			check_deferred(boss)
			check_enrage(boss)
			down_and_off(0, true)
	if game.stage_index == 1 and game.state == "combat":
		game.enter_room(2)
		freeze()
		if summon() and expect_mini("zero_day", "ZERO-DAY", 18, "force_push_bandit", "idle"):
			finish_dip()
			check_fight_track(Catalog.MINI_BOSS_MUSIC, "Zero-Day")
			see_minimap()
			var boss = game.boss
			if leave_intro(boss):
				check_enrage(boss)
				down_and_off(1, false)
	if game.stage_index == 2 and game.state == "combat": check_grand()
	await check_retry()
	await check_swing_kills()
	# The Force Merge hands off to the celebration, which hands off to the ending once.
	await check_celebration_pause()
	print("Code City mini-boss failures: ", failures)
	await shutdown()
	quit(1 if failures else 0)
func shutdown() -> void:
	if is_instance_valid(game): game.queue_free()
	var audio: Node = root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	await create_timer(.4).timeout
