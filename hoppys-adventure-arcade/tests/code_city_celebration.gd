extends SceneTree
## The Code City victory party (modes/beatem_up/celebration.gd) on a stub owner, so it needs
## none of the game's finisher hooks. Covers the clock, the victory pose, the boss-music duck,
## the single jingle, the loop hand-off to the flow, cancel and replay, coarse steps, an owner
## without a camera, and loop-resource immutability. Rendered runs also save captures.
const Celebration = preload("res://modes/beatem_up/celebration.gd")
const StageFlow = preload("res://modes/beatem_up/stage_flow.gd")
const COMBAT := "res://Assets/code-city-brawl-player/combat.tres"
const MANIFEST := "res://Assets/code-city-brawl-player/manifest.json"
const JINGLE := "res://Assets/Audio/Beat'em Up/code_city_victory_jingle.wav"
const LOOP := "res://Assets/Audio/Beat'em Up/code_city_victory_loop.wav"
const BOSS_MUSIC := "res://Assets/Audio/Beat'em Up/code_city_district_boss.ogg"
const CAPTURE_DIR := "/tmp/s3-captures/celebration"
const DT := 1.0/60.0
## Frames to wait for the last autoload before giving up, so a stuck start fails instead of hanging.
const READY_FRAMES := 600
## Contract times, seconds on the party clock.
const JINGLE_AT := .3
const LOOP_AT := 3.8
const LENGTH := 5.2
const WALL_MAX := 6.0
const HUD_COLOR := Color(1.0, 0.0, 1.0)
const MENU_COLOR := Color(0.0, 1.0, 1.0)

class StubPlayer extends Node2D:
	var body := AnimatedSprite2D.new()
	var facing := 1.0
	var poses: Array[String] = []
	func _init() -> void:
		body.sprite_frames = load("res://Assets/code-city-brawl-player/combat.tres")
		body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(body)
	func show_pose(pose: String, _base := false) -> void:
		poses.append(pose)
		if body.sprite_frames.has_animation(pose): body.play(pose)

class StubOwner extends Node2D:
	var player: StubPlayer
	var ui_layer := CanvasLayer.new()
	var camera: Camera2D = Camera2D.new()
	var flow
	var music := AudioStreamPlayer.new()
	var shake := 0.0
	func sound(_key: String, _at: Vector2 = Vector2.ZERO) -> void: pass

## An owner with the optional knockout_hud_nodes() hook, as the real games have.
class StubHudOwner extends StubOwner:
	var hud_nodes: Array[CanvasItem] = []
	func knockout_hud_nodes() -> Array[CanvasItem]: return hud_nodes

class StubNoCamera extends Node2D:
	var player: StubPlayer
	var ui_layer := CanvasLayer.new()
	var flow
	var music := AudioStreamPlayer.new()
	var shake := 0.0
	func sound(_key: String, _at: Vector2 = Vector2.ZERO) -> void: pass

var failures := 0
var passes := 0
var party
var stage
var calls := 0
var boss_stream: AudioStream

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if ok: passes += 1
	else: failures += 1

func done() -> void: calls += 1

## A fresh stub owner in the tree with its flow and boss music playing, like the finisher's start.
func make_owner(with_camera := true, hud := false):
	var owner = StubHudOwner.new() if hud else StubOwner.new() if with_camera else StubNoCamera.new()
	owner.player = StubPlayer.new()
	owner.add_child(owner.player)
	owner.add_child(owner.ui_layer)
	owner.add_child(owner.music)
	if with_camera:
		owner.add_child(owner.camera)
		owner.camera.position = Vector2(640, 360)
		owner.camera.zoom = Vector2.ONE
	var flow = StageFlow.new()
	owner.add_child(flow)
	flow.setup(owner.ui_layer, owner.music, {})
	owner.flow = flow
	if hud: add_hud_fixtures(owner)
	root.add_child(owner)
	boss_stream = load(BOSS_MUSIC)
	flow.play_music(boss_stream)
	if stage != null and is_instance_valid(stage): stage.free()
	stage = owner
	party = Celebration.new()
	calls = 0
	return owner

## HUD chrome in loud magenta so a leak is unmistakable in a capture: a top strip with the score,
## a bottom controls strip, a boss-name plate and a minimap, plus a node that was already hidden.
## `menu` is the pause/menu overlay: it is NOT in the hook's list and must always stay visible.
func add_hud_fixtures(owner) -> void:
	var make := func(name: String, rect: Rect2, text: String) -> ColorRect:
		var panel := ColorRect.new()
		panel.name = name
		panel.color = HUD_COLOR
		panel.position = rect.position
		panel.size = rect.size
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 22)
		label.position = Vector2(14, 8)
		panel.add_child(label)
		owner.ui_layer.add_child(panel)
		return panel
	var top: ColorRect = make.call("HudTop", Rect2(0, 0, 1280, 60), "HOPPY  ♥ ♥ ♥     SCORE 01234     CLI / IDE DISTRICT · 3/3")
	var bottom: ColorRect = make.call("HudControls", Rect2(0, 668, 1280, 44), "WASD · Move    Space · Jump    J, X · Combo    E · Pickup    Esc · Pause")
	var boss: ColorRect = make.call("HudBoss", Rect2(380, 70, 520, 34), "GRAND MERGE CONFLICT")
	var minimap: ColorRect = make.call("HudMinimap", Rect2(1020, 320, 240, 90), "MINIMAP")
	var prior: ColorRect = make.call("HudPriorHidden", Rect2(0, 600, 200, 40), "HIDDEN")
	prior.visible = false
	var menu := ColorRect.new()
	menu.name = "PauseMenu"
	menu.color = MENU_COLOR
	menu.position = Vector2(20, 560)
	menu.size = Vector2(160, 60)
	owner.ui_layer.add_child(menu)
	owner.hud_nodes.assign([top, bottom, boss, minimap, prior])
	owner.set_meta("menu", menu)
