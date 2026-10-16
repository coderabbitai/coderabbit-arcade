extends SceneTree
## Child process for tests/booth_soak.gd, skipped as a suite in tools/tests/suites.toml. It runs
## while a soak does (pass --soak after --) and leaks an orphan node every frame, so the soak's leak
## check has something real to catch and must exit 1.
## Usage: --script res://tests/support/soak_leak.gd -- --soak=<minutes> [--soak-dwell=...]
var leaked: Array[Node] = []

func _process(_delta: float) -> bool:
	leaked.append(Node.new())
	return false
