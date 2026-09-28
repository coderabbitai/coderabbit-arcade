extends SceneTree
## Endless Runner boss validator (systems spec §10.8, contract §11.12). Every boss x phase x
## pattern x entry lane x cycle 0-4 is driven through a virtual runner by the *real* autopilot
## planner, from the telegraph alone: the bot never sees a projectile node, only the
## `boss_attack_telegraph` the encounter emits, exactly as it would in a live fight.
## Run with --path <project> --script res://tests/runner_boss_validator.gd.
##
## What it proves, for every fight in the endless roster:
## B1 telegraph + travel >= 0.98 s, so the reaction budget survives the cycle escalation (§11.6);
## B2 every beat leaves a free lane or is jumpable / rollable;
## B3 the launch window for the body actions is at least 0.35 s wide and opens 0.35 s after the
##    telegraph, so the shot can be answered on reaction rather than on reflex;
## B4 the bot takes zero hits, beat by beat and across whole pattern cycles at the real interval;
## B5 an accepted tool is reachable inside boss_tool_guarantee_seconds.
##
## Nothing here writes user:// and nothing instantiates runner_game.tscn, so there is no board to
## point anywhere: the facade is a bare runner_game.gd object that never enters the tree.

## Only scripts that never reach runner_game.gd can be preloaded: under --script this test is
## compiled before the autoloads exist (see tests/runner_logic.gd). autopilot.gd does reach it, so
## it is loaded inside run().
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const TICK := 1.0 / 60.0
const LANE_COUNT := 3
const EPS := 0.001
## Cycles 0-4 of the endless roster (contract §11.1).
const CYCLES := 5
## Contract §11.6: the reaction budget a telegraph plus its travel has to leave.
const MIN_REACTION := 0.98
## Systems spec §1.1: the choice-reaction slice of that budget.
const MIN_LAUNCH_WINDOW := 0.35
## Mask streams the pattern sweep replays; each one follows boss_encounter's own no-repeat rule.
const MASK_STREAM_SEEDS := [1, 2, 3]
## Pattern cycles one sequence pass plays through.
const PATTERN_CYCLES := 2
## Tool spawn offsets swept inside the guarantee window, in seconds.
const TOOL_OFFSET_STEP := 0.5
## Hard stop on any simulation, in ticks, so a bot that never resolves fails instead of hanging.
const STEP_GUARD := 4000
## Board the facade points at. Nothing here finishes a run, so the file is never created; the
## override exists so no code path can ever reach the real board.
const SCRATCH_BOARD := "user://boss_validator_leaderboard.cfg"

