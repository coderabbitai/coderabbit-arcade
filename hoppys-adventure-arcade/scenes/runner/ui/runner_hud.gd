extends CanvasLayer
## Graybox run HUD (contract §5.6). Backend-authored placeholder, frozen after the contract PR.

const Style = preload("res://scenes/main_menu/menu_style.gd")

var game: Node
var hp_label: Label
var score_label: Label
var speed_label: Label
var pursuit_label: Label

func _ready() -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Style.theme()
	add_child(ui)
	hp_label = Style.label("HP  ♥ ♥", 22)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hp_label.position = Vector2(40, 32)
	ui.add_child(hp_label)
	score_label = Style.label("0", 32)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_label.position = Vector2(-320, 28)
	score_label.size.x = 280
	ui.add_child(score_label)
	speed_label = Style.label("12.0 m/s", 15, Color("afbdc9"))
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	speed_label.position = Vector2(-320, 74)
	speed_label.size.x = 280
	ui.add_child(speed_label)
	pursuit_label = Style.label("", 20, Color("ff7185"))
	pursuit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pursuit_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	pursuit_label.position = Vector2(0, 30)
	pursuit_label.visible = false
	ui.add_child(pursuit_label)

func bind(runner: Node) -> void:
	game = runner
	runner.score_changed.connect(_on_score_changed)
	runner.health_changed.connect(_on_health_changed)
	runner.pursuit_progress.connect(_on_pursuit_progress)
	runner.pursuit_recovered.connect(_on_pursuit_recovered)
	runner.speed_changed.connect(_on_speed_changed)

func _on_score_changed(score: int, multiplier: float) -> void:
	score_label.text = str(score) if is_equal_approx(multiplier, 1.0) else "%d   x%.1f" % [score, multiplier]

func _on_health_changed(hp: int, max_hp: int) -> void:
	hp_label.text = "HP  " + " ".join(PackedStringArray(Array(range(max_hp)).map(
		func(i: int) -> String: return "♥" if i < hp else "·")))

func _on_pursuit_progress(remaining: float, total: float) -> void:
	pursuit_label.visible = true
	var span := total if total > 0.0 else 1.0
	pursuit_label.text = "PURSUED — %0.1fs  (%d%%)" % [remaining, roundi((1.0 - remaining / span) * 100.0)]

func _on_pursuit_recovered(_reason: StringName) -> void:
	pursuit_label.visible = false
	pursuit_label.text = ""

func _on_speed_changed(speed: float, _normalized: float) -> void:
	speed_label.text = "%.1f m/s" % speed
