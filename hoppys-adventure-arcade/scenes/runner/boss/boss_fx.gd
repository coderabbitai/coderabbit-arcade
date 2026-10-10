extends Node3D
## Boss fight effects in arena space (contract §11.8): the DANGER lane telegraphs, tool tracers,
## damage numbers and, contract 2.4, the per-boss signature marks drawn on top of the telegraphs.
##
## Every telegraph becomes an attack record (boss_attack_planned carries the attack just before its
## boss_attack_telegraph). A record owns an entry in each lane slot it covers (telegraph.gd keeps
## several per lane, so a branching volley or an overlapping beat never overwrites another), and
## draws its signature mode into the one-draw SignatureMarks layer every frame:
##   Swarm   flaky: glitch tiles alternate between the candidates, then SNAP to the commit;
##           scatter: tiles down the middle, a fork at the split, the outer impact lanes after it.
##   Hydra   branching: one branch line per head grown in firing order, numbered by chevrons;
##           sweep: the diagonal path across the lanes; force_push: chevrons shoving down two lanes.
##   Monolith quake: an expanding ring and lane fissures; legacy_wall: fissures on the blocked
##           lanes with the gap and its shift target in MINT from the start; debris: floor shadows
##           that grow until impact.
## DANGER stays the base meaning (the lane slots); the accent is MATRIX / LILAC / ORANGE per boss.
## Everything is clock-driven from PAUSABLE _process deltas, and nothing is allocated per beat:
## records, lane entries and mark instances are all preallocated here.
const DefeatBurst = preload("res://scenes/runner/boss/defeat_burst.gd")
const Telegraph = preload("res://scenes/runner/boss/telegraph.tscn")
const Tracer = preload("res://scenes/runner/boss/tool_tracer.gd")
const Number = preload("res://scenes/runner/boss/damage_number.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Marks = preload("res://scenes/runner/boss/visuals/boss_telegraph_marks.gd")
const ProjectileArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
var explosions: DefeatBurst
var defeat_mode: StringName = &""
var _burst_index := 0
var _boss_model: Node3D
var telegraphs: Array[Node3D] = []
var tracers: Array[Node3D] = []
var numbers: Array[Node3D] = []
var game: Node
var connections: Dictionary = {}
var cursor := 0
var number_cursor := 0
const MAX_ACTIVE_NUMBERS := 3
## Attack records: enough for a three-head volley overlapping two more beats.
const MAX_RECORDS := 8
## Seconds a record's marks fade out after its telegraph ran out.
const TAIL := 0.3
const LANE_WIDTH := 2.0
## Art review r1: the committed flaky column's DANGER fill alpha (never below 0.5).
const COMMIT_FILL_ALPHA := 0.55
## Art review r1: the legacy wall's MINT gap lines, metres (>= 4 px at the boss from the chase camera).
const GAP_LINE_WIDTH := 0.24
var records: Array[Dictionary] = []
var marks: Marks
## Shared empties, so a plain beat or a missing key allocates nothing.
const NO_ATTACK := {}
const NO_LIST := []
var _next_attack: Dictionary = NO_ATTACK
var _has_next := false
var _record_id := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	explosions = DefeatBurst.new()
	add_child(explosions)
	for i in 3:
		var node := Telegraph.instantiate() as Node3D
		add_child(node)
		telegraphs.append(node)
	for i in 4:
		var node := Tracer.new()
		add_child(node)
		node.arrived.connect(_arrival)
		tracers.append(node)
	for i in 6:
		var node := Number.new()
		add_child(node)
		numbers.append(node)
	marks = Marks.new()
	add_child(marks)
	for i in MAX_RECORDS:
		records.append({"active": false, "id": -1, "attack": {}, "mask": 0, "kind": &"orb", "seconds": 1.0,
			"elapsed": 0.0, "flaky": false, "committed": true, "commit_mask": 0, "commit_age": -1.0})
	# The arena mounts with the run: build every signature projectile's shared resources now, so
	# no shot ever builds one on a gameplay frame.
	ProjectileArt.warm()

func bind(value: Node) -> void:
	if game == value and not connections.is_empty(): return
	_disconnect()
	clear()
	game = value
	connections = {&"boss_intro": _intro, &"boss_attack_planned": _planned, &"boss_attack_telegraph": _telegraph,
		&"boss_attack_committed": _committed, &"tool_collected": _tool, &"boss_defeated": _end,
		&"boss_retreated": _end, &"boss_cinematic": _cinematic, &"boss_cinematic_ended": _cinematic_ended, &"caught": clear, &"run_started": _reset}
	for event: StringName in connections:
		if game.has_signal(event): game.connect(event, connections[event])
	if game.has_method("get_boss_info"):
		var info: Dictionary = game.get_boss_info()
		for row: Dictionary in info.get("pending_attacks", []):
			_resume(row)

func _disconnect() -> void:
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.has_signal(event) and game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	connections.clear()

## A pending_attacks row (contract §11.4) from a fight already under way when bind() ran.
func _resume(row: Dictionary) -> void:
	var attack: Dictionary = row.get("attack", {})
	var remaining := float(row.get("remaining", 0))
	var total := maxf(float(attack.get("telegraph", remaining)), remaining)
	var committed := bool(row.get("committed", true))
	var mask := int(attack.get("telegraph_mask", row.get("lane_mask", 0))) if not committed or attack.is_empty() else int(row.get("lane_mask", 0))
	var record := _open(attack, mask, StringName(row.get("kind", "orb")), total, total - remaining)
	if record.flaky and committed:
		record.committed = true
		record.commit_mask = int(row.get("lane_mask", 0))
		record.commit_age = 1.0

## Contract 2.4: the full attack, on the same tick and immediately before its telegraph.
func _planned(attack: Dictionary) -> void:
	_next_attack = attack
	_has_next = true

func _telegraph(mask: int, kind: StringName, seconds: float) -> void:
	var attack: Dictionary = NO_ATTACK
	if _has_next and int(_next_attack.get("telegraph_mask", -1)) == mask and StringName(_next_attack.get("variant", &"")) == kind:
		attack = _next_attack
	_has_next = false
	_next_attack = NO_ATTACK
	_open(attack, mask, kind, seconds, 0.0)

## A flaky telegraph settled (commits arrive in telegraph order): the candidate that lost gives its
## lanes back, the committed lanes keep counting down.
func _committed(mask: int, kind: StringName, seconds: float) -> void:
	var record: Dictionary = {}
	for entry in records:
		if entry.active and entry.flaky and not entry.committed and (record.is_empty() or entry.id < record.id):
			record = entry
	var id := -1
	if not record.is_empty():
		record.committed = true
		record.commit_mask = mask
		record.commit_age = 0.0
		record.elapsed = maxf(record.elapsed, record.seconds - seconds)
		id = record.id
	for lane in 3:
		var slot := telegraphs[lane]
		if mask & (1 << lane):
			if id < 0 or not slot.has_entry(id): slot.start(lane, kind, seconds, id)
		elif id >= 0:
			slot.remove(id)

func _open(attack: Dictionary, mask: int, kind: StringName, seconds: float, elapsed: float) -> Dictionary:
	var record := records[0]
	for entry in records:
		if not entry.active:
			record = entry
			break
		if entry.seconds - entry.elapsed < record.seconds - record.elapsed: record = entry
	if record.active:
		for lane in 3: telegraphs[lane].remove(record.id)
	_record_id += 1
	record.active = true
	record.id = _record_id
	record.attack = attack
	record.mask = mask
	record.kind = kind
	record.seconds = maxf(seconds, 0.001)
	record.elapsed = clampf(elapsed, 0.0, record.seconds)
	record.flaky = StringName(attack.get("signature", &"")) == BossAttacks.SIG_FLAKY
	record.committed = not record.flaky
	record.commit_mask = mask
	record.commit_age = -1.0
	for lane in 3:
		if mask & (1 << lane): telegraphs[lane].start(lane, kind, seconds, record.id, record.elapsed)
	_draw_marks()
	return record

func _process(delta: float) -> void:
	if is_instance_valid(game) and game.get("paused") == true: return
	_sample_defeat()
	if is_instance_valid(game) and "boss_time_factor" in game: delta *= float(game.get("boss_time_factor"))
	var any := false
	for record in records:
		if not record.active: continue
		record.elapsed += delta
		if record.commit_age >= 0.0: record.commit_age += delta
		if record.elapsed > record.seconds + TAIL:
			record.active = false
			continue
		any = true
	_apply_gains()
	if any or marks.visible: _draw_marks()

## A flaky candidate that is not the one showing right now dims its lane (the red alternates with
## the glitch tiles); every other lane shows at full strength.
func _apply_gains() -> void:
	for lane in 3:
		var gain := -1.0
		for record in records:
			if record.active and record.elapsed <= record.seconds and record.mask & (1 << lane):
				gain = maxf(gain, lane_gain(record, lane))
		telegraphs[lane].gain = 1.0 if gain < 0.0 else gain

func lane_gain(record: Dictionary, lane: int) -> float:
	if not record.flaky or record.committed: return 1.0
	return 1.0 if showing_mask(record) & (1 << lane) else 0.18

## The candidate mask a flaky record is showing at its current elapsed time.
func showing_mask(record: Dictionary) -> int:
	var candidates: Array = record.attack.get("candidates", NO_LIST)
	if candidates.is_empty(): return record.mask
	var swap := maxf(float(record.attack.get("swap_seconds", 0.15)), 0.02)
	return int(candidates[int(floor(record.elapsed / swap)) % candidates.size()])

func _tool(kind: StringName, damage: int) -> void:
	if not is_instance_valid(game): return
	var player := game.get("player") as Node3D
	var boss := game.get("boss") as Node3D
	if not is_instance_valid(player) or not is_instance_valid(boss): return
	var destination := boss.global_position
	# Follow the self-swaying visual, without requiring a backend implementation detail.
	for child in boss.get_children():
		if child is Node3D and child.has_method("play_hit"):
			destination = child.global_position
			break
	tracers[cursor].fire(to_local(player.global_position + Vector3(0, 1.1, 0)), to_local(destination), kind, damage)
	cursor = (cursor + 1) % tracers.size()

func _arrival(kind: StringName, damage: int, point: Vector3) -> void:
	numbers[number_cursor].start(point, damage, Palette.ORANGE if kind == &"lint_rule" else Palette.MATRIX, sin(number_cursor * 2.4) * 0.35)
	number_cursor = (number_cursor + 1) % numbers.size()

func _end(_kind: StringName, _bonus: int) -> void:
	# Keep the killing tracer alive through the backend outro.
	for node in telegraphs: node.clear()
	_clear_records()

func _reset(_seed: int) -> void:
	clear()

func clear() -> void:
	_cinematic_ended(&"")
	for node in telegraphs + tracers + numbers: node.clear()
	cursor = 0
	number_cursor = 0
	_clear_records()

func _clear_records() -> void:
	for record in records: record.active = false
	_has_next = false
	_next_attack = NO_ATTACK
	if marks != null: marks.clear()

func _exit_tree() -> void:
	_disconnect()

func _intro(_kind: StringName, _name: String, _seconds: float) -> void:
	# The encounter now calls play_cinematic itself, including progress 0. Do not restart it.
	pass

func _cinematic(kind: StringName, mode: StringName, _seconds: float) -> void:
	_cinematic_ended(&"")
	if mode not in [&"defeat_full", &"defeat_short"]: return
	defeat_mode = mode
	explosions.accent = accent_for(kind)
	var boss := game.get_node_or_null("World/TurnRig/BossArena/Boss") as Node3D
	if boss == null and "boss" in game: boss = game.get("boss") as Node3D
	if boss != null:
		for node in boss.find_children("*", "Node3D", true, false):
			if node.has_method("socket"):
				_boss_model = node
				break
		for i in DefeatBurst.BEATS.size(): explosions.origins[i] = explosions.to_local(boss.global_position)
	_sample_defeat()

func _sample_defeat() -> void:
	if defeat_mode == &"" or not is_instance_valid(game): return
	var p := clampf(float(game.get("boss_cinematic_progress")), 0, 1)
	while _burst_index < DefeatBurst.BEATS.size() and p >= float(DefeatBurst.BEATS[_burst_index]):
		if is_instance_valid(_boss_model):
			var socket: Node3D = _boss_model.socket("fx_core" if _burst_index == 6 else "fx_%d" % _burst_index)
			if socket != null: explosions.origins[_burst_index] = explosions.to_local(socket.global_position)
		if "camera_rig" in game:
			var rig: Node = game.get("camera_rig")
			if is_instance_valid(rig) and rig.has_method("shake"): rig.shake(0.24 if _burst_index == 6 else 0.12)
		_burst_index += 1
	explosions.sample(p)

func _cinematic_ended(_mode: StringName) -> void:
	defeat_mode = &""
	_burst_index = 0
	_boss_model = null
	if explosions != null: explosions.clear()

func limit_numbers(incoming: Node3D) -> void:
	# Keep six reusable slots for the established smoke contract; only three draw.
	var active: Array[Node3D] = []
	for node in numbers:
		if node != incoming and node.active: active.append(node)
	while active.size() >= MAX_ACTIVE_NUMBERS:
		var oldest := active[0]
		for node in active:
			if node.age > oldest.age: oldest = node
		oldest.clear()
		active.erase(oldest)

# --- signature marks ---

static func accent_for(boss_kind: StringName) -> Color:
	match boss_kind:
		&"flaky_test_swarm": return Palette.MATRIX
		&"merge_conflict_hydra": return Palette.LILAC
		&"legacy_monolith": return Palette.ORANGE
	return Color(0, 0, 0, 0)

static func lane_x(lane: int) -> float:
	return (lane - 1) * LANE_WIDTH

static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)

