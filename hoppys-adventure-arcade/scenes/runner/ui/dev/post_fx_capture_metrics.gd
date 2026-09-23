extends RefCounted
## Pure capture assertions, independently testable without a display.

static func canvas_items(node: Node) -> int:
	var count := 1 if node is CanvasItem else 0
	for child in node.get_children():
		count += canvas_items(child)
	return count

static func pixel_delta(before: Image, after: Image) -> Dictionary:
	if before == null or after == null or before.is_empty() or after.is_empty() or before.get_size() != after.get_size():
		return {"valid": false, "changed_pixels": 0, "mean_rgb_delta": 0.0, "max_rgb_delta": 0}
	var a := before.duplicate() as Image
	var b := after.duplicate() as Image
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var first := a.get_data()
	var second := b.get_data()
	var changed := 0
	var total := 0
	var peak := 0
	for offset in range(0, first.size(), 3):
		var pixel_peak := 0
		for channel in 3:
			var delta := absi(int(first[offset + channel]) - int(second[offset + channel]))
			total += delta
			pixel_peak = maxi(pixel_peak, delta)
		if pixel_peak > 0:
			changed += 1
		peak = maxi(peak, pixel_peak)
	return {"valid": true, "changed_pixels": changed, "mean_rgb_delta": float(total) / first.size(), "max_rgb_delta": peak}

static func has_visible_delta(delta: Dictionary) -> bool:
	return bool(delta.get("valid", false)) and int(delta.get("changed_pixels", 0)) > 0