func hud_states(owner) -> Array:
	var states := []
	for n in owner.hud_nodes: states.append(is_instance_valid(n) and n.visible)
	return states
## What a game does before each party tick: its minimap, toast and HUD refresh show themselves.
func owner_refresh(owner) -> void:
	for n in owner.hud_nodes:
		if is_instance_valid(n): n.visible = true
func run_for(seconds: float, dt := DT) -> void:
	var left := seconds
	while left>1e-6 and party.active():
		var step := minf(dt, left)
		party.tick(step)
		left -= step

## Players the party made itself: every AudioStreamPlayer under the owner that isn't the flow's.
func jingles(owner) -> Array[AudioStreamPlayer]:
	var found: Array[AudioStreamPlayer] = []
	for child in owner.get_children():
		if child is AudioStreamPlayer and child!=owner.music and not is_queued_for_free(child): found.append(child)
	return found
func is_queued_for_free(node: Node) -> bool: return node.is_queued_for_deletion()
func playing_jingles(owner) -> int:
	var count := 0
	for j in jingles(owner):
		if j.playing: count += 1
	return count
## Visible Control or Node2D chrome the party added to the UI layer.
func visible_ui(owner) -> int:
	var count := 0
	for child in owner.ui_layer.get_children():
		if child is CanvasItem and child.visible and not child.is_queued_for_deletion() and child.name!="StageFlow": count += 1
	return count
func pose_has_victory(owner) -> bool:
	return "victory" in owner.player.poses

func run() -> void:
	# Rendered, SaveService's window-mode call pumps the loop inside its _ready and fires the deferred
	# run() early, so wait for the last autoload.
	var waited := 0
	while not (root.has_node("ControllerService") and root.get_node("ControllerService").is_node_ready()) and waited < READY_FRAMES:
		await process_frame
		waited += 1
	if not (root.has_node("ControllerService") and root.get_node("ControllerService").is_node_ready()):
		check(false, "ControllerService is ready within %d frames" % READY_FRAMES)
		quit(1)
		return
	await process_frame
	await settle_window()
	check_asset_clip()
	check_music_assets()
	check_clock_and_poses()
	check_music_flow()
	check_camera()
	check_no_camera()
	check_cancel_phases()
	check_cancel_ownership()
	check_replay_and_callbacks()
	check_coarse_steps()
	check_loop_immutable()
	check_pause_clock()
	check_hud_hidden()
	check_hud_restore()
	check_hud_edge_cases()
	await check_capture()
	await check_real_game()
	print("Celebration passes: ", passes, " failures: ", failures)
	if is_instance_valid(stage): stage.free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)

## The new victory clip: three frames, the same 96x96 cell and 48,86 pivot as every clip.
func check_asset_clip() -> void:
	var frames: SpriteFrames = load(COMBAT)
	var has := frames!=null and frames.has_animation("victory")
	check(has, "combat.tres has a victory clip")
	if has:
		check(frames.get_frame_count("victory")==3, "the victory clip has 3 frames (%d)" % frames.get_frame_count("victory"))
		check(frames.get_animation_loop("victory"), "the victory clip loops")
		var cells_ok := true
		for i in frames.get_frame_count("victory"):
			var tex := frames.get_frame_texture("victory", i)
			if not (tex is AtlasTexture) or tex.region.size!=Vector2(96, 96): cells_ok = false
		check(cells_ok, "every victory frame is a 96x96 cell")
		check(frames.get_animation_speed("victory")>0.0, "the victory clip has a positive speed")
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var manifest_ok: bool = data is Dictionary and Vector2(data.cell[0], data.cell[1])==Vector2(96, 96) and Vector2(data.pivot[0], data.pivot[1])==Vector2(48, 86)
	check(manifest_ok, "the manifest keeps the 96x96 cell and the 48,86 pivot")
	var clip = data.clips.get("victory") if data is Dictionary and data.has("clips") else null
	check(clip is Array and clip[0].size()==3 and bool(clip[2]), "the manifest lists victory as 3 looping frames")

