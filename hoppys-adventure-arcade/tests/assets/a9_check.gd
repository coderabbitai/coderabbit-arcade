extends SceneTree
const Metrics = preload("res://scenes/runner/ui/dev/post_fx_capture_metrics.gd")
const PostFX = preload("res://scenes/runner/ui/post_fx.tscn")
const Preview = preload("res://scenes/runner/ui/dev/post_fx_preview.tscn")
const PreviewScript = preload("res://scenes/runner/ui/dev/post_fx_preview.gd")

## The preview stub predates the cinematic clock. Post FX reads that clock for the letterbox.
class CinematicGame extends PreviewScript.StubGame:
	signal boss_cinematic(kind: StringName, mode: StringName, seconds: float)
	signal boss_cinematic_skipped(mode: StringName)
	signal boss_cinematic_ended(mode: StringName)
	var boss_cinematic_progress := 0.0
	var boss_time_factor := 1.0

## Title layout reads the encounter clock off its game node.
class TitleFixture extends Node:
	var boss_cinematic_progress := 1.0
	var stage_index := 1
	var paused := false

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ASSET A9: " + message)

func step(fx: Node, seconds: float) -> void:
	for tween: Tween in fx.transitions.values():
		if tween.is_valid():
			tween.custom_step(seconds)
	fx._process(seconds)

func value(fx: Node, key: String) -> float:
	return float(fx.material.get_shader_parameter(key))

func inspect(node: Node) -> void:
	if node is MultiMeshInstance3D:
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "cosmetic MultiMesh interpolation")
	for child in node.get_children():
		inspect(child)

