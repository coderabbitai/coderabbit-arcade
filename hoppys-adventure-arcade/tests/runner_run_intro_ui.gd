extends SceneTree
## Runner intro presentation (plan S5): ui/run_intro, data/run_intro_shots, post_fx letterbox.
## Drives the UI only through ui/dev/mock_run_intro_game.gd, so no runner_game.gd is compiled.
## Run with --path hoppys-adventure-arcade --script res://tests/runner_run_intro_ui.gd.
##
## Inspects public presentation fields directly; no production test-only hooks.

const UI_SCENE := "res://scenes/runner/ui/run_intro.tscn"
const MOCK := "res://scenes/runner/ui/dev/mock_run_intro_game.gd"
const SHOTS := "res://scenes/runner/data/run_intro_shots.gd"
const POST_SCENE := "res://scenes/runner/ui/post_fx.tscn"
const BOSS_UI_SCENE := "res://scenes/runner/ui/boss_cinematic.tscn"
const TICK := 1.0 / 60.0
const FULL_LENGTH := 6.0
const SHORT_LENGTH := 2.2
const SKIP_AFTER := 0.3
const SKIP_TAIL := 0.4
const FULL_BEATS := [[1.0, "TITLE"], [3.0, "3"], [3.8, "2"], [4.6, "1"], [5.4, "GO!"]]
const SHORT_BEATS := [[1.0, "READY"], [1.6, "GO!"]]
const INTRO_SIGNALS: Array[StringName] = [&"run_intro", &"run_intro_beat", &"run_intro_skipped", &"run_intro_ended"]

## Facade stand-in for the beat-timing checks: just the signals and mirrors the overlay reads.
class BeatClock extends Node:
	signal run_intro(mode: StringName, seconds: float)
	signal run_intro_beat(index: int, label: String)
	signal run_intro_skipped
	signal run_intro_ended
	signal paused_changed(value: bool)
	var run_intro_mode: StringName = &""
	var run_intro_progress := 0.0
	var paused := false
	func can_skip_run_intro() -> bool:
		return false

## Restores the SceneTree pause on every exit path: explicit restore() on the normal path, and
## NOTIFICATION_PREDELETE when a runtime error aborts the function that owns the guard.
class PauseGuard extends RefCounted:
	var tree: SceneTree
	var prior := false
	func _init(owner: SceneTree) -> void:
		tree = owner
		prior = owner.paused
	func restore() -> void:
		if tree != null:
			tree.paused = prior
			tree = null
	func _notification(what: int) -> void:
		# Inline: self methods are no longer callable during PREDELETE.
		if what == NOTIFICATION_PREDELETE and tree != null:
			tree.paused = prior

var failures := 0
var checks := 0
var mock_script: GDScript
var junk: Array[Node] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER RUN INTRO UI: " + message)

func note(message: String) -> void:
	print("RUNNER RUN INTRO UI: " + message)

func run() -> void:
	note("start")
	while not root.is_node_ready():
		await process_frame
	for path in [UI_SCENE, MOCK, SHOTS, POST_SCENE]:
		if not ResourceLoader.exists(path):
			check(false, "%s is missing" % path)
	if failures > 0:
		await finish()
		return
	mock_script = load(MOCK) as GDScript
	await run_shots()
	await run_card_and_beats(&"full", FULL_LENGTH, FULL_BEATS)
	await run_card_and_beats(&"short", SHORT_LENGTH, SHORT_BEATS)
	await run_skip_guard()
	await run_skip_cleanup()
	await run_skip_go_fade()
	await run_skip_short_tail()
	await run_late_skip_rejected()
	await run_end_cleanup()
	await run_rebind()
	await run_pause()
	await run_beat_timing()
	await run_letterbox()
	await run_boss_regressions()
	await finish()

func finish() -> void:
	paused = false
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	for node in junk:
		if is_instance_valid(node):
			node.free()
	# AudioStreamPlayer.stop queues playback disposal on the audio thread. Match the
	# existing boss suite drain before quitting so its autoload cannot outlive the tree.
	await create_timer(0.3).timeout
	await process_frame
	note("%d checks, %d failures" % [checks, failures])
	paused = false
	quit(1 if failures > 0 else 0)

## -- helpers ---------------------------------------------------------------------------------

func make_pair() -> Dictionary:
	var game := mock_script.new() as Node
	root.add_child(game)
	junk.append(game)
	var ui := (load(UI_SCENE) as PackedScene).instantiate()
	root.add_child(ui)
	junk.append(ui)
	ui.bind(game)
	return {"game": game, "ui": ui}