func check_music_assets() -> void:
	var jingle = load(JINGLE) if ResourceLoader.exists(JINGLE) else null
	var loop = load(LOOP) if ResourceLoader.exists(LOOP) else null
	check(jingle is AudioStream, "the jingle asset loads")
	check(loop is AudioStream, "the loop asset loads")
	if jingle is AudioStream:
		var length: float = jingle.get_length()
		check(length>3.2 and length<=LOOP_AT-JINGLE_AT+.05, "the jingle is about 3.5 s so it ends as the loop begins (%.2f)" % length)
	if loop is AudioStream:
		check(loop.get_length()>2.0, "the loop is long enough to carry the ending pages (%.2f s)" % loop.get_length())
	for asset in [jingle, loop]:
		if asset is AudioStreamWAV:
			var name := "jingle" if asset==jingle else "loop"
			check(asset.format==AudioStreamWAV.FORMAT_16_BITS, "the %s imports as raw 16-bit PCM (format %d)" % [name, asset.format])
			var bytes: PackedByteArray = asset.data
			var channels := 2 if asset.stereo else 1
			if asset.format==AudioStreamWAV.FORMAT_16_BITS and bytes.size()>=2*channels:
				var ends := true
				for c in channels:
					if bytes.decode_s16(c*2)!=0 or bytes.decode_s16(bytes.size()-(channels-c)*2)!=0: ends = false
				check(ends, "the %s's first and last samples are exactly zero, so the seam can't click" % name)
	if jingle is AudioStream and "loop_mode" in jingle:
		check(jingle.loop_mode==AudioStreamWAV.LOOP_DISABLED, "the jingle does not loop")

func check_clock_and_poses() -> void:
	var owner = make_owner()
	check(not party.active(), "a new party is idle")
	party.play(owner, done)
	check(party.active() and calls==0, "play() starts the party without calling done")
	check(pose_has_victory(owner), "Hoppy takes the victory pose at once")
	check(visible_ui(owner)>0, "the banner and confetti layer appears in the UI layer")
	run_for(LENGTH-DT*3.0)
	check(party.active() and calls==0, "the party is still running just before 5.2 s")
	run_for(DT*6.0)
	check(not party.active() and calls==1, "the party ends and calls done once at 5.2 s")
	check(visible_ui(owner)==0, "the UI is cleared once the party ends")
	check(owner.player.body.position.is_equal_approx(Vector2.ZERO) and is_zero_approx(owner.player.body.rotation), "Hoppy's body rests on the shadow afterwards")
	run_for(2.0)
	party.tick(1.0)
	check(calls==1, "ticking after the end never calls done again")
	party.cancel()
	check(calls==1 and not party.active(), "cancel() after the end is quiet")

func check_music_flow() -> void:
	var owner = make_owner()
	var flow = owner.flow
	party.play(owner, done)
	var boss_playing: bool = flow.music.playing
	run_for(.1)
	check(flow.music_db<0.0 and boss_playing, "the boss track ducks as the party starts (%.1f dB)" % flow.music_db)
	check(flow.music.stream==boss_stream, "the boss track is only ducked, not replaced, before the loop")
	check(playing_jingles(owner)==0, "the jingle has not started before 0.3 s")
	run_for(JINGLE_AT+.1)
	check(playing_jingles(owner)==1, "one jingle player plays after 0.3 s on its own child player")
	check(jingles(owner).size()==1 and jingles(owner)[0]!=flow.music, "the jingle is not the flow's music player")
	check(flow.music.stream==boss_stream and flow.music_db<0.0, "the boss track stays ducked under the jingle")
	run_for(LOOP_AT-JINGLE_AT-.3)
	check(playing_jingles(owner)<=1 and jingles(owner).size()==1, "the jingle is never doubled")
	check(flow.music.stream==boss_stream, "the boss track is still the flow's stream just before the loop is due (%.2f s)" % party.clock)
	# Timed on the party's own clock, so the switch time can't drift from a local counter.
	var seen_loop := false
	var swapped_at := -1.0
	while party.active() and party.clock<LENGTH:
		party.tick(DT)
		if flow.music.stream!=boss_stream and swapped_at<0.0:
			swapped_at = party.clock
			seen_loop = true
		if party.clock>LOOP_AT+.2: break
	check(seen_loop and absf(swapped_at-LOOP_AT)<=.25, "the flow's music switches to the loop at about 3.8 s (%.2f)" % swapped_at)
	check(is_equal_approx(flow.music_db, 0.0), "the duck is lifted once the loop starts")
	check(flow.music.playing and flow.music_track!=boss_stream, "the loop is playing on the flow's player")
	run_for(10.0)
	check(calls==1 and not party.active(), "the party completes once")
	check(flow.music.playing and flow.music.stream!=boss_stream, "the loop is flow-owned and keeps playing after completion")
	var looped: AudioStream = flow.music.stream
	var loops: bool = looped!=null and (("loop_mode" in looped and looped.loop_mode!=AudioStreamWAV.LOOP_DISABLED) or ("loop" in looped and looped.loop))
	check(loops, "the stream the flow plays loops (without editing the shared asset)")
	if looped is AudioStreamWAV:
		var pcm: PackedByteArray = looped.data
		var tail_ok: bool = looped.format==AudioStreamWAV.FORMAT_16_BITS and pcm.size()>=2 and pcm.decode_s16(0)==0 and pcm.decode_s16(pcm.size()-(4 if looped.stereo else 2))==0
		check(tail_ok, "the runtime loop is 16-bit PCM with a zero first and last sample")
	check(playing_jingles(owner)==0, "the jingle player is stopped at completion")
	check(is_equal_approx(flow.music_db, 0.0), "the duck stays lifted after completion")
	var held: AudioStream = flow.music.stream
	party.cancel()
	check(not flow.music.playing or flow.music.stream!=held, "cancel() after completion stops the party's own loop")

