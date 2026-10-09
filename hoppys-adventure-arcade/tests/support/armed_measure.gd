extends RefCounted
## Shared armed-run measurements for the motion and asset suites, so every suite measures the
## body the same way the builder's check_run_body does.

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