func drop(pair: Dictionary) -> void:
	for key in ["ui", "game"]:
		var node: Node = pair[key]
		junk.erase(node)
		if is_instance_valid(node):
			root.remove_child(node)
			node.free()

## Hand-driven 1/60 ticks of mock intro time, then one rendered frame.
func advance_seconds(game: Node, seconds: float) -> void:
	var steps := int(round(seconds / TICK))
	for i in steps:
		game.advance_intro(TICK)
	await process_frame

## -- UI field readers (run_intro.gd exposes plain fields; no test-only hooks) ------------------

func active(ui: Node) -> bool:
	return ui.mode != &"" and ui.root.visible

func card_text(ui: Node) -> String:
	return ui.title.text if ui.title_group.visible and ui.title_group.modulate.a > 0.01 else ""

func count_text(ui: Node) -> String:
	return ui.count_label.text if ui.countdown.visible and ui.countdown.modulate.a > 0.01 else ""

func skip_visible(ui: Node) -> bool:
	return ui.skip_prompt.visible and ui.skip_button.visible

func anim(ui: Node) -> Dictionary:
	return {
		"title_scale": ui.title_group.scale, "title_mod": ui.title_group.modulate,
		"count_scale": ui.countdown.scale, "count_mod": ui.countdown.modulate,
		"header": ui.header.modulate, "footer": ui.footer.modulate,
		"flash": ui.flash.color, "burst": ui.burst.age,
	}

## -- shots -----------------------------------------------------------------------------------

func run_shots() -> void:
	var shots: Dictionary = (load(SHOTS) as GDScript).get_script_constant_map().get("SHOTS", {})
	check(shots is Dictionary, "SHOTS is a Dictionary")
	if not (shots is Dictionary):
		return
	for key in [&"full", &"short"]:
		check(shots.has(key), "SHOTS has a %s table" % key)
		var entry: Dictionary = shots.get(key, {})
		check(float(entry.get("cut", -1.0)) >= 0.0 and float(entry.get("ret", 2.0)) <= 1.0, "%s has valid cut/ret" % key)
		var rows: Array = entry.get("keys", [])
		check(rows.size() >= 2, "%s table has at least two rows" % key)
		var previous := -1.0
		for row in rows:
			check(row is Array and row.size() == 6, "%s row is [p,distance,height,orbit,fov,look_bias]" % key)
			if not (row is Array) or row.size() != 6:
				continue
			for value in row:
				check(typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)), "%s row values are finite numbers" % key)
			check(float(row[0]) > previous, "%s progress strictly increases (%s after %s)" % [key, row[0], previous])
			previous = float(row[0])
			check(float(row[1]) > 0.0, "%s distance is positive" % key)
			check(float(row[4]) > 1.0 and float(row[4]) < 179.0, "%s fov is a sane angle" % key)
		if rows.size() >= 2:
			check(is_equal_approx(float(rows[0][0]), 0.0), "%s table starts at p = 0" % key)
			check(is_equal_approx(float(rows[rows.size() - 1][0]), 1.0), "%s table ends at p = 1" % key)

## -- card and beats --------------------------------------------------------------------------

func run_card_and_beats(mode: StringName, length: float, beats: Array) -> void:
	var pair := make_pair()
	var game: Node = pair["game"]
	var ui: Node = pair["ui"]
	check(not active(ui), "%s: UI idle before the intro" % mode)
	var heard: Array = []
	game.run_intro_beat.connect(func(index: int, label: String) -> void: heard.append([index, label]))
	game.begin_intro(mode)
	await process_frame
	check(active(ui), "%s: UI active once run_intro fires" % mode)
	check(is_equal_approx(game.run_intro_progress, 0.0), "%s: progress starts at 0" % mode)
	check(count_text(ui) == "", "%s: no countdown glyph at t=0" % mode)
	var elapsed := 0.0
	var seen_beats := 0
	var steps := int(ceil(length / TICK))
	for i in steps:
		game.advance_intro(TICK)
		elapsed += TICK
		await process_frame
		if seen_beats < beats.size() and elapsed >= float(beats[seen_beats][0]) + TICK:
			var label: String = beats[seen_beats][1]
			if label == "TITLE":
				check(card_text(ui).to_upper().contains("CODEBASE CORRIDOR"), "full: title card reads THE CODEBASE CORRIDOR at %.2fs (got '%s')" % [elapsed, card_text(ui)])
			else:
				check(count_text(ui).to_upper().contains(label), "%s: beat %s shows at %.2fs (got '%s')" % [mode, label, elapsed, count_text(ui)])
			seen_beats += 1
		if game.phase != &"intro":
			break
	check(seen_beats == beats.size(), "%s: every beat was observed (%d/%d)" % [mode, seen_beats, beats.size()])
	check(heard.size() == beats.size(), "%s: mock emitted %d beats" % [mode, heard.size()])
	for k in heard.size():
		check(heard[k][0] == k, "%s: beat indices arrive in order" % mode)
	if mode == &"short":
		check(card_text(ui) == "", "short: no title card")
	await advance_seconds(game, 1.0)
	check(not active(ui), "%s: UI inactive after the intro completes" % mode)
	drop(pair)

