extends RefCounted
## Only the worker writes result/cpu_ms; the main thread reads after joining.
var generator: Callable
var finalizer: Callable
var package: String
var key: String
var task_id := -1
var result: Variant
var cpu_ms := 0.0
var worker_thread := false

func generate() -> void:
	worker_thread = not Thread.is_main_thread()
	var started := Time.get_ticks_usec()
	result = generator.call()
	cpu_ms = (Time.get_ticks_usec() - started) / 1000.0