## The contract §7 kinematics runner_chunk_validator.gd simulates (gravity 28, jump 9.8 / 0.70 s
## airtime, roll 0.70 s, lane tween 0.13 s ease-out), as a CharacterBody3D the real autopilot can
## drive: `game.player` is typed, and the bot reads `target_lane` / `queued_lane_dir` and calls
## `request_jump` / `request_roll` / `request_lane` on it exactly as it does on runner_player.gd.
const VIRTUAL_RUNNER_SOURCE := """
extends CharacterBody3D
var lane_width := 2.0
var lane_change_time := 0.13
var gravity := 28.0
var jump_velocity := 9.8
var jump_buffer_seconds := 0.10
var roll_seconds := 0.70
var roll_cooldown_seconds := 0.25
var lane := 1
var target_lane := 1
var lane_t := 1.0
var lane_from_x := 0.0
var queued_lane_dir := 0
var at_x := 0.0
var at_y := 0.0
var vy := 0.0
var airborne := false
var rolling := false
var jump_buffer := 0.0
var roll_remaining := 0.0
var roll_cooldown := 0.0
var roll_buffer := 0.0
var jumps := 0
var rolls := 0
var lane_requests := 0

func lane_x(index: int) -> float:
	return (float(index) - 1.0) * lane_width

func place(entry_lane: int) -> void:
	lane = entry_lane
	target_lane = entry_lane
	at_x = lane_x(entry_lane)
	lane_from_x = at_x
	lane_t = 1.0
	queued_lane_dir = 0
	at_y = 0.0
	vy = 0.0
	airborne = false
	rolling = false
	jump_buffer = 0.0
	roll_remaining = 0.0
	roll_cooldown = 0.0
	roll_buffer = 0.0
	jumps = 0
	rolls = 0
	lane_requests = 0

func request_jump() -> void:
	jumps += 1
	jump_buffer = jump_buffer_seconds

func request_roll() -> void:
	rolls += 1
	if airborne:
		roll_buffer = jump_buffer_seconds
		return
	if rolling or roll_cooldown > 0.0:
		return
	rolling = true
	roll_remaining = roll_seconds

func request_lane(direction: int) -> void:
	lane_requests += 1
	var dir := signi(direction)
	if dir == 0:
		return
	if lane_t < 1.0:
		queued_lane_dir = dir
		return
	var goal := clampi(lane + dir, 0, 2)
	if goal == lane:
		return
	target_lane = goal
	lane_from_x = at_x
	lane_t = 0.0

## One physics tick in runner_player's own order: the jump buffer is tested before it is aged and
## the launch tick takes a half step of gravity, so the arc is y(t) = 9.8 t - 14 t^2.
func step(delta: float, standing_clear: bool) -> void:
	var launched := false
	if jump_buffer > 0.0 and not airborne and not rolling:
		airborne = true
		vy = jump_velocity - gravity * delta * 0.5
		jump_buffer = 0.0
		launched = true
	else:
		jump_buffer = maxf(jump_buffer - delta, 0.0)
	if airborne:
		if not launched:
			vy -= gravity * delta
		at_y = maxf(at_y + vy * delta, 0.0)
		if at_y <= 0.0:
			airborne = false
			vy = 0.0
			if roll_buffer > 0.0:
				roll_buffer = 0.0
				request_roll()
	if roll_buffer > 0.0:
		roll_buffer -= delta
	if rolling:
		roll_remaining -= delta
		if roll_remaining <= 0.0:
			if standing_clear:
				rolling = false
				roll_cooldown = roll_cooldown_seconds
			else:
				roll_remaining = delta
	elif roll_cooldown > 0.0:
		roll_cooldown -= delta
	if lane_t < 1.0:
		lane_t = minf(lane_t + delta / lane_change_time, 1.0)
		var eased := 1.0 - pow(1.0 - lane_t, 3.0)
		at_x = lerpf(lane_from_x, lane_x(target_lane), eased)
		if lane_t >= 1.0:
			lane = target_lane
			at_x = lane_x(lane)
			var queued := queued_lane_dir
			queued_lane_dir = 0
			if queued != 0:
				request_lane(queued)
"""

var failures := 0
var checks := 0
var config: RunConfig
var game: Node3D
var bot: Node
var player: CharacterBody3D
## One reusable tool node, moved and re-grouped per pass; the bot finds it through runner_tools.
var tool_node: Node3D
var junk: Array[Node] = []
## Per-fight log lines, printed when that fight fails anything.
var fight_log: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER BOSS: " + message)