func check_camera() -> void:
	var owner = make_owner()
	var pos := Vector2(900, 300)
	var zoom := Vector2(1.05, 1.05)
	owner.camera.position = pos
	owner.camera.zoom = zoom
	party.play(owner, done)
	var peak := 0.0
	var moved := false
	for _i in int(LENGTH/DT)+30:
		if not party.active(): break
		party.tick(DT)
		peak = maxf(peak, owner.camera.zoom.x)
		if not owner.camera.position.is_equal_approx(pos): moved = true
	check(peak>zoom.x+.03, "the camera pushes in during the party (peak %.3f)" % peak)
	check(calls==1 and owner.camera.position.is_equal_approx(pos) and owner.camera.zoom.is_equal_approx(zoom), "completion restores the camera position and zoom (%s, %s)" % [str(owner.camera.position), str(owner.camera.zoom)])
	owner.camera.position = pos
	owner.camera.zoom = zoom
	party.play(owner, done)
	run_for(2.0)
	check(not owner.camera.zoom.is_equal_approx(zoom), "the camera is mid-push before cancel")
	party.cancel()
	check(owner.camera.position.is_equal_approx(pos) and owner.camera.zoom.is_equal_approx(zoom), "cancel() restores the camera position and zoom")

func check_no_camera() -> void:
	var owner = make_owner(false)
	check(not ("camera" in owner), "the stub owner has no camera")
	party.play(owner, done)
	run_for(LENGTH+1.0)
	check(calls==1 and not party.active(), "a party without a camera still runs to done once")
	check(pose_has_victory(owner), "the camera-less party still poses Hoppy")
	party.play(owner, done)
	run_for(1.0)
	party.cancel()
	check(calls==1 and visible_ui(owner)==0, "cancelling a camera-less party clears its UI")

func check_cancel_phases() -> void:
	for cut in [.05, 1.0, 3.0, 4.5]:
		var owner = make_owner()
		var flow = owner.flow
		party.play(owner, done)
		run_for(cut)
		party.cancel()
		var label := "cancel() at %.2f s" % cut
		check(not party.active() and calls==0, label+" ends the party without done")
		check(visible_ui(owner)==0, label+" clears the UI")
		check(playing_jingles(owner)==0, label+" stops the jingle")
		check(is_equal_approx(flow.music_db, 0.0), label+" lifts the duck")
		check(owner.camera.position.is_equal_approx(Vector2(640, 360)) and owner.camera.zoom.is_equal_approx(Vector2.ONE), label+" restores the camera")
		check(owner.player.body.position.is_equal_approx(Vector2.ZERO) and is_zero_approx(owner.player.body.rotation), label+" rests the body")
		party.tick(1.0)
		run_for(LENGTH+1.0)
		check(calls==0, label+" never calls done afterwards")
		party.cancel()
		check(calls==0, label+" is idempotent")

## Cancel stops only the track the party started; music something else started later is left alone.
func check_cancel_ownership() -> void:
	var owner = make_owner()
	var flow = owner.flow
	party.play(owner, done)
	run_for(2.0)
	party.cancel()
	check(flow.music.stream==boss_stream and flow.music.playing, "cancel() before the switch leaves the boss track playing")
	owner = make_owner()
	flow = owner.flow
	party.play(owner, done)
	run_for(LENGTH+.5)
	var next: AudioStream = load(BOSS_MUSIC)
	flow.play_music(next)
	party.cancel()
	check(flow.music.playing and flow.music.stream==next, "cancel() leaves music started after the party playing")
	owner = make_owner()
	flow = owner.flow
	party.play(owner, done)
	run_for(LOOP_AT+.5)
	party.cancel()
	check(not flow.music.playing or flow.music.stream==boss_stream, "cancel() after the switch stops the party's loop")

func check_replay_and_callbacks() -> void:
	var owner = make_owner()
	var first := [0]
	var second := [0]
	party.play(owner, func(): first[0] += 1)
	run_for(1.5)
	party.play(owner, func(): second[0] += 1)
	check(party.active() and visible_ui(owner)>0, "replaying restarts the party")
	check(jingles(owner).size()<=1, "replay leaves at most one jingle player")
	run_for(LENGTH+1.0)
	check(first[0]==0 and second[0]==1, "replay calls only the latest done, once")
	check(visible_ui(owner)==0 and playing_jingles(owner)==0, "replay leaves no stray UI or jingle")
	# done may start another party (the next stage's) without being re-entered or double counted.
	var chained := [0]
	var again := func():
		chained[0] += 1
		if chained[0]==1: party.play(owner, func(): chained[0] += 10)
	party.play(owner, again)
	run_for(LENGTH+.5)
	check(chained[0]==1 and party.active(), "a done that starts a new party is not cancelled by the old one")
	run_for(LENGTH+.5)
	check(chained[0]==11, "the chained party completes on its own")
	# done may cancel: it must not recurse or double fire.
	var cancelling := [0]
	party.play(owner, func():
		cancelling[0] += 1
		party.cancel())
	run_for(LENGTH+.5)
	check(cancelling[0]==1, "a done that calls cancel() fires once")

