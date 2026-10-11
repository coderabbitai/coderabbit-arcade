extends SceneTree
## Clock-driven story scenes for both beat'em up openings. The host ticks by hand;
## nothing here depends on a Tween or on the engine advancing the game clock.
const StoryScene = preload("res://modes/beatem_up/story_scene.gd")
const City = preload("res://modes/beatem_up/catalog.gd")
const Heroes = preload("res://modes/beatem_up/reinvent/catalog.gd")
const VictoryScreen = preload("res://modes/beatem_up/victory_screen.gd")
const DT := 1.0/60.0
const IMAGE_A := "res://Assets/code-city-brawl-assets-only/code_city/district_background.png"
const IMAGE_B := "res://Assets/code-city-brawl-assets-only/code_city/hq_background.png"
const OPENINGS := [
	"res://Assets/heroes-vs-villains-assets-only/presentation/opening_situation.tscn",
	"res://Assets/heroes-vs-villains-assets-only/presentation/opening_complication.tscn",
	"res://Assets/heroes-vs-villains-assets-only/presentation/opening_resolution.tscn"]
var failures := 0
var checks := 0
var game
var holder: Node

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func mount(node: Node) -> Node:
	if holder == null:
		holder = Node2D.new()
		holder.name = "StoryProbe"
		root.add_child(holder)
	holder.add_child(node)
	return node
func drop_holder() -> void:
	if holder and is_instance_valid(holder): holder.free()
	holder = null
func covers(scene: Control) -> bool:
	var view: Rect2 = scene.view_rect()
	var pic := Rect2(scene.picture.position, scene.picture.size)
	return pic.grow(1.0).encloses(view)
func encloses(outer: Control, inner: Control) -> bool:
	var area := outer.get_global_rect().grow(1.0)
	var item := inner.get_global_rect()
	if item.size.x <= 0.0 or item.size.y <= 0.0: return false
	return area.encloses(item)
func close_vec(a: Vector3, b: Vector3) -> bool:
	return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y) and is_equal_approx(a.z, b.z)
## Non-strict: a component that does not change (a pure pan, equal zoom) stays put.
func moves_toward(previous: float, current: float, start: float, finish: float) -> bool:
	var lo := minf(start, finish)-1e-4
	var hi := maxf(start, finish)+1e-4
	if current < lo or current > hi: return false
	if absf(finish-start) <= 1e-5: return is_equal_approx(current, start)
	if finish > start: return current+1e-5 >= previous
	return current <= previous+1e-5
## How many 1/60 additions it takes for a clock that starts at 0 to reach `seconds`.
## 270 additions land one ulp under 4.5, so a 4.5s hold crosses on tick 271.
func ticks_to_cross(seconds: float) -> int:
	var clock := 0.0
	var n := 0
	while clock < seconds and n < 10000:
		clock += DT
		n += 1
	return n
func run() -> void:
	var hold: float = City.FLOW.intro_hold
	check(is_equal_approx(hold, 4.5), "Code City intro hold is 4.5s")
	for key in ["opening_situation", "opening_complication", "opening_resolution"]:
		check(is_equal_approx(float(Heroes.CARD_HOLD[key]), hold), "HvV %s hold is 4.5s" % key)
	check_textures()
	check_ending_data()
	await check_victory_screen()
	for index in City.STORY.size():
		await exercise(City, "Code City", index, hold)
	for index in Heroes.STORY.size():
		await exercise(Heroes, "HvV", index, hold)
	await check_pure_pan(hold)
	await check_long_caption(hold)
	await check_idle(hold)
	await check_aspect(hold)
	check_openings()
	drop_holder()
	await check_code_city(hold)
	await check_hvv(hold)
	await check_hvv_ending()
	print("Story checks: ", checks, " failures: ", failures)
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(0.4).timeout
	quit(1 if failures else 0)

func check_textures() -> void:
	var preferred: Texture2D = StoryScene.texture_for({"image": IMAGE_A, "fallback": IMAGE_B})
	var stood_in: Texture2D = StoryScene.texture_for({"image": "res://Assets/beatemup-story/missing.png", "fallback": IMAGE_B})
	check(preferred == load(IMAGE_A) and preferred != load(IMAGE_B), "texture_for prefers image when that path exists")
	check(stood_in == load(IMAGE_B), "texture_for uses fallback when image is missing")
	check(StoryScene.texture_for({"image": "", "fallback": ""}) == null, "texture_for returns null when both paths are missing")
	for catalog in [City, Heroes]:
		check(catalog.STORY.size() == 3, "%s has three story scenes" % catalog.STORY_ROOT)
		for entry in catalog.STORY:
			var tex: Texture2D = StoryScene.texture_for(entry)
			var image_exists := ResourceLoader.exists(str(entry["image"]))
			var expect := str(entry["image"] if image_exists else entry["fallback"])
			var caption := str(entry["caption"]).strip_edges()
			var kicker := str(entry["kicker"]).strip_edges()
			check(tex != null and tex == load(expect), "%s texture is %s" % [kicker, expect.get_file()])
			check(caption != "" and kicker != "", "%s has a caption and a kicker" % kicker)

