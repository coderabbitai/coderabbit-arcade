extends Node3D
const Telegraph = preload("res://scenes/runner/boss/telegraph.tscn")
const Tracer = preload("res://scenes/runner/boss/tool_tracer.gd")
const Number = preload("res://scenes/runner/boss/damage_number.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var telegraphs: Array[Node3D] = []
var tracers: Array[Node3D] = []
var numbers: Array[Node3D] = []
var game: Node
var connections: Dictionary = {}
var cursor := 0
var number_cursor := 0
const MAX_ACTIVE_NUMBERS := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
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

func bind(value: Node) -> void:
	if game == value and not connections.is_empty(): return
	_disconnect()
	clear()
	game = value
	connections = {&"boss_intro": _intro, &"boss_attack_telegraph": _telegraph, &"tool_collected": _tool, &"boss_defeated": _end, &"boss_retreated": _end, &"caught": clear, &"run_started": _reset}
	for event: StringName in connections:
		if game.has_signal(event): game.connect(event, connections[event])
	if game.has_method("get_boss_info"):
		var info: Dictionary = game.get_boss_info()
		for attack: Dictionary in info.get("pending_attacks", []):
			_telegraph(int(attack.get("lane_mask", 0)), StringName(attack.get("kind", "orb")), float(attack.get("remaining", 0)))

func _disconnect() -> void:
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.has_signal(event) and game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	connections.clear()

func _telegraph(mask: int, kind: StringName, seconds: float) -> void:
	for lane in 3:
		if mask & (1 << lane): telegraphs[lane].start(lane, kind, seconds)

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

func _reset(_seed: int) -> void:
	clear()

func clear() -> void:
	for node in telegraphs + tracers + numbers: node.clear()
	cursor = 0
	number_cursor = 0

func _exit_tree() -> void:
	_disconnect()

func _intro(_kind: StringName, _name: String, seconds: float) -> void:
	# The visual is already mounted, but the facade mirrors boss at boss_spawned.
	# Resolve the documented mount for the earlier intro signal, then mock/v1 fallback.
	var boss := game.get_node_or_null("World/TurnRig/BossArena/Boss") as Node3D
	if boss == null: boss = game.get("boss") as Node3D
	if not is_instance_valid(boss): return
	for visual in boss.get_children():
		if visual.has_method("play_intro"): visual.play_intro(seconds)

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