func check_coarse_steps() -> void:
	for step in [.25, .5, 1.0, 2.5, 10.0]:
		var owner = make_owner()
		party.play(owner, done)
		var guard := 0
		while party.active() and guard<64:
			party.tick(step)
			guard += 1
		check(calls==1 and not party.active(), "dt %.2f finishes with done once" % step)
		check(owner.flow.music.stream!=boss_stream and is_equal_approx(owner.flow.music_db, 0.0), "dt %.2f still reaches the loop with the duck lifted" % step)
		check(visible_ui(owner)==0 and playing_jingles(owner)==0, "dt %.2f leaves nothing behind" % step)
		check(owner.camera.zoom.is_equal_approx(Vector2.ONE), "dt %.2f restores the camera" % step)
	var owner = make_owner()
	party.play(owner, done)
	party.tick(0.0)
	party.tick(-1.0)
	check(party.active() and calls==0, "a zero or negative dt does not advance or end the party")
	var wall := 0.0
	while party.active() and wall<WALL_MAX+1.0:
		party.tick(DT)
		wall += DT
	check(wall<=WALL_MAX, "the party finishes inside 6 s of wall time (%.2f)" % wall)

## The loop resource is shared and cached by the engine: the party must not edit it.
func check_loop_immutable() -> void:
	if not ResourceLoader.exists(LOOP) or not ResourceLoader.exists(JINGLE): return
	var loop: AudioStream = load(LOOP)
	var jingle: AudioStream = load(JINGLE)
	if loop==null or jingle==null:
		check(false, "the loop and jingle load as audio streams for the immutability check")
		return
	var before := snapshot(loop)
	var before_jingle := snapshot(jingle)
	var owner = make_owner()
	party.play(owner, done)
	run_for(LENGTH+.5)
	check(snapshot(loop)==before, "the loop resource's settings are unchanged after a full party")
	check(snapshot(jingle)==before_jingle, "the jingle resource's settings are unchanged after a full party")
	party.cancel()
	check(snapshot(loop)==before and load(LOOP)==loop, "cancel() leaves the cached loop resource untouched")
func snapshot(stream: AudioStream) -> Array:
	var state: Array = [stream.resource_path, stream.get_length()]
	if stream is AudioStreamWAV:
		state.append_array([stream.loop_mode, stream.loop_begin, stream.loop_end, stream.mix_rate, stream.format, stream.stereo, stream.data.size()])
	return state

## Rendered only: the banner and confetti at three moments, saved as PNGs for review.
func check_capture() -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	var owner = make_owner(true, true)
	var backdrop := ColorRect.new()
	backdrop.color = Color(.16, .2, .3)
	backdrop.size = Vector2(1280, 720)
	backdrop.z_index = -10
	owner.add_child(backdrop)
	owner.player.position = Vector2(640, 520)
	owner.player.body.scale = Vector2(3, 3)
	owner.player.body.offset = Vector2(0, -38)
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	await process_frame
	await RenderingServer.frame_post_draw
	# Before the party the HUD is on screen: the magenta fixtures prove the capture can see a leak.
	var before: Image = root.get_texture().get_image()
	check(image_ok_save(before, "celebration_hud_before"), "the pre-party capture with HUD chrome is saved")
	var hud_before := count_color(before, HUD_COLOR, .12)
	check(hud_before>20000, "the HUD fixtures are plainly visible before the party (%d magenta px)" % hud_before)
	check(count_color(before, MENU_COLOR, .12)>1000, "the menu fixture is visible before the party")
	for n in owner.hud_nodes: n.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var plain: Image = root.get_texture().get_image()
	owner_refresh(owner)
	owner.hud_nodes[4].hide()
	party.play(owner, done)
	var shots := {1.0:"celebration_start", 2.5:"celebration_mid", 4.6:"celebration_end"}
	var clock := 0.0
	for at in shots:
		while clock<float(at) and party.active():
			owner_refresh(owner)
			party.tick(DT)
			clock += DT
		if clock<float(at):
			check(false, "the party is still running at %.1f s for capture %s (clock %.2f)" % [float(at), shots[at], clock])
			break
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(frame_ok(image), "capture %s is 1280x720 (%dx%d)" % [shots[at], image.get_width(), image.get_height()])
		check(image_ok_save(image, shots[at]), "capture %s saved" % shots[at])
		check(changed_pixels(plain, image)>2000, "capture %s differs from the bare stage (%d px)" % [shots[at], changed_pixels(plain, image)])
		# A gray or empty frame must fail: Hoppy's orange, the gold title and the dark banner strip must all be drawn.
		check(count_color(image, Color(1.0, .33, .0), .18)>1200, "capture %s draws Hoppy (%d orange px)" % [shots[at], count_color(image, Color(1.0, .33, .0), .18)])
		check(count_color(image, Color("ffd36b"), .12)>400, "capture %s draws the gold MERGE SUCCESSFUL title (%d px)" % [shots[at], count_color(image, Color("ffd36b"), .12)])
		check(not is_flat(image), "capture %s is not a single flat color" % shots[at])
		var leak := count_color(image, HUD_COLOR, .12)
		check(leak==0, "capture %s shows none of the HUD chrome: no top strip, controls, boss plate or minimap (%d magenta px)" % [shots[at], leak])
		check(count_color(image, MENU_COLOR, .12)>1000, "capture %s keeps the excluded menu overlay visible" % shots[at])
	run_for(2.0)
	check(calls==1, "the rendered party also completes once")
	check(hud_states(owner)==[true, true, true, true, false], "the HUD is back after the rendered party (%s)" % str(hud_states(owner)))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(count_color(root.get_texture().get_image(), HUD_COLOR, .12)>20000, "the HUD fixtures are drawn again after completion")
	backdrop.queue_free()
