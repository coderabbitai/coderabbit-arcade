extends Control
## The credits screen. It shows the hand-written sections in credits.json first (original music
## and anything else people add there as data), then the asset credits that
## tools/credits/build_credits.py generates from ASSETS_LICENSES.md. The list scrolls by itself;
## Up and Down (or the mouse wheel) scroll it by hand, and Back or Esc / B return to the hub.
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Prompts := preload("res://app/controller_prompts.gd")
## Hand-written sections: {"title", "lines": [String], "tracks": [{"title", "used_by"}]}.
const CREDITS := "res://scenes/credits/credits.json"
## Generated; do not edit. Sections of credits:
## {"credit", "license", "used_by", "source_url", "license_url"}.
const ASSET_CREDITS := "res://scenes/credits/asset_credits.json"
const SCROLL_SPEED := 36.0
## After a manual scroll, the list waits this long before scrolling by itself again.
const MANUAL_HOLD := 4.0
## One press of Up or Down moves the list this far; holding it scrolls this fast. Held D-pad
## buttons send no repeat events, so holding is polled each frame.
const STEP := 90.0
const HELD_SPEED := 540.0
const HELD_AFTER := 0.3
## At the bottom, the list waits this long, then starts again from the top.
const END_HOLD := 3.0
const MUTED := Color("afbdc9")
var scroll: ScrollContainer
var list: VBoxContainer
var back: Button
var offset := 0.0
var hold := 1.5
var leaving := false
## How long Up or Down has been held, to start continuous scrolling after HELD_AFTER.
var held := 0.0

func _ready() -> void:
	theme = Style.theme()
	var background := ColorRect.new()
	background.color = Color("101d2d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 76)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(Style.label("HOPPY'S ADVENTURE ARCADE", 16, Color("ff9a43")))
	column.add_child(Style.label("CREDITS", 38))
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for section in sections():
		_add_section(section)
	_add_gap(18)
	_add_text("Source code: MIT License. CodeRabbit and the Hoppy mascot are trademarks of"
		+ " CodeRabbit, Inc.", 15, MUTED)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	column.add_child(footer)
	back = Style.button("Return to Main Menu", 48)
	back.name = "BackButton"
	footer.add_child(back)
	back.pressed.connect(leave)
	var hint := Style.label("", 14, MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Prompts.track(hint, func() -> String:
		return "%s: scroll     %s: back" % [Prompts.keys_or_pad("↑ ↓", Prompts.if_pad("D-pad")),
			Prompts.either("Esc", &"ui_cancel")])
	footer.add_child(hint)
	back.grab_focus()

## Every section in display order: the hand-written ones, then the generated asset credits.
static func sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(read_sections(CREDITS))
	result.append_array(read_sections(ASSET_CREDITS))
	return result

## The "sections" array of a credits file, keeping only dictionaries with a title.
static func read_sections(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary and data.get("sections") is Array):
		push_error("Credits: %s is missing or has no sections array" % path)
		return result
	for section: Variant in data.sections:
		if section is Dictionary and str(section.get("title", "")) != "":
			result.append(section)
	return result

func _add_section(section: Dictionary) -> void:
	_add_gap(18)
	_add_text(str(section.title).to_upper(), 22, Style.MINT)
	for line: Variant in section.get("lines", []):
		_add_text(str(line), 19)
	for track: Variant in section.get("tracks", []):
		if track is Dictionary:
			var used_by := str(track.get("used_by", ""))
			_add_text(str(track.get("title", "")) + ("  ·  " + used_by if used_by != "" else ""), 17)
	for entry: Variant in section.get("credits", []):
		if not entry is Dictionary:
			continue
		_add_gap(4)
		_add_text(str(entry.get("credit", "")), 18)
		var details := PackedStringArray()
		for key in ["license", "used_by"]:
			if str(entry.get(key, "")) != "":
				details.append(str(entry[key]))
		_add_text("  ·  ".join(details), 14, MUTED)
		var links := PackedStringArray()
		for key in ["source_url", "license_url"]:
			if str(entry.get(key, "")) != "":
				links.append(str(entry[key]))
		if not links.is_empty():
			_add_text("   ".join(links), 13, MUTED)

func _add_text(text: String, font_size: int, color: Color = Style.CREAM) -> void:
	var label := Style.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(label)

func _add_gap(height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	list.add_child(gap)

func _process(delta: float) -> void:
	# A scroll that didn't come from here (the mouse wheel) counts as a manual one.
	if scroll.scroll_vertical != int(offset):
		offset = scroll.scroll_vertical
		hold = MANUAL_HOLD
	var direction := Input.get_axis(&"ui_up", &"ui_down")
	held = held + delta if absf(direction) > 0.5 else 0.0
	if held > HELD_AFTER:
		_scroll_by(signf(direction) * HELD_SPEED * delta)
		return
	if hold > 0.0:
		hold -= delta
		return
	var bottom := maxf(0.0, list.size.y - scroll.size.y)
	if offset >= bottom:
		offset = 0.0
		hold = END_HOLD
	else:
		offset = minf(bottom, offset + SCROLL_SPEED * delta)
		if offset >= bottom:
			hold = END_HOLD
	scroll.scroll_vertical = int(offset)

func _input(event: InputEvent) -> void:
	# One step per press; keyboard echo is ignored, since holding is handled in _process().
	for action in [&"ui_up", &"ui_down"]:
		if event.is_action_pressed(action):
			_scroll_by(STEP if action == &"ui_down" else -STEP)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		leave()
		get_viewport().set_input_as_handled()

## Move the list by `pixels` within its bounds; a manual scroll pauses the automatic one.
func _scroll_by(pixels: float) -> void:
	offset = clampf(offset + pixels, 0.0, maxf(0.0, list.size.y - scroll.size.y))
	scroll.scroll_vertical = int(offset)
	hold = MANUAL_HOLD

## AppRouter ignores go() mid-transition, so a press then is dropped rather than latched, and a
## route change that fails lets the player try again. The autoload is looked up by path: suites
## preload this script before autoloads exist.
func leave() -> void:
	var router := get_node(^"/root/AppRouter")
	if leaving or router.busy:
		return
	leaving = true
	if not await router.go("hub"):
		leaving = false