## -- skip ------------------------------------------------------------------------------------

func run_skip_guard() -> void:
	var pair := make_pair()
	var game: Node = pair["game"]
	var ui: Node = pair["ui"]
	game.begin_intro(&"full")
	await advance_seconds(game, 0.1)
	check(not skip_visible(ui), "skip prompt hidden before %.1fs" % SKIP_AFTER)
	check(not game.can_skip_run_intro(), "mock refuses skip before %.1fs" % SKIP_AFTER)
	await advance_seconds(game, 0.3)
	check(game.can_skip_run_intro(), "skip becomes allowed after %.1fs" % SKIP_AFTER)
	check(skip_visible(ui), "skip prompt visible once skip is allowed")
	check(ui.skip_prompt.text.strip_edges() != "", "skip prompt text comes from controller_prompts (non-empty)")
	var prompts := load("res://app/controller_prompts.gd") as GDScript
	check(prompts != null, "app/controller_prompts.gd loads")
	# Mouse passthrough: only the skip button may stop clicks.
	var offenders: Array[String] = []
	collect_blocking_controls(ui, offenders)
	for name in offenders:
		check(name.to_lower().contains("skip"), "only the skip control captures the mouse (found %s)" % name)
	drop(pair)

func collect_blocking_controls(node: Node, out: Array[String]) -> void:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		out.append(String(node.name))
	for child in node.get_children():
		collect_blocking_controls(child, out)

func run_skip_cleanup() -> void:
	var pair := make_pair()
	var game: Node = pair["game"]
	var ui: Node = pair["ui"]
	var skipped := [0]
	var ended := [0]
	game.run_intro_skipped.connect(func(_mode: StringName = &"") -> void: skipped[0] += 1)
	game.run_intro_ended.connect(func(_mode: StringName = &"") -> void: ended[0] += 1)
	game.begin_intro(&"full")
	await advance_seconds(game, 1.5)
	game.skip_run_intro()
	await process_frame
	check(skipped[0] == 1, "skip emits run_intro_skipped once")
	check(ended[0] == 0, "ended waits for the skip tail")
	check(not skip_visible(ui), "skip prompt hides after a skip")
	check(card_text(ui) == "", "title card clears immediately on skip")
	check(count_text(ui).to_upper().contains("GO"), "final GO! burst shows immediately after skip (got '%s')" % count_text(ui))
	check(ui.burst.go, "the burst is the GO burst after skip")
	game.skip_run_intro()
	check(skipped[0] == 1, "a second skip is ignored")
	await advance_seconds(game, SKIP_TAIL * 0.5)
	check(ended[0] == 0, "still in the tail halfway through")
	await advance_seconds(game, SKIP_TAIL)
	check(ended[0] == 1, "ended fires once after the tail")
	check(not active(ui), "UI cleaned up after a skip")
	check(card_text(ui) == "" and count_text(ui) == "", "no card or countdown left after a skip")
	check(not ui.countdown.visible, "GO burst cleared on end")
	drop(pair)

