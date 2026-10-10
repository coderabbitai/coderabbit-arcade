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
## B5 an accepted tool is reachable inside boss_tool_guarantee_seconds;
## B6 (contract 2.4) every signature event — a flaky commit, a scatter split, a rebase sweep, a legacy
##    gap shift, a debris shadow and its landing, a branching volley — leaves, from every lane, a
##    survivable answer that can still be started boss_signature_reaction_min (0.35 s) after it.
## B7 (contract 2.6 §11.14) the cinematic copy table (ui/boss_copy.gd, frontend-owned) names every
##    boss in the roster, and only those, with a real epithet (REGRESSED vN from the second lap), threat
##    line and source path. Each phase gets a hint row whose tools are exactly BossDefs.accepted_tools,
##    so the "how to resolve" row can never contradict the fight.
##
## Since contract 2.4 the shots are not assumed to fly straight: every beat is resolved through
## boss/boss_attacks.gd (the same code boss_encounter.gd fires from), the bot hears the encounter's
## own boss_attack_planned / boss_attack_telegraph / boss_attack_committed, and every collision is
## tested against the motion API (x_at / y_range_at / z_at) the live projectile flies.
##
## Nothing here writes user:// and nothing instantiates runner_game.tscn, so there is no board to
## point anywhere: the facade is a bare runner_game.gd object that never enters the tree.

## Only scripts that never reach runner_game.gd can be preloaded: under --script this test is
## compiled before the autoloads exist (see tests/runner_logic.gd). autopilot.gd does reach it, so
## it is loaded inside run().
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
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
## Attack streams the pattern sweep replays; each one follows boss_encounter's own no-repeat rule.
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
## B7: the frontend copy table. It is loaded at run time, so a missing file is a failed check rather
## than a compile error that would stop the whole validator.
const COPY_PATH := "res://scenes/runner/ui/boss_copy.gd"
## A kind no roster will ever hold, whose answers are boss_copy's own fallbacks.
const NO_SUCH_BOSS: StringName = &"__no_such_boss__"

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
## Signature events B6 measured, by name, so the report can say they were all reached, and the
## tightest window each kind left.
var event_counts := {}
var event_min := {}

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
	check(game.has_signal(&"boss_attack_planned") and game.has_signal(&"boss_attack_committed"),
		"the facade does not declare boss_attack_planned / boss_attack_committed (contract 2.4 §11.4)")

	print("RUNNER BOSS: validating %d bosses x %d cycles x %d phases"
		% [BossDefs.SLOTS.size(), CYCLES, BossDefs.PHASE_COUNT])
	for slot in BossDefs.SLOTS.size():
		for cycle in CYCLES:
			var stage_index := cycle * BossDefs.SLOTS.size() + slot + 1
			_validate_fight(stage_index)
	_check_escalation_floors()
	_check_signature_coverage()
	_check_copy()
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

# --- B1 / B2 / B3 / B4 / B6: one beat at a time ---

## Every option of every beat (each random lane draw a beat can make, contract 2.4 boss_attacks.gd
## beat_options), each attack of that option, and every entry lane.
func _check_beats(tag: String, def: Dictionary, phase: int) -> void:
	for beat in BossDefs.pattern_for(def, phase):
		var options := BossAttacks.beat_options(beat, def, phase, config)
		check(not options.is_empty(), "%s: a beat resolves to no attack at all: %s" % [tag, beat])
		for item in options:
			var option: Array = item
			var span := 0.0
			for attack_item in option:
				var attack: Dictionary = attack_item
				_check_attack(tag, attack)
				span = maxf(span, float(attack["exit"]))
			# B6: every signature event (and a branching volley as a whole) leaves a reaction window.
			_check_events(tag, option)
			var stream: Array[Dictionary] = []
			for attack_item in option:
				stream.append({"at": 0.0, "attack": attack_item})
			for lane in LANE_COUNT:
				var result := _simulate(int(def["stage_index"]), stream, [], lane, span + 1.0)
				# B4: zero hits, from every entry lane.
				check(String(result["hit"]).is_empty(),
					"%s: the bot was hit from lane %d by %s: %s"
						% [tag, lane, _option_label(option), result["hit"]])

