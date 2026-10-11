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

## Hoppy's shirt, found without weapon, paw or anatomy anchors, for Code City torso registration.
## The head is the largest 4-connected orange component. The torso is the largest neutral dark gray
## component whose pixels start within 2 rows above to 20 rows below the head's lowest row and sit
## within 18 px of the head's centroid x. Side runs read the component's back edge plus
## SHIRT_BACK_EDGE_OFFSET, which a staff shaft or a moving arm in front of the chest does not move;
## every other pose reads the centroid. Positions are in cell pixels, NaN when unreadable.
const SHIRT_WINDOW := 18.0
const SHIRT_BACK_EDGE_OFFSET := 6.0

static func _is_orange(c: Color) -> bool:
	var r := c.r8
	var g := c.g8
	var b := c.b8
	return c.a8 >= 128 and r > 200 and g > 40 and g < 170 and b < 100 and r - g > 70 and g - b > 25

static func _is_shirt_gray(c: Color) -> bool:
	var lo := mini(c.r8, mini(c.g8, c.b8))
	var hi := maxi(c.r8, maxi(c.g8, c.b8))
	return c.a8 >= 128 and lo >= 20 and hi < 85 and hi - lo < 22

## Largest 4-connected group of pixels where `test(color, x, y)` is true, as an Array of Vector2i.
static func _largest_component(image: Image, test: Callable) -> Array:
	var w := image.get_width()
	var h := image.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var best := []
	for y in h:
		for x in w:
			if seen[y * w + x] == 1 or not test.call(image.get_pixel(x, y), x, y):
				continue
			var group := []
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * w + x] = 1
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				group.append(at)
				for step in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nxt: Vector2i = at + step
					if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h or seen[nxt.y * w + nxt.x] == 1:
						continue
					if test.call(image.get_pixel(nxt.x, nxt.y), nxt.x, nxt.y):
						seen[nxt.y * w + nxt.x] = 1
						stack.append(nxt)
			if group.size() > best.size():
				best = group
	return best

static func shirt_landmark(cell_image: Image, side_run := false) -> Vector2:
	return shirt_measure(cell_image, side_run).position

## Shirt landmark, the pixel count of its component, the head centroid x and `head_to_back` (head x
## minus the shirt back edge). A tiny component means the front view's cream chest hid most of the
## shirt, so callers can require a minimum before trusting x.
static func shirt_measure(cell_image: Image, side_run := false) -> Dictionary:
	var missing := {"position": Vector2(NAN, NAN), "size": 0, "head_x": NAN, "head_to_back": NAN}
	var head := _largest_component(cell_image, func(c: Color, _x: int, _y: int) -> bool: return _is_orange(c))
	if head.is_empty():
		return missing
	var head_bottom := 0
	var head_x := 0.0
	for p in head:
		head_bottom = maxi(head_bottom, p.y)
		head_x += p.x
	head_x /= float(head.size())
	var core := _largest_component(cell_image, func(c: Color, x: int, y: int) -> bool:
		return _is_shirt_gray(c) and y >= head_bottom - 2 and y <= head_bottom + 20 and absf(float(x) - head_x) < SHIRT_WINDOW)
	if core.is_empty():
		return missing
	var sum := Vector2.ZERO
	var back_edge := INF
	for p in core:
		sum += Vector2(p)
		back_edge = minf(back_edge, float(p.x))
	var centroid := sum / float(core.size())
	if side_run:
		centroid.x = back_edge + SHIRT_BACK_EDGE_OFFSET
	return {"position": centroid, "size": core.size(), "head_x": head_x, "head_to_back": head_x - back_edge}

## Run frame count the spec publishes; Heroes stays at 4 and Code City publishes 6.
static func run_frame_count(spec: Dictionary) -> int:
	var clips: Variant = spec.get("clips", {})
	var run: Variant = clips.get("run", {}) if clips is Dictionary else {}
	var frames: Variant = run.get("frames", []) if run is Dictionary else []
	return frames.size() if frames is Array and frames.size() > 0 else 4

## Shirt x (side run back edge + 6) of the run frame the body is showing, for body registered sheets.
static func shirt_run_cel(body: AnimatedSprite2D, anim_frame: int) -> float:
	if body.sprite_frames == null or not body.sprite_frames.has_animation("run"):
		return NAN
	var texture := body.sprite_frames.get_frame_texture("run", anim_frame)
	var image := texture.get_image() if texture != null else null
	if image == null:
		return NAN
	var measured := shirt_measure(image, true)
	return measured.position.x if measured.size >= 15 else NAN

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
	sample.limit = RUN_BODY_LIMIT_PX * float(actor.body.scale.x)
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
				var cel := shirt_run_cel(actor.body, f) if spec.has("body_registration") else armed_run_cel(actor.body, spec, f)
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
			# Body registered sheets pass when the shirt (side run back edge + 6) stays within
			# RUN_BODY_LIMIT_PX of itself; Heroes keeps its paw anchored body reference.
			report.call(sample.measured and sample.worlds.size() == run_frame_count(spec) and sample.worst <= sample.limit, "%s facing %d armed run %s %.2f px across run frames (worst %.2f between %s; world x %s; cel x %s)" % [weapon, int(facing), "body stays within", sample.limit, sample.worst, sample.worst_at, fmt_xs(sample.worlds), fmt_xs(sample.cels)])
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