func run() -> void:
	config = (load(CONFIG_PATH) as RunConfig).duplicate()
	var game_script := load("res://scenes/runner/runner_game.gd") as GDScript
	var bot_script := load("res://scenes/runner/systems/autopilot.gd") as GDScript
	var runner_script := _compile(VIRTUAL_RUNNER_SOURCE)
	if game_script == null or bot_script == null or runner_script == null:
		check(false, "the runner scripts could not be loaded")
		_report()
		return
	# The facade never enters the tree: runner_game.gd's _ready() would go looking for the scene's
	# children, and nothing here needs them. The bot and the virtual runner do live in the tree —
	# the bot calls get_tree() for the hazard and tool groups.
	game = game_script.new()
	game.config = config
	# Nothing here ever calls start_run(), but the facade keeps the board rule anyway: a throwaway
	# path means no code path in this validator can reach the player's user://leaderboard.cfg.
	game.leaderboard_path = SCRATCH_BOARD
	game.state = &"running"
	game.phase = &"boss"
	junk.append(game)
	player = CharacterBody3D.new()
	player.set_script(runner_script)
	root.add_child(player)
	junk.append(player)
	_apply_player_tuning()
	game.player = player
	bot = bot_script.new()
	root.add_child(bot)
	bot.set_physics_process(false)
	bot.setup(game)
	junk.append(bot)
	tool_node = Node3D.new()
	root.add_child(tool_node)
	junk.append(tool_node)

	print("RUNNER BOSS: validating %d bosses x %d cycles x %d phases"
		% [BossDefs.SLOTS.size(), CYCLES, BossDefs.PHASE_COUNT])
	for slot in BossDefs.SLOTS.size():
		for cycle in CYCLES:
			var stage_index := cycle * BossDefs.SLOTS.size() + slot + 1
			_validate_fight(stage_index)
	_check_escalation_floors()
	_report()

## Every phase of one stage's fight: the beat sweep, the pattern sweep and the tool guarantee.
func _validate_fight(stage_index: int) -> void:
	var def := BossDefs.fight_def(stage_index, config)
	check(BossDefs.slot(stage_index) == int(def["slot"]) and BossDefs.cycle(stage_index) == int(def["cycle"]),
		"stage %d: fight_def disagrees with slot()/cycle()" % stage_index)
	for phase in range(1, BossDefs.PHASE_COUNT + 1):
		var tag := "%s c%d p%d" % [def["kind"], int(def["cycle"]), phase]
		fight_log.clear()
		var before := failures
		_check_beats(tag, def, phase)
		_check_pattern_sequences(tag, def, phase)
		_check_tool_guarantee(tag, def, phase)
		if failures > before:
			print("RUNNER BOSS: log for %s" % tag)
			for line in fight_log:
				print("  " + line)

# --- B1 / B2 / B3 / B4: one beat at a time ---

func _check_beats(tag: String, def: Dictionary, phase: int) -> void:
	var telegraph := BossDefs.telegraph_for(def, phase)
	var closing := float(def["projectile_speed"])
	for beat in BossDefs.pattern_for(def, phase):
		var variant: StringName = (beat as Dictionary).get("variant", &"orb")
		var arrival: float = bot.telegraph_arrival(telegraph, closing, variant)
		# B1: the whole reaction budget, telegraph plus travel, at this cycle's escalation.
		check(arrival >= MIN_REACTION - EPS,
			"%s: %s leaves %.3f s from telegraph to impact, need %.2f"
				% [tag, variant, arrival, MIN_REACTION])
		fight_log.append("%s telegraph %.2f speed %.1f arrival %.3f" % [variant, telegraph, closing, arrival])
		_check_launch_window(tag, variant, closing, arrival)
		for mask in _beat_masks(beat):
			var slice: Dictionary = bot.attack_slice(mask, variant, closing)
			# B2: something in the corridor answers this beat.
			check(not _free_lanes(mask).is_empty() or bool(slice["jumpable"]) or bool(slice["rollable"]),
				"%s: %s on lanes %d blocks the corridor with no free lane and no body answer"
					% [tag, variant, mask])
			for lane in LANE_COUNT:
				var shots: Array[Dictionary] = [{
					"at": 0.0, "mask": mask, "variant": variant,
					"telegraph": telegraph, "closing_v": closing
				}]
				var result := _simulate(int(def["stage_index"]), shots, [], lane, arrival + 1.0)
				# B4: zero hits, from every entry lane.
				check(String(result["hit"]).is_empty(),
					"%s: the bot was hit from lane %d by %s on lanes %d: %s"
						% [tag, lane, variant, mask, result["hit"]])