## B1 / B2 / B3 for one attack, all measured from the moment its lanes are final: the telegraph for
## every attack but a flaky one, whose clock starts at the commit (contract 2.4 boss_commit_min).
func _check_attack(tag: String, attack: Dictionary) -> void:
	var variant: StringName = attack.get("variant", &"orb")
	var from_t := maxf(float(attack.get("commit_at", -1.0)), 0.0)
	var arrival := float(attack["enter"]) - from_t
	check(not (attack["shots"] as Array).is_empty(), "%s: %s fires no projectile" % [tag, _attack_label(attack)])
	# B1: the whole reaction budget, telegraph (or commit) plus travel, at this cycle's escalation.
	check(arrival >= MIN_REACTION - EPS,
		"%s: %s leaves %.3f s from telegraph to impact, need %.2f"
			% [tag, _attack_label(attack), arrival, MIN_REACTION])
	fight_log.append("%s telegraph %.2f speed %.1f arrival %.3f" % [_attack_label(attack),
		float(attack["telegraph"]), float(attack["speed"]), arrival])
	# A plain shot keeps the v2.0 number the bot has always planned with.
	if StringName(attack.get("signature", BossAttacks.SIG_PLAIN)) == BossAttacks.SIG_PLAIN:
		var plain: float = bot.telegraph_arrival(float(attack["telegraph"]), float(attack["speed"]), variant)
		check(is_equal_approx(plain, float(attack["enter"])),
			"%s: the motion API puts a straight %s at %.4f s, the planner at %.4f s"
				% [tag, variant, float(attack["enter"]), plain])
	# B2: something in the corridor answers this attack where it passes the player.
	var impact := int(attack["impact_mask"])
	check(not _free_lanes(impact).is_empty() or bool(attack["jumpable"]) or bool(attack["rollable"]),
		"%s: %s blocks the corridor with no free lane and no body answer" % [tag, _attack_label(attack)])
	_check_launch_window(tag, attack, arrival)

## B3: the span of launch times that still clears the shot, and how long the bot has to choose one.
## A jumpable variant is measured against the jump arc over its impact height, a roll-only one
## against the roll window, both at the attack's own closing speed (systems spec §1.1).
func _check_launch_window(tag: String, attack: Dictionary, arrival: float) -> void:
	var variant: StringName = attack.get("variant", &"orb")
	var def := HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant)
	var hint: StringName = def.get("dodge_hint", &"")
	var pass_seconds := _pass_seconds(variant, float(attack["speed"]))
	if HazardDefs.JUMP_HINTS.has(hint):
		# A jump-hinted shot must be in its final geometry by the time it passes (a debris slab has
		# landed), or the hint is a lie.
		check(bool(attack["jumpable"]),
			"%s: %s is jump-hinted but not in its landed geometry for the pass" % [tag, _attack_label(attack)])
		var height := float(attack["clear_height"])
		var span := _clear_span(height)
		check(span.y > span.x, "%s: %s at y %.2f cannot be jumped at all" % [tag, variant, height])
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