## Rendered only: let the window-mode change settle, then pin the viewport to 1280x720 so every
## capture has the same size. Gives up after 120 process frames and the captures refuse a wrong size.
const FRAME := Vector2i(1280, 720)
func settle_window() -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	await create_timer(.5).timeout
	DisplayServer.window_set_size(FRAME)
	root.size = FRAME
	var frames := 0
	while Vector2i(root.get_texture().get_size())!=FRAME and frames<120:
		await process_frame
		frames += 1
	print("window settled at ", root.get_texture().get_size(), " after ", frames, " frames")
	if Vector2i(root.get_texture().get_size())!=FRAME: check(false, "the window settles to 1280x720 within 120 frames")
func frame_ok(image: Image) -> bool:
	return Vector2i(image.get_width(), image.get_height())==FRAME
func image_ok_save(image: Image, name: String) -> bool:
	if not frame_ok(image): return false
	return image.save_png("%s/%s.png" % [CAPTURE_DIR, name])==OK
func changed_pixels(a: Image, b: Image) -> int:
	var count := 0
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r-pb.r)+absf(pa.g-pb.g)+absf(pa.b-pb.b)>.12: count += 16
	return count
func count_color(image: Image, target: Color, tol: float) -> int:
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var px := image.get_pixel(x, y)
			if Vector3(px.r-target.r, px.g-target.g, px.b-target.b).length()<=tol: count += 4
	return count
func is_flat(image: Image) -> bool:
	var first := image.get_pixel(0, 0)
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			if image.get_pixel(x, y)!=first: return false
	return true

## Pause freezes the party clock, the confetti and the jingle's progress; only unpaused ticks count.
func check_pause_clock() -> void:
	var owner = make_owner()
	party.play(owner, done)
	run_for(1.0)
	var clock: float = party.clock
	check(clock>.9 and clock<1.1, "the party clock is about 1 s after 1 s of ticks (%.3f)" % clock)
	paused = true
	for _i in 180: party.tick(DT)
	party.tick(5.0)
	var frozen: bool = is_equal_approx(party.clock, clock) and party.active() and calls==0
	paused = false
	check(frozen, "a paused tree freezes the party clock, even for a huge dt, and calls no done (clock %.3f)" % party.clock)
	run_for(.5)
	check(party.clock>clock+.45 and party.clock<clock+.55, "unpausing resumes from where it froze (%.3f)" % party.clock)
	paused = true
	run_for(10.0)
	check(party.active() and calls==0, "pausing at any point leaves the party running but unfinished")
	paused = false
	run_for(LENGTH+1.0)
	check(calls==1 and not party.active(), "the party still completes once after the pauses")

## Every hook node is hidden at play(), stays hidden while the owner re-shows it each frame, and the
## menu overlay (not in the hook) is never touched. Without the hook nothing is hidden.
func check_hud_hidden() -> void:
	var owner = make_owner(true, true)
	var menu: Control = owner.get_meta("menu")
	check(hud_states(owner)==[true, true, true, true, false], "the HUD fixtures start visible with one already hidden")
	party.play(owner, done)
	check(hud_states(owner)==[false, false, false, false, false], "play() hides every HUD node immediately (%s)" % str(hud_states(owner)))
	var leaked := false
	var menu_hidden := false
	var guard := 0
	while party.active() and guard<600:
		owner_refresh(owner)
		party.tick(DT)
		if party.active() and hud_states(owner)!=[false, false, false, false, false]: leaked = true
		if not menu.visible: menu_hidden = true
		guard += 1
	check(not party.active(), "the HUD party ends within %d ticks" % guard)
	check(not leaked, "the HUD stays hidden on every tick even when the owner re-shows it first")
	check(not menu_hidden and menu.visible, "the pause/menu overlay outside the hook is never hidden")
	# Paused: the owner's refresh still happens, and the pause menu must stay usable.
	owner = make_owner(true, true)
	menu = owner.get_meta("menu")
	party.play(owner, done)
	run_for(1.0)
	paused = true
	party.tick(DT)
	check(hud_states(owner)==[false, false, false, false, false] and menu.visible, "while paused the hidden snapshot stays hidden and the menu overlay stays visible")
	paused = false
	owner_refresh(owner)
	party.tick(DT)
	check(hud_states(owner)==[false, false, false, false, false] and menu.visible, "after resume the next tick hides the HUD again and the menu stays")
	party.cancel()
	# No hook: nothing is hidden and nothing throws.
	owner = make_owner()
	check(not owner.has_method("knockout_hud_nodes"), "the plain stub owner has no knockout_hud_nodes() hook")
	var extra := ColorRect.new()
	owner.ui_layer.add_child(extra)
	party.play(owner, done)
	run_for(1.0)
	check(extra.visible and party.active(), "without the hook the owner's UI is left alone and the party runs")
	run_for(LENGTH+1.0)
	check(calls==1, "a hookless owner still completes once")