## B3: the span of launch times that still clears the shot, and how long the bot has to choose one.
## A jumpable variant is measured against the jump arc, a roll-only one against the roll window; the
## budget is the same either way (systems spec §1.1 reaction budget).
func _check_launch_window(tag: String, variant: StringName, closing: float, arrival: float) -> void:
	var def := HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant)
	var hint: StringName = def.get("dodge_hint", &"")
	var pass_seconds := _pass_seconds(variant, closing)
	if HazardDefs.JUMP_HINTS.has(hint):
		var span := _clear_span(float(def.get("y_max", 0.0)))
		check(span.y > span.x,
			"%s: %s at y %.2f cannot be jumped at all" % [tag, variant, float(def.get("y_max", 0.0))])
		var window := (span.y - span.x) - pass_seconds
		check(window >= MIN_LAUNCH_WINDOW - EPS,
			"%s: the %s jump launch window is %.3f s wide, need %.2f" % [tag, variant, window, MIN_LAUNCH_WINDOW])
		check(arrival - span.x >= MIN_LAUNCH_WINDOW - EPS,
			"%s: the last %s jump launch falls %.3f s after the telegraph, need %.2f"
				% [tag, variant, arrival - span.x, MIN_LAUNCH_WINDOW])
		return
	if not HazardDefs.ROLL_HINTS.has(hint):
		return
	var roll := float(config.roll_duration) - pass_seconds
	check(roll >= MIN_LAUNCH_WINDOW - EPS,
		"%s: the %s roll window is %.3f s wide, need %.2f" % [tag, variant, roll, MIN_LAUNCH_WINDOW])
	check(arrival - float(config.roll_duration) + pass_seconds >= 0.0,
		"%s: a %s roll cannot be started late enough to still cover the pass" % [tag, variant])

# --- B4: whole pattern cycles at the real attack interval ---

func _check_pattern_sequences(tag: String, def: Dictionary, phase: int) -> void:
	var pattern := BossDefs.pattern_for(def, phase)
	if pattern.is_empty():
		return
	var telegraph := BossDefs.telegraph_for(def, phase)
	var interval := BossDefs.attack_interval_for(def, phase)
	var closing := float(def["projectile_speed"])
	for stream in MASK_STREAM_SEEDS:
		var shots := _mask_stream(pattern, int(stream), telegraph, closing, interval)
		var last: Dictionary = shots[shots.size() - 1]
		var tail: float = bot.telegraph_arrival(telegraph, closing, StringName(last["variant"]))
		var span := float(last["at"]) + tail + 1.0
		for lane in LANE_COUNT:
			var result := _simulate(int(def["stage_index"]), shots, [], lane, span)
			check(String(result["hit"]).is_empty(),
				"%s: the bot was hit from lane %d during pattern stream %d (%s): %s"
					% [tag, lane, int(stream), _stream_label(shots), result["hit"]])