func run() -> void:
	await check_ui_layers()
	var game := CinematicGame.new()
	root.add_child(game)
	var fx := PostFX.instantiate()
	fx.bind(game) # Binding before ready must work, too.
	root.add_child(fx)
	fx.bind(game)
	for event: StringName in fx.signal_handlers:
		check(game.get_signal_connection_list(event).size() == 1, "idempotent signal " + event)
	check(fx.layer == 9 and fx.process_mode == Node.PROCESS_MODE_PAUSABLE, "layer and pause contract")
	check(fx.get_child_count() == 1 and fx.screen is ColorRect, "exactly one fullscreen draw node")
	check(fx.screen.mouse_filter == Control.MOUSE_FILTER_IGNORE, "input passes through")
	check(fx.screen.anchor_right == 1.0 and fx.screen.anchor_bottom == 1.0, "fullscreen envelope")
	check(fx.screen.process_mode == Node.PROCESS_MODE_PAUSABLE, "rect pausable")
	check(fx.screen.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "rect interpolation off")
	check(not fx.screen.material.get_shader().code.contains("textureLod"), "no mipmap bloom passes")
	inspect(fx)
	var draws := 0
	var triangles := 0
	for child in fx.get_children():
		if child is ColorRect:
			draws += 1
			triangles += 2
	check(draws == 1 and triangles == 2, "post census budget")
	check(fx.material.get_shader_parameter("screen_texture") == null, "no allocated art textures; renderer backbuffer only")
	print("ASSET A9 CENSUS: fullscreen_draws=%d triangles=%d generated_textures=0 particles=0 lights=0 collision_shapes=0" % [draws, triangles])
	var time_pattern := RegEx.new()
	time_pattern.compile("\\bTIME\\b")
	for path in ["res://scenes/runner/shaders/post_grade.gdshader", "res://scenes/runner/shaders/vignette.gdshader"]:
		var shader := load(path) as Shader
		check(shader != null and time_pattern.search(shader.code) == null, "pause-safe shader " + path)
	for parameter in ["strength", "color", "corner_bars", "pulse", "scanlines"]:
		check(fx.material.shader.code.contains("uniform " + ("vec4" if parameter == "color" else "float") + " " + parameter), "legacy API " + parameter)
	check_round_two(fx, game)
	game.run_started.emit(912)
	var seed_value: int = fx.grain_seed
	step(fx, 1.0)
	game.run_started.emit(912)
	check(fx.grain_seed == seed_value and fx.clock == 0.0, "deterministic seeded grain and retry clock")
	game.damage_taken.emit(&"bug_swarm", 2)
	step(fx, 0.035)
	check(value(fx, "aberration") > 0.95, "damage pulse")
	step(fx, 1.0)
	check(is_zero_approx(value(fx, "aberration")), "pulse decays")
	check(fx.transitions.is_empty(), "finished damage tween pruned synchronously")
	game.paused_changed.emit(true)
	game.paused_changed.emit(false)
	game.paused_changed.emit(false)
	check(fx.transitions.is_empty() and fx.suspended.is_empty(), "finished damage tween cannot be replayed on resume")
	game.paused_changed.emit(true)
	game.damage_taken.emit(&"bug_swarm", 2)
	var paused_hit: Tween = fx.transitions["aberration"]
	check(paused_hit.is_valid() and not paused_hit.is_running(), "tween created during pause is suspended")
	game.paused_changed.emit(true)
	game.paused_changed.emit(false)
	check(paused_hit.is_running() and fx.suspended.is_empty(), "duplicate pause preserves resumable tween")
	step(fx, 1.0)
	check(fx.transitions.is_empty(), "resumed damage tween finishes and is pruned")
	game.damage_taken.emit(&"bug_swarm", 2)
	var replaced: Tween = fx.transitions["aberration"]
	game.paused_changed.emit(true)
	game.damage_taken.emit(&"bug_swarm", 1)
	check(not replaced.is_valid(), "replacement kills paused tween")
	fx._transition_finished("aberration", replaced.get_instance_id())
	check(fx.transitions.has("aberration") and fx.suspended.has("aberration"), "stale finish cannot erase replacement")
	game.paused_changed.emit(false)
	step(fx, 1.0)
	check(fx.transitions.is_empty() and fx.suspended.is_empty(), "replacement completion clears all tracking")
	game.tool_collected.emit(&"lint_rule", 0)
	step(fx, 0.025)
	check(is_zero_approx(value(fx, "aberration")), "resisted tool has no hit pulse")
	game.tool_collected.emit(&"lint_rule", 12)
	step(fx, 0.025)
	check(is_equal_approx(value(fx, "aberration"), 0.42), "damaging tool pulse")
	game.pursuit_started.emit(6.0)
	step(fx, 0.1)
	check(is_equal_approx(value(fx, "strength"), 0.25), "pursuit starts at legacy strength")
	game.pursuit_progress.emit(0.0, 6.0)
	step(fx, 0.1)
	check(is_equal_approx(value(fx, "strength"), 0.85) and value(fx, "corner_bars") == 1.0, "critical pursuit and bars")
	game.pursuit_progress.emit(-1.0, 0.0)
	step(fx, 0.1)
	check(is_finite(value(fx, "strength")), "invalid pursuit duration clamped")
	game.pursuit_recovered.emit(&"clean")
	step(fx, 0.4)
	check(value(fx, "strength") == 0.0 and value(fx, "corner_bars") == 0.0, "recovery clears")
	game.caught.emit()
	step(fx, 0.3)
	check(value(fx, "strength") == 1.0, "catch strength")
	game.speed_changed.emit(32.0, 2.0)
	# Per-tick signals ease in _process: no Tween is allocated per physics step.
	check(not fx.transitions.has("speed") and fx.channels.has("speed"), "per-tick speed eases without a Tween")
	game.speed_changed.emit(32.0, 2.0)
	check(fx.channels["speed"].age == 0.0 and fx.channels.size() >= 1, "repeated identical target keeps one channel")
	game.power_up_collected.emit(&"nitro", 6.0)
	step(fx, 0.3)
	check(value(fx, "speed") == 1.0 and value(fx, "bloom_lift") == 1.0, "speed clamp and Nitro lift")
	game.power_up_expired.emit(&"nitro")
	step(fx, 0.4)
	check(value(fx, "bloom_lift") == 0.0, "Nitro expires")
	game.boss_cinematic_progress = 1.0
	game.boss_cinematic.emit(&"legacy_monolith", &"intro_full", 3.0)
	step(fx, 0.2)
	check(value(fx, "letterbox") == 1.0, "boss bars open")
	game.boss_cinematic_ended.emit(&"intro_full")
	step(fx, 0.3)
	check(value(fx, "letterbox") == 0.0, "boss bars close")
	game.stage_cleared.emit(1, 500)
	step(fx, 0.2)
	check(value(fx, "letterbox") == 1.0, "clear card bars open")
	step(fx, 3.0)
	check(value(fx, "letterbox") == 0.0, "clear card bars close")
	for phase in [&"run", &"idle"]:
		game.stage_cleared.emit(1, 500)
		step(fx, 0.2)
		game.phase_changed.emit(phase)
		step(fx, 0.3)
		check(value(fx, "letterbox") == 0.0, "phase cancels stale bars " + phase)
	game.damage_taken.emit(&"bug", 1)
	game.paused_changed.emit(true)
	var old_clock: float = fx.clock
	var old_aberration := value(fx, "aberration")
	await process_frame
	await process_frame
	check(fx.clock == old_clock and value(fx, "aberration") == old_aberration, "facade pause freezes clock and tween")
	game.paused_changed.emit(false)
	paused = true
	await process_frame
	await process_frame
	check(fx.clock == old_clock and value(fx, "aberration") == old_aberration, "tree pause freezes clock and tween")
	paused = false
	game.run_finished.emit({})
	check(fx.transitions.is_empty(), "finish cancels tweens")
	for key: String in fx.values:
		check(value(fx, key) == 0.0, "finish resets " + key)
	for key: String in fx.settings:
		fx.set_settings({key: false})
	game.damage_taken.emit(&"bug", 1)
	game.power_up_collected.emit(&"nitro", 6.0)
	game.pursuit_progress.emit(0.0, 6.0)
	game.speed_changed.emit(32.0, 1.0)
	game.stage_cleared.emit(1, 500)
	step(fx, 0.2)
	for key in ["grade", "grain", "vignette", "strength", "corner_bars", "aberration", "letterbox", "speed", "bloom_lift"]:
		check(value(fx, key) == 0.0, "disable effect " + key)
	var other := Node.new()
	root.add_child(other)
	fx.bind(other)
	for event: StringName in fx.signal_handlers:
		check(game.get_signal_connection_list(event).is_empty(), "rebind disconnect " + event)
	fx.bind(null)
	check(fx.game == null, "null unbind")
	var second := PostFX.instantiate()
	root.add_child(second)
	check(second.material != fx.material and value(second, "grade") > 0.0, "per-instance materials and settings")
	second.free()
	fx.free()
	game.free()
	other.free()
	var fixture := Preview.instantiate()
	root.add_child(fixture)
	for index in 7:
		fixture.set_view(index)
		step(fixture.post, 0.2)
		check(fixture.post.game == fixture.game, "standalone preview view %d" % index)
	check(value(fixture.post, "grade") == 0.85 and value(fixture.post, "grain") == 0.0, "grade-only comparison preset")
	fixture.set_view(0)
	check(not fixture.post.settings.pursuit and value(fixture.post, "grain") > 0.0, "preview restores safe integrated defaults")
	fixture.free()
	if root.has_node("AudioService"):
		root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("ASSET A9: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

# These CPU/source assertions lock intended math and fixture behavior, not GPU appearance.
func grade_reference(src: Vector3) -> Vector3:
	var luma := src.dot(Vector3(0.2126, 0.7152, 0.0722))
	var x := luma * 0.85
	var curve := clampf((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0)
	var graded := src * lerpf(1.0, curve / maxf(luma, 0.001), 0.85)
	var shadows := (1.0 - smoothstep(0.02, 0.32, luma)) * smoothstep(0.0, 0.08, luma)
	var highlights := smoothstep(0.5, 1.0, luma)
	graded += Vector3(-0.020, 0.009, 0.045) * shadows
	graded *= Vector3.ONE.lerp(Vector3(0.96, 1.06, 1.01), highlights)
	graded = graded.lerp(Vector3(1.0, 0.941, 0.827) * luma, highlights * 0.18)
	var danger := smoothstep(0.08, 0.28, src.x - maxf(src.y, src.z))
	return src.lerp(graded, 0.85 * (1.0 - danger * 0.9))

func check_round_two(fx: Node, game: Node) -> void:
	# B1: validate the same measurement helper used by the host capture.
	check(Metrics.canvas_items(fx) == 1, "B1 exactly one CanvasItem recursively")
	var extra := Control.new()
	fx.screen.add_child(extra)
	check(Metrics.canvas_items(fx) == 2, "B1 nested extra CanvasItem detected")
	extra.free()
	var before := Image.create(2, 2, false, Image.FORMAT_RGB8)
	before.fill(Color.BLACK)
	var after := before.duplicate() as Image
	check(not Metrics.has_visible_delta(Metrics.pixel_delta(before, after)), "B1 identical frames fail visible delta")
	after.set_pixel(1, 1, Color(1.0 / 255.0, 0.0, 0.0))
	var delta := Metrics.pixel_delta(before, after)
	check(Metrics.has_visible_delta(delta) and delta.changed_pixels == 1 and delta.max_rgb_delta == 1, "B1 one-step pixel change detected")
	check(is_equal_approx(delta.mean_rgb_delta, 1.0 / 12.0), "B1 normalized RGB metric")
	check(not Metrics.has_visible_delta(Metrics.pixel_delta(before, null)), "B1 absent capture rejected")
	check(not Metrics.has_visible_delta(Metrics.pixel_delta(before, Image.create(1, 1, false, Image.FORMAT_RGB8))), "B1 size mismatch rejected")
	var code: String = fx.material.shader.code
	var capture_source := FileAccess.get_file_as_string("res://scenes/runner/ui/dev/capture_a9.gd")
	check(not capture_source.contains("calls - baseline") and capture_source.contains("Metrics.has_visible_delta"), "B1 no 3D counter pass condition")
	check(capture_source.contains("a9-grade-off.png") and capture_source.contains("a9-grade-on.png"), "B2 paired grade captures")
	# B2: coefficient locks tie the analytical samples to the actual shader source.
	check(value(fx, "grade") == 0.85 and code.contains("max(luma, 0.001), 0.85"), "B2 grade and curve authority")
	check(code.contains("vec3(-0.020, 0.009, 0.045)") and code.contains("highlights * 0.18"), "B2 visible shadow and highlight tint")
	check(code.contains("grade * (1.0 - danger * 0.9)") and code.contains("src.r - max(src.g, src.b)"), "B2 danger-red protection in shader")
	check(grade_reference(Vector3.ZERO) == Vector3.ZERO, "B2 exact black remains black")
	var mid := Vector3.ONE * 0.35
	check(grade_reference(mid).distance_to(mid) > 0.025, "B2 perceptible midtone grade")
	var navy := Vector3(8.0, 17.0, 28.0) / 255.0
	check(grade_reference(navy).distance_to(navy) > 2.0 / 255.0, "B2 perceptible navy grade")
	var red := Vector3(1.0, 77.0 / 255.0, 61.0 / 255.0)
	check(grade_reference(red).distance_to(red) < 0.03, "B2 danger-red change bounded")
	# B3: peak amplitude in 8-bit steps, with a navy floor and true-black exclusion.
	var grain_peak := 0.5 * value(fx, "grain") * 255.0
	check(grain_peak >= 1.5 and grain_peak <= 3.0, "B3 midtone grain 1.5-3 steps")
	check(grain_peak * 0.75 >= 1.5, "B3 navy grain survives")
	check(code.contains("smoothstep(0.0, 0.003, luma) * (0.75 + 0.25 * smoothstep(0.02, 0.2, luma))"), "B3 navy mask preserves black")
	# B4: measure minimum-motion border coverage at full speed, before vignette.
	check(code.contains(")), 6.0)") and code.contains("speed * 0.22 * (1.0 + 0.5 * bloom_lift)"), "B4 wider brighter Nitro streaks")
	check(code.contains("edge * edge * speed") and code.contains("0.35 + 0.65 * motion"), "B4 center protection and sustained streak floor")
	var visible_spokes := 0
	for sample in 720:
		var angle := float(sample) / 720.0 * TAU
		var spoke := pow(maxf(0.0, sin(angle * 48.0 + sin(angle * 19.0) * 4.0)), 6.0)
		if spoke * 0.35 * 0.22 * 0.878 * 255.0 > 8.0:
			visible_spokes += 1
	check(visible_spokes > 80, "B4 measurable bright border coverage")
	# B5: integrated pursuit must remain absent until explicit ownership handover.
	check(not fx.settings.pursuit, "B5 pursuit disabled by default")
	for key in ["grade", "grain", "vignette", "aberration", "letterbox", "speed", "bloom_lift"]:
		check(fx.settings[key], "B5 other effect enabled: " + key)
	game.pursuit_progress.emit(0.0, 6.0)
	step(fx, 0.2)
	check(value(fx, "strength") == 0.0 and value(fx, "corner_bars") == 0.0, "B5 no duplicate HUD pursuit wash")
	fx.set_settings({"pursuit": true})
	check(is_equal_approx(value(fx, "strength"), 0.85) and value(fx, "corner_bars") == 1.0, "B5 explicit handover enables existing hook state")
	game.run_started.emit(912)

func effective_layer(node: Node) -> int:
	var ancestor := node
	while ancestor != null:
		if ancestor is CanvasLayer: return ancestor.layer
		ancestor = ancestor.get_parent()
	return 0

func check_ui_layers() -> void:
	var production := load("res://scenes/runner/runner_game.tscn") as PackedScene
	var skeleton := production.instantiate()
	var mounts: Dictionary = skeleton.get_script().get("FRONTEND_MOUNTS")
	var post := PostFX.instantiate()
	var post_layer: int = post.layer
	post.free()
	for parent_path in ["HUD", "Overlays"]:
		for path: String in mounts[parent_path]:
			if path == "res://scenes/runner/ui/post_fx.tscn": continue
			# Contract 2.7 §11.15: run_intro.tscn is an optional mount. S5 may not have built it,
			# and a missing scene must not abort the layer checks for the panels that do exist.
			if not ResourceLoader.exists(path):
				check(path == "res://scenes/runner/ui/run_intro.tscn",
					"only the optional run intro mount may be absent, missing " + path)
				continue
			var ui := (load(path) as PackedScene).instantiate()
			skeleton.get_node(parent_path).add_child(ui)
			check(effective_layer(ui) > post_layer, "production UI above post: " + path)
	skeleton.free()
	# Check actual card bounds at the authored viewport with post bars fully open.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var hud := CanvasLayer.new()
	hud.layer = 10
	viewport.add_child(hud)
	var boss := (load("res://scenes/runner/ui/boss_hud.tscn") as PackedScene).instantiate()
	var clear := (load("res://scenes/runner/ui/stage_clear.tscn") as PackedScene).instantiate()
	hud.add_child(boss)
	hud.add_child(clear)
	var cinematic := (load("res://scenes/runner/ui/boss_cinematic.tscn") as PackedScene).instantiate()
	viewport.add_child(cinematic)
	var fixture := TitleFixture.new()
	viewport.add_child(fixture)
	cinematic.game = fixture
	cinematic._cinematic(&"legacy_monolith", &"intro_full", 3.0)
	clear.show()
	clear.title.text = "STAGE 1 CLEAR"
	clear.subtitle.text = "LEGACY MONOLITH / FIXED"
	clear._process(0.3)
	await process_frame
	await process_frame
	check(boss.border == boss.panel.get_theme_stylebox("panel"), "boss animation owns visible polished border")
	var shader := load("res://scenes/runner/shaders/post_grade.gdshader") as Shader
	check(shader.code.contains("letterbox * 0.065"), "tested letterbox height matches shader")
	var bar_height := 720.0 * 0.065 + 1.0
	for card: Control in [cinematic.title_group, clear.panel]:
		var rect := card.get_global_rect()
		check(effective_layer(card) > post_layer, "card stays above letterbox: " + card.name)
		check(rect.position.y > bar_height and rect.end.y < 720.0 - bar_height, "bars frame card bounds: " + card.name)
	viewport.free()
