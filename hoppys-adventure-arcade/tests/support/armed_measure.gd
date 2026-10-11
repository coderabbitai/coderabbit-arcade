extends RefCounted
## Shared armed measurements for the motion and asset suites, so every suite measures the
## body the same way the builder's check_run_body does.
##
## The posed run check allows RUN_BODY_LIMIT_PX of cel drift times the body scale. Callers
## pass art lookups, offsets, face boxes, and whether a sheet must publish a cell. This
## script does not choose a mode.

## Cel pixels of body drift allowed between adjacent armed run frames, before body scale.
const RUN_BODY_LIMIT_PX := 3.0

## Mean x of opaque pixels behind the weapon paw, from the foot row up one unarmed body.
static func body_reference_x(cell_image: Image, foot_y: int, hand_x: int, body_height: int) -> float:
	var y0 := maxi(0, foot_y - body_height)
	var y1 := mini(cell_image.get_height() - 1, foot_y)
	var x_end := mini(cell_image.get_width(), hand_x - 2)
	if y1 < y0 or x_end <= 0:
		return NAN
	var sum := 0.0
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x_end):
			if cell_image.get_pixel(x, y).a >= 128.0 / 255.0:
				sum += float(x)
				count += 1
	if count == 0:
		return NAN
	return sum / float(count)

static func fmt_xs(values: PackedFloat32Array) -> String:
	var text := ""
	for i in values.size():
		text += (", " if i > 0 else "") + "%.2f" % values[i]
	return text if not text.is_empty() else "none"

## Body reference of one armed run frame, measured on the texture the sprite is showing.
static func armed_run_cel(body: AnimatedSprite2D, spec: Dictionary, anim_frame: int) -> float:
	var clips: Variant = spec.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var run_frames: Variant = run.get("frames", []) if run is Dictionary else []
	var anchors: Variant = spec.get("anchors", {})
	var hands: Variant = anchors.get("hand", {}) if anchors is Dictionary else {}
	var pivot: Variant = spec.get("pivot", [])
	var cell_data: Variant = spec.get("cell", [])
	if not run_frames is Array or anim_frame < 0 or anim_frame >= run_frames.size():
		return NAN
	if not hands is Dictionary or not pivot is Array or pivot.size() < 2 or not cell_data is Array or cell_data.size() < 2:
		return NAN
	if not spec.has("unarmed_idle_height"):
		return NAN
	var sheet_frame := int(run_frames[anim_frame])
	var hand: Variant = hands.get(str(sheet_frame), [])
	if not hand is Array or hand.size() < 2:
		return NAN
	if body.sprite_frames == null or not body.sprite_frames.has_animation("run"):
		return NAN
	var texture := body.sprite_frames.get_frame_texture("run", anim_frame)
	if texture == null:
		return NAN
	var image := texture.get_image()
	if image == null:
		return NAN
	if image.is_compressed():
		image.decompress()
	if image.get_size() != Vector2i(int(cell_data[0]), int(cell_data[1])):
		return NAN
	return body_reference_x(image, int(pivot[1]), int(hand[0]), int(spec.unarmed_idle_height))

## Fields the armed-run check mutates, so the suite can put the actor back.
static func snapshot_actor(actor) -> Dictionary:
	return {
		"position": actor.position,
		"facing": actor.facing,
		"weapon": actor.weapon,
		"visual_weapon": actor.visual_weapon,
		"durability": actor.durability,
		"pickup_time": actor.pickup_time,
		"swing_left": actor.swing_left,
		"combo": actor.combo,
		"combo_window": actor.combo_window,
		"height": actor.height,
		"rise": actor.rise,
		"stagger": actor.stagger,
		"queued": actor.queued,
		"knock": actor.knock,
		"velocity": actor.velocity,
		"held_visible": actor.held.visible,
		"frames": actor.body.sprite_frames,
		"animation": actor.body.animation,
		"offset": actor.body.offset,
		"flip": actor.body.flip_h,
		"speed_scale": actor.body.speed_scale,
		"body_position": actor.body.position,
		"modulate": actor.body.modulate,
		"frame": actor.body.frame,
	}