## `PATTERN_CYCLES` laps of the beat list, with the random beats resolved the way boss_encounter's
## `_pick_mask` resolves them: never a straight repeat of the previous mask while there is a choice.
func _mask_stream(pattern: Array, stream_seed: int, telegraph: float, closing: float,
		interval: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	var shots: Array[Dictionary] = []
	var last_mask := 0
	var at := 0.0
	for lap in PATTERN_CYCLES:
		for beat in pattern:
			var options := _beat_masks(beat)
			var choices: Array[int] = []
			for option in options:
				if option != last_mask:
					choices.append(option)
			if choices.is_empty():
				choices = options
			var mask := choices[rng.randi_range(0, choices.size() - 1)]
			last_mask = mask
			shots.append({
				"at": at, "mask": mask, "variant": (beat as Dictionary).get("variant", &"orb"),
				"telegraph": telegraph, "closing_v": closing
			})
			at += interval
	return shots

func _stream_label(shots: Array) -> String:
	var parts := PackedStringArray()
	for item in shots:
		var shot: Dictionary = item
		parts.append("%s/%d@%.2f" % [shot["variant"], int(shot["mask"]), float(shot["at"])])
	return " ".join(parts)

# --- B5: an accepted tool is reachable inside the guarantee window ---

## Contract §11.7: a fight never goes longer than `boss_tool_guarantee_seconds` without a tool in
## flight. This proves the other half — that such a tool is actually *collectable*: somewhere inside
## one guarantee window there is a lane and a spawn moment at which the greedy pass takes the tool
## and the bot still dodges everything the boss throws at it.
func _check_tool_guarantee(tag: String, def: Dictionary, phase: int) -> void:
	var guarantee := float(config.boss_tool_guarantee_seconds)
	check(float(def["tool_interval"]) <= guarantee + EPS,
		"%s: tools come every %.2f s, past the %.2f s guarantee"
			% [tag, float(def["tool_interval"]), guarantee])
	var pattern := BossDefs.pattern_for(def, phase)
	var telegraph := BossDefs.telegraph_for(def, phase)
	var interval := BossDefs.attack_interval_for(def, phase)
	var closing := float(def["projectile_speed"])
	var corridor := float(config.max_speed) + _stage_speed_bonus(int(def["stage_index"]))
	var travel := absf(float(config.boss_tool_spawn_z)) / corridor
	check(travel <= guarantee + EPS,
		"%s: a tool needs %.2f s to reach the player, past the %.2f s guarantee" % [tag, travel, guarantee])
	var shots := _mask_stream(pattern, MASK_STREAM_SEEDS[0], telegraph, closing, interval)
	var kinds := BossDefs.accepted_tools(def, phase)
	check(not kinds.is_empty(), "%s: the phase accepts no tool at all" % tag)
	if kinds.is_empty():
		return
	var best := ""
	var reached := false
	var offset := 0.0
	while offset < guarantee - EPS and not reached:
		for lane in LANE_COUNT:
			for kind in kinds:
				var tools: Array[Dictionary] = [{
					"at": offset, "lane": lane, "kind": kind,
					"y": _tool_height(StringName(kind))
				}]
				var result := _simulate(int(def["stage_index"]), shots, tools, 1,
					offset + travel + 1.0, corridor)
				if bool(result["collected"]) and String(result["hit"]).is_empty():
					best = "%s in lane %d at +%.2f s, collected after %.2f s" \
						% [kind, lane, offset, float(result["collected_at"]) - offset]
					reached = true
					break
			if reached:
				break
		offset += TOOL_OFFSET_STEP
	check(reached, "%s: no accepted tool was reachable inside the %.1f s guarantee window"
		% [tag, guarantee])
	if reached:
		fight_log.append("tool " + best)

# --- the simulation ---

## One pass. `shots` are telegraphs scheduled at `at` seconds, fed to the bot through the facade's
## own `boss_attack_telegraph`; `tools` are pickups that appear at `boss_tool_spawn_z` and ride the
## corridor in. The bot is the real autopilot, ticked through its own `_physics_process`.
## Returns {hit, collected, collected_at}.
func _simulate(stage_index: int, shots: Array, tools: Array, entry_lane: int, duration: float,
		corridor_v := 0.0) -> Dictionary:
	var corridor := corridor_v if corridor_v > 0.0 else float(config.max_speed)
	bot.reset()
	bot.set_mode(2)
	bot.set_enabled(true)
	player.place(entry_lane)
	game.stage_index = stage_index
	game.phase = &"boss"
	game.speed = corridor
	game.elapsed = 0.0
	var pending_shots := shots.duplicate()
	var pending_tools := tools.duplicate()
	var live: Array[Dictionary] = []
	var tool_live := {}
	_park_tool()
	var time := 0.0
	var hit := ""
	var collected_at := -1.0
	var steps := mini(int(duration / TICK) + 2, STEP_GUARD)
	for step in steps:
		# 1. Telegraphs the boss sends this tick, through the facade signal the bot listens to.
		while not pending_shots.is_empty() and float((pending_shots[0] as Dictionary)["at"]) <= time + EPS:
			var shot: Dictionary = pending_shots.pop_front()
			game.boss_attack_telegraph.emit(int(shot["mask"]), StringName(shot["variant"]),
				float(shot["telegraph"]))
			live.append({
				"spawn_t": time + float(shot["telegraph"]),
				"mask": shot["mask"], "variant": shot["variant"], "closing_v": shot["closing_v"]
			})
		# 2. Tools entering the corridor.
		while not pending_tools.is_empty() and float((pending_tools[0] as Dictionary)["at"]) <= time + EPS:
			var entry: Dictionary = pending_tools.pop_front()
			tool_live = {
				"lane": int(entry["lane"]), "y": float(entry["y"]),
				"z": float(config.boss_tool_spawn_z)
			}
			_place_tool(tool_live)
		# 3. The bot: its own entry point, so the live code decides everything.
		bot._physics_process(TICK)
		# 4. The virtual runner, then the world.
		player.step(TICK, _standing_clear(live, time))
		time += TICK
		game.elapsed = time
		if not tool_live.is_empty():
			tool_live["z"] = float(tool_live["z"]) + corridor * TICK
			_place_tool(tool_live)
			if _player_box().intersects(_tool_box(tool_live)):
				collected_at = time
				tool_live = {}
				_park_tool()
			elif float(tool_live["z"]) > float(config.despawn_z):
				tool_live = {}
				_park_tool()
		hit = _collision(live, time)
		if not hit.is_empty():
			break
		if pending_shots.is_empty() and pending_tools.is_empty() and live.is_empty() \
				and tool_live.is_empty():
			break
		_retire(live, time)
	_park_tool()
	game.phase = &"idle"
	return {"hit": hit, "collected": collected_at >= 0.0, "collected_at": collected_at}

## Shots that have swept past the player are done with; the list stays short across a long pattern.
func _retire(live: Array[Dictionary], time: float) -> void:
	for index in range(live.size() - 1, -1, -1):
		if _shot_z(live[index], time) > float(config.despawn_z):
			live.remove_at(index)

func _shot_z(shot: Dictionary, time: float) -> float:
	var since := time - float(shot["spawn_t"])
	if since < 0.0:
		return float(config.boss_z) - 1000.0
	return float(config.boss_z) + float(shot["closing_v"]) * since

## The first shot the runner is inside this tick, or "" when the pass is still clean.
func _collision(live: Array[Dictionary], time: float) -> String:
	var body := _player_box()
	for item in live:
		var shot: Dictionary = item
		var z := _shot_z(shot, time)
		if z < float(config.boss_z) - 1.0:
			continue
		for group in _lane_groups(int(shot["mask"]), StringName(shot["variant"])):
			if not _shot_box(group, StringName(shot["variant"]), z).intersects(body):
				continue
			return "%s lanes %d at z %.2f, t %.2f (player x %.2f y %.2f%s)" % [
				shot["variant"], group, z, time, float(player.at_x), float(player.at_y),
				", rolling" if bool(player.rolling) else ""]
	return ""

## Systems spec §3: stay crouched while something overhead still needs rolling under.
func _standing_clear(live: Array[Dictionary], time: float) -> bool:
	var standing := _player_box(true)
	standing.position.z -= float(config.max_speed) * 2.0 * TICK + 0.3
	standing.size.z += float(config.max_speed) * 2.0 * TICK + 0.3
	for item in live:
		var shot: Dictionary = item
		var variant := StringName(shot["variant"])
		var hint: StringName = HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant).get("dodge_hint", &"")
		if not HazardDefs.ROLL_HINTS.has(hint):
			continue
		var z := _shot_z(shot, time)
		if z < float(config.boss_z) - 1.0:
			continue
		for group in _lane_groups(int(shot["mask"]), variant):
			if _shot_box(group, variant, z).intersects(standing):
				return false
	return true