func _draw_marks() -> void:
	if marks == null: return
	marks.begin()
	for record in records:
		if record.active: draw_record(record)
	marks.finish()

## The signature mode of one record, into the marks layer (public for tests and captures).
func draw_record(record: Dictionary) -> void:
	var attack: Dictionary = record.attack
	var accent := accent_for(StringName(attack.get("boss_kind", &"")))
	if accent.a <= 0.0: return
	var fade: float = minf(record.elapsed / 0.12, 1.0)
	if record.elapsed > record.seconds: fade *= clampf(1.0 - (record.elapsed - record.seconds) / TAIL, 0.0, 1.0)
	var progress: float = clampf(record.elapsed / record.seconds, 0.0, 1.0)
	var from_z := float(attack.get("from_z", -14.0))
	match StringName(attack.get("signature", &"")):
		BossAttacks.SIG_FLAKY: _flaky(record, from_z, fade)
		BossAttacks.SIG_SCATTER: _scatter(record, from_z, fade, progress)
		BossAttacks.SIG_BRANCHING: _branching(record, from_z, fade, accent)
		BossAttacks.SIG_SWEEP: _sweep(record, from_z, fade, accent)
		BossAttacks.SIG_FORCE_PUSH: _force_push(record, from_z, fade, accent)
		BossAttacks.SIG_QUAKE: _quake(record, from_z, fade, progress, accent)
		BossAttacks.SIG_LEGACY_WALL: _legacy_wall(record, from_z, fade, accent)
		BossAttacks.SIG_DEBRIS: _debris(record, from_z, fade, progress, accent)
		_: _plain(record, from_z, fade, accent)

