extends SceneTree
## Clock-driven story scenes for both beat'em up openings. The host ticks by hand;
## nothing here depends on a Tween or on the engine advancing the game clock.
const StoryScene = preload("res://modes/beatem_up/story_scene.gd")
const City = preload("res://modes/beatem_up/catalog.gd")
const Heroes = preload("res://modes/beatem_up/reinvent/catalog.gd")
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
	await check_return_to_menu()

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