# --- geometry ---

func _player_box(force_standing := false) -> AABB:
	var standing := force_standing or not bool(player.rolling)
	var height := float(config.stand_height) if standing else float(config.roll_height)
	var radius := float(config.hurtbox_radius)
	return AABB(
		Vector3(float(player.at_x) - radius + EPS, float(player.at_y) + EPS, -radius + EPS),
		Vector3(radius * 2.0 - EPS * 2.0, height - EPS * 2.0, radius * 2.0 - EPS * 2.0))

func _tool_box(entry: Dictionary) -> AABB:
	var radius := float(config.pickup_radius)
	return AABB(
		Vector3(_lane_x(int(entry["lane"])) - radius, float(entry["y"]) - radius, float(entry["z"]) - radius),
		Vector3(radius * 2.0, radius * 2.0, radius * 2.0))

## The hitbox one lane group of a shot occupies, from the contract §11.6 table.
func _shot_box(group: int, variant: StringName, z: float) -> AABB:
	var def := HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant)
	var size: Vector3 = def.get("size", Vector3.ONE)
	var y_min := float(def.get("y_min", 0.0))
	var y_max := float(def.get("y_max", 0.0))
	return AABB(
		Vector3(_mask_center_x(group) - size.x * 0.5, y_min, z - size.z * 0.5),
		Vector3(size.x, maxf(y_max - y_min, 0.01), size.z))

