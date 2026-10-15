extends Node3D
## One boss fight (contract §11.4–§11.7, systems spec §10.3). The StageManager owns the phase this
## runs in: `setup(game)` once, `start(stage_index)` on entering `boss`, `tick(delta)` every physics
## tick of that phase, `finished` polled for the end, `abort()` when the run is lost mid-fight.
##
## The boss itself has no hitbox: it is a Node3D the projectiles are fired from, so the only things
## that can touch the player during a fight are hazards (projectiles) and pickups (tools). The
## arena is inert while `game` is null — every entry point returns immediately, which is what makes
## the scene safe to load and instance on its own.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
## Beats -> attacks -> shots, and the shot motion (contract 2.4 §11.6); pure, shared with the planner.
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const ScoreManager = preload("res://scenes/runner/systems/score_manager.gd")
## Typed so `kind` / `closing_speed` are checked property accesses and not dynamic ones (neither
## script preloads this one back, so there is no cycle).
const Projectile = preload("res://scenes/runner/hazards/projectile.gd")
const ToolPickup = preload("res://scenes/runner/powerups/tool_pickup.gd")
## The cinematic-focus default (contract §11.5) for a visual without the hook, the graybox included;
## the base preloads nothing, so there is no cycle.
const BossVisualBase = preload("res://scenes/runner/boss/boss_visual_base.gd")
const PROJECTILE_SCENE := "res://scenes/runner/hazards/projectile.tscn"
const TOOL_SCENE := "res://scenes/runner/powerups/tool_pickup.tscn"
const VISUAL_DIR := "res://scenes/runner/boss/visuals/"

## The fight RNG is the run seed with a fixed salt, re-seeded per stage, so one seed replays the same
## lanes and tools for each stage.
const RNG_SALT := 0x2A5B1C3D
## Spreads the per-stage fight seeds apart (the 32-bit golden-ratio constant).
const RNG_STAGE_STEP := 0x9E3779B1
## Contract §11.5: the boss centre hovers at y 2.6, at config.boss_z.
const BOSS_CENTER_Y := 2.6
## Graybox boss (systems spec §10.3): a DANGER box 4 x 2.4 x 1.5 with a Label3D name plate. It is
## lifted so its bottom edge sits on the contract §11.5 floor (y 1.6) instead of 0.2 m under it.
const GRAYBOX_SIZE := Vector3(4.0, 2.4, 1.5)
const GRAYBOX_FLOOR_Y := 1.6
const GRAYBOX_LABEL_SIZE := 64
const GRAYBOX_LABEL_PIXEL_SIZE := 0.01
## Label3D height above the box centre, in metres.
const GRAYBOX_LABEL_Y := 1.6
## A phase change never leaves longer than this before the next attack (systems spec §10.3).
const PHASE_CHANGE_ATTACK_DELAY := 0.6
## Camera punch on a damaging tool (contract §11.4), used only while the facade has no on_tool_hit().
const CAMERA_SHAKE_ON_TOOL := 0.35
## Lanes 0/1/2 (contract §11.7).
const LANE_COUNT := 3
## Contract 2.6 §11.14 cinematic modes: a full intro on the run's first meeting with a boss, a short
## one on every later meeting, and the same split for the defeat.
const CINEMATIC_INTRO_FULL: StringName = &"intro_full"
const CINEMATIC_INTRO_SHORT: StringName = &"intro_short"
const CINEMATIC_DEFEAT_FULL: StringName = &"defeat_full"
const CINEMATIC_DEFEAT_SHORT: StringName = &"defeat_short"
## The time factor during the defeat's hit-stop (contract §11.14 boss_time_factor).
const HIT_STOP_FACTOR := 0.05

# --- read-only state (the facade mirrors these into contract §11.4 properties) ---

var game: RunnerGame
var config: RunConfig
## This fight's boss_defs row, already scaled for its cycle. Empty outside a fight.
var def := {}
var kind: StringName = &""
var boss_name := ""
var stage_index := 0
var hp := 0
var max_hp := 0
## 1-based, raised at the config.boss_phase_thresholds crossings.
var phase := 1
## Polled by the StageManager: true once the outro is over (systems spec §10.3).
var finished := false
## Cumulative over the run, read into `result` (contract §11.4).
var bosses_defeated := 0
var bosses_escaped := 0
var tools_used := 0
var boss_damage_dealt := 0
var fight_rng := RandomNumberGenerator.new()
## The mounted boss visual (frontend scene or graybox); a child of Boss, freed after the outro.
var visual: Node3D
## The live boss node (the Boss mount) during a fight, null outside one: the facade mirrors this
## into its own `boss` property (contract §11.4).
var boss: Node3D
## The cinematic playing now (contract 2.6 §11.14), &"" when none, and its whole length. An intro
## runs on the `_intro` countdown and a defeat on `_outro`, so the cinematic clock and the fight's
## own windows can never drift apart.
var cinematic_mode: StringName = &""
var cinematic_seconds := 0.0
## Where the cinematic camera aims, in the Boss mount's space (contract §11.5): the visual's
## cinematic_focus(), read once straight after on_spawned() at its rest pose and kept for the fight.
## Zero outside a fight.
var cinematic_focus := Vector3.ZERO

@onready var boss_root: Node3D = $Boss
@onready var projectiles_root: Node3D = $Projectiles
@onready var tools_root: Node3D = $Tools