func exercise(catalog, label: String, index: int, hold: float) -> void:
	var entry: Dictionary = catalog.STORY[index]
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(catalog, index)
	var name := "%s / %s" % [label, entry["kicker"]]
	check(scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "%s samples nearest" % name)
	var ratio_ok := true
	var ratio_why := ""
	var previous_ratio := 0.0
	var grew := false
	var done_at := -1.0
	var dip_ok := true
	var text_ok := true
	var cover_ok := true
	var framing_ok := true
	var from_v: Vector3 = entry["from"]
	var to_v: Vector3 = entry["to"]
	var previous := from_v
	var i := 0
	while true:
		var raw := i*DT
		var t := hold if raw >= hold else raw
		scene.advance(t, hold)
		var ratio := scene.typed_ratio()
		var chars: int = scene.caption.visible_characters
		if t < StoryScene.TYPE_DELAY:
			if not is_equal_approx(ratio, 0.0) or chars != 0:
				ratio_ok = false
				ratio_why = "typed before the delay at %s" % snappedf(t, 0.001)
		if ratio+1e-6 < previous_ratio:
			ratio_ok = false
			ratio_why = "ratio fell at %s" % snappedf(t, 0.001)
		if ratio > previous_ratio: grew = true
		if is_equal_approx(ratio, 1.0) and chars == -1 and done_at < 0.0: done_at = t
		previous_ratio = ratio
		var alpha := scene.dip_alpha()
		if t <= 0.0 and not is_equal_approx(alpha, 1.0): dip_ok = false
		if t >= StoryScene.DIP and t <= hold-StoryScene.DIP and not is_equal_approx(alpha, 0.0): dip_ok = false
		if is_equal_approx(t, hold) and not is_equal_approx(alpha, 1.0): dip_ok = false
		if not is_equal_approx(scene.kicker.modulate.a, 1.0-alpha) or not is_equal_approx(scene.caption.modulate.a, 1.0-alpha):
			text_ok = false
		if not is_equal_approx(scene.dip.color.a, alpha): dip_ok = false
		if scene.picture.texture == null or not covers(scene): cover_ok = false
		var now := scene.framing()
		if i == 0:
			framing_ok = close_vec(now, from_v)
		else:
			framing_ok = framing_ok and moves_toward(previous.x, now.x, from_v.x, to_v.x)
			framing_ok = framing_ok and moves_toward(previous.y, now.y, from_v.y, to_v.y)
			framing_ok = framing_ok and moves_toward(previous.z, now.z, from_v.z, to_v.z)
		previous = now
		if raw >= hold: break
		i += 1
		if i > 2000:
			ratio_ok = false
			ratio_why = "step loop did not reach the hold"
			break
	scene.advance(0.0, hold)
	var bars_in := is_equal_approx(scene.bars_shown(), 0.0 if index == 0 else 1.0)
	var top0 := scene.top_bar.size.y
	var bottom0 := scene.bottom_bar.size.y
	scene.advance(StoryScene.BAR_SLIDE, hold)
	var shown := scene.bars_shown()
	var full := is_equal_approx(shown, 1.0) and is_equal_approx(scene.top_bar.size.y, StoryScene.TOP_BAR) and is_equal_approx(scene.bottom_bar.size.y, StoryScene.BOTTOM_BAR)
	var early_full := index > 0 and is_equal_approx(top0, StoryScene.TOP_BAR) and is_equal_approx(bottom0, StoryScene.BOTTOM_BAR)
	var visible := scene.top_bar.visible and scene.bottom_bar.visible and scene.top_bar.is_visible_in_tree()
	var contained := encloses(scene.bottom_bar, scene.drain) and encloses(scene.bottom_bar, scene.hint) and encloses(scene.top_bar, scene.kicker)
	var dip_points := true
	scene.advance(0.0, hold)
	dip_points = dip_points and is_equal_approx(scene.dip_alpha(), 1.0) and is_equal_approx(scene.kicker.modulate.a, 0.0)
	scene.advance(StoryScene.DIP, hold)
	dip_points = dip_points and is_equal_approx(scene.dip_alpha(), 0.0) and is_equal_approx(scene.caption.modulate.a, 1.0)
	scene.advance(hold-StoryScene.DIP, hold)
	dip_points = dip_points and is_equal_approx(scene.dip_alpha(), 0.0)
	scene.advance(hold-StoryScene.DIP*0.5, hold)
	dip_points = dip_points and scene.dip_alpha() > 0.4 and scene.dip_alpha() < 0.6
	scene.advance(hold, hold)
	dip_points = dip_points and is_equal_approx(scene.dip_alpha(), 1.0) and is_equal_approx(scene.caption.modulate.a, 0.0)
	var finished: bool = done_at >= 0.0 and done_at <= hold-StoryScene.DIP+1e-4
	check(ratio_ok and grew and finished, "%s caption types with the clock and finishes before the dip (%s)" % [name, ratio_why])
	check(dip_ok and dip_points and text_ok, "%s dips in, holds clear, and dips out; the words fade with it" % name)
	check(bars_in and full and (index == 0 or early_full) and visible, "%s bars %s" % [name, "slide in" if index == 0 else "are in from the start"])
	check(contained, "%s drain and hint sit in the bottom bar, kicker in the top bar" % name)
	check(framing_ok and close_vec(previous, to_v), "%s pan/zoom moves from its framing to the next" % name)
	check(cover_ok, "%s picture covers the view for the whole hold" % name)
	scene.queue_free()

func check_pure_pan(hold: float) -> void:
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(City, 0)
	scene.scene = (scene.scene as Dictionary).duplicate()
	scene.scene["from"] = Vector3(0.22, 0.48, 1.0)
	scene.scene["to"] = Vector3(0.78, 0.48, 1.0)
	var from_v: Vector3 = scene.scene["from"]
	var to_v: Vector3 = scene.scene["to"]
	var previous := from_v
	var ok := true
	var covered := true
	var i := 0
	while true:
		var raw := i*DT
		var t := hold if raw >= hold else raw
		scene.advance(t, hold)
		var now := scene.framing()
		if i == 0: ok = close_vec(now, from_v)
		else:
			ok = ok and moves_toward(previous.x, now.x, from_v.x, to_v.x)
			ok = ok and moves_toward(previous.y, now.y, from_v.y, to_v.y)
			ok = ok and moves_toward(previous.z, now.z, from_v.z, to_v.z)
		if not covers(scene): covered = false
		previous = now
		if raw >= hold: break
		i += 1
	check(ok and close_vec(previous, to_v) and is_equal_approx(from_v.z, to_v.z), "A pure pan with equal zoom stays monotonic")
	check(covered, "A zoom of 1 still covers the view")
	scene.queue_free()