## B6 (contract 2.4): every commit, split, sweep, gap shift and debris shadow / landing — and a
## branching volley as a whole — leaves, from every lane the player can be standing in at that
## moment, a survivable answer whose latest start is at least boss_signature_reaction_min after the
## event. The answer is searched over every final lane and every body action (none / jump / roll)
## against the attacks' impact geometry; lane changes cost one lane_change_time per step.
func _check_events(tag: String, option: Array) -> void:
	var floor_seconds := float(config.boss_signature_reaction_min)
	check(floor_seconds >= MIN_LAUNCH_WINDOW - EPS,
		"boss_signature_reaction_min %.2f is below the %.2f s choice-reaction budget" % [floor_seconds, MIN_LAUNCH_WINDOW])
	var moments: Array[Dictionary] = []
	for item in option:
		var attack: Dictionary = item
		for event in BossAttacks.events(attack):
			moments.append({"name": event["name"], "at": float(event["at"]), "attacks": [attack]})
	if option.size() > 1:
		moments.append({"name": &"volley", "at": 0.0, "attacks": option})
	for moment in moments:
		var name: StringName = moment["name"]
		event_counts[name] = int(event_counts.get(name, 0)) + 1
		var attacks: Array = moment["attacks"]
		var at := float(moment["at"])
		var first_enter := INF
		for item in attacks:
			first_enter = minf(first_enter, float((item as Dictionary)["enter"]))
		check(at < first_enter - EPS, "%s: the %s of %s happens %.3f s after it already reached the player"
			% [tag, name, _option_label(option), at - first_enter])
		for lane in LANE_COUNT:
			var best := _best_answer(attacks, lane)
			var window := float(best["latest"]) - at
			check(not String(best["answer"]).is_empty() and window >= floor_seconds - EPS,
				"%s: after the %s of %s, lane %d has %s with %.3f s to start it, need %.2f"
					% [tag, name, _option_label(option), lane,
						best["answer"] if not String(best["answer"]).is_empty() else "no answer", window, floor_seconds])
			fight_log.append("B6 %s %s lane %d -> %s, %.3f s" % [_option_label(option), name, lane, best["answer"], window])
			event_min[name] = minf(float(event_min.get(name, INF)), window)

## The answer with the latest start, as {answer, latest} (latest in seconds after the telegraph).
func _best_answer(attacks: Array, lane: int) -> Dictionary:
	var best := {"answer": "", "latest": -INF}
	for goal in LANE_COUNT:
		for body: StringName in [&"none", &"jump", &"roll"]:
			var latest := _answer_latest(attacks, lane, goal, body)
			if latest > float(best["latest"]):
				best = {"answer": "lane %d%s" % [goal, "" if body == &"none" else " + " + String(body)],
					"latest": latest}
	return best

## Latest start of "end in `goal`, then `body`" against `attacks`, or -INF when it does not survive.
func _answer_latest(attacks: Array, lane: int, goal: int, body: StringName) -> float:
	var latest := INF
	var body_in := INF
	var body_out := -INF
	var height := 0.0
	for item in attacks:
		var attack: Dictionary = item
		var impact := int(attack["impact_mask"])
		if (impact & (1 << goal)) != 0:
			if body == &"jump" and bool(attack["jumpable"]):
				pass
			elif body == &"roll" and bool(attack["rollable"]):
				pass
			else:
				return -INF
			body_in = minf(body_in, float(attack["enter"]))
			body_out = maxf(body_out, float(attack["exit"]))
			height = maxf(height, float(attack["clear_height"]))
		if goal != lane:
			for crossed in range(mini(lane, goal), maxi(lane, goal) + 1):
				if (impact & (1 << crossed)) != 0:
					latest = minf(latest, float(attack["enter"]) - float(config.lane_change_time) * absi(goal - lane))
					break
	if body_in < INF:
		if body == &"jump":
			var span := _clear_span(height)
			if span.y <= span.x or body_out - span.y > body_in - span.x:
				return -INF
			latest = minf(latest, body_in - span.x)
		elif body == &"roll":
			if body_out - float(config.roll_duration) > body_in:
				return -INF
			latest = minf(latest, body_in)
	return latest

# --- B4: whole pattern cycles at the real attack interval ---