## The skipped GO! stays up through the tail and is nearly faded by the time ended fires.
func run_skip_go_fade() -> void:
	for mode in [&"full", &"short"]:
		var pair := make_pair()
		var game: Node = pair["game"]
		var ui: Node = pair["ui"]
		var ended := [0]
		game.run_intro_ended.connect(func(_mode: StringName = &"") -> void: ended[0] += 1)
		game.begin_intro(mode)
		await advance_seconds(game, 1.5 if mode == &"full" else 0.5)
		check(game.skip_run_intro(), "%s: skip accepted" % mode)
		await process_frame
		check(count_text(ui).to_upper().contains("GO"), "%s: GO! visible right after skip" % mode)
		check(ui.countdown.modulate.a > 0.9, "%s: GO! starts opaque after skip (%.3f)" % [mode, ui.countdown.modulate.a])
		await advance_seconds(game, SKIP_TAIL * 0.5)
		check(ended[0] == 0 and ui.countdown.visible, "%s: GO! still visible halfway through the tail" % mode)
		var halfway: float = ui.countdown.modulate.a
		check(halfway < 1.0 and halfway > 0.0, "%s: GO! is fading halfway (%.3f)" % [mode, halfway])
		await advance_seconds(game, SKIP_TAIL * 0.45)
		check(ended[0] == 0, "%s: still inside the tail" % mode)
		check(ui.countdown.modulate.a < 0.15, "%s: GO! nearly gone just before ended (%.3f)" % [mode, ui.countdown.modulate.a])
		check(ui.countdown.modulate.a < halfway, "%s: GO! fades monotonically" % mode)
		await advance_seconds(game, SKIP_TAIL)
		check(ended[0] == 1, "%s: ended fires once" % mode)
		check(not ui.countdown.visible and not active(ui), "%s: GO! cleared at ended" % mode)
		drop(pair)

## A shorter configured tail: the fade runs over the remaining time, not a fixed 0.4 s.
func run_skip_short_tail() -> void:
	for item in [[&"full", 6.0, 4], [&"short", 2.2, 1]]:
		var mode: StringName = item[0]
		var length: float = item[1]
		var tail := 0.2
		var pair := make_stub_pair()
		var game: Node = pair["game"]
		var ui: Node = pair["ui"]
		game.run_intro_mode = mode
		stub_set_progress(game, 0.0)
		game.run_intro.emit(mode, length)
		stub_set_progress(game, (length - tail) / length)
		game.run_intro_skipped.emit()
		game.run_intro_beat.emit(item[2], "GO!")
		await process_frame
		var tag := "%s tail %.1fs: " % [mode, tail]
		check(count_text(ui).to_upper().contains("GO") and ui.countdown.modulate.a > 0.95, tag + "GO! opaque at skip (%.3f)" % ui.countdown.modulate.a)
		stub_set_progress(game, (length - tail * 0.5) / length)
		await process_frame
		var mid: float = ui.countdown.modulate.a
		check(ui.countdown.visible and mid < 1.0 and mid > 0.1, tag + "GO! mid-fade halfway (%.3f)" % mid)
		stub_set_progress(game, (length - 0.01) / length)
		await process_frame
		check(ui.countdown.modulate.a < 0.15 and ui.countdown.modulate.a < mid, tag + "GO! nearly gone before ended (%.3f)" % ui.countdown.modulate.a)
		game.run_intro_ended.emit()
		await process_frame
		check(not ui.countdown.visible and not active(ui), tag + "cleared at ended")
		drop(pair)

## Once GO! has been emitted the facade refuses a skip: the prompt is gone and a press changes nothing.
func run_late_skip_rejected() -> void:
	for mode in [&"full", &"short"]:
		var go_at := 5.4 if mode == &"full" else 1.6
		var pair := make_pair()
		var game: Node = pair["game"]
		var ui: Node = pair["ui"]
		var skipped := [0]
		var in_signal: Array = []
		game.run_intro_skipped.connect(func(_mode: StringName = &"") -> void: skipped[0] += 1)
		game.run_intro_beat.connect(func(_index: int, label: String) -> void:
			if label.to_upper().begins_with("GO"):
				in_signal.append(game.can_skip_run_intro()))
		game.begin_intro(mode)
		await advance_seconds(game, go_at - 0.1)
		check(game.can_skip_run_intro() and skip_visible(ui), "%s: skip still offered just before GO!" % mode)
		await advance_seconds(game, 0.15)
		check(in_signal.size() == 1 and in_signal[0] == false, "%s: guard already closed when GO! is emitted (%s)" % [mode, in_signal])
		check(not game.can_skip_run_intro(), "%s: skip refused after GO!" % mode)
		check(not skip_visible(ui), "%s: skip prompt hidden after GO!" % mode)
		var label_before := count_text(ui)
		check(label_before.to_upper().contains("GO"), "%s: GO! showing" % mode)
		check(not game.skip_run_intro(), "%s: late skip returns false" % mode)
		await process_frame
		check(skipped[0] == 0 and not ui.skipped, "%s: late skip does not reach the overlay" % mode)
		check(count_text(ui) == label_before and ui.countdown.visible, "%s: late skip does not clear GO!" % mode)
		drop(pair)