## Telegraphs in flight: {mask: int, variant: StringName, remaining: float} plus, for every beat
## queued by this arena, {attack, impact_mask, commit_remaining, committed} (contract 2.4). `mask`
## is what the telegraph currently shows: a flaky beat's two candidates until it commits, then the
## committed lanes. A bare {mask, variant, remaining} entry (a test's) still fires a straight shot.
var _pending: Array[Dictionary] = []
var _active := false
var _intro := 0.0
var _outro := 0.0
## Seconds of ACTIVE fight (the intro does not count against boss_timeout_seconds).
var _fight_timer := 0.0
var _attack_timer := 0.0
var _tool_timer := 0.0
var _since_tool := 0.0
## Index into the current phase's beat list.
var _beat := 0
var _last_mask := 0
var _last_tool_lane := -1
var _graybox: Node3D
var _scene_cache := {}
## Per-run kind -> true sets (contract §11.14): a boss already met plays the short intro, and one
## already beaten plays the short defeat.
var _met := {}
var _defeated_kinds := {}
## Set by mark_met() / mark_defeated(): the next start() keeps the restored sets even on stage 1,
## where it would otherwise reset the run's tallies.
var _met_restored := false
var _cinematic_skipped := false

# --- StageManager entry points ---

func _ready() -> void:
	# runner_game.tscn hands the arena its facade through setup(), like every other system. This is
	# the fallback for a tree that mounts the arena without that call: an inert boss would be a
	# silent no-show rather than a loud failure, so the arena adopts the facade it lives under.
	if game == null:
		var owner_game := _find_facade()
		if owner_game != null:
			setup(owner_game)

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config if runner != null else null
	_seed_rng()

## The RunnerGame this arena is mounted under, or null when it is standing on its own.
func _find_facade() -> RunnerGame:
	var node := get_parent()
	while node != null:
		var candidate := node as RunnerGame
		if candidate != null:
			return candidate
		node = node.get_parent()
	return null

## A fresh run: drop the fight and the counters the result reads.
func reset() -> void:
	abort()
	_reset_run_stats()
	_met_restored = false

## Contract §11.13/§11.14: a checkpoint retry restores the bosses its run had already met, so the
## retried boss counts as a repeat meeting and plays the short intro. Kept by the next start(),
## stage 1 included.
func mark_met(kinds: Array) -> void:
	_mark(_met, kinds)

## The same for the bosses the run had already beaten (bosses_defeated_kinds), so a retry that
## kills one of them again plays the short defeat.
func mark_defeated(kinds: Array) -> void:
	_mark(_defeated_kinds, kinds)

## The kinds this run has met so far, for the boss checkpoint (contract §11.13 bosses_met).
func met_kinds() -> Array[StringName]:
	return _kinds(_met)

## The kinds this run has beaten so far (contract §11.13 bosses_defeated_kinds).
func defeated_kinds() -> Array[StringName]:
	return _kinds(_defeated_kinds)

func _mark(into: Dictionary, kinds: Array) -> void:
	for entry in kinds:
		var restored := StringName(entry)
		if restored != &"":
			into[restored] = true
	_met_restored = true

func _kinds(from: Dictionary) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for entry in from:
		kinds.append(entry)
	return kinds

## Enter the fight for `index` (contract §11.1 stage index, 1-based and never reset inside a run).
func start(index: int) -> void:
	if game == null or not is_instance_valid(game) or config == null:
		return
	# A fight started over a live one still closes the old cinematic, so a hold never outlives it.
	_end_cinematic()
	stage_index = maxi(index, 1)
	# Stage 1 is the first fight of a run, so it is also where a restart's counters start again —
	# unless a checkpoint retry has just restored this run's meetings.
	if stage_index <= 1 and not _met_restored:
		_reset_run_stats()
	_met_restored = false
	_seed_rng()
	def = BossDefs.fight_def(stage_index, config)
	var def_kind: StringName = def.get("kind", &"")
	kind = def_kind
	boss_name = String(def.get("name", ""))
	max_hp = maxi(int(def.get("hp", 1)), 1)
	hp = max_hp
	phase = 1
	finished = false
	_pending.clear()
	_beat = 0
	_last_mask = 0
	_last_tool_lane = -1
	_fight_timer = 0.0
	_since_tool = 0.0
	# Contract §11.14: the first meeting this run plays the full intro, every later one the short.
	var first_meeting := not _met.has(kind)
	_met[kind] = true
	_intro = _cinematic_length(float(config.boss_intro_seconds), float(config.boss_intro_short_seconds),
		first_meeting)
	_outro = 0.0
	_attack_timer = _attack_interval()
	_tool_timer = _tool_interval() * 0.5
	_clear_projectiles()
	_free_tools()
	_mount_boss()
	boss = boss_root
	_active = true
	# The entrance card goes out first (contract §11.4): boss_intro opens the intro, the cinematic
	# that plays it follows (§11.14), boss_spawned right behind them is the moment the boss is
	# visible and armed, and the attacks start once the _intro seconds boss_intro carries have run
	# down.
	_emit(&"boss_intro", [kind, boss_name, _intro])
	_begin_cinematic(CINEMATIC_INTRO_FULL if first_meeting else CINEMATIC_INTRO_SHORT, _intro)
	_emit(&"boss_spawned", [kind, hp])
	_emit(&"boss_health_changed", [hp, max_hp])
	# Contract §11.5: the visual hears every boss_health_changed, the opening full-HP one included.
	_visual_call(&"set_health", [hp, max_hp])

## One physics tick of the `boss` phase. Projectiles and tools move themselves; this drives the
## intro, the telegraph queue, the attack and tool clocks, the timeout and the outro.
func tick(delta: float) -> void:
	if game == null or not is_instance_valid(game) or not _active:
		return
	if _outro > 0.0:
		_outro -= delta
		if _outro <= 0.0:
			_end_cinematic()
			_finish()
		else:
			_push_cinematic_state()
		return
	if _intro > 0.0:
		_intro -= delta
		if _intro <= 0.0:
			_intro = 0.0
			_end_cinematic()
		else:
			_push_cinematic_state()
		return
	_fight_timer += delta
	_advance_telegraphs(delta)
	_advance_attacks(delta)
	_advance_tools(delta)
	if _fight_timer >= float(config.boss_timeout_seconds):
		_retreat()

