extends SceneTree
## Host-only: actual shipping corridor, paired background/body/full renders (capture_a4_job.gd).
##   Godot --path . --always-on-top --script res://scenes/runner/powerups/dev/capture_a4.gd
## The same job also runs batched after capture_a3.gd (`-- --with-a4`), so one window covers both.
const Job = preload("res://scenes/runner/powerups/dev/capture_a4_job.gd")

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A4 CAPTURE: FAIL (graphical renderer required)")
		quit(1)
		return
	call_deferred("capture")

func capture() -> void:
	var passed: bool = await Job.new(self).capture()
	quit(0 if passed else 1)