## A plain beat from a boss: its accent edges the DANGER lanes.
func _plain(record: Dictionary, from_z: float, fade: float, accent: Color) -> void:
	for lane in 3:
		if not record.mask & (1 << lane): continue
		for side_index in 2:
			var side := side_index * 2.0 - 1.0
			marks.segment(Vector2(lane_x(lane) + side * 0.9, from_z + 1.0), Vector2(lane_x(lane) + side * 0.9, 0.0), 0.07, Color(accent, 0.5 * fade))

func _tile_column(lane: int, from_z: float, step: float, alpha: float, jitter: float, size: float, glitch: bool) -> void:
	for k in 7:
		var z := from_z + 1.5 + k * 1.75
		var seed := step * 1.3 + k * 7.1 + lane * 13.7
		if glitch and _hash(seed) < 0.14: continue
		# DANGER tiles with a MATRIX glitch now and then: a candidate is a threat, never a pickup.
		var color := Palette.MATRIX if glitch and _hash(seed + 3.3) > 0.72 else Palette.DANGER
		var x := lane_x(lane) + (_hash(seed + 1.1) - 0.5) * jitter
		marks.add(x, z, size, size, 0.0, Color(color, alpha))

## Swarm flaky: two candidate columns alternate at the swap rate, then SNAP into the commit.
func _flaky(record: Dictionary, from_z: float, fade: float) -> void:
	var step: float = floorf(record.elapsed / 0.08)
	if not record.committed:
		var showing := showing_mask(record)
		for lane in 3:
			if not record.mask & (1 << lane): continue
			var shown := bool(showing & (1 << lane))
			_tile_column(lane, from_z, step, (0.75 if shown else 0.1) * fade, 0.5, 0.62, true)
		return
	var snap: float = clampf(record.commit_age / 0.12, 0.0, 1.0)
	var flash: float = 1.0 if record.commit_age < 0.12 else 0.55
	for lane in 3:
		if not record.mask & (1 << lane) and not record.commit_mask & (1 << lane): continue
		if record.commit_mask & (1 << lane):
			# Tiles lock into one solid DANGER column (alpha >= COMMIT_FILL_ALPHA, so the committed
			# lane can never read as a safe one) and its edges light up; one MATRIX seam per tile
			# is all that is left of the glitch.
			for k in 7:
				var z := from_z + 1.5 + k * 1.75
				# A steady fill: additive DANGER at full alpha over the red lane washes out to pink.
				marks.add(lane_x(lane), z, lerpf(0.62, 1.5, snap), lerpf(0.62, 1.7, snap), 0.0, Color(Palette.DANGER, COMMIT_FILL_ALPHA * fade))
				marks.add(lane_x(lane), z + 0.9, lerpf(0.3, 1.2, snap), 0.07, 0.0, Color(Palette.MATRIX, 0.5 * fade))
			for side_index in 2:
				var side := side_index * 2.0 - 1.0
				marks.segment(Vector2(lane_x(lane) + side * 0.92, from_z + 0.8), Vector2(lane_x(lane) + side * 0.92, 0.0), 0.14, Color(Palette.DANGER, flash * fade))
		else:
			# The losing candidate scatters out and is gone within 0.15 s.
			var gone: float = clampf(record.commit_age / 0.15, 0.0, 1.0)
			if gone < 1.0: _tile_column(lane, from_z, step, 0.5 * (1.0 - gone) * fade, 0.5 + gone * 2.0, 0.62 * (1.0 - gone), true)