## The run was lost mid-fight: everything goes, with no bonus and no fight signal (systems spec
## §10.1). A cinematic that was playing still closes with boss_cinematic_ended (contract §11.14), so
## every listener that froze for it lets go.
func abort() -> void:
	_end_cinematic()
	_active = false
	finished = false
	boss = null
	_intro = 0.0
	_outro = 0.0
	_pending.clear()
	_clear_projectiles()
	_free_tools()
	_free_visual()

## A tool reached the player (tool_pickup.collect). Damages the boss unless this phase resists the
## kind, in which case the hit still pays the pickup bonus and reports tool_collected(kind, 0).
func apply_tool(tool_kind: StringName) -> void:
	if game == null or not is_instance_valid(game) or not _active:
		return
	if hp <= 0 or _outro > 0.0:
		return
	var accepted := BossDefs.accepts(def, phase, tool_kind)
	var damage := ToolDefs.damage(tool_kind) if accepted else 0
	hp = maxi(hp - damage, 0)
	boss_damage_dealt += damage
	tools_used += 1
	_emit(&"tool_collected", [tool_kind, damage])
	if damage > 0:
		_visual_call(&"play_hit", [tool_kind, damage])
		_punch_camera()
	else:
		_visual_call(&"play_resist", [tool_kind])
	_add_bonus(int(config.tool_bonus), ScoreManager.REASON_TOOL)
	_emit(&"boss_health_changed", [hp, max_hp])
	_visual_call(&"set_health", [hp, max_hp])
	_advance_phase()
	if hp <= 0:
		_defeat()

# --- facade reads ---

## Contract §11.4 get_boss_info(). `pending_attacks` lists the telegraphs still in flight, newest
## last: {lane_mask, kind, remaining} plus the contract 2.4 {impact_mask, signature, committed,
## commit_remaining, attack}. Outside a fight — before the first one and from the moment
## the outro ends — every key reads empty, which is the same shape RunnerGame.get_boss_info()
## returns with no arena mounted, so a HUD never sees the last boss lingering on a cleared stage.
func get_info() -> Dictionary:
	if not _active:
		return empty_info()
	var pending: Array[Dictionary] = []
	for entry in _pending:
		var variant: StringName = entry.get("variant", &"")
		var attack: Dictionary = entry.get("attack", {})
		pending.append({
			"lane_mask": int(entry.get("mask", 0)),
			"kind": variant,
			"remaining": float(entry.get("remaining", 0.0)),
			"impact_mask": int(entry.get("impact_mask", entry.get("mask", 0))),
			"signature": attack.get("signature", BossAttacks.SIG_PLAIN),
			"committed": bool(entry.get("committed", true)),
			"commit_remaining": float(entry.get("commit_remaining", -1.0)),
			"attack": attack
		})
	return {
		"kind": kind,
		"name": boss_name,
		"hp": hp,
		"max_hp": max_hp,
		"phase": phase,
		# How many phases this fight has at all, so a HUD can draw "2 / 3" without a second lookup.
		"phase_count": int(def.get("phase_count", BossDefs.PHASE_COUNT)),
		"accepted_tools": BossDefs.accepted_tools(def, phase),
		"pending_attacks": pending
	}

## The same dictionary under the name RunnerGame.get_boss_info() delegates to (contract §11.4).
func get_boss_info() -> Dictionary:
	return get_info()

## The contract §11.4 boss block with every field empty. Static so a caller with no live fight (a
## HUD between stages, a test) can ask for the shape without an arena; RunnerGame.get_boss_info()
## builds the same dictionary by hand rather than preloading this script back.
static func empty_info() -> Dictionary:
	var no_tools: Array[StringName] = []
	var no_attacks: Array[Dictionary] = []
	return {
		"kind": &"",
		"name": "",
		"hp": 0,
		"max_hp": 0,
		"phase": 0,
		"phase_count": 0,
		"accepted_tools": no_tools,
		"pending_attacks": no_attacks
	}

## True between start() and the end of the outro (the intro counts as part of the fight).
func is_active() -> bool:
	return _active

## The same value as `finished`, for a caller that guards with has_method().
func is_finished() -> bool:
	return finished

## Live projectiles, for the DebugOverlay and the validators.
func projectile_count() -> int:
	return _live_children(projectiles_root).size()

## Live tools, same.
func tool_count() -> int:
	return _live_children(tools_root).size()

# --- cinematics (contract 2.6 §11.14) ---

## 0..1 through the cinematic playing now, 0 when none is.
func cinematic_progress() -> float:
	if cinematic_mode == &"" or cinematic_seconds <= 0.0:
		return 0.0
	return clampf(_cinematic_elapsed() / cinematic_seconds, 0.0, 1.0)

## True once an intro has played boss_cinematic_skip_after seconds, until it is skipped or is already
## inside its last boss_cinematic_skip_tail seconds. A defeat is never skippable (contract §11.14):
## the fight's jump mashing would otherwise eat the payoff.
func can_skip_cinematic() -> bool:
	if not _active or not _is_intro(cinematic_mode) or _cinematic_skipped or config == null:
		return false
	var elapsed := _cinematic_elapsed()
	return elapsed >= float(config.boss_cinematic_skip_after) and elapsed < cinematic_seconds - _skip_tail()

## Jump to the last boss_cinematic_skip_tail seconds, so the camera return still plays, and announce
## it with boss_cinematic_skipped. The intro window shrinks with it: the attacks follow the tail.
## Returns false when the cinematic cannot be skipped right now (always, for a defeat).
func skip_cinematic() -> bool:
	if not can_skip_cinematic():
		return false
	_cinematic_skipped = true
	_intro = _skip_tail()
	_emit(&"boss_cinematic_skipped", [cinematic_mode])
	# A zero tail has nothing left to play: the intro ends on the spot, since tick() would otherwise
	# step straight into the fight and never close it (contract §11.14: ended follows the tail).
	if _intro <= 0.0:
		_intro = 0.0
		_end_cinematic()
	else:
		_push_cinematic_state()
	return true