## Restore is exact: visible nodes come back, the prior-hidden one stays hidden, and on completion it
## happens before done is called.
func check_hud_restore() -> void:
	var owner = make_owner(true, true)
	var seen := []
	var at_done := func():
		calls += 1
		seen.append(hud_states(owner))
	party.play(owner, at_done)
	run_for(LENGTH+1.0)
	check(calls==1 and seen.size()==1 and seen[0]==[true, true, true, true, false], "completion restores the HUD before done is called (%s)" % str(seen))
	check(hud_states(owner)==[true, true, true, true, false], "the prior-hidden node stays hidden and the rest are visible after completion")
	# cancel mid-party
	calls = 0
	party.play(owner, done)
	run_for(2.0)
	check(hud_states(owner)==[false, false, false, false, false], "the HUD is hidden mid-party")
	party.cancel()
	check(hud_states(owner)==[true, true, true, true, false] and calls==0, "cancel() restores the HUD exactly and suppresses done")
	# cancel idempotence: the owner may hide things itself afterwards; a second cancel must not re-show
	owner.hud_nodes[0].visible = false
	party.cancel()
	party.cancel()
	check(hud_states(owner)==[false, true, true, true, false], "repeated cancel() never re-applies the snapshot")
	owner.hud_nodes[0].visible = true
	# a cancel after completion is also quiet
	party.play(owner, done)
	run_for(LENGTH+1.0)
	owner.hud_nodes[1].visible = false
	party.cancel()
	check(hud_states(owner)==[true, false, true, true, false], "cancel() after completion does not touch the HUD")
	owner.hud_nodes[1].visible = true
	# coarse step completion restores too
	calls = 0
	party.play(owner, done)
	for _i in 20: party.tick(1.0)
	check(calls==1 and hud_states(owner)==[true, true, true, true, false], "a coarse-step completion restores the HUD")

func check_hud_edge_cases() -> void:
	var owner = make_owner(true, true)
	# Replay while running: the second play must snapshot the restored (visible) state.
	party.play(owner, done)
	run_for(1.0)
	party.play(owner, done)
	check(hud_states(owner)==[false, false, false, false, false], "a replay hides the HUD again")
	party.cancel()
	check(hud_states(owner)==[true, true, true, true, false], "a replay captured the original visibility, not the hidden one (%s)" % str(hud_states(owner)))
	# A node freed mid-party is skipped quietly, on tick, cancel and completion.
	calls = 0
	party.play(owner, done)
	run_for(1.0)
	var doomed: CanvasItem = owner.hud_nodes[2]
	owner.hud_nodes.remove_at(2)
	doomed.free()
	run_for(LENGTH+1.0)
	check(calls==1 and not party.active(), "a freed HUD node does not break the party or its completion")
	check(hud_states(owner)==[true, true, true, false], "the surviving nodes are restored (%s)" % str(hud_states(owner)))
	party.play(owner, done)
	run_for(1.0)
	var second: CanvasItem = owner.hud_nodes[0]
	owner.hud_nodes.remove_at(0)
	second.free()
	party.cancel()
	check(hud_states(owner)==[true, true, false], "cancel() after a node was freed restores the rest")
	# A duplicate or invalid entry from the hook is tolerated.
	owner.hud_nodes.append(owner.hud_nodes[0])
	party.play(owner, done)
	run_for(.5)
	party.cancel()
	check(hud_states(owner)[0]==true, "a node listed twice is restored to its original visibility")
	# The hook may return different nodes on the next play: each party snapshots anew.
	var fresh := ColorRect.new()
	owner.ui_layer.add_child(fresh)
	owner.hud_nodes.assign([fresh])
	party.play(owner, done)
	check(not fresh.visible, "a node added to the hook list before play() is hidden")
	party.cancel()
	check(fresh.visible, "and restored on cancel")

## Optional, real game: finisher -> celebration -> ending -> results through _physics_process, so the
## game's own tick order, minimap refresh and toasts run against the party. Skipped on a game
## without celebrate(), so an older base still passes. The game's physics is frozen and stepped by hand.
const CODE_CITY := "res://scenes/beatem_up/code_city_brawl.tscn"
var game
func real_step() -> void:
	game._physics_process(DT)
func hud_visible(nodes: Array) -> int:
	var count := 0
	for n in nodes:
		if is_instance_valid(n) and n.is_visible_in_tree(): count += 1
	return count
func real_freeze() -> void:
	game.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)
		game.player.controlled = false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
func real_settle() -> void:
	game.reset_physics_interpolation()
func real_capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or not RenderingServer.render_loop_enabled: return
	real_settle()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	check(frame_ok(image), "real-game capture %s is 1280x720 (%dx%d)" % [name, image.get_width(), image.get_height()])
	check(image_ok_save(image, name), "real-game capture %s saved" % name)
	check(not is_flat(image), "real-game capture %s is not a flat frame" % name)
func real_abort() -> void:
	if is_instance_valid(current_scene): current_scene.queue_free()