## Swarm scatter: glitch tiles down the middle to the split, a fork, then the outer impact lanes.
func _scatter(record: Dictionary, from_z: float, fade: float, progress: float) -> void:
	var attack: Dictionary = record.attack
	var speed := float(attack.get("speed", 13.0))
	var split_z := minf(from_z + speed * float(attack.get("split_at", 0.3)), -1.0)
	var fork_z := minf(split_z + speed * BossAttacks.SPLIT_SECONDS * 2.0, -0.5)
	var step: float = floorf(record.elapsed / 0.08)
	var z := from_z + 1.2
	var k := 0
	while z < split_z - 0.4:
		if _hash(step + k * 3.7) > 0.12: marks.add((_hash(step * 2.0 + k) - 0.5) * 0.3, z, 0.5, 0.5, 0.0, Color(Palette.DANGER, 0.7 * fade))
		z += 0.9
		k += 1
	marks.diamond(0.0, split_z, 0.8, Color(Palette.MATRIX, fade))
	for side_index in 2:
		var side := side_index * 2.0 - 1.0
		marks.segment(Vector2(0.0, split_z), Vector2(side * LANE_WIDTH, fork_z), 0.22, Color(Palette.MATRIX, 0.85 * fade))
		marks.segment(Vector2(side * LANE_WIDTH, fork_z), Vector2(side * LANE_WIDTH, 0.0), 1.3, Color(Palette.DANGER, lerpf(0.12, 0.32, progress) * fade))
		for edge_index in 2:
			var edge := edge_index * 2.0 - 1.0
			marks.segment(Vector2(side * LANE_WIDTH + edge * 0.9, fork_z), Vector2(side * LANE_WIDTH + edge * 0.9, 0.0), 0.07, Color(Palette.MATRIX, 0.6 * fade))