func run_end_cleanup() -> void:
	var pair := make_pair()
	var game: Node = pair["game"]
	var ui: Node = pair["ui"]
	var baseline := count_nodes(ui)
	for round_index in 2:
		game.begin_intro(&"short")
		await advance_seconds(game, 3.0)
		check(not active(ui), "round %d: inactive after natural end" % round_index)
		check(count_text(ui) == "", "round %d: no countdown left" % round_index)
	check(count_nodes(ui) == baseline, "repeat intros do not leak nodes (%d vs %d)" % [count_nodes(ui), baseline])
	drop(pair)

func count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += count_nodes(child)
	return total

## -- rebind ----------------------------------------------------------------------------------

func ui_connections(game: Node, ui: Node) -> int:
	var total := 0
	for sig in INTRO_SIGNALS:
		for connection in game.get_signal_connection_list(sig):
			var callable: Callable = connection["callable"]
			if callable.get_object() == ui:
				total += 1
	return total

func run_rebind() -> void:
	var pair := make_pair()
	var first: Node = pair["game"]
	var ui: Node = pair["ui"]
	var attached := ui_connections(first, ui)
	check(attached > 0, "bind connects the intro signals")
	ui.bind(first)
	check(ui_connections(first, ui) == attached, "binding the same game twice adds no duplicate connections")
	var second := mock_script.new() as Node
	root.add_child(second)
	junk.append(second)
	first.begin_intro(&"full")
	await advance_seconds(first, 2.0)
	check(active(ui), "UI active on the first game")
	ui.bind(second)
	check(ui_connections(first, ui) == 0, "rebinding disconnects every signal from the old game")
	check(ui_connections(second, ui) == attached, "rebinding connects the new game")
	check(not active(ui), "rebinding resets the presentation")
	await advance_seconds(first, 1.0)
	check(not active(ui), "the old game can no longer drive the UI")
	second.begin_intro(&"short")
	await process_frame
	check(active(ui), "the new game drives the UI")
	ui.bind(null)
	check(ui_connections(second, ui) == 0, "bind(null) disconnects everything")
	drop(pair)
	junk.erase(second)
	second.free()

## -- pause -----------------------------------------------------------------------------------

func run_pause() -> void:
	var pair := make_pair()
	var game: Node = pair["game"]
	var ui: Node = pair["ui"]
	check(ui.process_mode == Node.PROCESS_MODE_PAUSABLE, "UI is pausable")
	game.begin_intro(&"full")
	await advance_seconds(game, 3.2)
	game.pause_intro(true)
	var pause_guard := PauseGuard.new(self)
	paused = true
	var frozen: Dictionary = anim(ui)
	for i in 20:
		await process_frame
	check(anim(ui) == frozen, "animation state is frozen while paused")
	check(frozen.size() > 0, "animation_state reports values")
	game.advance_intro(TICK * 30.0)
	await process_frame
	check(anim(ui) == frozen, "progress does not move while the game is paused")
	pause_guard.restore()
	game.pause_intro(false)
	await advance_seconds(game, 0.3)
	check(anim(ui) != frozen, "animation resumes after unpause")
	# The UI reads progress, not its own timers: identical progress gives an identical state.
	var a: Dictionary = anim(ui)
	for i in 10:
		await process_frame
	check(anim(ui) == a, "state is a pure function of progress (no free-running timers)")
	drop(pair)

## -- beat timing: the overlay animates from beat arrival, not from default beat times --------

func make_stub_pair() -> Dictionary:
	var game := BeatClock.new()
	root.add_child(game)
	junk.append(game)
	var ui := (load(UI_SCENE) as PackedScene).instantiate()
	root.add_child(ui)
	junk.append(ui)
	ui.bind(game)
	return {"game": game, "ui": ui}

func stub_set_progress(game: Node, value: float) -> void:
	game.run_intro_progress = value

