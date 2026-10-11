extends SceneTree
## The runner menu's prewarm renders every cue at once on WorkerThreadPool, one task per recipe
## (environment/hifi/prewarm.gd). Godot 4.7's VM caches an untyped operator's evaluator in the
## shared bytecode the first time that instruction runs (gdscript_vm.cpp OPCODE_OPERATOR). It
## stores the signature, then the function pointer, with no synchronisation, so a thread arriving
## at the same cold `a * b` can see the signature and call a null or torn pointer. That was the
## runner-start SIGSEGV in sfx_synth.gd render(), whose mixing weights were untyped.
##
## Every round compiles a fresh copy of the script, so none of its instructions has run. Family
## rounds render every recipe on the pool as prewarm does. Barrier rounds park one thread per core,
## then release them at the same microsecond into the same short cue, which is where the race is
## likeliest. A crash fails the suite by exit code: with the untyped weights it crashed 10 of 10
## runs with 18 threads on a Mac, and the race needs real parallelism, so fewer cores catch it less
## often.
## Every render must also match a single-threaded one. Every wait has a deadline: a thread that
## can't start or never reaches the barrier fails the suite, and one that never finishes ends the
## process (it can't be joined).
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
## How far ahead of now the start is set once every thread is parked: time for each to read it.
const LEAD_USEC := 5000
## A barrier round's threads must all be parked, and then all done, each within this long.
const ROUND_USEC := 10_000_000
## A family round (every recipe on the pool) must finish within this long.
const FAMILY_USEC := 60_000_000
var failures := 0
var checks := 0
var source := ""

## The barrier. Threads count themselves in, then read `start_usec` under the mutex (0 until all
## have arrived) and spin on their own clock until it. Each thread reads a value published under
## the lock, then waits without touching shared memory, so they all leave at once.
class Gate extends RefCounted:
	var mutex := Mutex.new()
	var arrived := 0
	var start_usec := 0
	var abort := false

	func count() -> int:
		mutex.lock()
		var value := arrived
		mutex.unlock()
		return value

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
	var mismatched := 0
	for round in BARRIER_ROUNDS:
		var kind: StringName = BURST[round % BURST.size()]
		var problem := released_together(cold_synth(), kind, threads, expected[kind])
		if problem == "mismatch":
			mismatched += 1
		elif problem != "":
			check(false, "barrier round %d (%s, %d threads): %s" % [round, kind, threads, problem])
			finish()
			return
	check(mismatched == 0, "%d of %d barrier rounds (%d threads) render as on one thread" % [BARRIER_ROUNDS - mismatched, BARRIER_ROUNDS, threads])
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
	var deadline := Time.get_ticks_usec() + FAMILY_USEC
	if not wait_for(func() -> bool: return jobs.all(func(job: ImageJob) -> bool: return WorkerThreadPool.is_task_completed(job.task_id)), deadline):
		stuck("a family round's pool tasks are still running after %d s" % (FAMILY_USEC / 1_000_000))
	var same := 0
	for job in jobs:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		if matches(job.result, expected[StringName(job.key)]): same += 1
	return same

## `count` threads park on the gate, then all render `kind` with `synth` at once. Returns "" when
## every render matches `want`, "mismatch" when one doesn't, or why the round couldn't run.
func released_together(synth: GDScript, kind: StringName, count: int, want: Dictionary) -> String:
	var gate := Gate.new()
	var deadline := Time.get_ticks_usec() + ROUND_USEC
	var threads: Array[Thread] = []
	var problem := ""
	for i in count:
		var thread := Thread.new()
		var error := thread.start(_parked_render.bind(gate, synth, kind, deadline))
		if error != OK:
			problem = "thread %d of %d failed to start (%s)" % [i + 1, count, error_string(error)]
			break
		threads.append(thread)
	if problem == "" and not wait_for(func() -> bool: return gate.count() == count, deadline):
		problem = "only %d of %d threads reached the barrier within %d s" % [gate.count(), count, ROUND_USEC / 1_000_000]
	gate.mutex.lock()
	if problem == "": gate.start_usec = Time.get_ticks_usec() + LEAD_USEC
	else: gate.abort = true
	gate.mutex.unlock()
	if not wait_for(func() -> bool: return threads.all(func(thread: Thread) -> bool: return not thread.is_alive()), deadline + ROUND_USEC):
		stuck("barrier threads for %s are still running after %d s" % [kind, 2 * ROUND_USEC / 1_000_000])
	var same := true
	for thread in threads: same = matches(thread.wait_to_finish(), want) and same
	if problem == "" and not same: problem = "mismatch"
	return problem

## Runs on each barrier thread: parks until the gate publishes the start (or aborts, or
## `deadline_usec` passes), spins on its own clock to that instant, then renders.
static func _parked_render(gate: Gate, synth: GDScript, kind: StringName, deadline_usec: int) -> Variant:
	gate.mutex.lock()
	gate.arrived += 1
	gate.mutex.unlock()
	var start := 0
	while start == 0:
		gate.mutex.lock()
		start = -1 if gate.abort else gate.start_usec
		gate.mutex.unlock()
		if start == 0:
			if Time.get_ticks_usec() > deadline_usec: return null
			OS.delay_usec(20)
	if start < 0: return null
	while Time.get_ticks_usec() < start: pass
	return synth.call("render_family", kind)

## Polls `test` (sleeping between polls) until it holds or `deadline_usec` passes.
static func wait_for(test: Callable, deadline_usec: int) -> bool:
	while not test.call():
		if Time.get_ticks_usec() > deadline_usec: return false
		OS.delay_usec(100)
	return true

static func matches(got: Variant, want: Dictionary) -> bool:
	return got is Dictionary and got.base.data == want.base.data and got.variants == want.variants

## A thread that never finishes can't be joined, and quitting would wait on it. Report and end.
func stuck(message: String) -> void:
	check(false, message)
	print("RUNNER SYNTH THREADS: FAIL (%d checks, %d failures; ending the process)" % [checks, failures])
	OS.kill(OS.get_process_id())

func finish() -> void:
	print("RUNNER SYNTH THREADS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