## boss_encounter._lane_groups: one projectile per contiguous run of at most `lanes_wide` lanes.
func _lane_groups(mask: int, variant: StringName) -> Array[int]:
	var width := HazardDefs.lanes_wide(HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant))
	var groups: Array[int] = []
	var run: Array[int] = []
	for lane in range(LANE_COUNT + 1):
		if lane < LANE_COUNT and (mask & (1 << lane)) != 0:
			run.append(lane)
			continue
		var index := 0
		while index < run.size():
			var group := 0
			for offset in range(index, mini(index + width, run.size())):
				group |= 1 << run[offset]
			groups.append(group)
			index += width
		run.clear()
	return groups

func _mask_center_x(mask: int) -> float:
	var total := 0.0
	var count := 0
	for lane in LANE_COUNT:
		if (mask & (1 << lane)) == 0:
			continue
		total += _lane_x(lane)
		count += 1
	return total / float(count) if count > 0 else 0.0

func _lane_x(lane: int) -> float:
	return (float(clampi(lane, 0, LANE_COUNT - 1)) - 1.0) * float(config.lane_width)

func _free_lanes(mask: int) -> Array[int]:
	var free: Array[int] = []
	for lane in LANE_COUNT:
		if (mask & (1 << lane)) == 0:
			free.append(lane)
	return free

## Seconds the player spends inside a shot's z range: its depth plus the capsule footprint, at the
## closing speed.
func _pass_seconds(variant: StringName, closing: float) -> float:
	var depth: float = bot.projectile_depth(variant)
	return (depth + float(config.hurtbox_radius) * 2.0) / maxf(closing, 0.1)

## The window (t_low, t_high) after a launch in which the feet are above `height`, from the contract
## §7 arc y(t) = jump_velocity t - gravity t^2 / 2. An empty window comes back as (0, 0).
func _clear_span(height: float) -> Vector2:
	var v := float(config.jump_velocity)
	var g := float(config.gravity)
	var disc := v * v - 2.0 * g * height
	if disc <= 0.0 or g <= 0.0:
		return Vector2.ZERO
	var root := sqrt(disc)
	return Vector2((v - root) / g, (v + root) / g)