## The factor the visuals, effects and HUD multiply into their own delta (boss_time_factor; the
## engine time scale is never touched). 1 outside a defeat cinematic.
func time_factor() -> float:
	if config == null or not _is_defeat(cinematic_mode):
		return 1.0
	return time_factor_profile(_cinematic_elapsed(), float(config.boss_hitstop_seconds),
		float(config.boss_slowmo_seconds), float(config.boss_slowmo_factor))

## The defeat's time factor `elapsed` seconds in (contract §11.14): HIT_STOP_FACTOR for `hitstop`
## seconds, then `slowmo_factor` smoothstepped back to 1 over `slowmo` seconds, and 1 after. Pure,
## so a test or a preview can read the profile without a fight.
static func time_factor_profile(elapsed: float, hitstop: float, slowmo: float, slowmo_factor: float) -> float:
	if elapsed < 0.0:
		return 1.0
	var stop := maxf(hitstop, 0.0)
	if elapsed < stop:
		return HIT_STOP_FACTOR
	var span := maxf(slowmo, 0.0)
	var t := elapsed - stop
	if span <= 0.0 or t >= span:
		return 1.0
	return lerpf(clampf(slowmo_factor, HIT_STOP_FACTOR, 1.0), 1.0, smoothstep(0.0, 1.0, t / span))

## Seconds into the cinematic, measured off the countdown it rides (`_intro` or `_outro`).
func _cinematic_elapsed() -> float:
	if cinematic_mode == &"":
		return 0.0
	var remaining := _intro if _is_intro(cinematic_mode) else _outro
	return clampf(cinematic_seconds - remaining, 0.0, cinematic_seconds)

func _skip_tail() -> float:
	var tail := float(config.boss_cinematic_skip_tail) if config != null else 0.0
	return clampf(tail, 0.0, cinematic_seconds)

## The full length on a first meeting / first defeat, else min(short, full); never negative.
func _cinematic_length(full_seconds: float, short_seconds: float, first: bool) -> float:
	var full := maxf(full_seconds, 0.0)
	return full if first else minf(maxf(short_seconds, 0.0), full)

## Open a cinematic of `seconds` (contract §11.14). A zero-length one is not played at all: no
## boss_cinematic, no boss_cinematic_ended, and nothing for the stage machine to hold.
func _begin_cinematic(mode: StringName, seconds: float) -> void:
	# A kill landed inside the intro (a tool collected by hand) closes the intro before the defeat.
	_end_cinematic()
	if seconds <= 0.0:
		return
	cinematic_mode = mode
	cinematic_seconds = seconds
	_cinematic_skipped = false
	_emit(&"boss_cinematic", [kind, mode, seconds])
	_visual_call(&"play_cinematic", [mode, seconds])
	_push_cinematic_state()

## Close the cinematic, if one is playing, with boss_cinematic_ended. The visual hears progress 1.0
## and a time factor of 1.0 first, so its last pose is the end of the shot. Idempotent.
func _end_cinematic() -> void:
	if cinematic_mode == &"":
		return
	var mode := cinematic_mode
	cinematic_mode = &""
	cinematic_seconds = 0.0
	_cinematic_skipped = false
	_visual_call(&"set_cinematic_progress", [mode, 1.0])
	_visual_call(&"set_time_factor", [1.0])
	_emit(&"boss_cinematic_ended", [mode])

## The visual's per-tick cinematic feed (contract §11.5): where the cinematic is, then the factor for
## its ambient motion. Sent on the opening tick (progress 0), every tick it runs and after a skip —
## and never without a cinematic, so a retreat's outro feeds the visual nothing.
func _push_cinematic_state() -> void:
	if cinematic_mode == &"":
		return
	_visual_call(&"set_cinematic_progress", [cinematic_mode, cinematic_progress()])
	_visual_call(&"set_time_factor", [time_factor()])

static func _is_intro(mode: StringName) -> bool:
	return mode == CINEMATIC_INTRO_FULL or mode == CINEMATIC_INTRO_SHORT

static func _is_defeat(mode: StringName) -> bool:
	return mode == CINEMATIC_DEFEAT_FULL or mode == CINEMATIC_DEFEAT_SHORT

# --- attacks ---

## Count every telegraph down; a flaky one commits on the way, and the ones that reach zero fire
## this tick. Commits run oldest first, so boss_attack_committed follows the telegraph order.
func _advance_telegraphs(delta: float) -> void:
	for entry in _pending:
		if bool(entry.get("committed", true)):
			continue
		entry["commit_remaining"] = float(entry.get("commit_remaining", 0.0)) - delta
		if float(entry["commit_remaining"]) <= 0.0:
			_commit(entry, float(entry.get("remaining", 0.0)) - delta)
	for index in range(_pending.size() - 1, -1, -1):
		var entry := _pending[index]
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		if float(entry["remaining"]) > 0.0:
			continue
		_pending.remove_at(index)
		_fire(entry)

## A flaky telegraph stops alternating and shows the lanes it will really fire on (contract 2.4
## §11.4 boss_attack_committed); `seconds` is what is left of the telegraph.
func _commit(entry: Dictionary, seconds: float) -> void:
	var attack: Dictionary = entry.get("attack", {})
	var mask := int(attack.get("mask", entry.get("mask", 0)))
	var variant: StringName = entry.get("variant", &"orb")
	entry["committed"] = true
	entry["commit_remaining"] = 0.0
	entry["mask"] = mask
	var left := maxf(seconds, 0.0)
	_emit(&"boss_attack_committed", [mask, variant, left])
	_visual_call(&"play_commit", [mask, variant, left])