func check_real_game() -> void:
	if is_instance_valid(stage): stage.free()
	stage = null
	if change_scene_to_file(CODE_CITY)!=OK:
		check(false, "the Code City scene starts loading")
		return
	await process_frame
	await process_frame
	game = current_scene
	if game==null:
		check(false, "the Code City scene loads for the real-game check")
		return
	if not game.has_method("celebrate"):
		print("real-game celebration check skipped: this game has no celebrate()")
		if is_instance_valid(current_scene): current_scene.queue_free()
		await process_frame
		return
	print("--- real game ---")
	game.test_mode = true
	paused = false
	if game.state=="paused": game.resume()
	game.start_stage(2)
	real_freeze()
	var guard := 0
	while game.state!="combat" and guard<400:
		real_step()
		guard += 1
	if game.state!="combat":
		check(false, "the real game reaches combat within %d ticks (state %s)" % [guard, game.state])
		real_abort()
		return
	real_freeze()
	game.enter_room(2)
	real_freeze()
	game.playing = true
	var has_boss: bool = is_instance_valid(game.boss) and is_instance_valid(game.player)
	check(has_boss, "the real game has its final boss and player in room 3")
	if not has_boss:
		real_abort()
		return
	var nodes: Array = game.knockout_hud_nodes() if game.has_method("knockout_hud_nodes") else []
	check(nodes.size()>0, "the real game lists HUD nodes for the party")
	game.player.hp = 3
	# The genuine final-boss path: three exposed hits take it through its phases to the resolved core,
	# so the finisher plays on the right sheet.
	for damage in [12, 6, 6]:
		game.boss.vulnerable = true
		game.boss.take_hit(damage, 0, Vector2.ZERO, true)
	check(game.state=="finisher", "the final boss's last hit starts the finisher")
	guard = 0
	while game.state=="finisher" and guard<600:
		real_step()
		guard += 1
	var celebrating: bool = game.state=="celebration" and game.get("party")!=null and game.party.active()
	check(celebrating, "the finisher hands over to the celebration (state %s)" % game.state)
	if not celebrating:
		real_abort()
		return
	# The very tick that enters the celebration must already have hidden the chrome, not the next one.
	check(hud_visible(nodes)==0, "every HUD node is hidden on the tick that enters the celebration (%d visible)" % hud_visible(nodes))
	check(game.party.clock<=DT*2.0+.001, "the celebration entry is on its first tick (clock %.3f)" % game.party.clock)
	var leaked := 0
	var refreshed := 0
	guard = 0
	var shot := false
	while game.state=="celebration" and guard<900:
		# The game's own refreshes: its minimap and toast show themselves, then the physics tick runs.
		if game.has_method("_refresh_minimap"): game._refresh_minimap(DT)
		game.toast("CELEBRATION CHATTER", .5)
		refreshed += 1
		real_step()
		if game.state=="celebration":
			leaked += hud_visible(nodes)
			# The toast just raised above counts on its own, whatever knockout_hud_nodes() returns.
			if game.toast_label.is_visible_in_tree(): leaked += 1
		if not shot and game.party.clock>=2.5:
			shot = true
			await real_capture("real_celebration")
			if game.state!="celebration": break
		if game.state=="celebration" and guard==120:
			game.pause("x")
			check(game.state=="paused" and game.overlay.visible, "pause during the real celebration shows the overlay")
			var frozen: float = game.party.clock
			for _i in 30: real_step()
			check(is_equal_approx(game.party.clock, frozen), "the party clock is frozen while the real game is paused")
			game.resume()
			check(game.state=="celebration", "resume returns to the celebration")
		guard += 1
	check(refreshed>60, "the real celebration ran for many refreshed ticks (%d)" % refreshed)
	check(leaked==0, "no HUD, minimap or toast node was visible on any celebration tick (%d leaks)" % leaked)
	check(game.state=="ending" and game.story.visible, "completion moves to the ending with the story visible (state %s)" % game.state)
	check(not game.party.active() and not is_instance_valid(game.party.root), "the party's chrome is gone once the ending starts")
	# The ending opens on its black fade; let the page come up before the capture.
	guard = 0
	while game.state=="ending" and game.intro_clock<.75 and guard<240:
		real_step()
		guard += 1
	check(game.intro_clock>=.75 or game.state!="ending", "the ending page has faded in before its capture (clock %.2f)" % game.intro_clock)
	await real_capture("real_ending")
	game.show_victory()
	check(game.state=="won" and game.victory.visible, "the results screen shows")
	check(not game.party.active() and not is_instance_valid(game.party.root), "no celebration chrome is left on the results screen")
	check(not game.story.visible and not game.overlay.visible, "the results screen shows neither the story nor the menu overlay")
	var back: ColorRect = game.victory.backdrop
	var full: bool = back.is_visible_in_tree() and is_equal_approx(back.color.a, 1.0) and is_equal_approx(back.modulate.a, 1.0)
	check(full, "the results backdrop is fully opaque (alpha %.2f, modulate %.2f)" % [back.color.a, back.modulate.a])
	var covered: Rect2 = back.get_global_rect()
	var view := Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size)
	check(covered.encloses(view), "the results backdrop covers the whole viewport (%s vs %s)" % [str(covered), str(view)])
	guard = 0
	while not game.victory.landed and guard<600:
		real_step()
		guard += 1
	check(game.victory.landed, "the results screen has landed before its capture")
	await real_capture("real_results")
	if is_instance_valid(current_scene): current_scene.queue_free()