func _check_pattern_sequences(tag: String, def: Dictionary, phase: int) -> void:
	var pattern := BossDefs.pattern_for(def, phase)
	if pattern.is_empty():
		return
	var interval := BossDefs.attack_interval_for(def, phase)
	for stream_seed in MASK_STREAM_SEEDS:
		var stream := _attack_stream(pattern, def, phase, int(stream_seed), interval)
		var span := 0.0
		for item in stream:
			span = maxf(span, float(item["at"]) + float((item["attack"] as Dictionary)["exit"]))
		for lane in LANE_COUNT:
			var result := _simulate(int(def["stage_index"]), stream, [], lane, span + 1.0)
			check(String(result["hit"]).is_empty(),
				"%s: the bot was hit from lane %d during pattern stream %d (%s): %s"
					% [tag, lane, int(stream_seed), _stream_label(stream), result["hit"]])

## `PATTERN_CYCLES` laps of the beat list, every beat resolved the way boss_encounter's _queue_beat
## resolves it: boss_attacks.pick_option, never a straight repeat of the previous beat's impact lanes
## while there is a choice. A branching volley puts all its heads on the same beat.
func _attack_stream(pattern: Array, def: Dictionary, phase: int, stream_seed: int,
		interval: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	var stream: Array[Dictionary] = []
	var last_key := 0
	var at := 0.0
	for lap in PATTERN_CYCLES:
		for beat in pattern:
			var options := BossAttacks.beat_options(beat, def, phase, config)
			var pick := BossAttacks.pick_option(options, last_key, rng, true)
			if pick < 0:
				continue
			var option: Array = options[pick]
			last_key = BossAttacks.option_key(option)
			for attack in option:
				stream.append({"at": at, "attack": attack})
			at += interval
	return stream

func _stream_label(stream: Array) -> String:
	var parts := PackedStringArray()
	for item in stream:
		parts.append("%s@%.2f" % [_attack_label(item["attack"]), float(item["at"])])
	return " ".join(parts)

func _option_label(option: Array) -> String:
	var parts := PackedStringArray()
	for attack in option:
		parts.append(_attack_label(attack))
	return "+".join(parts)

func _attack_label(attack: Dictionary) -> String:
	var signature := String(attack.get("signature", BossAttacks.SIG_PLAIN))
	var label := "%s/%d" % [attack.get("variant", &"orb"), int(attack.get("impact_mask", 0))]
	if signature.is_empty():
		return label
	return "%s[%s tel %d]" % [label, signature, int(attack.get("telegraph_mask", 0))]

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
	var interval := BossDefs.attack_interval_for(def, phase)
	var corridor := float(config.max_speed) + _stage_speed_bonus(int(def["stage_index"]))
	var travel := absf(float(config.boss_tool_spawn_z)) / corridor
	check(travel <= guarantee + EPS,
		"%s: a tool needs %.2f s to reach the player, past the %.2f s guarantee" % [tag, travel, guarantee])
	var stream := _attack_stream(pattern, def, phase, MASK_STREAM_SEEDS[0], interval)
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
				var result := _simulate(int(def["stage_index"]), stream, tools, 1,
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

## One pass. `stream` holds attacks scheduled at `at` seconds, fed to the bot through the facade's
## own signals in the encounter's order — boss_attack_planned, boss_attack_telegraph, and for a
## flaky attack boss_attack_committed at its commit — and flown through the boss_attacks.gd motion
## API when their telegraph runs out. `tools` are pickups that appear at `boss_tool_spawn_z` and ride
## the corridor in. The bot is the real autopilot, ticked through its own `_physics_process`.
## Returns {hit, collected, collected_at}.
func _simulate(stage_index: int, stream: Array, tools: Array, entry_lane: int, duration: float,
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
	var pending_attacks := stream.duplicate()
	var pending_tools := tools.duplicate()
	var commits: Array[Dictionary] = []
	var live: Array[Dictionary] = []
	var tool_live := {}
	_park_tool()
	var time := 0.0
	var hit := ""
	var collected_at := -1.0
	var steps := mini(int(duration / TICK) + 2, STEP_GUARD)
	for step in steps:
		# 1. Attacks the boss sends this tick, through the facade signals the bot listens to.
		while not pending_attacks.is_empty() and float((pending_attacks[0] as Dictionary)["at"]) <= time + EPS:
			var item: Dictionary = pending_attacks.pop_front()
			var attack: Dictionary = item["attack"]
			game.boss_attack_planned.emit(attack)
			game.boss_attack_telegraph.emit(int(attack["telegraph_mask"]), StringName(attack["variant"]),
				float(attack["telegraph"]))
			if float(attack.get("commit_at", -1.0)) >= 0.0:
				commits.append({"t": time + float(attack["commit_at"]), "attack": attack})
			var fire_t := time + float(attack["telegraph"])
			for shot in attack["shots"]:
				live.append({"spawn_t": fire_t, "shot": shot})
		# 2. Flaky telegraphs settling.
		while not commits.is_empty() and float(commits[0]["t"]) <= time + EPS:
			var commit: Dictionary = commits.pop_front()
			var settled: Dictionary = commit["attack"]
			game.boss_attack_committed.emit(int(settled["mask"]), StringName(settled["variant"]),
				float(settled["telegraph"]) - float(settled["commit_at"]))
		# 3. Tools entering the corridor.
		while not pending_tools.is_empty() and float((pending_tools[0] as Dictionary)["at"]) <= time + EPS:
			var entry: Dictionary = pending_tools.pop_front()
			tool_live = {
				"lane": int(entry["lane"]), "y": float(entry["y"]),
				"z": float(config.boss_tool_spawn_z)
			}
			_place_tool(tool_live)
		# 4. The bot: its own entry point, so the live code decides everything.
		bot._physics_process(TICK)
		# 5. The virtual runner, then the world.
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
		if pending_attacks.is_empty() and commits.is_empty() and pending_tools.is_empty() \
				and live.is_empty() and tool_live.is_empty():
			break
		_retire(live, time)
	_park_tool()
	game.phase = &"idle"
	return {"hit": hit, "collected": collected_at >= 0.0, "collected_at": collected_at}

## Shots that have swept past the player are done with; the list stays short across a long pattern.
func _retire(live: Array[Dictionary], time: float) -> void:
	for index in range(live.size() - 1, -1, -1):
		var since := time - float(live[index]["spawn_t"])
		if since >= 0.0 and BossAttacks.z_at(live[index]["shot"], since) > float(config.despawn_z):
			live.remove_at(index)

## The first shot the runner is inside this tick, or "" when the pass is still clean.
func _collision(live: Array[Dictionary], time: float) -> String:
	var body := _player_box()
	for item in live:
		var since := time - float(item["spawn_t"])
		if since < 0.0:
			continue
		var shot: Dictionary = item["shot"]
		var box := _shot_box(shot, since)
		if not box.intersects(body):
			continue
		return "%s lanes %d at x %.2f z %.2f y %.2f, t %.2f (player x %.2f y %.2f%s)" % [
			shot["variant"], BossAttacks.lane_mask_at(shot, since, config), box.get_center().x,
			box.get_center().z, box.position.y, time, float(player.at_x), float(player.at_y),
			", rolling" if bool(player.rolling) else ""]
	return ""

## Systems spec §3: stay crouched while something overhead still needs rolling under.
func _standing_clear(live: Array[Dictionary], time: float) -> bool:
	var standing := _player_box(true)
	standing.position.z -= float(config.max_speed) * 2.0 * TICK + 0.3
	standing.size.z += float(config.max_speed) * 2.0 * TICK + 0.3
	for item in live:
		var since := time - float(item["spawn_t"])
		if since < 0.0:
			continue
		var shot: Dictionary = item["shot"]
		var hint: StringName = BossAttacks.shot_def(shot).get("dodge_hint", &"")
		if not HazardDefs.ROLL_HINTS.has(hint):
			continue
		if _shot_box(shot, since).intersects(standing):
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

## The hitbox of one shot `since` seconds after it was fired, straight off the motion API: x from
## x_at, y from y_range_at, z from z_at, the extent from the contract §11.6 table.
func _shot_box(shot: Dictionary, since: float) -> AABB:
	var size: Vector3 = BossAttacks.shot_def(shot).get("size", Vector3.ONE)
	var y := BossAttacks.y_range_at(shot, since)
	var x := BossAttacks.x_at(shot, since)
	var z := BossAttacks.z_at(shot, since)
	return AABB(
		Vector3(x - size.x * 0.5, y.x, z - size.z * 0.5),
		Vector3(size.x, maxf(y.y - y.x, 0.01), size.z))

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

## Contract 2.4: every signature the roster uses was actually swept, each boss owns its own, and B6
## reached every event kind — so a pattern edit that drops a signature cannot pass silently.
func _check_signature_coverage() -> void:
	var expected := {
		&"flaky_test_swarm": [BossAttacks.SIG_FLAKY, BossAttacks.SIG_SCATTER],
		&"merge_conflict_hydra": [BossAttacks.SIG_BRANCHING, BossAttacks.SIG_SWEEP, BossAttacks.SIG_FORCE_PUSH],
		&"legacy_monolith": [BossAttacks.SIG_LEGACY_WALL, BossAttacks.SIG_QUAKE, BossAttacks.SIG_DEBRIS]
	}
	for entry in BossDefs.SLOTS:
		var kind: StringName = entry["kind"]
		var seen := {}
		for row in entry["patterns"]:
			for beat in row:
				seen[StringName((beat as Dictionary).get("signature", BossAttacks.SIG_PLAIN))] = true
		for signature in expected.get(kind, []):
			check(seen.has(signature), "%s no longer fires its %s signature" % [kind, signature])
	for name: StringName in [&"commit", &"split", &"sweep", &"shift", &"shadow", &"land", &"volley"]:
		check(int(event_counts.get(name, 0)) > 0, "B6 never measured a %s event" % name)
	var tightest := PackedStringArray()
	for name in event_min:
		tightest.append("%s %.3f s" % [name, float(event_min[name])])
	print("RUNNER BOSS: B6 events measured %s; tightest windows: %s" % [event_counts, ", ".join(tightest)])

# --- B7: the cinematic copy table agrees with the roster and the fight (contract 2.6 §11.14) ---

## Every roster boss at every cycle, through boss_copy's own API: epithet / threat / source path are
## real (not the fallback an unknown kind gets), the epithet carries "REGRESSED vN" from the second
## lap on, and hint_rows() gives one row per phase whose tools are BossDefs.accepted_tools exactly
## and whose text names them (or says every tool lands). The copy table ships with contract 2.6, so a
## tree without it fails: renaming or dropping the file must not silently drop this check.
func _check_copy() -> void:
	check(ResourceLoader.exists(COPY_PATH), "B7: %s is missing, so the cinematic copy cannot be checked" % COPY_PATH)
	if not ResourceLoader.exists(COPY_PATH):
		return
	var copy := load(COPY_PATH) as GDScript
	check(copy != null, "B7: %s did not load as a script" % COPY_PATH)
	if copy == null:
		return
	var table: Dictionary = copy.get_script_constant_map().get("COPY", {})
	var roster := {}
	for entry in BossDefs.SLOTS:
		roster[StringName(entry["kind"])] = true
	check(table.size() == roster.size(), "B7: the copy table has %d rows for a %d-boss roster" % [table.size(), roster.size()])
	for row_kind in table:
		check(roster.has(StringName(row_kind)), "B7: the copy table carries %s, which no stage fights" % row_kind)
	var fallback_epithet := String(copy.epithet(NO_SUCH_BOSS))
	var fallback_threat := String(copy.threat(NO_SUCH_BOSS))
	var fallback_path := String(copy.source_path(NO_SUCH_BOSS))
	var every_tool := ToolDefs.kinds().size()
	var samples := PackedStringArray()
	for slot in BossDefs.SLOTS.size():
		var kind: StringName = BossDefs.SLOTS[slot]["kind"]
		check(table.has(kind), "B7: %s has no copy row" % kind)
		var first_epithet := String(copy.epithet(kind, 1))
		check(not first_epithet.is_empty() and first_epithet != fallback_epithet,
			"B7: %s epithet is the fallback %s" % [kind, first_epithet])
		var threat := String(copy.threat(kind))
		check(not threat.is_empty() and threat != fallback_threat, "B7: %s threat is the fallback %s" % [kind, threat])
		var path := String(copy.source_path(kind))
		check(path != fallback_path and path.contains(":"), "B7: %s source path is %s, expected a path:line" % [kind, path])
		for cycle in CYCLES:
			var stage_index := cycle * BossDefs.SLOTS.size() + slot + 1
			var def := BossDefs.fight_def(stage_index, config)
			var lap := cycle + 1
			var epithet := String(copy.epithet(kind, lap))
			var tag := "REGRESSED v%d" % lap
			check(epithet.begins_with(first_epithet) and (epithet.contains(tag) == (lap >= 2)),
				"B7: %s lap %d epithet is %s" % [kind, lap, epithet])
			_check_hint_rows(copy, def, kind, cycle, every_tool, samples)
	print("RUNNER BOSS: B7 copy covers %d bosses x %d cycles; hints %s" % [roster.size(), CYCLES, "; ".join(samples)])

## One fight's hint rows against BossDefs: one per phase, in order, with the accepted tools and the
## all-tools flag the fight really has, and text that names those tools and no other.
func _check_hint_rows(copy: GDScript, def: Dictionary, kind: StringName, cycle: int, every_tool: int,
		samples: PackedStringArray) -> void:
	var rows: Array = copy.hint_rows(def)
	var phases := int(def.get("phase_count", BossDefs.PHASE_COUNT))
	check(rows.size() == phases, "B7: %s c%d has %d hint rows for %d phases" % [kind, cycle, rows.size(), phases])
	for index in mini(rows.size(), phases):
		var row: Dictionary = rows[index]
		var phase := index + 1
		var accepted := _sorted_names(BossDefs.accepted_tools(def, phase))
		var tag := "%s c%d p%d" % [kind, cycle, phase]
		check(int(row.get("phase", 0)) == phase, "B7: %s row is for phase %s" % [tag, row.get("phase", "<missing>")])
		check(_sorted_names(row.get("accepted_tools", [])) == accepted and _sorted_names(row.get("tools", [])) == accepted,
			"B7: %s hint tools %s / %s, BossDefs accepts %s"
				% [tag, row.get("accepted_tools", []), row.get("tools", []), accepted])
		var all_tools := accepted.size() == every_tool
		check(bool(row.get("all_tools", not all_tools)) == all_tools,
			"B7: %s all_tools is %s, but %d of %d tools land" % [tag, row.get("all_tools", "<missing>"), accepted.size(), every_tool])
		var text := String(row.get("text", ""))
		check(not text.is_empty(), "B7: %s hint row has no text" % tag)
		if all_tools:
			check(text.contains("EVERY TOOL LANDS"), "B7: %s accepts every tool but its hint reads %s" % [tag, text])
		else:
			for tool_kind in ToolDefs.kinds():
				var label := ToolDefs.label(tool_kind).to_upper()
				var named := text.contains(label)
				check(named == accepted.has(String(tool_kind)),
					"B7: %s hint %s %s %s, BossDefs accepts %s"
						% [tag, text, "names" if named else "omits", label, accepted])
		if cycle == 0:
			samples.append("%s p%d \"%s\"" % [kind, phase, text])

func _sorted_names(tools: Variant) -> PackedStringArray:
	var names := PackedStringArray()
	if tools is Array:
		for tool_kind in tools:
			names.append(String(tool_kind))
	names.sort()
	return names

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