func _advance_attacks(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	_queue_beat()

## Telegraph the next beat of this phase's pattern. Patterns cycle a fixed beat list; a beat with a
## random draw never repeats the impact lanes it used last. boss_attacks.gd resolves the beat into
## its attacks (one, or one per head of a branching volley); each one is announced with
## boss_attack_planned (the full attack, contract 2.4) immediately before its boss_attack_telegraph.
func _queue_beat() -> void:
	var pattern := BossDefs.pattern_for(def, phase)
	_attack_timer = _attack_interval()
	if pattern.is_empty():
		return
	var beat: Dictionary = pattern[_beat % pattern.size()]
	_beat += 1
	var options := BossAttacks.beat_options(beat, def, phase, config)
	var pick := BossAttacks.pick_option(options, _last_mask, fight_rng, BossAttacks.draws_random(beat, options))
	if pick < 0:
		return
	var option: Array = options[pick]
	_last_mask = BossAttacks.option_key(option)
	for item in option:
		var attack: Dictionary = item
		var variant: StringName = attack.get("variant", &"orb")
		var mask := int(attack.get("telegraph_mask", 0))
		var seconds := float(attack.get("telegraph", _telegraph_seconds()))
		var commit_at := float(attack.get("commit_at", -1.0))
		_pending.append({
			"mask": mask,
			"variant": variant,
			"remaining": seconds,
			"attack": attack,
			"impact_mask": int(attack.get("impact_mask", mask)),
			"commit_remaining": commit_at,
			"committed": commit_at < 0.0
		})
		_emit(&"boss_attack_planned", [attack])
		_emit(&"boss_attack_telegraph", [mask, variant, seconds])
		_visual_call(&"play_telegraph", [mask, variant, seconds])

## The telegraph ran out: one projectile per shot of the attack, all fired from the boss. An entry
## without an attack (a bare test entry) fires the v2.0 straight shots on its mask.
func _fire(entry: Dictionary) -> void:
	var variant: StringName = entry.get("variant", &"orb")
	var attack: Dictionary = entry.get("attack", {})
	if attack.is_empty():
		attack = BossAttacks.plain_attack(int(entry.get("mask", 0)), variant, 0.0, _projectile_speed(), config)
	var speed := float(attack.get("speed", _projectile_speed()))
	var signature: StringName = attack.get("signature", BossAttacks.SIG_PLAIN)
	var fired := 0
	for item in attack.get("shots", []):
		var shot: Dictionary = item
		var projectile := _spawn_projectile(shot, signature)
		if projectile == null:
			continue
		fired += 1
		_emit(&"boss_projectile_fired", [projectile, int(shot.get("lanes", 0)), variant, speed])
	if fired > 0:
		_visual_call(&"play_attack", [variant])

## Split a lane mask into one group per projectile (boss_attacks.lane_groups): `orb` covers one
## lane, `wide` two adjacent ones, `low` / `high` the full width.
func _lane_groups(mask: int, variant: StringName) -> Array[int]:
	return BossAttacks.lane_groups(mask, variant)

## One projectile flying `shot` (a boss_attacks.gd motion). kind / variant / closing_speed /
## boss_kind / signature / motion are all set before add_child, so the visual sees them before
## on_spawned(); the root starts where the motion says it is at t = 0.
func _spawn_projectile(shot: Dictionary, signature: StringName = BossAttacks.SIG_PLAIN) -> Area3D:
	if projectiles_root == null or not is_instance_valid(projectiles_root):
		return null
	var scene := _packed(PROJECTILE_SCENE)
	if scene == null:
		return null
	var projectile := scene.instantiate() as Projectile
	if projectile == null:
		push_warning("Runner boss encounter: %s did not instantiate as a projectile.gd Area3D" % PROJECTILE_SCENE)
		return null
	projectile.kind = HazardDefs.PROJECTILE_KIND
	projectile.variant = StringName(shot.get("variant", &"orb"))
	projectile.closing_speed = float(shot.get("speed", _projectile_speed()))
	projectile.boss_kind = kind
	projectile.signature = signature
	# A straight shot carries no motion, so it flies (and reads) exactly like a v2.0 one.
	var keys: PackedVector2Array = shot.get("x_keys", PackedVector2Array())
	var moving := keys.size() > 1 or float(shot.get("drop_height", 0.0)) > 0.0
	projectile.motion = shot if moving else {}
	# Fired from the boss, projected down to the lane centres: the y range of the variant (contract
	# §11.6) is measured from the floor, so the root stays at y 0 (a falling slab starts lifted) and
	# the hitbox offset does the rest.
	projectile.position = Vector3(BossAttacks.x_at(shot, 0.0), BossAttacks.y_offset_at(shot, 0.0),
		float(shot.get("from_z", _boss_z())))
	projectiles_root.add_child(projectile)
	projectile.setup(game)
	return projectile

# --- tools ---

func _advance_tools(delta: float) -> void:
	_since_tool += delta
	_tool_timer -= delta
	var guarantee := float(config.boss_tool_guarantee_seconds)
	# The guarantee only fires when nothing is on its way: a fight never goes longer than this
	# without a tool in flight (contract §11.7).
	var overdue := guarantee > 0.0 and _since_tool >= guarantee and tool_count() == 0
	if _tool_timer > 0.0 and not overdue:
		return
	_spawn_tool()

## Both clocks are reset on every attempt, not only on a successful spawn: a draw that cannot place
## anything (no Tools mount, no scene, no kind left to roll) would otherwise come back on the very
## next tick and keep coming back. The guarantee is unchanged for a fight that can spawn at all —
## the reset stands in for the tool that was owed.
func _spawn_tool() -> void:
	_tool_timer = _tool_interval()
	_since_tool = 0.0
	if tools_root == null or not is_instance_valid(tools_root):
		return
	var scene := _packed(TOOL_SCENE)
	if scene == null:
		return
	var tool_kind := _pick_tool_kind()
	if tool_kind == &"":
		return
	var lane := _pick_tool_lane()
	var pickup := scene.instantiate() as ToolPickup
	if pickup == null:
		push_warning("Runner boss encounter: %s did not instantiate as a tool_pickup.gd Area3D" % TOOL_SCENE)
		return
	pickup.kind = tool_kind
	pickup.position = Vector3(_lane_x(lane), _tool_height(tool_kind), float(config.boss_tool_spawn_z))
	tools_root.add_child(pickup)
	pickup.setup(game)
	_last_tool_lane = lane

## A lane the player can actually cross into, never the same lane twice in a row (contract §11.7).
## "Clear" means no live projectile still on its way down the corridor covers the lane and no queued
## telegraph is about to (systems spec §10.3). The no-repeat rule wins: when it leaves only blocked
## lanes the draw takes the one that frees up first rather than dropping the tool.
func _pick_tool_lane() -> int:
	var blocked := _blocked_lane_mask()
	var clear_lanes: Array[int] = []
	var other_lanes: Array[int] = []
	for lane in LANE_COUNT:
		if lane == _last_tool_lane:
			continue
		other_lanes.append(lane)
		if (blocked & (1 << lane)) == 0:
			clear_lanes.append(lane)
	if not clear_lanes.is_empty():
		return clear_lanes[fight_rng.randi_range(0, clear_lanes.size() - 1)]
	if other_lanes.is_empty():
		return maxi(_last_tool_lane, 0)
	return _least_blocked_lane(other_lanes)

## Lanes a tool must not drop into: every lane a live projectile still covers, plus every lane a
## queued telegraph will. A full-width attack is answered with a jump or a roll rather than with a
## lane change, so — exactly as in autopilot.pending_lane_mask() — it rules out no lane at all.
func _blocked_lane_mask() -> int:
	var mask := 0
	for node in _live_children(projectiles_root):
		var projectile := node as Projectile
		if projectile == null or not projectile.is_blocking() or not _projectile_is_live(projectile):
			continue
		mask |= _lane_mask_of(projectile.impact_lane_mask())
	# A queued attack blocks the lanes it will hit, which for a split, a sweep or a shifting gap is
	# not the lane its telegraph starts on.
	for entry in _pending:
		mask |= _lane_mask_of(int(entry.get("impact_mask", entry.get("mask", 0))))
	return mask

## `mask` unless it covers the whole width, in which case it blocks nothing.
func _lane_mask_of(mask: int) -> int:
	var lanes := mask & BossDefs.LANE_ALL
	return 0 if lanes == BossDefs.LANE_ALL else lanes

## Still between the boss and the player as far as a tool lane is concerned: a shot stops ruling its
## lane out once it is boss_tool_lane_clearance metres past the player, which is the point the
## player can cross in behind it.
func _projectile_is_live(projectile: Projectile) -> bool:
	var clearance := absf(float(config.boss_tool_lane_clearance)) if config != null else 0.0
	return _track_z(projectile) < clearance

## The blocked lane whose shot is furthest along, i.e. the one that opens up first. A lane held by a
## telegraph alone has nothing in flight yet, so it stays blocked longest and sorts last.
func _least_blocked_lane(lanes: Array[int]) -> int:
	var best := lanes[0]
	var best_progress := -INF
	for lane in lanes:
		var progress := _lane_block_progress(lane)
		if progress > best_progress:
			best = lane
			best_progress = progress
	return best

## Track z of the furthest-along live projectile covering `lane`, or -INF when none does.
func _lane_block_progress(lane: int) -> float:
	var progress := -INF
	for node in _live_children(projectiles_root):
		var projectile := node as Projectile
		if projectile == null or not projectile.is_blocking() or not _projectile_is_live(projectile):
			continue
		if (_lane_mask_of(projectile.impact_lane_mask()) & (1 << lane)) == 0:
			continue
		progress = maxf(progress, _track_z(projectile))
	return progress

## Weighted over tool_defs; a phase that resists a kind keeps only (1 - boss_shield_tool_bias) of
## its weight, so a resisting phase mostly drops tools that actually work.
func _pick_tool_kind() -> StringName:
	var accepted := BossDefs.accepted_tools(def, phase)
	var bias := clampf(float(config.boss_shield_tool_bias), 0.0, 1.0)
	var kinds: Array[StringName] = []
	var weights := PackedFloat32Array()
	for entry in ToolDefs.kinds():
		var candidate: StringName = entry
		var weight := float(ToolDefs.weight(candidate))
		if not accepted.has(candidate):
			weight *= 1.0 - bias
		if weight <= 0.0:
			continue
		kinds.append(candidate)
		weights.append(weight)
	if kinds.is_empty():
		return &""
	var pick := fight_rng.rand_weighted(weights)
	if pick < 0 or pick >= kinds.size():
		pick = fight_rng.randi_range(0, kinds.size() - 1)
	return kinds[pick]

## Run row or jump row (contract §11.7 spawn y), from the same config heights the spawner uses.
func _tool_height(tool_kind: StringName) -> float:
	if config == null:
		return ToolDefs.spawn_y(tool_kind)
	if ToolDefs.uses_jump_height(tool_kind):
		return float(config.pickup_height_jump)
	return float(config.pickup_height_run)

# --- phases and the end of the fight ---

## Raise the phase once per threshold crossed, so three phases mean at most two signals per fight.
func _advance_phase() -> void:
	var target := _phase_for_hp()
	while phase < target:
		phase += 1
		# The new phase answers straight away rather than waiting out the old interval.
		_attack_timer = minf(_attack_timer, PHASE_CHANGE_ATTACK_DELAY)
		_emit(&"boss_phase_changed", [phase])
		_visual_call(&"set_phase", [phase])

## The phase the current HP ratio belongs to (contract §11.10 boss_phase_thresholds 1.0/0.66/0.33).
func _phase_for_hp() -> int:
	var thresholds := _thresholds()
	var ratio := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var result := 1
	for index in range(1, thresholds.size()):
		if ratio <= float(thresholds[index]):
			result = index + 1
	return clampi(result, 1, int(def.get("phase_count", BossDefs.PHASE_COUNT)))

## contract §11.10 boss_phase_thresholds, with the §11.10 default for an emptied config.
func _thresholds() -> Array[float]:
	if config != null:
		var rows: Array[float] = config.boss_phase_thresholds
		if not rows.is_empty():
			return rows
	return [1.0, 0.66, 0.33]

## The kill pays and announces itself on this tick, exactly as before the cinematics (contract
## §11.14 leaves scoring alone); the defeat cinematic follows and holds the outro for its length.
## The outro is armed first, so a boss_cinematic listener already reads progress 0 and the hit-stop.
func _defeat() -> void:
	var bonus := _kill_bonus()
	_add_bonus(bonus, ScoreManager.REASON_BOSS_KILL)
	bosses_defeated += 1
	_emit(&"boss_defeated", [kind, bonus])
	_visual_call(&"play_defeat", [])
	var first_defeat := not _defeated_kinds.has(kind)
	_defeated_kinds[kind] = true
	var seconds := _cinematic_length(float(config.boss_defeat_seconds),
		float(config.boss_defeat_short_seconds), first_defeat)
	_end_fight(seconds)
	if _active:
		_begin_cinematic(CINEMATIC_DEFEAT_FULL if first_defeat else CINEMATIC_DEFEAT_SHORT, seconds)

## The fight ran out of time: a part of the kill bonus, in proportion to the damage that landed.
func _retreat() -> void:
	var missing := 1.0 - (float(hp) / float(max_hp) if max_hp > 0 else 0.0)
	var ratio := float(config.boss_retreat_bonus_ratio)
	var bonus := int(round(float(_kill_bonus()) * ratio * clampf(missing, 0.0, 1.0)))
	_add_bonus(bonus, ScoreManager.REASON_BOSS_RETREAT)
	bosses_escaped += 1
	_emit(&"boss_retreated", [kind, bonus])
	_visual_call(&"play_retreat", [])
	_end_fight(float(config.boss_outro_seconds))

func _kill_bonus() -> int:
	return int(config.boss_kill_bonus_base) + int(config.boss_kill_bonus_per_stage) * (stage_index - 1)

## Both endings clear the arena and hold the fight open for `outro_seconds`: the defeat cinematic's
## length after a kill, boss_outro_seconds after a retreat (contract §11.14). The StageManager waits
## for `finished` rather than for the signal, so the visual gets its play_defeat / play_retreat time.
func _end_fight(outro_seconds: float) -> void:
	_pending.clear()
	_clear_projectiles()
	_free_tools()
	_attack_timer = 0.0
	_tool_timer = 0.0
	_intro = 0.0
	_outro = maxf(outro_seconds, 0.0)
	if _outro <= 0.0:
		_end_cinematic()
		_finish()

func _finish() -> void:
	_outro = 0.0
	_active = false
	boss = null
	_free_visual()
	finished = true

func _reset_run_stats() -> void:
	bosses_defeated = 0
	bosses_escaped = 0
	tools_used = 0
	boss_damage_dealt = 0
	_met.clear()
	_defeated_kinds.clear()

# --- the boss node ---

## Mount boss/visuals/<kind>_visual.tscn if the frontend ships one, else the graybox. The contract
## §11.5 base vars are set before on_spawned(), and the Boss node is placed first so a visual that
## reads its own transform sees the hover position.
func _mount_boss() -> void:
	_free_visual()
	if boss_root == null or not is_instance_valid(boss_root):
		return
	boss_root.position = Vector3(0.0, BOSS_CENTER_Y, _boss_z())
	var path := VISUAL_DIR + String(kind) + "_visual.tscn"
	if ResourceLoader.exists(path):
		var scene := _packed(path)
		if scene != null:
			var instance := scene.instantiate()
			if instance is Node3D:
				visual = instance
				boss_root.add_child(visual)
				_apply_visual_vars()
				if visual.has_method("on_spawned"):
					visual.on_spawned()
				_read_cinematic_focus()
				return
			if instance != null:
				push_warning("Runner boss visual at %s root is %s, expected Node3D; using graybox" % [path, instance.get_class()])
				instance.queue_free()
	_graybox = _build_graybox()
	visual = _graybox
	boss_root.add_child(visual)
	_read_cinematic_focus()

## The camera's aim for this fight (contract §11.5), taken at the rest pose on_spawned() leaves and
## before any cinematic cue: the visual's own cinematic_focus() when it has one (a Vector3), else the
## shared rest_focus() default, carried into the mount's space through the visual's transform.
func _read_cinematic_focus() -> void:
	cinematic_focus = Vector3.ZERO
	if not is_instance_valid(visual):
		return
	var local := BossVisualBase.rest_focus(visual)
	if visual.has_method("cinematic_focus"):
		var value: Variant = visual.call(&"cinematic_focus")
		if value is Vector3:
			local = value
	cinematic_focus = visual.transform * local

## The contract §11.5 base vars, set before on_spawned(). A visual that does not extend
## boss_visual_base.gd simply does not receive them.
func _apply_visual_vars() -> void:
	if not is_instance_valid(visual):
		return
	var values := {
		&"kind": kind,
		&"boss_name": boss_name,
		&"max_hp": max_hp,
		&"phase_count": int(def.get("phase_count", BossDefs.PHASE_COUNT)),
		&"hover_z": _boss_z(),
		&"sway_amplitude": float(config.boss_sway_amplitude),
		&"sway_period": float(config.boss_sway_period)
	}
	for key in values:
		if key in visual:
			visual.set(key, values[key])

## Tinted box of the systems spec §10.3 size with a Label3D name plate, so a graybox fight still
## says who is shooting.
func _build_graybox() -> Node3D:
	var root := Node3D.new()
	root.name = "Graybox"
	var mesh := MeshInstance3D.new()
	mesh.name = "Box"
	var box := BoxMesh.new()
	box.size = GRAYBOX_SIZE
	mesh.mesh = box
	# Lift the box so its bottom edge sits at the contract §11.5 floor instead of below it.
	mesh.position = Vector3(0.0, maxf(GRAYBOX_FLOOR_Y + GRAYBOX_SIZE.y * 0.5 - BOSS_CENTER_Y, 0.0), 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = BossDefs.color(kind)
	mesh.material_override = material
	root.add_child(mesh)
	var plate := Label3D.new()
	plate.name = "NamePlate"
	plate.text = boss_name
	plate.font_size = GRAYBOX_LABEL_SIZE
	plate.pixel_size = GRAYBOX_LABEL_PIXEL_SIZE
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.position = Vector3(0.0, GRAYBOX_LABEL_Y, 0.0)
	root.add_child(plate)
	return root

func _free_visual() -> void:
	if is_instance_valid(visual):
		var parent := visual.get_parent()
		if parent != null:
			parent.remove_child(visual)
		visual.queue_free()
	visual = null
	_graybox = null
	cinematic_focus = Vector3.ZERO

# --- arena housekeeping ---

## clear() first, so the projectiles leave runner_hazards in this frame and score no dodge.
func _clear_projectiles() -> void:
	for node in _live_children(projectiles_root):
		if node.has_method("clear"):
			node.call(&"clear")
		_detach(node)

## Tools live in runner_tools, which _track_dodges never scans, so nothing here can score a dodge;
## _detach() is what stops one from auto-firing at a boss that is already down.
func _free_tools() -> void:
	for node in _live_children(tools_root):
		_detach(node)

## Take `node` out of play. Both ends of a fight can be reached from an area_entered callback — a
## tool that auto-fires the killing blow lands in _end_fight() inside the physics query flush, and a
## catch does the same through abort() — and taking a CollisionObject out of the tree there is an
## engine error ("Removing a CollisionObject node during a physics callback is not allowed"). So the
## node is disarmed now and freed the deferred way, and it never leaves the tree by hand:
## queue_free() is already end-of-frame, and _live_children() skips anything queued, so
## projectile_count() / tool_count() still drop on this tick.
func _detach(node: Node) -> void:
	if node.is_queued_for_deletion():
		return
	_disarm(node)
	node.queue_free()

## Stop a node that is on its way out from touching the player in the frames before its free lands:
## a projectile has already left runner_hazards in clear(), but a tool has no clear() of its own, so
## both are marked consumed (collect() and hit_player() both refuse a consumed node) and have their
## hitbox switched off the only way a physics callback allows.
func _disarm(node: Node) -> void:
	if &"consumed" in node:
		node.set(&"consumed", true)
	var area := node as Area3D
	if area != null:
		area.set_deferred(&"monitoring", false)

func _live_children(root: Node3D) -> Array[Node]:
	var live: Array[Node] = []
	if root == null or not is_instance_valid(root):
		return live
	for child in root.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			live.append(child)
	return live

# --- facade plumbing ---

## Every facade emit goes through here: the arena never assumes RunnerGame carries a signal, so an
## older facade (or a test harness) simply hears nothing instead of crashing the fight.
func _emit(signal_name: StringName, args: Array) -> void:
	if game == null or not is_instance_valid(game) or not game.has_signal(signal_name):
		return
	game.callv(&"emit_signal", [signal_name] + args)

func _add_bonus(points: int, reason: StringName) -> void:
	if points == 0 or game == null or not is_instance_valid(game):
		return
	var score: Node = game.score_manager
	if score != null and is_instance_valid(score) and score.has_method("add_bonus"):
		score.add_bonus(points, reason)

## The facade owns the camera punch on a damaging tool (contract §11.4); on_tool_hit() is the v2
## hook for it. Until that lands, shake the rig directly so the feedback is never missing.
func _punch_camera() -> void:
	if game == null or not is_instance_valid(game):
		return
	if game.has_method("on_tool_hit"):
		game.call(&"on_tool_hit")
		return
	var rig: Node = game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method("shake"):
		rig.shake(CAMERA_SHAKE_ON_TOOL)

func _visual_call(method: StringName, args: Array) -> void:
	if not is_instance_valid(visual) or not visual.has_method(method):
		return
	visual.callv(method, args)

# --- config and RNG ---

func _telegraph_seconds() -> float:
	return BossDefs.telegraph_for(def, phase)

func _attack_interval() -> float:
	return BossDefs.attack_interval_for(def, phase)

func _tool_interval() -> float:
	return float(def.get("tool_interval", 2.0))

func _projectile_speed() -> float:
	return float(def.get("projectile_speed", 26.0))

func _boss_z() -> float:
	return float(config.boss_z) if config != null else 0.0

## Rig-local z of anything in the arena (systems spec §10.5), so a bent corridor can never skew a
## lane test. The facade owns the accessor; a standalone arena falls back to its own local z.
func _track_z(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if game != null and is_instance_valid(game) and game.has_method("track_z"):
		return float(game.track_z(node))
	return node.position.z

func _lane_x(lane: int) -> float:
	if config != null:
		return config.lane_x(lane)
	return (float(lane) - 1.0) * 2.0


## One seeding per fight, from the run seed, the fight salt and the stage index alone: a stage's
## lane and tool streams replay identically whether it is reached by a normal run or by a boss
## checkpoint retry (contract §11.13), since no earlier fight's draws carry into it.
func _seed_rng() -> void:
	var source := int(game.seed) if game != null and is_instance_valid(game) else 0
	fight_rng.seed = (source ^ RNG_SALT) + maxi(stage_index, 1) * RNG_STAGE_STEP

func _packed(path: String) -> PackedScene:
	if _scene_cache.has(path):
		var cached: PackedScene = _scene_cache[path]
		return cached
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	if scene == null:
		push_warning("Runner boss encounter: %s is missing or is not a PackedScene" % path)
	_scene_cache[path] = scene
	return scene