func check_long_caption(hold: float) -> void:
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(City, 1)
	scene.caption.text = "W".repeat(800)
	var deadline := StoryScene.TYPE_DELAY+StoryScene.TYPE_SHARE*hold
	var previous := 0.0
	var ok := true
	var i := 0
	while true:
		var raw := i*DT
		var t := deadline if raw >= deadline else raw
		scene.advance(t, hold)
		var ratio := scene.typed_ratio()
		if t < StoryScene.TYPE_DELAY and not is_equal_approx(ratio, 0.0): ok = false
		if ratio+1e-6 < previous: ok = false
		previous = ratio
		if raw >= deadline: break
		i += 1
	var chars: int = scene.caption.visible_characters
	check(ok and is_equal_approx(scene.typed_ratio(), 1.0) and chars == -1, "A long caption still finishes by the typing share of the hold")
	check(is_equal_approx(scene.type_end(), deadline), "The long caption's type_end is the typing share")
	scene.queue_free()

func check_idle(hold: float) -> void:
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(Heroes, 2)
	scene.advance(1.2, hold)
	var seconds := scene.seconds
	var pos := scene.picture.position
	var size := scene.picture.size
	var chars: int = scene.caption.visible_characters
	var framed := scene.framing()
	for _i in 8: await process_frame
	check(is_equal_approx(scene.seconds, seconds), "Stepping frames without advance leaves the scene clock")
	check(scene.picture.position == pos and scene.picture.size == size, "Stepping frames without advance leaves the picture")
	check(scene.caption.visible_characters == chars and close_vec(scene.framing(), framed), "Stepping frames without advance leaves the caption")
	scene.queue_free()

## Headless may ignore a window resize. A scaled parent still changes view_rect, which is the
## path a non-16:9 expand viewport and HvV's centred card host both go through.
func check_aspect(hold: float) -> void:
	var saved: Vector2i = root.size
	root.size = Vector2i(1000, 780)
	await process_frame
	await process_frame
	var viewport := root.get_visible_rect().size
	var resized := absf(viewport.x/viewport.y-16.0/9.0) > 0.05
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(City, 2)
	scene.advance(hold*0.5, hold)
	if resized: check(covers(scene), "Picture covers a non-16:9 viewport %s" % viewport)
	else: print("NOTE: headless kept the viewport at ", viewport, "; checking a scaled parent instead")
	var host := Control.new()
	host.position = Vector2(36, 48)
	host.scale = Vector2(1.4, 0.75)
	holder.add_child(host)
	var shifted := StoryScene.new()
	host.add_child(shifted)
	shifted.show_scene(Heroes, 0)
	shifted.advance(hold*0.5, hold)
	await process_frame
	shifted.advance(hold*0.5, hold)
	var view := shifted.view_rect().size
	var odd := absf(view.x/view.y-16.0/9.0) > 0.05
	check(odd and covers(shifted), "Picture covers a non-16:9 parent transform %s" % view)
	root.size = saved
	await process_frame
	scene.queue_free()
	host.queue_free()

func check_openings() -> void:
	for index in OPENINGS.size():
		var scene := mount(load(OPENINGS[index]).instantiate()) as StoryScene
		var entry: Dictionary = Heroes.STORY[index]
		check(scene.kicker.text == str(entry["kicker"]), "Opening %d rests on %s" % [index+1, entry["kicker"]])
		check(is_equal_approx(scene.typed_ratio(), 1.0) and scene.caption.visible_characters == -1, "Opening %d poster caption is complete" % [index+1])
		check(is_equal_approx(scene.bars_shown(), 1.0) and is_equal_approx(scene.dip_alpha(), 0.0), "Opening %d poster has the bars in and no dip" % [index+1])
		check(scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Opening %d samples nearest" % [index+1])
		scene.queue_free()

func load_mode(path: String) -> void:
	change_scene_to_file(path)
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	paused = false
	freeze()
	if game.state == "paused" and str(game.pause_return_state) in ["intro", "cards"]:
		game.resume()
		paused = false
		freeze()
func freeze() -> void:
	game.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)
		game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if "bosses" in game:
		for e in game.bosses:
			if is_instance_valid(e): e.set_physics_process(false)
	elif is_instance_valid(game.boss):
		game.boss.set_physics_process(false)
func reopen_city() -> void:
	game.flow.cancel()
	game.start_stage(0, true)
	paused = false
	freeze()
func action_button(text: String) -> Button:
	for child in game.story.actions.get_children():
		if child is Button and child.text == text: return child
	return null
func focused_next() -> bool:
	return game.get_viewport().gui_get_focus_owner() == game.intro_next