func run_beat_timing() -> void:
	# [mode, seconds, [[index, label, arrival progress], ...]]. Durations and arrivals both
	# differ from the 6.0 / 2.2 s defaults and from the default beat times.
	var cases := [
		[&"full", 10.0, [[1, "3", 0.42], [2, "2", 0.55], [4, "GO!", 0.80]]],
		# Late arrivals must start visible even when the default animation already faded.
		[&"full", 10.0, [[1, "3", 0.72], [4, "GO!", 0.92]]],
		[&"short", 5.0, [[0, "READY", 0.30], [1, "GO!", 0.70]]],
	]
	for item in cases:
		var mode: StringName = item[0]
		var length: float = item[1]
		var pair := make_stub_pair()
		var game: Node = pair["game"]
		var ui: Node = pair["ui"]
		game.run_intro_mode = mode
		stub_set_progress(game, 0.0)
		game.run_intro.emit(mode, length)
		await process_frame
		for beat in item[2]:
			var label: String = beat[1]
			var arrival: float = beat[2]
			stub_set_progress(game, arrival)
			game.run_intro_beat.emit(beat[0], label)
			var tag := "%s %s at %.2f (%.1fs): " % [mode, label, arrival, length]
			check(count_text(ui) == label.to_upper(), tag + "visible at arrival (got '%s')" % count_text(ui))
			check(is_equal_approx(ui.countdown.modulate.a, 1.0), tag + "alpha 1 at arrival (%.3f)" % ui.countdown.modulate.a)
			var pop_start: float = ui.countdown.scale.x
			check(pop_start > 1.2, tag + "pop at full size at arrival (%.3f)" % pop_start)
			# 0.1 s after arrival: the pop has progressed, GO! is still on screen.
			stub_set_progress(game, arrival + 0.1 / length)
			await process_frame
			check(ui.countdown.scale.x < pop_start, tag + "pop animates after progress advances")
			check(ui.countdown.visible and ui.countdown.modulate.a > 0.9, tag + "still visible 0.1s later")
			# 0.7 s after arrival: faded out, so the animation follows the arrival, not defaults.
			stub_set_progress(game, minf(arrival + 0.7 / length, 0.99))
			await process_frame
			check(ui.countdown.modulate.a < 0.5, tag + "fades by 0.7s after arrival (%.3f)" % ui.countdown.modulate.a)
		game.run_intro_ended.emit()
		await process_frame
		check(not active(ui), "%s: reset after ended" % mode)
		drop(pair)

## -- letterbox -------------------------------------------------------------------------------

func run_letterbox() -> void:
	var game := mock_script.new() as Node
	root.add_child(game)
	junk.append(game)
	var post := (load(POST_SCENE) as PackedScene).instantiate()
	root.add_child(post)
	junk.append(post)
	post.bind(game)
	await process_frame
	check(float(post.values["letterbox"]) < 0.01, "letterbox starts closed")
	game.begin_intro(&"full")
	await advance_seconds(game, 0.8)
	for i in 30:
		await process_frame
	check(float(post.values["letterbox"]) > 0.5, "letterbox opens during the intro (%.2f)" % float(post.values["letterbox"]))
	await advance_seconds(game, 5.5)
	for i in 90:
		await process_frame
	check(float(post.values["letterbox"]) < 0.05, "letterbox is gone after the intro (%.2f)" % float(post.values["letterbox"]))
	game.begin_intro(&"full")
	await advance_seconds(game, 1.0)
	game.skip_run_intro()
	await advance_seconds(game, 1.0)
	for i in 90:
		await process_frame
	check(float(post.values["letterbox"]) < 0.05, "letterbox is gone after a skip")
	post.bind(null)
	game.begin_intro(&"full")
	await advance_seconds(game, 1.0)
	for i in 30:
		await process_frame
	check(float(post.values["letterbox"]) < 0.05, "an unbound post_fx ignores intro progress")
	junk.erase(post)
	junk.erase(game)
	post.free()
	game.free()

## -- boss regressions ------------------------------------------------------------------------

func run_boss_regressions() -> void:
	check(ResourceLoader.exists(BOSS_UI_SCENE), "boss_cinematic.tscn still exists")
	var boss_ui := (load(BOSS_UI_SCENE) as PackedScene).instantiate()
	check(boss_ui != null, "boss_cinematic still instantiates")
	if boss_ui != null:
		boss_ui.free()
	var post_script := load("res://scenes/runner/ui/post_fx.gd") as GDScript
	var post := post_script.new() as Node
	for event in [&"boss_cinematic", &"boss_cinematic_skipped", &"boss_cinematic_ended"]:
		check(post.signal_handlers.has(event), "post_fx still handles %s" % event)
	post.free()