## Hydra branching: this head's branch grows out of the trunk in firing order, runs down its lane,
## and head+1 chevrons number it.
func _branching(record: Dictionary, from_z: float, fade: float, accent: Color) -> void:
	var attack: Dictionary = record.attack
	var head := int(attack.get("head", 0))
	var heads := maxi(int(attack.get("heads", 1)), 1)
	var lane := 1
	for i in 3:
		if record.mask & (1 << i): lane = i
	var start := Vector2((head - (heads - 1) * 0.5) * 0.45, from_z + 1.2)
	var node := Vector2(lane_x(lane), from_z + 5.0)
	var local: float = record.elapsed - head * 0.14
	var grow: float = clampf(local / 0.3, 0.0, 1.0)
	if grow <= 0.0:
		marks.diamond(start.x, start.y, 0.45, Color(accent, 0.5 * fade))
		return
	marks.segment(start, start.lerp(node, grow), 0.16, Color(accent, 0.85 * fade))
	marks.diamond(start.x, start.y, 0.45, Color(accent, 0.9 * fade))
	if grow < 1.0: return
	var fill: float = clampf((local - 0.3) / maxf(record.seconds - 0.3 - head * 0.14, 0.1), 0.0, 1.0)
	var fire: float = 1.0 if record.seconds - record.elapsed < 0.12 else 0.0
	marks.diamond(node.x, node.y, 0.7 + 0.25 * fire, Color(accent, fade))
	marks.segment(node, Vector2(node.x, lerpf(node.y, 0.0, fill)), 0.12, Color(accent, 0.8 * fade))
	for n in head + 1:
		marks.diamond(node.x, -2.2 - n * 0.75, 0.4, Color(accent, 0.9 * fade))