static func restore_actor(actor, saved: Dictionary) -> void:
	actor.position = saved.position
	actor.facing = saved.facing
	actor.weapon = saved.weapon
	actor.visual_weapon = saved.visual_weapon
	actor.durability = saved.durability
	actor.pickup_time = saved.pickup_time
	actor.swing_left = saved.swing_left
	actor.combo = saved.combo
	actor.combo_window = saved.combo_window
	actor.height = saved.height
	actor.rise = saved.rise
	actor.stagger = saved.stagger
	actor.queued = saved.queued
	actor.knock = saved.knock
	actor.velocity = saved.velocity
	actor.held.visible = saved.held_visible
	actor.body.position = saved.body_position
	actor.body.modulate = saved.modulate
	actor.body.sprite_frames = saved.frames
	actor.body.flip_h = saved.flip
	actor.body.speed_scale = saved.speed_scale
	var anim := str(saved.animation)
	if actor.body.sprite_frames != null and actor.body.sprite_frames.has_animation(anim):
		actor.body.animation = anim
		actor.body.pause()
		var count: int = actor.body.sprite_frames.get_frame_count(anim)
		if count > 0:
			actor.body.frame = clampi(int(saved.frame), 0, count - 1)
	actor.body.offset = saved.offset

## Opaque carry texels (alpha > .5, texel centre) mapped into the unarmed cel.
static func carry_face_hits(carry: Sprite2D, image: Image, box: Rect2, body_scale: float, pivot: Vector2) -> int:
	if image.is_compressed():
		image.decompress()
	var size := Vector2(image.get_width(), image.get_height())
	var shift := size * .5 if carry.centered else Vector2.ZERO
	var xform := carry.get_transform()
	var hits := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= .5:
				continue
			var cel: Vector2 = xform * (Vector2(x + .5, y + .5) + carry.offset - shift) / body_scale + pivot
			if box.has_point(cel):
				hits += 1
	return hits

## Cel pixels the grounded feet must travel between adjacent foot registered run frames.
const RUN_STRIDE_MIN_PX := 4.0

## Run frame count the spec publishes; Heroes stays at 4 and Code City publishes 6.
static func run_frame_count(spec: Dictionary) -> int:
	var clips: Variant = spec.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var frames: Variant = run.get("frames", []) if run is Dictionary else []
	return frames.size() if frames is Array and frames.size() > 0 else 4

## Mean x of opaque pixels on the foot rows of one run frame. Foot registered sheets move this
## from frame to frame because the stance advances instead of the body staying still.
static func foot_reference_x(body: AnimatedSprite2D, spec: Dictionary, anim_frame: int) -> float:
	var pivot: Variant = spec.get("pivot", [])
	if body == null or body.sprite_frames == null or not body.sprite_frames.has_animation("run") or not pivot is Array or pivot.size() < 2:
		return NAN
	if anim_frame < 0 or anim_frame >= body.sprite_frames.get_frame_count("run"):
		return NAN
	var texture := body.sprite_frames.get_frame_texture("run", anim_frame)
	var image := texture.get_image() if texture != null else null
	if image == null:
		return NAN
	if image.is_compressed():
		image.decompress()
	var sum := 0.0
	var count := 0
	for y in range(maxi(0, int(pivot[1]) - 3), mini(image.get_height(), int(pivot[1]) + 1)):
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 128.0 / 255.0:
				sum += float(x)
				count += 1
	return sum / float(count) if count > 0 else NAN

## One weapon's run frames (4 for Heroes, 6 for Code City). Packed arrays stay on the object so formatting sees the same values.
class RunSample:
	var pose_ok := false
	var detail := ""
	var measured := false
	var worlds := PackedFloat32Array()
	var cels := PackedFloat32Array()
	var limit := 0.0
	var worst := 0.0
	var worst_at := "n/a"
	var foot := false

## Sheet, clip, offset, and body-x drift across the four run frames.
static func measure_run_frames(actor, sheet: SpriteFrames, spec: Dictionary, expected_offset: Vector2, facing: float) -> RunSample:
	var sample := RunSample.new()
	if actor == null or actor.body == null:
		sample.measured = false
		sample.detail = "no body"
		return sample
	var frames: SpriteFrames = actor.body.sprite_frames
	sample.pose_ok = frames != null and frames == sheet and actor.body.animation == "run" and frames.has_animation("run") and frames.get_frame_count("run") == run_frame_count(spec)
	sample.detail = "clip %s offset %s expected %s" % [actor.body.animation, actor.body.offset, expected_offset]
	sample.measured = sample.pose_ok
	sample.foot = spec.get("run_registration", "body") == "foot"
	sample.limit = (RUN_STRIDE_MIN_PX if sample.foot else RUN_BODY_LIMIT_PX) * float(actor.body.scale.x)
	if sample.pose_ok:
		var pivot: Variant = spec.get("pivot", [])
		if not pivot is Array or pivot.is_empty() or not (pivot[0] is int or pivot[0] is float):
			sample.measured = false
			sample.detail = "run spec has no pivot"
		else:
			var pivot_x := float(pivot[0])
			var sign: float = -1.0 if facing < 0.0 else 1.0
			for f in run_frame_count(spec):
				actor.body.pause()
				actor.body.frame = f
				var frame_ok: bool = actor.body.sprite_frames == sheet and actor.body.animation == "run" and actor.body.offset.is_equal_approx(expected_offset) and actor.body.flip_h == (facing < 0.0)
				if not frame_ok:
					sample.pose_ok = false
					sample.measured = false
					sample.detail = "frame %d clip %s offset %s expected %s flip %s" % [f, actor.body.animation, actor.body.offset, expected_offset, actor.body.flip_h]
					break
				var cel := foot_reference_x(actor.body, spec, f) if sample.foot else armed_run_cel(actor.body, spec, f)
				if is_nan(cel):
					sample.measured = false
					sample.detail = "frame %d has no body pixels behind the paw" % f
					break
				sample.cels.append(cel)
				sample.worlds.append((cel - pivot_x) * actor.body.scale.x * sign)
	else:
		sample.measured = false
	if sample.worlds.size() == run_frame_count(spec):
		for i in sample.worlds.size():
			var nxt := (i + 1) % sample.worlds.size()
			var step := absf(sample.worlds[nxt] - sample.worlds[i])
			if step > sample.worst:
				sample.worst = step
				sample.worst_at = "%d to %d" % [i + 1, nxt + 1]
	return sample

