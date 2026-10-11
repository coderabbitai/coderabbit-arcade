extends Node3D
## Standalone facade fixture. No backend systems or persistence are used.
const Config = preload("res://scenes/runner/data/run_config.tres")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Hud = preload("res://scenes/runner/ui/runner_hud.tscn")
const PauseMenu = preload("res://scenes/runner/ui/pause_menu.tscn")
const GameOver = preload("res://scenes/runner/ui/game_over.tscn")
const Leaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
signal stage_started(index: int, name: StringName, speed: float)
signal stage_cleared(index: int, bonus: int)
signal boss_intro(kind: StringName, name: String, seconds: float)
signal phase_changed(phase: StringName)
var phase: StringName = &"idle"
var stage_index := 1
var stage_name: StringName = &"Merge Conflict Hydra"
var stage_banner: Control
var stage_clear: Control
signal boss_spawned(kind: StringName, hp: int)
signal boss_health_changed(hp: int, max_hp: int)
signal boss_phase_changed(phase: int)
signal boss_attack_telegraph(lane_mask: int, kind: StringName, seconds: float)
signal boss_projectile_fired(projectile: Area3D, lane_mask: int, kind: StringName, speed: float)
signal boss_defeated(kind: StringName, bonus: int)
signal boss_retreated(kind: StringName, bonus: int)
signal tool_collected(kind: StringName, damage: int)
var boss: Node3D
var boss_hp := 0
var boss_phase := 1
var boss_kind := &"merge_conflict_hydra"
var boss_phase_count := 3
var boss_fx: Node3D
var boss_overlay: Control
signal run_started(seed: int)
signal state_changed(state: StringName)
signal health_changed(hp: int, max_hp: int)
signal damage_taken(kind: StringName, hp: int)
signal damage_blocked(kind: StringName, reason: StringName)
signal shield_changed(active: bool)
signal pursuit_alert(kind: StringName, seconds: float)
signal pursuit_started(recovery_seconds: float)
signal pursuit_progress(remaining: float, total: float)
signal pursuit_recovered(reason: StringName)
signal caught
signal run_finished(result: Dictionary)
signal leaderboard_saved(entries: Array, rank: int)
signal score_changed(score: int, multiplier: float)
signal bonus_awarded(points: int, reason: StringName)
signal speed_changed(speed: float, normalized: float)
signal difficulty_changed(difficulty: float)
signal power_up_collected(kind: StringName, duration: float)
signal power_up_expired(kind: StringName)
signal hazard_cleared(hazard: Area3D)
signal hazards_blasted(count: int)
signal player_action(action: StringName)
signal chunk_spawned(chunk: Node3D)
signal paused_changed(paused: bool)


class MockCamera extends Node3D:
	var last_shake := 0.0
	func shake(strength: float, _duration: float = 0.35) -> void:
		last_shake = strength
	func punch_fov(_degrees: float, _seconds: float) -> void:
		pass