## Contract §11.7 spawn rows: the run row, or the jump row for auto_fix_patch.
func _tool_height(kind: StringName) -> float:
	if ToolDefs.uses_jump_height(kind):
		return float(config.pickup_height_jump)
	return float(config.pickup_height_run)

func _stage_speed_bonus(stage_index: int) -> float:
	return clampf(float(config.stage_speed_step) * float(maxi(stage_index, 1) - 1),
		0.0, maxf(float(config.stage_speed_bonus_max), 0.0))

## The lane masks one beat can fire on: the fixed one, or every option the random rolls draw from.
func _beat_masks(beat: Variant) -> Array[int]:
	var row: Dictionary = beat
	var mode: StringName = row.get("lanes", BossDefs.LANES_FIXED)
	if mode == BossDefs.LANES_RANDOM_SINGLE:
		return BossDefs.SINGLE_LANE_MASKS.duplicate()
	if mode == BossDefs.LANES_RANDOM_ADJACENT:
		return BossDefs.ADJACENT_LANE_MASKS.duplicate()
	var fixed: Array[int] = [int(row.get("mask", BossDefs.LANE_ALL))]
	return fixed

# --- the escalation floors the whole sweep rests on ---

## Cycle 4 is where every growth curve has bottomed out (contract §11.10), so this pins that the
## sweep above really did run against the floors and the caps and not against some milder middle.
func _check_escalation_floors() -> void:
	for slot in BossDefs.SLOTS.size():
		var stage_index := (CYCLES - 1) * BossDefs.SLOTS.size() + slot + 1
		var def := BossDefs.fight_def(stage_index, config)
		check(int(def["cycle"]) == CYCLES - 1,
			"stage %d should be cycle %d, got %d" % [stage_index, CYCLES - 1, int(def["cycle"])])
		check(is_equal_approx(float(def["projectile_speed"]), float(config.boss_projectile_speed_max)),
			"%s: cycle %d projectile speed is %.2f, expected the %.2f cap"
				% [def["kind"], CYCLES - 1, float(def["projectile_speed"]), float(config.boss_projectile_speed_max)])
		for phase in range(1, BossDefs.PHASE_COUNT + 1):
			check(is_equal_approx(BossDefs.telegraph_for(def, phase), float(config.boss_telegraph_min)),
				"%s p%d: cycle %d telegraph is %.3f, expected the %.2f floor"
					% [def["kind"], phase, CYCLES - 1, BossDefs.telegraph_for(def, phase),
						float(config.boss_telegraph_min)])

# --- harness ---

func _compile(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		return null
	return script

## The virtual runner reads its tuning from the same RunConfig the bot plans against.
func _apply_player_tuning() -> void:
	player.lane_width = float(config.lane_width)
	player.lane_change_time = float(config.lane_change_time)
	player.gravity = float(config.gravity)
	player.jump_velocity = float(config.jump_velocity)
	player.jump_buffer_seconds = float(config.jump_buffer)
	player.roll_seconds = float(config.roll_duration)
	player.roll_cooldown_seconds = float(config.roll_cooldown)

## Put the one tool node where the pass wants it and make sure the bot can see it.
func _place_tool(entry: Dictionary) -> void:
	tool_node.position = Vector3(_lane_x(int(entry["lane"])), float(entry["y"]), float(entry["z"]))
	if not tool_node.is_in_group(&"runner_tools"):
		tool_node.add_to_group(&"runner_tools")

## Out of the group and far behind the player: a pass with no tool must see none.
func _park_tool() -> void:
	if tool_node.is_in_group(&"runner_tools"):
		tool_node.remove_from_group(&"runner_tools")
	tool_node.position = Vector3(0.0, 0.0, 1000.0)

func _report() -> void:
	for node in junk:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	junk.clear()
	game = null
	bot = null
	player = null
	tool_node = null
	print("RUNNER BOSS: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	quit(failures)