## Armed run keeps the body still, in the sheet and on the stage-exit run-out.
## `sheet_for` / `spec_for` / `offset_for` are the mode's art lookups.
## `require_cell` rejects a spec that has no cell. `show_held` shows the carry before each equip.
## `flow` is the stage director (play_exit, tick, cancel). `report` is the suite's check().
static func check_armed_run_registration(
	actor,
	weapons: Dictionary,
	report: Callable,
	sheet_for: Callable,
	spec_for: Callable,
	offset_for: Callable,
	exit_weapon: String,
	flow,
	require_cell: bool,
	show_held: bool,
) -> void:
	var saved := snapshot_actor(actor)
	for weapon in weapons:
		var sheet: SpriteFrames = sheet_for.call(weapon)
		var spec: Dictionary = spec_for.call(weapon)
		var missing := sheet == null or spec.is_empty() or not spec.has("pivot")
		if require_cell:
			missing = missing or not spec.has("cell")
		if missing:
			for facing in [1.0, -1.0]:
				report.call(false, "%s facing %d armed run uses the sheet, clip run, and armed offset (no armed sheet)" % [weapon, int(facing)])
				report.call(false, "%s facing %d armed run body stays within %d * scale px (no armed sheet)" % [weapon, int(facing), int(RUN_BODY_LIMIT_PX)])
			continue
		actor.swing_left = 0
		actor.visual_weapon = ""
		actor.stagger = 0
		actor.height = 0
		if show_held:
			actor.held.show()
		actor.equip(weapon)
		actor.pickup_time = 0
		for facing in [1.0, -1.0]:
			actor.facing = facing
			actor.swing_left = 0
			actor.show_pose("run")
			var expected_offset: Vector2 = offset_for.call(weapon, facing)
			var sample := measure_run_frames(actor, sheet, spec, expected_offset, facing)
			report.call(sample.pose_ok, "%s facing %d armed run uses the sheet, clip run, and armed offset (%s)" % [weapon, int(facing), sample.detail])
			# Foot-registered sheets pass on their largest adjacent step: the run cycle has to move
			# the foot reference at all. Contact and passing frames hold the planted foot, so some
			# adjacent steps are legitimately near zero (0.27-1.17 px on today's sheets), and a
			# smallest-step check would reject correct art. hoppy_armed_assets checks per-frame
			# sliding with its 1 px planted-foot drift limit.
			report.call(sample.measured and sample.worlds.size() == run_frame_count(spec) and ((sample.worst >= sample.limit) if sample.foot else (sample.worst <= sample.limit)), "%s facing %d armed run %s %.2f px across run frames (worst %.2f between %s; world x %s; cel x %s)" % [weapon, int(facing), "feet advance by at least" if sample.foot else "body stays within", sample.limit, sample.worst, sample.worst_at, fmt_xs(sample.worlds), fmt_xs(sample.cels)])
	actor.swing_left = 0
	actor.visual_weapon = ""
	if show_held:
		actor.held.show()
	actor.equip(exit_weapon)
	actor.pickup_time = 0
	var exit_sheet: SpriteFrames = sheet_for.call(exit_weapon)
	flow.play_exit(func(): pass)
	for _tick in 4:
		flow.tick(1.0 / 60.0, actor)
	report.call(exit_sheet != null and actor.body.animation == "run" and actor.body.sprite_frames == exit_sheet, "%s stage exit run uses the armed sheet (clip %s)" % [exit_weapon, actor.body.animation])
	flow.cancel()
	restore_actor(actor, saved)