func check_code_city(hold: float) -> void:
	await load_mode("res://scenes/beatem_up/code_city_brawl.tscn")
	reopen_city()
	await process_frame
	check(game.state == "intro" and game.intro_page == 0 and not game.playing, "Code City opens on story page 1")
	check(focused_next(), "Next has focus when a page shows")
	check(not game.toast_label.visible and game.held_toast == "", "The encounter toast is hidden on the intro")
	var clock: float = game.intro_clock
	var seconds: float = game.story.seconds
	var pos: Vector2 = game.story.picture.position
	var chars: int = game.story.caption.visible_characters
	for _i in 6: await process_frame
	check(is_equal_approx(game.intro_clock, clock) and is_equal_approx(game.story.seconds, seconds), "Idle frames do not advance the intro or the scene")
	check(game.story.picture.position == pos and game.story.caption.visible_characters == chars, "Idle frames do not move the hosted picture or caption")
	var guard := 0
	while game.story.typed_ratio() < 0.3 and game.state == "intro" and guard < 180:
		game._physics_process(DT)
		guard += 1
	check(not game.toast_label.visible and game.held_toast == "" and game.intro_page == 0, "The encounter toast stays hidden through the first page")
	var page: int = game.intro_page
	clock = game.intro_clock
	seconds = game.story.seconds
	pos = game.story.picture.position
	var pic_size: Vector2 = game.story.picture.size
	chars = game.story.caption.visible_characters
	var caption: String = game.story.caption.text
	game.pause("x")
	game._physics_process(1.0)
	for _i in 4: await process_frame
	var frozen: bool = game.state == "paused" and game.pause_return_state == "intro"
	frozen = frozen and game.intro_page == page and is_equal_approx(game.intro_clock, clock)
	frozen = frozen and is_equal_approx(game.story.seconds, seconds)
	frozen = frozen and game.story.picture.position == pos and game.story.picture.size == pic_size
	frozen = frozen and game.story.caption.visible_characters == chars and game.story.caption.text == caption
	check(frozen, "Pause freezes the intro clock and the story picture and caption")
	var scene_path := str(game.scene_file_path)
	for child in game.story.actions.get_children():
		if child is Button: child.pressed.emit()
	var ignored: bool = game.state == "paused" and game.intro_page == page and is_equal_approx(game.intro_clock, clock)
	ignored = ignored and game.scene_file_path == scene_path
	check(ignored, "Next, Skip and Return do nothing while the intro is paused")
	game.resume()
	paused = false
	var restored: bool = game.state == "intro" and game.intro_page == page and is_equal_approx(game.intro_clock, clock)
	restored = restored and is_equal_approx(game.story.seconds, clock) and game.story.kicker.text == str(City.STORY[page]["kicker"])
	check(restored, "Resume restores the same page and clock")
	check(focused_next(), "Next takes focus again when the page is restored")
	game.intro_next.pressed.emit()
	check(game.state == "intro" and game.intro_page == page+1 and is_equal_approx(game.intro_clock, 0.0), "Next advances one page and resets the clock")
	check(is_equal_approx(game.story.seconds, 0.0) and game.story.kicker.text == str(City.STORY[page+1]["kicker"]), "The new page starts its own scene at 0")
	check(focused_next() and game.intro_next.text == "Next →", "Next is focused on the middle page")
	game.intro_next.pressed.emit()
	var last := City.STORY.size()-1
	check(game.state == "intro" and game.intro_page == last and game.intro_next.text == "Start the review →", "Page 3 offers to start the review")
	check(is_equal_approx(game.intro_clock, 0.0) and focused_next(), "Page 3 starts at 0 with Next focused")
	game.intro_next.pressed.emit()
	check(game.state == "stage_enter" and not game.story.visible and not game.playing, "Next on page 3 leads into the stage entrance")
	reopen_city()
	var skip := action_button("Skip intro")
	check(skip != null, "Skip intro is one of the story actions")
	if skip: skip.pressed.emit()
	check(game.state == "stage_enter" and not game.story.visible, "Skip intro goes straight to the stage with the story hidden")
	reopen_city()
	await run_city_hands_free(hold)
	await check_city_ending_controls()
	check_intro_guard()
	await check_return_to_menu()

## Resuming into "intro" once the intro is over (reachable only by forcing the state) hands off
## to the stage entrance instead of indexing past the last scene, and the scene clamps its index.
func check_intro_guard() -> void:
	reopen_city()
	var count := City.STORY.size()
	game.intro_page = count
	game.pause_return_state = "intro"
	game.state = "paused"
	paused = true
	game.resume()
	check(game.state == "stage_enter" and not paused and not game.story.visible and not game.overlay.visible, "Resuming into a finished intro hands off to the stage entrance")
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(City, count)
	check(scene.index == count-1 and scene.kicker.text == str(City.STORY[count-1]["kicker"]), "An index past the last scene shows the last one")
	scene.show_scene(City, -1)
	check(scene.index == 0 and scene.kicker.text == str(City.STORY[0]["kicker"]), "A negative index shows the first scene")
	drop_holder()
	# A resume consumes its return state, so a later hand-forced pause resumes into play, not
	# into an intro that is over (code_city_logic forces one after a startup focus pause).
	reopen_city()
	game.pause("x")
	game.resume()
	check(game.state == "intro" and game.pause_return_state == "combat", "Resuming the intro consumes its return state")
	game.state = "paused"
	paused = true
	game.resume()
	check(game.state == "combat" and game.playing and not paused and not game.story.visible, "A hand-forced pause afterwards resumes into play with the story hidden")

func run_city_hands_free(hold: float) -> void:
	reopen_city()
	var per := ticks_to_cross(hold)
	var expect := per*City.STORY.size()
	var toast_ok := true
	for _i in expect-1:
		if game.toast_label.visible or str(game.held_toast) != "": toast_ok = false
		game._physics_process(DT)
	var before: bool = game.state == "intro" and game.intro_page == City.STORY.size()-1 and game.intro_clock < hold
	check(before, "The intro is still on its last page one tick before 13.5s (page %s clock %.6f)" % [game.intro_page, float(game.intro_clock)])
	check(toast_ok, "The encounter toast stays hidden for the whole intro")
	game._physics_process(DT)
	check(game.state == "stage_enter" and not game.playing, "The intro reaches the stage entrance hands-free (%d ticks)" % expect)
	check(absi(per-int(round(hold/DT))) <= 2, "Each 4.5s page crosses within 2 ticks (%d)" % per)
	await run_city_ending_hands_free()

func check_return_to_menu() -> void:
	reopen_city()
	var back := action_button("Return to Beat'em Up menu")
	check(back != null and back.get_parent() == game.story.actions, "Return to the Beat'em Up menu lives in the story actions")
	if back == null: return
	var guard := 0
	while game.story.bars_shown() < 1.0 and guard < 90:
		game._physics_process(DT)
		guard += 1
	await process_frame
	check(game.story.bars_shown() >= 1.0 and encloses(game.story.bottom_bar, back), "Return sits inside the bottom bar")
	check(back.focus_mode != Control.FOCUS_NONE, "Return is focusable")
	back.grab_focus()
	check(game.get_viewport().gui_get_focus_owner() == back, "Return can take focus")
	back.pressed.emit()
	var arrived := false
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var router := root.get_node("AppRouter")
		if is_instance_valid(current_scene) and current_scene.scene_file_path.ends_with("beatem_menu.tscn") and not router.busy:
			arrived = true
			break
	check(arrived, "Return changes scene to the Beat'em Up menu")