## Hydra sweep: flowing dashes along the real path, diagonal across the lanes to the sweep end,
## then straight down the end lane.
func _sweep(record: Dictionary, from_z: float, fade: float, accent: Color) -> void:
	var attack: Dictionary = record.attack
	var speed := float(attack.get("speed", 15.0))
	var a := Vector2(lane_x(int(attack.get("sweep_from", 0))), from_z + 0.8)
	var b := Vector2(lane_x(int(attack.get("sweep_to", 2))), minf(from_z + speed * float(attack.get("sweep_end", 0.5)), -1.0))
	var c := Vector2(b.x, 0.0)
	var first := a.distance_to(b)
	var total := first + b.distance_to(c)
	var spacing := total / 20.0
	for i in 20:
		var s: float = fposmod(i * spacing + record.elapsed * 5.0, total)
		var p := a.lerp(b, s / first) if s < first else b.lerp(c, (s - first) / maxf(total - first, 0.001))
		var d := (b - a).normalized() if s < first else Vector2(0, 1)
		var wiggle: Vector2 = Vector2(d.y, -d.x) * sin(s * 2.2 - record.elapsed * 9.0) * 0.18
		marks.add(p.x + wiggle.x, p.y + wiggle.y, 0.34, 0.5, atan2(d.x, d.y), Color(accent, 0.8 * fade))
	marks.diamond(a.x, a.y, 0.6, Color(accent, fade))
	var back := (a - b).normalized()
	for side_index in 2:
		var side := side_index * 2.0 - 1.0
		var arm := back.rotated(side * 0.6) * 0.8
		marks.segment(b, b + arm, 0.16, Color(accent, fade))

## Hydra force push: chevrons shoved down the two lanes, a merge bar pulsing at the boss.
func _force_push(record: Dictionary, from_z: float, fade: float, accent: Color) -> void:
	var total := 0.0
	var count := 0
	for lane in 3:
		if record.mask & (1 << lane):
			total += lane_x(lane)
			count += 1
	var cx := total / maxi(count, 1)
	var pulse: float = 0.6 + 0.4 * absf(sin(record.elapsed * 10.0))
	marks.segment(Vector2(cx - 1.8, from_z + 0.8), Vector2(cx + 1.8, from_z + 0.8), 0.3, Color(accent, pulse * fade))
	for k in 5:
		var z: float = from_z + 1.5 + fposmod(k * 2.6 + record.elapsed * 7.0, 13.0)
		for side_index in 2:
			var side := side_index * 2.0 - 1.0
			marks.segment(Vector2(cx + side * 1.4, z - 0.7), Vector2(cx, z), 0.22, Color(accent, 0.75 * fade))

## A jagged ORANGE fissure down a lane between two track z values.
func _fissure(lane: int, z0: float, z1: float, color: Color) -> void:
	if z1 - z0 < 0.2: return
	var steps := maxi(int((z1 - z0) / 1.8), 1)
	var previous := Vector2(lane_x(lane), z0)
	for i in steps:
		var z := lerpf(z0, z1, float(i + 1) / steps)
		var next := Vector2(lane_x(lane) + (_hash(lane * 5.1 + i * 2.3) - 0.5) * 0.8, z)
		marks.segment(previous, next, 0.11, color)
		previous = next