@export var autoplay := true
@export var result_qualifies := true
@export var result_leaderboard_error: Error = OK
var config: Resource = Config
var state: StringName = &"ready"
var paused := false
var seed := 4704
var run_id := "mock-f4"
var elapsed := 0.0
var distance := 0.0
var speed := 12.0
var normalized_speed := 0.0
var difficulty := 0.0
var hp := 2
var score := 0
var multiplier := 1.0
var player: CharacterBody3D
var camera_rig: Node3D
var cosmetic_rng := RandomNumberGenerator.new()
var hud: CanvasLayer
var pause_menu: CanvasLayer
var game_over: CanvasLayer
var submit_calls := 0
var save_succeeds := true
var menu_calls := 0
var demo_time := 0.0
var pursued := false
var remaining := 0.0
var critical_alert_sent := false
var effects := {}
var shield := false
var _action_tick := 0
var _chunk_tick := 0
var _caught_time := 0.0
var _events := {}
var _result := {}
var _board: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cosmetic_rng.seed = seed
	boss = Node3D.new()
	boss.position = Vector3(0, 2.6, -14)
	add_child(boss)
	player = CharacterBody3D.new()
	add_child(player)
	camera_rig = MockCamera.new()
	add_child(camera_rig)
	if get_node_or_null("Backdrop") == null:
		var corridor := Corridor.instantiate()
		corridor.name = "Backdrop"
		add_child(corridor)
	hud = Hud.instantiate()
	pause_menu = PauseMenu.instantiate()
	game_over = GameOver.instantiate()
	for overlay in [hud, pause_menu, game_over]:
		add_child(overlay)
		overlay.bind(self)
	boss_overlay = preload("res://scenes/runner/ui/boss_hud.tscn").instantiate()
	hud.add_child(boss_overlay)
	boss_overlay.bind(self)
	stage_banner = preload("res://scenes/runner/ui/stage_banner.tscn").instantiate()
	stage_clear = preload("res://scenes/runner/ui/stage_clear.tscn").instantiate()
	for overlay in [stage_banner, stage_clear]:
		hud.add_child(overlay)
		overlay.bind(self)
	boss_fx = preload("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	add_child(boss_fx)
	boss_fx.bind(self)

func _process(delta: float) -> void:
	if autoplay:
		advance_demo(delta)

func start_run(run_seed: int = 4704) -> void:
	seed = run_seed
	cosmetic_rng.seed = seed
	state = &"running"
	state_changed.emit(state)
	run_started.emit(seed)
	set_demo_phase(&"run")
	stage_started.emit(stage_index, stage_name, speed)
	health_changed.emit(hp, int(config.max_hp))
	score_changed.emit(score, multiplier)
	speed_changed.emit(speed, normalized_speed)

## Same deterministic timeline for interactive preview, smoke and capture.
## Recovery uses the configured duration; catch ends at the 40 second mark.
func advance_demo(delta: float) -> void:
	if paused or state == &"finished":
		return
	demo_time += delta
	if has_node("Backdrop"):
		get_node("Backdrop").set_scroll_speed(speed if state == &"running" else 0.0)
	if state == &"ready" and demo_time >= 2:
		start_run()
	if state == &"caught":
		_caught_time += delta
		if _caught_time >= float(config.caught_sequence_seconds):
			finish_demo()
		return
	if state == &"running":
		elapsed += delta
		var actions := [&"jump", &"land", &"roll", &"roll_end", &"lane_left", &"lane_right"]
		while _action_tick < int(elapsed):
			player_action.emit(actions[_action_tick % actions.size()])
			_action_tick += 1
		while _chunk_tick < int(elapsed / 4.0):
			var chunk := Node3D.new()
			add_child(chunk)
			chunk_spawned.emit(chunk)
			chunk.queue_free()
			_chunk_tick += 1
		normalized_speed = clampf(elapsed / 36, 0, 1)
		speed = lerpf(12, 24, normalized_speed)
		distance += speed * delta
		speed_changed.emit(speed, normalized_speed)
		var next_score := int(elapsed * 24)
		if score != next_score:
			score = next_score
			score_changed.emit(score, multiplier)
		var next_difficulty := normalized_speed
		if absf(next_difficulty - difficulty) >= 0.01:
			difficulty = next_difficulty
			difficulty_changed.emit(difficulty)
		for kind in effects.keys():
			effects[kind].remaining = maxf(0, effects[kind].remaining - delta)
			if effects[kind].remaining <= 0:
				effects.erase(kind)
				power_up_expired.emit(kind)
				if kind == &"nitro":
					multiplier = 1
					score_changed.emit(score, multiplier)
		if pursued:
			remaining = maxf(0, remaining - delta)
			pursuit_progress.emit(remaining, float(config.recovery_seconds))
			if remaining <= float(config.recovery_seconds) * 0.35 and not critical_alert_sent:
				critical_alert_sent = true
				pursuit_alert.emit(&"critical", remaining)
			if remaining <= 0:
				pursued = false
				hp = int(config.max_hp)
				health_changed.emit(hp, hp)
				pursuit_recovered.emit(&"timer")
				pursuit_alert.emit(&"clear", 0.0)
	for at in [3.0, 4.0, 5.0, 6.0, 7.0, 9.0, 14.0, 17.4, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 30.0, 34.0, 38.4, 40.0]:
		if demo_time >= at and not _events.has(at):
			_events[at] = true
			match at:
				17.4:
					set_demo_phase(&"boss")
				27.0:
					set_demo_phase(&"stage_clear")
					stage_cleared.emit(stage_index, 400)
				18.0:
					boss_hp = 140
					mount_demo_boss()
					boss_intro.emit(boss_kind, "Merge Conflict Hydra", 3.0)
					boss_spawned.emit(boss_kind, boss_hp)
					boss_health_changed.emit(boss_hp, 140)
				21.0:
					boss_attack_telegraph.emit(5, &"orb", 0.8)
					tool_collected.emit(&"review_comment", 10)
					boss_hp = 90
					boss_health_changed.emit(boss_hp, 140)
					boss_phase = 2
					boss_phase_changed.emit(2)
				22.0:
					boss_projectile_fired.emit(null, 5, &"orb", 28.0)
					tool_collected.emit(&"auto_fix_patch", 0)
				23.0: boss_attack_telegraph.emit(7, &"high", 0.7)
				24.0:
					tool_collected.emit(&"unit_test", 15)
					boss_hp = 40
					boss_phase = 3
					boss_health_changed.emit(boss_hp, 140)
					boss_phase_changed.emit(3)
				25.0: tool_collected.emit(&"lint_rule", 12)
				26.0:
					boss_hp = 0
					boss_health_changed.emit(0, 140)
					boss_defeated.emit(boss_kind, 800)
				3.0: collect(&"approve_shield", 0)
				5.0: hit()
				7.0: collect(&"auto_fix", 0)
				4.0: collect(&"nitro", 4)
				6.0: collect(&"code_review", 0)
				9.0: hit()
				14.0: collect(&"nitro", 8)
				30.0:
					set_demo_phase(&"run")
					stage_index += 1
					stage_started.emit(stage_index, stage_name, speed)
					collect(&"lgtm", 3)
				34.0: hit()
				38.4: hit()
				40.0: finish_demo()
			if state == &"caught":
				break

func collect(kind: StringName = &"nitro", duration: float = 8) -> void:
	if state != &"running" or paused:
		return
	if duration > 0:
		effects[kind] = {"remaining": duration, "total": duration}
	power_up_collected.emit(kind, duration)
	bonus_awarded.emit(25, &"pickup")
	if kind == &"approve_shield":
		shield = true
		shield_changed.emit(true)
	elif kind == &"auto_fix":
		for i in 3:
			var hazard := Area3D.new()
			add_child(hazard)
			hazard_cleared.emit(hazard)
			hazard.queue_free()
		hazards_blasted.emit(3)
	if kind == &"nitro":
		multiplier = 2
		score_changed.emit(score, multiplier)

func hit() -> void:
	if state != &"running" or paused:
		return
	if shield:
		damage_blocked.emit(&"pr_backlog_low", &"shield")
		shield = false
		shield_changed.emit(false)
		return
	hp = maxi(0, hp - 1)
	damage_taken.emit(&"pr_backlog_low", hp)
	health_changed.emit(hp, int(config.max_hp))
	power_up_expired.emit(&"code_review")
	if hp == 0:
		_caught_time = 0.0
		state = &"caught"
		state_changed.emit(state)
		caught.emit()
		pursuit_alert.emit(&"clear", 0.0)
	elif not pursued:
		pursued = true
		critical_alert_sent = false
		remaining = float(config.recovery_seconds)
		pursuit_started.emit(remaining)
		pursuit_alert.emit(&"warn", remaining)

func finish_demo() -> void:
	if not _result.is_empty():
		return
	var placed := result_qualifies and result_leaderboard_error == OK
	_result = {"run_id": run_id, "mode": "runner", "outcome": "caught", "score": score,
		"score_exact": float(score), "duration": elapsed, "distance": distance,
		"hazards_dodged": 24, "power_ups": 6, "hazards_blasted": 3, "hits_taken": 3,
		"recoveries": 1, "blocked_hits": 1, "seed": seed, "max_speed_reached": speed,
		"best_multiplier": 2.0, "chunks_spawned": 12, "score_rule_revision": 1,
		"submitted_at": 0, "rank": 3 if placed else 0, "qualifies": placed, "leaderboard_error": result_leaderboard_error, "player_name": "Hoppy"}
	_board.clear()
	for i in 10:
		var current := placed and i == 2
		_board.append({"run_id": run_id if current else "fixture-%d" % i,
			"name": "Hoppy" if current else "Reviewer %02d" % (i + 1),
			"score": score + (2 - i) * 50, "duration": elapsed, "seed": seed, "submitted_at": 0})
	if result_leaderboard_error == OK:
		leaderboard_saved.emit(get_leaderboard(), int(_result.rank))
	state = &"finished"
	state_changed.emit(state)
	run_finished.emit(get_result())

func pause() -> void:
	if state == &"running" and not paused:
		paused = true
		paused_changed.emit(true)

func resume() -> void:
	if paused:
		paused = false
		paused_changed.emit(false)

func toggle_pause() -> void:
	if paused:
		resume()
	else:
		pause()

func retry() -> void:
	resume()
	get_tree().reload_current_scene()

func go_to_menu() -> void:
	resume()
	menu_calls += 1
	game_over.hide()

func hit_stop(_seconds: float) -> void:
	pass

func submit_name(value: String) -> bool:
	submit_calls += 1
	if not save_succeeds or _result.is_empty():
		return false
	var clean := Leaderboard.sanitize_name(value)
	_result.player_name = clean
	for entry in _board:
		if entry.run_id == run_id:
			entry.name = clean
	leaderboard_saved.emit(get_leaderboard(), int(_result.rank))
	return true

func get_leaderboard() -> Array[Dictionary]:
	return _board.duplicate(true)

func get_result() -> Dictionary:
	return _result.duplicate(true)

func get_active_effects() -> Dictionary:
	return effects.duplicate(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == &"running":
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H: hit()
			KEY_N: collect()
			_: return
		get_viewport().set_input_as_handled()

func get_boss_info() -> Dictionary:
	if boss_hp <= 0: return {}
	return {"kind": boss_kind, "name": "Merge Conflict Hydra", "hp": boss_hp, "max_hp": 140, "phase": boss_phase, "phase_count": boss_phase_count, "accepted_tools": [&"lint_rule", &"unit_test"] if boss_phase == 2 else [&"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch"], "pending_attacks": []}

func set_demo_phase(value: StringName) -> void:
	phase = value
	phase_changed.emit(value)

func get_stage_info() -> Dictionary:
	return {"index": stage_index, "name": stage_name, "phase": phase, "distance": distance, "target": 260.0, "speed_bonus": 0.0, "difficulty_floor": 0.0}

func mount_demo_boss() -> void:
	for child in boss.get_children(): child.free()
	var scene := load("res://scenes/runner/boss/visuals/%s_visual.tscn" % boss_kind) as PackedScene
	if scene == null: return
	var visual := scene.instantiate() as Node3D
	boss.add_child(visual)
	visual.kind = boss_kind
	visual.boss_name = String(stage_name)
	visual.max_hp = 140
	visual.hover_z = -14.0
	visual.sway_amplitude = 2.4
	visual.sway_period = 3.2
	visual.on_spawned()
