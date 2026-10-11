extends SceneTree
## The runner menu's prewarm renders every cue at once on WorkerThreadPool, one task per recipe
## (environment/hifi/prewarm.gd). Godot 4.7's VM caches an untyped operator's evaluator in the
## shared bytecode the first time that instruction runs (gdscript_vm.cpp OPCODE_OPERATOR). It
## stores the signature, then the function pointer, with no synchronisation, so a thread arriving
## at the same cold `a * b` can see the signature and call a null or torn pointer. That was the
## runner-start SIGSEGV in sfx_synth.gd render(), whose mixing weights were untyped.
##
## Every round compiles a fresh copy of the script, so none of its instructions has run. Family
## rounds render every recipe on the pool as prewarm does. Barrier rounds park one thread per core
## on a spin barrier, then release them together into the same short cue, which is where the race
## is likeliest. A crash fails the suite by exit code: with the untyped weights it crashed 10 of 10
## runs on a 10-core Mac, and the race needs real parallelism, so fewer cores catch it less often.
## Every render must also match a single-threaded one.
## Run with --path <project> --script res://tests/runner_synth_threads.gd. Pass
## -- --synth=<path> to run it on another copy of sfx_synth.gd, such as an older one.
const SYNTH := "res://scenes/runner/audio/sfx_synth.gd"
## The job prewarm queues: each task writes only its own result.
const ImageJob = preload("res://scenes/runner/environment/hifi/image_warm_job.gd")
const FAMILY_ROUNDS := 2
const BARRIER_ROUNDS := 320
const MAX_THREADS := 32
## Short non-looping cues of several waveforms, so a barrier round is a few milliseconds of PCM.
const BURST := [&"telegraph_tick", &"footstep", &"intro_count", &"lane_left", &"land", &"boss_title"]
var failures := 0
var checks := 0
var source := ""

class Gate extends RefCounted:
	var go := false
	var arrived := 0
	var mutex := Mutex.new()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

## An independent copy compiled from source, so none of its instructions has run yet.
func cold_synth() -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	return script if script.reload() == OK else null

func run() -> void:
	var path := SYNTH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--synth="): path = arg.trim_prefix("--synth=")
	source = FileAccess.get_file_as_string(path)
	var reference := cold_synth()
	if reference == null:
		check(false, "%s compiles from source" % path)
		finish()
		return
	var kinds: Array = reference.get("RECIPES").keys()
	var expected := {}
	for kind: StringName in kinds:
		expected[kind] = reference.call("render_family", kind)
	for kind: StringName in BURST:
		check(kind in kinds, "%s is a recipe" % kind)
	for round in FAMILY_ROUNDS:
		var same := on_pool(cold_synth(), kinds, expected)
		check(same == kinds.size(), "family round %d: %d of %d cues render as on one thread" % [round, same, kinds.size()])
	var threads := clampi(OS.get_processor_count(), 2, MAX_THREADS)
	var matched := 0
	for round in BARRIER_ROUNDS:
		var kind: StringName = BURST[round % BURST.size()]
		matched += 1 if released_together(cold_synth(), kind, threads, expected[kind]) else 0
	check(matched == BARRIER_ROUNDS, "%d of %d barrier rounds (%d threads) render as on one thread" % [matched, BARRIER_ROUNDS, threads])
	finish()

## Renders `kinds` on WorkerThreadPool with `synth`, one task each, and counts the matches.
func on_pool(synth: GDScript, kinds: Array, expected: Dictionary) -> int:
	var jobs: Array = []
	for kind: StringName in kinds:
		var job := ImageJob.new()
		job.key = kind
		job.generator = Callable(synth, "render_family").bind(kind)
		job.task_id = WorkerThreadPool.add_task(job.generate, false, "Synth threads " + String(kind))
		jobs.append(job)
	var same := 0
	for job in jobs:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		if matches(job.result, expected[StringName(job.key)]): same += 1
	return same

## `count` threads wait on a spin barrier, then all render `kind` with `synth` at once.
func released_together(synth: GDScript, kind: StringName, count: int, want: Dictionary) -> bool:
	var gate := Gate.new()
	var threads: Array[Thread] = []
	for i in count:
		var thread := Thread.new()
		thread.start(_parked_render.bind(gate, synth, kind))
		threads.append(thread)
	while true:
		gate.mutex.lock()
		var all := gate.arrived == count
		gate.mutex.unlock()
		if all: break
	gate.go = true
	var same := true
	for thread in threads: same = matches(thread.wait_to_finish(), want) and same
	return same

static func _parked_render(gate: Gate, synth: GDScript, kind: StringName) -> Variant:
	gate.mutex.lock()
	gate.arrived += 1
	gate.mutex.unlock()
	while not gate.go: pass
	return synth.call("render_family", kind)

static func matches(got: Variant, want: Dictionary) -> bool:
	return got is Dictionary and got.base.data == want.base.data and got.variants == want.variants

func finish() -> void:
	print("RUNNER SYNTH THREADS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