## Monolith quake: an ORANGE ring expanding from the boss's floor and fissures racing the lanes.
func _quake(record: Dictionary, from_z: float, fade: float, progress: float, accent: Color) -> void:
	for ring in 2:
		var radius := lerpf(1.2, 9.0, progress) * (1.0 if ring == 0 else 0.66)
		var alpha := (0.85 if ring == 0 else 0.45) * fade
		for i in 36:
			var a0 := TAU * i / 36.0
			var a1 := TAU * (i + 1) / 36.0
			var p0 := Vector2(sin(a0), cos(a0)) * radius + Vector2(0, from_z)
			var p1 := Vector2(sin(a1), cos(a1)) * radius + Vector2(0, from_z)
			if absf(p0.x) > 3.9 or absf(p1.x) > 3.9 or p0.y > 0.8 or p1.y > 0.8: continue
			marks.segment(p0, p1, 0.22, Color(accent, alpha))
	for lane in 3:
		_fissure(lane, from_z + 1.0, lerpf(from_z + 1.0, -0.5, minf(progress * 1.3, 1.0)), Color(accent, 0.7 * fade))

## Monolith legacy wall: fissures where the slabs stand, the gap in MINT, and the shift to the
## lane next to it drawn as an arrow at the z where it happens, from the first frame.
func _legacy_wall(record: Dictionary, from_z: float, fade: float, accent: Color) -> void:
	var attack: Dictionary = record.attack
	var speed := float(attack.get("speed", 12.0))
	var gap_from := int(attack.get("gap_from", 0))
	var gap_to := int(attack.get("gap_to", 1))
	var shift_z := minf(from_z + speed * float(attack.get("shift_at", 0.3)), -2.0)
	var shift_end := minf(shift_z + speed * BossAttacks.SHIFT_SECONDS * maxi(absi(gap_to - gap_from), 1), -1.0)
	var safe: Color = Color(Palette.MINT, (0.6 + 0.3 * absf(sin(record.elapsed * 8.0))) * fade)
	for lane in 3:
		if lane == gap_from:
			_fissure(lane, shift_end, 0.0, Color(accent, 0.7 * fade))
		elif lane == gap_to:
			_fissure(lane, from_z + 1.0, shift_z, Color(accent, 0.7 * fade))
		else:
			_fissure(lane, from_z + 1.0, 0.0, Color(accent, 0.7 * fade))
	# GAP_LINE_WIDTH keeps the MINT gap lines >= 4 px wide even at the boss end of the lane.
	for side_index in 2:
		var side := side_index * 2.0 - 1.0
		marks.segment(Vector2(lane_x(gap_from) + side * 0.9, from_z + 1.0), Vector2(lane_x(gap_from) + side * 0.9, shift_z), GAP_LINE_WIDTH, safe)
		marks.segment(Vector2(lane_x(gap_to) + side * 0.9, shift_end), Vector2(lane_x(gap_to) + side * 0.9, 0.0), GAP_LINE_WIDTH, safe)
	var tail := Vector2(lane_x(gap_from), shift_z)
	var tip := Vector2(lane_x(gap_to), shift_end)
	marks.segment(tail, tip, 0.32, safe)
	var back := (tail - tip).normalized()
	for side_index in 2:
		var side := side_index * 2.0 - 1.0
		marks.segment(tip, tip + back.rotated(side * 0.55) * 0.9, 0.28, safe)

## Monolith debris: one shadow per slab at the spot it lands, growing until the telegraph fires,
## with a dashed drop line from the boss.
func _debris(record: Dictionary, from_z: float, fade: float, progress: float, accent: Color) -> void:
	var attack: Dictionary = record.attack
	var land_z := minf(from_z + float(attack.get("speed", 16.5)) * float(attack.get("land_at", 0.2)), -1.0)
	var radius := lerpf(0.35, 0.85, progress * progress)
	for shot: Dictionary in attack.get("shots", NO_LIST):
		var keys: PackedVector2Array = shot.get("x_keys", PackedVector2Array())
		var x := keys[0].y if not keys.is_empty() else 0.0
		marks.add(x, land_z, radius * 1.6, radius * 1.3, 0.0, Color(accent, 0.28 * fade))
		for i in 14:
			var a0 := TAU * i / 14.0
			var a1 := TAU * (i + 1) / 14.0
			marks.segment(Vector2(x + sin(a0) * radius, land_z + cos(a0) * radius * 0.8), Vector2(x + sin(a1) * radius, land_z + cos(a1) * radius * 0.8), 0.09, Color(accent, 0.9 * fade))
		for n in 5:
			var z := lerpf(from_z + 1.0, land_z - radius, (n + 0.5) / 5.0)
			marks.add(x, z, 0.12, 0.5, 0.0, Color(accent, 0.4 * fade))
