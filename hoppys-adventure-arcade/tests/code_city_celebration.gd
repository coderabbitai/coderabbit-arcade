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
const BOSS_MUSIC := "res://Assets/Audio/Beat'em Up/Boss Fight 2.mp3"
const CAPTURE_DIR := "/tmp/s3-captures/celebration"
const DT := 1.0/60.0
## Contract times, seconds on the party clock.
const JINGLE_AT := .3
const LOOP_AT := 3.8
const LENGTH := 5.2
const WALL_MAX := 6.0

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
func make_owner(with_camera := true):
	var owner = StubOwner.new() if with_camera else StubNoCamera.new()
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
	root.add_child(owner)
	boss_stream = load(BOSS_MUSIC)
	flow.play_music(boss_stream)
	if stage != null and is_instance_valid(stage): stage.free()
	stage = owner
	party = Celebration.new()
	calls = 0
	return owner

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
	while not (root.has_node("ControllerService") and root.get_node("ControllerService").is_node_ready()): await process_frame
	await process_frame
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
	await check_capture()
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
	var seen_loop := false
	var swapped_at := -1.0
	var elapsed := LOOP_AT-.2
	while party.active() and elapsed<LENGTH:
		party.tick(DT)
		elapsed += DT
		if flow.music.stream!=boss_stream and swapped_at<0.0:
			swapped_at = elapsed
			seen_loop = true
		if elapsed>LOOP_AT+.2: break
	check(seen_loop and absf(swapped_at-LOOP_AT)<=.25, "the flow's music switches to the loop at about 3.8 s (%.2f)" % swapped_at)
	check(is_equal_approx(flow.music_db, 0.0), "the duck is lifted once the loop starts")
	check(flow.music.playing and flow.music_track!=boss_stream, "the loop is playing on the flow's player")
	run_for(10.0)
	check(calls==1 and not party.active(), "the party completes once")
	check(flow.music.playing and flow.music.stream!=boss_stream, "the loop is flow-owned and keeps playing after completion")
	var looped: AudioStream = flow.music.stream
	var loops: bool = ("loop_mode" in looped and looped.loop_mode!=AudioStreamWAV.LOOP_DISABLED) or ("loop" in looped and looped.loop)
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
	var owner = make_owner()
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
	var plain: Image = root.get_texture().get_image()
	party.play(owner, done)
	var shots := {1.0:"celebration_start", 2.5:"celebration_mid", 4.6:"celebration_end"}
	var clock := 0.0
	for at in shots:
		while clock<float(at) and party.active():
			party.tick(DT)
			clock += DT
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.save_png("%s/%s.png" % [CAPTURE_DIR, shots[at]])==OK, "capture %s saved" % shots[at])
		check(changed_pixels(plain, image)>2000, "capture %s differs from the bare stage (%d px)" % [shots[at], changed_pixels(plain, image)])
		# A gray or empty frame must fail: Hoppy's orange, the gold title and the dark banner strip must all be drawn.
		check(count_color(image, Color(1.0, .33, .0), .18)>1200, "capture %s draws Hoppy (%d orange px)" % [shots[at], count_color(image, Color(1.0, .33, .0), .18)])
		check(count_color(image, Color("ffd36b"), .12)>400, "capture %s draws the gold MERGE SUCCESSFUL title (%d px)" % [shots[at], count_color(image, Color("ffd36b"), .12)])
		check(not is_flat(image), "capture %s is not a single flat color" % shots[at])
	run_for(2.0)
	check(calls==1, "the rendered party also completes once")
	backdrop.queue_free()
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
