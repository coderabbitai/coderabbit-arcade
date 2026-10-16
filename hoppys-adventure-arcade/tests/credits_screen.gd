extends SceneTree
## Credits screen (scenes/credits/): the hub's Credits button opens it; it shows the hand-written
## sections (original music) and every asset credit generated from ASSETS_LICENSES.md, with each
## license; a track added to credits.json shows up; it scrolls by itself and by hand; Esc and the
## Back button return to the hub. Run headless with --script res://tests/credits_screen.gd.
const Credits := preload("res://scenes/credits/credits.gd")
## The original tracks that play in the game (Assets/Audio/**/PROMPTS.md), kept apart from credits.json
## so a track dropped from the credits fails the suite.
const ORIGINAL_TRACKS := ["Send in the Rabbit", "Send in the Rabbit (Instrumental)", "Cable Car Hop",
	"Merge Conflict Monster", "Zero-G Deploy", "The Deprecated API", "The Enchanted Repo", "The Legacy Monolith",
	"Stage Clear", "CLI / IDE District", "Security Sector", "Git Repository HQ", "District Boss",
	"The Grand Merge Conflict", "The Generation Floor", "AI SLOP", "The Review Gauntlet",
	"Agent Army and the 10,000-Line PR", "The Agentic Core", "Machine-Speed Hacker"]
var failures := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

## Wait for the route change to finish, up to five seconds of wall time; a change that doesn't
## finish is a failed check.
func settle_route() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while router.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not router.busy, "The route change finishes")
	await process_frame

func texts(screen: Node) -> PackedStringArray:
	var result := PackedStringArray()
	for child in screen.list.get_children():
		if child is Label:
			result.append(child.text)
	return result

func press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func run() -> void:
	router = root.get_node("AppRouter")
	var written := Credits.read_sections(Credits.CREDITS)
	var generated := Credits.read_sections(Credits.ASSET_CREDITS)
	check(not written.is_empty() and written[0].title == "Original music"
		and "Music by Erik Thorelli" in written[0].lines and written[0].tracks is Array,
		"credits.json opens with Original music, by Erik Thorelli, and a tracks list to extend")
	var music_tracks: Array = written[0].tracks if not written.is_empty() else []
	var track_titles := {}
	for track: Variant in music_tracks:
		if track is Dictionary and track.get("title", "") is String and track.get("title", "") != "" \
				and track.get("used_by", "") is String and track.get("used_by", "") != "":
			track_titles[track.title] = "%s  ·  %s" % [track.title, track.used_by]
	check(music_tracks.size() > 0 and track_titles.size() == music_tracks.size(),
		"Every original track has a unique title and the part of the game it plays in (%d tracks)" % music_tracks.size())
	var expected_titles := {}
	for title in ORIGINAL_TRACKS:
		expected_titles[title] = true
	check(track_titles.keys().size() == ORIGINAL_TRACKS.size() and track_titles.keys().all(func(t: String) -> bool: return expected_titles.has(t)),
		"credits.json lists exactly the %d original tracks that play in the game" % ORIGINAL_TRACKS.size())
	var all_credits: Array = []
	for section in generated:
		all_credits.append_array(section.credits)
	check(all_credits.size() > 0, "The generated asset credits are loaded (%d)" % all_credits.size())

	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await wait(0.4)
	var menu := current_scene
	var credits_button: Button = menu.buttons[menu.buttons.size() - 1]
	check(menu.buttons.size() == 6 and credits_button.text == "Credits"
		and menu.buttons[3].text == "Settings" and menu.buttons[4].text == "Quit Game",
		"The hub's Credits button follows Settings and Quit Game")
	credits_button.pressed.emit()
	await settle_route()
	var screen := current_scene
	check(screen != null and screen.scene_file_path == router.ROUTES["credits"],
		"The Credits button opens the credits screen")
	await wait(0.2)

	var shown := texts(screen)
	check("ORIGINAL MUSIC" in shown and "Music by Erik Thorelli" in shown,
		"The screen credits the original music to Erik Thorelli")
	var unlisted := track_titles.keys().filter(func(title: String) -> bool: return not track_titles[title] in shown)
	check(not track_titles.is_empty() and unlisted.is_empty(),
		"The screen lists every original track title%s" % ("" if unlisted.is_empty() else " (missing: %s)" % ", ".join(unlisted)))
	var missing: Array = []
	var unlicensed: Array = []
	for entry: Dictionary in all_credits:
		var at := shown.find(entry.credit)
		if at < 0:
			missing.append(entry.credit)
		elif at + 1 >= shown.size() or not shown[at + 1].begins_with(entry.license):
			unlicensed.append(entry.credit)
	check(missing.is_empty(), "Every asset credit is on screen (missing %s)" % [missing])
	check(unlicensed.is_empty(),
		"Each credit is followed by its license (wrong for %s)" % [unlicensed])
	var attributed := 0
	var unattributed := []
	for entry: Dictionary in all_credits:
		if String(entry.license).contains("CC BY"):
			attributed += 1
			if not (entry.credit in shown and String(entry.credit).contains(" by ")):
				unattributed.append(entry.asset)
	check(unattributed.is_empty(), "Every CC BY credit (%d) is shown with its attribution"
		% attributed + " (missing %s)" % [unattributed])

	screen._add_section({"title": "Theme", "tracks": [{"title": "A New Track", "used_by": "Hub"}]})
	check("A New Track  ·  Hub" in texts(screen), "A track added to a section's list is shown")

	# Pad the list so scrolling has room, however few assets the table holds today.
	var filler: Array[String] = []
	for i in 80:
		filler.append("Test line %d" % i)
	screen._add_section({"title": "Scroll test", "lines": filler})
	screen.offset = 0.0
	screen.scroll.scroll_vertical = 0
	screen.hold = 1.0
	await process_frame
	await process_frame
	check(screen.list.size.y > screen.scroll.size.y, "The padded credits are longer than the screen")
	await wait(screen.hold + 1.2)
	check(screen.scroll.scroll_vertical > 0, "The credits scroll by themselves")
	var before: int = screen.scroll.scroll_vertical
	await press(&"ui_down")
	var stepped: int = screen.scroll.scroll_vertical
	check(stepped >= before + 80, "Down scrolls by hand")
	await wait(0.5)
	check(screen.scroll.scroll_vertical == stepped, "A manual scroll pauses the automatic one")
	Input.action_press(&"ui_down")
	await wait(0.8)
	var while_held: int = screen.scroll.scroll_vertical
	Input.action_release(&"ui_down")
	check(while_held > stepped + screen.STEP, "Holding Down keeps scrolling")

	await press(&"ui_cancel")
	await settle_route()
	check(current_scene.name == "MainMenu", "Esc returns to the hub")
	router.go("credits")
	await settle_route()
	current_scene.back.pressed.emit()
	await settle_route()
	check(current_scene.name == "MainMenu", "Return to Main Menu returns to the hub")

	await root.get_node("AudioService").settle()
	print("Credits screen failures: ", failures)
	quit(1 if failures else 0)