func check_hvv(hold: float) -> void:
	await load_mode("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	check(game.state == "cards" and game.card_queue.size() == 3, "HvV opens on the three story cards")
	check(game.card_queue[0] == "opening_situation" and game.card.has_method("advance"), "The first opening card is a story scene")
	game.flow.cancel()
	game.show_cards(["opening_situation", "opening_complication", "opening_resolution"], game.enter_stage)
	freeze()
	paused = false
	check(game.card.has_method("advance") and game.card.position.x == 0.0, "A story card is placed at x=0, not slid in")
	check(game.card_progress == game.card.drain, "The card timer is the story drain bar")
	check(game.card.hint.text == game.CARD_HINT, "The story card shows the card hint")
	var x_ok := true
	advance_press(false)
	check(game.card_queue[0] == "opening_situation" and game.card_queue.size() == 3, "An advance press at 0 does not skip")
	var guard := 0
	while game.card_clock+DT <= 0.25 and guard < 40:
		game._physics_process(DT)
		if game.card.position.x != 0.0: x_ok = false
		guard += 1
	advance_press(false)
	check(game.card_clock <= 0.25 and game.card_queue[0] == "opening_situation", "An advance press at 0.25s does not skip")
	game._physics_process(DT)
	check(game.card_clock > 0.25 and game.card.position.x == 0.0, "The story card is still at x=0 just after 0.25s")
	advance_press(true)
	check(game.card_queue[0] == "opening_situation", "An echoed advance does not skip")
	var before: int = game.card_queue.size()
	advance_press(false)
	check(game.state == "cards" and game.card_queue.size() == before-1 and game.card_queue[0] == "opening_complication", "One advance press skips exactly one card")
	check(game.card.has_method("advance") and game.card.position.x == 0.0 and is_equal_approx(game.card_clock, 0.0), "The next story card starts in place at 0")
	guard = 0
	while game.card.typed_ratio() < 0.25 and guard < 180:
		game._physics_process(DT)
		if game.card.position.x != 0.0: x_ok = false
		guard += 1
	check(game.card.bars_shown() >= 1.0 and encloses(game.card.bottom_bar, game.card.hint), "The hint sits inside the bottom bar once the bars are in")
	var card_clock: float = game.card_clock
	var card_seconds: float = game.card.seconds
	var card_pos: Vector2 = game.card.picture.position
	var card_chars: int = game.card.caption.visible_characters
	var queued: int = game.card_queue.size()
	pause_press()
	game._physics_process(1.0)
	for _i in 4: await process_frame
	var frozen: bool = paused and game.state == "paused" and game.card_queue.size() == queued
	frozen = frozen and is_equal_approx(game.card_clock, card_clock) and is_equal_approx(game.card.seconds, card_seconds)
	frozen = frozen and game.card.picture.position == card_pos and game.card.caption.visible_characters == card_chars
	check(frozen, "Pause freezes the card clock and the story scene")
	pause_press()
	check(not paused and game.state == "cards" and is_equal_approx(game.card_clock, card_clock), "Resume keeps the same card and clock")
	check(is_equal_approx(game.card.seconds, card_seconds) and game.card.picture.position == card_pos, "Resume leaves the scene where pause froze it")
	check(x_ok, "Story cards stay at x=0 on every opening tick")
	game.flow.cancel()
	game.show_cards(["opening_situation", "opening_complication", "opening_resolution"], game.enter_stage)
	freeze()
	var per := ticks_to_cross(hold)
	var expect := per*3
	x_ok = true
	for _i in expect-1:
		if is_instance_valid(game.card) and game.card.position.x != 0.0: x_ok = false
		game._physics_process(DT)
	check(game.state == "cards" and game.card_queue[0] == "opening_resolution" and x_ok, "The opening is still on its last card one tick before 13.5s")
	game._physics_process(DT)
	check(game.state == "stage_enter" and not game.playing, "The three opening cards reach the stage entrance hands-free (%d ticks)" % expect)
	for plain in ["boss_ai_slop", "unlock_review", "victory"]:
		game.show_cards([plain], game.enter_stage)
		var story: bool = game.card.has_method("advance")
		check(not story and is_equal_approx(game.card.position.x, 1280.0), "%s still slides in from x=1280 and is not a story scene" % plain)
	# A resume consumes its return state, so a later hand-forced pause resumes into play rather
	# than into a card queue that has emptied.
	game.flow.cancel()
	game.show_cards(["opening_situation", "opening_complication", "opening_resolution"], game.enter_stage)
	freeze()
	pause_press()
	pause_press()
	check(game.state == "cards" and not paused and game.pause_return_state == "combat", "Resuming a card consumes its return state")
	game.state = "paused"
	paused = true
	game.resume()
	check(game.state == "combat" and game.playing and not paused and not game.card_host.visible, "A hand-forced HvV pause afterwards resumes into play with the cards hidden")

func advance_press(echo: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	key.echo = echo
	game._unhandled_input(key)
func pause_press() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	game._unhandled_input(event)

# --- The victory epilogue and the results screen ---
func check_ending_data() -> void:
	for catalog in [City, Heroes]:
		var label: String = catalog.STORY_ROOT
		var pages := StoryScene.page_list(catalog, "ENDING")
		check(pages.size() == 3, "%s ENDING has three pages" % label)
		check(StoryScene.page_list(catalog, "STORY").size() == 3 and StoryScene.page_list(catalog, "NOPE").is_empty(), "page_list reads STORY and ENDING, and nothing for an unknown list")
		for entry in pages:
			var kicker := str(entry["kicker"]).strip_edges()
			var caption := str(entry["caption"]).strip_edges()
			var tex: Texture2D = StoryScene.texture_for(entry)
			var expect := str(entry["image"] if ResourceLoader.exists(str(entry["image"])) else entry["fallback"])
			check(kicker != "" and caption != "", "%s ending page %s has a kicker and a caption" % [label.get_file(), kicker])
			check(tex != null and tex == load(expect), "%s ending page %s loads its image or fallback (%s)" % [label.get_file(), kicker, expect.get_file()])
		check(str(catalog.VICTORY.title).strip_edges() != "" and str(catalog.VICTORY.line).strip_edges() != "", "%s has a victory title and line" % label.get_file())
	check(is_equal_approx(float(City.FLOW.ending_hold), 5.0), "Code City ending pages hold 5.0s")
	check(Heroes.ENDING_CARDS.size() == 3, "HvV has three ending cards")
	for name in Heroes.ENDING_CARDS: check(is_equal_approx(float(Heroes.CARD_HOLD[name]), 5.0), "HvV %s holds 5.0s" % name)
	var scene := mount(StoryScene.new()) as StoryScene
	scene.show_scene(City, 1, "ENDING")
	check(scene.index == 1 and scene.kicker.text == str(City.ENDING[1]["kicker"]), "show_scene(list=ENDING) shows the ending page")
	scene.show_scene(City, 9, "ENDING")
	check(scene.index == 2, "An ending index past the last page shows the last one")
	scene.show_scene(City, 0, "MISSING")
	check(scene.index == 2, "An unknown list leaves the scene alone")
	drop_holder()

func lands_at(screen, score: int) -> Dictionary:
	var out := {"monotonic": true, "ticks": 0, "landed_calls": 0, "exact_before": false}
	var previous := 0
	var guard := 0
	while not screen.landed and guard < 1000:
		var before_landed: bool = screen.landed
		var crossed: bool = screen.advance(DT)
		guard += 1
		var shown: int = screen.shown_score()
		if shown < previous: out.monotonic = false
		if crossed: out.landed_calls += 1
		if not screen.landed and shown == score and score > 0 and screen.clock < screen.COUNT-0.3: out.exact_before = true
		previous = shown
	out.ticks = guard
	return out

func key_event(action_key: Key, pressed := true, echo := false) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = action_key
	key.keycode = action_key
	key.pressed = pressed
	key.echo = echo
	return key
func accept_press() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	return event
func click_press() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click

func check_victory_screen() -> void:
	var presses := [0]
	var screen := mount(VictoryScreen.new()) as VictoryScreen
	check(not screen.visible, "The results screen starts hidden")
	screen.show_result("T", "line", 12480, 95.0, Color.RED, "Back", func(): presses[0] += 1)
	await process_frame
	check(screen.visible and screen.shown_score() == 0 and screen.score_label.text == "000,000", "The count starts at zero")
	check(screen.time_label.text == "TIME  1:35" and screen.action.text == "Back" and screen.title.text.contains("T"), "Title, time and button label are set")
	check(screen.action.disabled and not screen.armed(), "The button is disabled before the count lands")
	var run := lands_at(screen, 12480)
	check(run.monotonic and not run.exact_before, "The count is monotonic and not at the score before COUNT")
	check(screen.landed and screen.shown_score() == 12480 and screen.score_label.text == "012,480", "The count lands exactly on the score")
	check(absi(run.ticks-int(ceil(screen.COUNT/DT))) <= 2 and run.landed_calls == 1, "It lands at COUNT on exactly one advance() call (%d ticks)" % run.ticks)
	check(not screen.advance(DT) and not screen.advance(DT), "advance() is true only on the landing frame")
	check(not screen.action.disabled and screen.armed() and screen.action.has_focus(), "The button is enabled and focused once landed and armed")
	# skip() lands the count at once.
	screen.show_result("T", "line", 5000, 10.0, Color.RED, "Back", func(): presses[0] += 1)
	check(screen.shown_score() == 0 and not screen.landed and screen.action.disabled, "A new result restarts the count and disables the button")
	screen.advance(.4)
	var mid: int = screen.shown_score()
	check(mid > 0 and mid < 5000, "Part-way through, the score is between zero and the total (%d)" % mid)
	screen.skip()
	check(screen.landed and screen.shown_score() == 5000 and screen.score_label.text == "005,000", "skip() lands the count")
	check(screen.advance(DT), "The first advance() after skip() reports the landing, so the win cue still plays")
	check(not screen.advance(DT), "Later advance() calls after skip() do not report it again")
	# Input before ARM is swallowed and never skips.
	screen.show_result("T", "line", 5000, 10.0, Color.RED, "Back", func(): presses[0] += 1)
	screen.advance(.2)
	screen._input(accept_press())
	screen._input(click_press())
	screen._input(key_event(KEY_ENTER))
	check(not screen.landed and presses[0] == 0, "Confirms and clicks before ARM are swallowed and do not skip")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	screen._input(touch)
	check(not screen.landed, "A touch before ARM does not skip")
	screen.advance(screen.ARM)
	check(not screen.landed and screen.action.disabled, "After ARM and before the landing the button is still disabled")
	screen._input(accept_press())
	check(screen.landed and screen.shown_score() == 5000 and presses[0] == 0, "A confirm after ARM lands the count (and does not press the button)")
	check(not screen.action.disabled and screen.action.has_focus(), "The button enables and takes focus after the skip")
	screen.action.pressed.emit()
	check(presses[0] == 1, "The button presses once enabled")
	# A re-shown result replaces the callback rather than stacking it.
	var later := [0]
	screen.show_result("T", "line", 1, 1.0, Color.RED, "Back", func(): later[0] += 1)
	screen.skip()
	screen.advance(1.0)
	screen.action.pressed.emit()
	check(presses[0] == 1 and later[0] == 1, "show_result replaces the button callback")
	screen.show_result("T", "line", -50, -3.0, Color.RED, "Back", func(): pass)
	screen.skip()
	check(screen.shown_score() == 0 and screen.time_label.text == "TIME  0:00", "A negative score and time clamp to zero")
	check(VictoryScreen._grouped(7) == "000,007" and VictoryScreen._grouped(1234567) == "1,234,567", "Scores group thousands")
	# A mode with its own confirm action (HvV) confirms with it alone: ui_accept is its jump.
	if not InputMap.has_action("victory_test_advance"): InputMap.add_action("victory_test_advance")
	var dedicated := InputEventAction.new()
	dedicated.action = "victory_test_advance"
	dedicated.pressed = true
	var own := [0]
	screen.confirm_actions = ["victory_test_advance"]
	screen.show_result("T", "line", 900, 1.0, Color.RED, "Back", func(): own[0] += 1)
	screen.advance(screen.ARM)
	screen._input(accept_press())
	check(not screen.landed, "With its own confirm action, ui_accept does not land the count")
	screen._input(dedicated)
	check(screen.landed and own[0] == 0, "The dedicated confirm lands the count")
	push_accept(screen)
	check(own[0] == 0, "ui_accept through the viewport does not reach the focused button once landed")
	screen._input(dedicated)
	check(own[0] == 1, "The dedicated confirm presses the button once landed")
	# Control: without its own confirm actions (Code City) the same ui_accept presses the button.
	screen.confirm_actions = []
	var city := [0]
	screen.show_result("T", "line", 900, 1.0, Color.RED, "Back", func(): city[0] += 1)
	screen.advance(screen.ARM)
	screen.skip()
	screen.advance(DT)
	push_accept(screen)
	check(city[0] == 1, "Without its own confirm actions, ui_accept through the viewport presses the button")
	drop_holder()

## A ui_accept press and release through the viewport, so the GUI's focused button sees whatever
## the screen's _input lets through.
func push_accept(screen: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = pressed
		screen.get_viewport().push_input(event)

## Steps the real tick loop from the boss's last hit to the results screen. Everything between
## runs on the game's own clocks; only the guard counts ticks.
func city_to_finisher() -> void:
	game.flow.cancel()
	game.start_stage(2)
	freeze()
	var guard := 0
	while game.state != "combat" and guard < 2000:
		game._physics_process(DT)
		guard += 1
	for e in game.enemies:
		if is_instance_valid(e): e.free()
	game.enemies.clear()
	game.enter_room(2)
	freeze()
	var boss = game.boss
	for damage in [12, 6, 6]:
		boss.vulnerable = true
		boss.take_hit(damage, 0, Vector2.ZERO, true)
	freeze()
func win_sounds_between(before: int) -> int:
	var count := 0
	for i in range(before, game.sound_index):
		if game.sound_pool[i%game.sound_pool.size()].stream == City.SOUNDS["win"]: count += 1
	return count

func run_city_ending_hands_free() -> void:
	city_to_finisher()
	check(game.state == "finisher", "The boss's last hit starts the Force Merge finisher")
	var guard := 0
	var celebrated := false
	while game.state in ["finisher", "celebration"] and guard < 1200:
		game._physics_process(DT)
		if game.state == "celebration": celebrated = true
		guard += 1
	check(celebrated and game.state == "ending" and game.story_pages == "ENDING" and game.intro_page == 0 and game.story.visible, "The finisher hands off through the celebration to the ending (%d ticks)" % guard)
	check(game.completion_count == 0 and not game.minimap.visible and not game.victory.visible, "The ending is not yet a win, and has no minimap or results")
	check(game.story.kicker.text == str(City.ENDING[0]["kicker"]) and game.intro_next.text == "Next →" and game.intro_skip.text == "Skip" and not game.intro_return.visible, "Ending page 1: Next, Skip, and no Return")
	var per := ticks_to_cross(float(City.FLOW.ending_hold))
	var expect := per*City.ENDING.size()
	var kickers_ok := true
	var count := 0
	while game.state == "ending" and count < expect+30:
		if game.story.kicker.text != str(City.ENDING[game.intro_page]["kicker"]): kickers_ok = false
		if count == expect-1: check(game.intro_page == City.ENDING.size()-1 and game.intro_next.text == "Results →", "One tick before the end the last page offers Results")
		game._physics_process(DT)
		count += 1
	check(kickers_ok, "Each ending page shows its own kicker as it turns")
	check(absi(count-expect) <= 3 and game.state == "won", "The three ending pages auto-advance into the results (%d ticks, expected %d)" % [count, expect])
	check(game.completion_count == 1 and game.victory.visible and not game.story.visible and not game.overlay.visible, "Results show once, with the story and overlay hidden")
	check(game.victory.final_score == game.score and game.victory.title.text.contains(City.VICTORY.title), "The results show the run's score and the victory title")
	check(game.victory.shown_score() == 0 and game.victory.action.disabled, "The score starts at zero")
	var before: int = game.sound_index
	var steps := 0
	var win_at := -1
	var last := -1
	while not game.victory.landed and steps < 400:
		var seen: int = game.sound_index
		game._physics_process(DT)
		steps += 1
		if win_sounds_between(seen) > 0: win_at = steps
		if game.victory.shown_score() < last: win_at = -99
		last = game.victory.shown_score()
	check(game.victory.landed and game.victory.shown_score() == game.score and absi(steps-int(ceil(VictoryScreen.COUNT/DT))) <= 2, "The count reaches exactly the score at COUNT (%d ticks)" % steps)
	check(win_sounds_between(before) == 1 and win_at == steps, "The win sound plays once, on the frame the count lands")
	var rest: int = game.sound_index
	for _i in 120: game._physics_process(DT)
	check(win_sounds_between(rest) == 0 and game.completion_count == 1 and game.state == "won", "No further win sound and no second completion afterwards")
	check(not game.victory.action.disabled and game.victory.action.has_focus(), "Return to the menu is enabled and focused after the count")
	game.boss_defeated()
	game.show_victory()
	check(game.completion_count == 1 and game.state == "won", "boss_defeated() and show_victory() cannot count a second completion")

func check_city_ending_controls() -> void:
	# Next, and the Return button hidden, then Skip.
	city_to_finisher()
	var guard := 0
	while game.state in ["finisher", "celebration"] and guard < 1200:
		game._physics_process(DT)
		guard += 1
	check(game.state == "ending" and not game.intro_return.visible, "The ending starts with Return hidden")
	game.intro_next.pressed.emit()
	check(game.state == "ending" and game.intro_page == 1 and is_equal_approx(game.intro_clock, 0.0), "Next turns to ending page 2 and resets the clock")
	check(game.story.kicker.text == str(City.ENDING[1]["kicker"]) and focused_next(), "Page 2 shows its kicker with Next focused")
	# Pause freezes the ending and resume restores the page.
	for _i in 60: game._physics_process(DT)
	var clock: float = game.intro_clock
	var seconds: float = game.story.seconds
	game.pause("x")
	game._physics_process(1.0)
	for _i in 4: await process_frame
	var frozen: bool = game.state == "paused" and game.pause_return_state == "ending" and game.intro_page == 1
	frozen = frozen and is_equal_approx(game.intro_clock, clock) and is_equal_approx(game.story.seconds, seconds)
	check(frozen, "Pause freezes the ending clock and the story scene")
	for child in game.story.actions.get_children():
		if child is Button: child.pressed.emit()
	check(game.state == "paused" and game.intro_page == 1 and is_equal_approx(game.intro_clock, clock), "Next, Skip and Return do nothing while the ending is paused")
	game.resume()
	paused = false
	var restored: bool = game.state == "ending" and game.intro_page == 1 and is_equal_approx(game.intro_clock, clock)
	restored = restored and game.story.kicker.text == str(City.ENDING[1]["kicker"]) and is_equal_approx(game.story.seconds, clock)
	check(restored and focused_next(), "Resume restores the ending page, its clock and the focus")
	# A second boss_defeated is ignored.
	var completions: int = game.completion_count
	game.boss_defeated()
	check(game.state == "ending" and game.completion_count == completions and game.intro_page == 1, "A second boss_defeated during the ending is ignored")
	game.intro_next.pressed.emit()
	check(game.state == "ending" and game.intro_page == 2 and game.intro_next.text == "Results →", "Next to the last page reads Results")
	game.intro_next.pressed.emit()
	check(game.state == "won" and game.completion_count == completions+1 and game.victory.visible, "Results → opens the results screen")
	# Skip.
	city_to_finisher()
	guard = 0
	while game.state in ["finisher", "celebration"] and guard < 1200:
		game._physics_process(DT)
		guard += 1
	var skip := action_button("Skip")
	check(skip != null and game.state == "ending" and action_button("Skip intro") == null, "The ending's skip button reads Skip")
	var done: int = game.completion_count
	if skip: skip.pressed.emit()
	check(game.state == "won" and game.completion_count == done+1 and game.victory.visible and not game.story.visible, "Skip goes straight to the results screen and completes once")
	# The next opening restores the intro's own labels.
	game.flow.cancel()
	game.start_stage(0, true)
	freeze()
	check(game.state == "intro" and game.story_pages == "STORY" and action_button("Skip intro") != null and game.intro_return.visible, "A new opening restores Skip intro and Return")

func check_hvv_ending() -> void:
	await load_mode("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	game.flow.cancel()
	game.start_stage(2)
	await process_frame
	freeze()
	game.begin_play()
	game.enter_room(2)
	freeze()
	for e in game.enemies:
		if is_instance_valid(e): e.free()
	game.enemies.clear()
	var hacker = game.bosses[0]
	hacker.take_hit(99, 0, Vector2.ZERO)
	hacker.tick(1)
	hacker.tick(2)
	hacker.take_hit(99, 0, Vector2.ZERO)
	hacker.tick(1)
	hacker.tick(2)
	hacker.take_hit(999, 0, Vector2.ZERO)
	game.check_boss_state()
	check(game.state == "boss_victory", "The Hacker's defeat starts the boss victory")
	game._physics_process(game.VICTORY_DURATION)
	var chain := ["unlock_security"]
	chain.append_array(Heroes.ENDING_CARDS)
	check(game.state == "cards" and game.card_queue == chain, "The last reward is unlock_security plus the three ending cards")
	check(game.card_callback == Callable(game, "win") and game.completion_count == 0, "The chain ends in win(), and nothing has completed yet")
	var guard := 0
	while game.card_queue[0] == "unlock_security" and guard < 600:
		game._physics_process(DT)
		guard += 1
	check(absi(guard-int(round(4.5/DT))) <= 3, "unlock_security holds 4.5s (%d ticks)" % guard)
	for i in Heroes.ENDING_CARDS.size():
		var name: String = Heroes.ENDING_CARDS[i]
		var entry: Dictionary = Heroes.ENDING[i]
		check(game.state == "cards" and game.card_queue[0] == name, "Ending card %d is %s" % [i+1, name])
		check(game.card.has_method("advance") and game.card.index == i and game.card.kicker.text == str(entry["kicker"]), "%s is a story scene showing ENDING page %d" % [name, i])
		check(game.card.pages == "ENDING" and game.card.position.x == 0.0 and game.card.picture.texture != null, "%s reads the ENDING list, sits at x=0 and has a picture" % name)
		check(game.card.caption.text == str(entry["caption"]) and not game.minimap.visible, "%s shows its caption with the minimap hidden" % name)
		var ticks := 0
		while game.card_queue.size() > 0 and game.card_queue[0] == name and ticks < 600:
			game._physics_process(DT)
			ticks += 1
		check(absi(ticks-ticks_to_cross(5.0)) <= 3, "%s holds 5.0s (%d ticks)" % [name, ticks])
	check(game.state == "won" and game.completion_count == 1 and game.victory.visible and not game.card_host.visible and not game.overlay.visible, "The ending cards lead to the results screen; completion counts once")
	check(game.victory.confirm_actions == ["heroes_popup_advance"] and game.victory.final_score == game.score, "The results screen takes the popup-advance and shows the score")
	check(game.victory.shown_score() == 0 and game.victory.action.disabled, "The HvV score starts at zero")
	var before: int = game.sound_index
	var steps := 0
	var last := -1
	var monotonic := true
	var win_at := -1
	while not game.victory.landed and steps < 400:
		var seen: int = game.sound_index
		game._physics_process(DT)
		steps += 1
		if win_sounds_between(seen) > 0: win_at = steps
		if game.victory.shown_score() < last: monotonic = false
		last = game.victory.shown_score()
	check(monotonic and game.victory.shown_score() == game.score and absi(steps-int(ceil(VictoryScreen.COUNT/DT))) <= 2, "The HvV count is monotonic and lands exactly on the score (%d ticks)" % steps)
	check(win_sounds_between(before) == 1 and win_at == steps, "The HvV win sound plays once, when the count lands")
	for _i in 120: game._physics_process(DT)
	check(win_sounds_between(before) == 1 and game.completion_count == 1, "No further win sound or completion afterwards")
	game.boss_defeated()
	game.win()
	check(game.completion_count == 1 and game.state == "won", "HvV completion counts exactly once")
	check(not game.victory.action.disabled and game.victory.action.has_focus(), "HvV Return is enabled and focused after the count")

