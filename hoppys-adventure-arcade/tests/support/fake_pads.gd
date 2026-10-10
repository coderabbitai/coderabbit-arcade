extends RefCounted
## A stand-in for the cr_kit roster's Hardware: pads are plugged and unplugged by the test.

var _pads := {}  # device -> {"name", "guid", "vendor"}
var _order: Array[int] = []


func plug(device: int, pad_name: String, pad_guid: String = "", vendor: int = 0) -> void:
	_pads[device] = {"name": pad_name, "guid": pad_guid if not pad_guid.is_empty() else "guid-" + pad_name, "vendor": vendor}
	if not _order.has(device):
		_order.append(device)


func unplug(device: int) -> void:
	_pads.erase(device)
	_order.erase(device)


func devices() -> Array[int]:
	return _order.duplicate()


func name(device: int) -> String:
	return _pads[device].name


func guid(device: int) -> String:
	return _pads[device].guid


## SDL-backed platforms report the vendor id as a decimal string; keep that shape.
func info(device: int) -> Dictionary:
	var vendor: int = _pads[device].vendor
	return {"vendor_id": str(vendor)} if vendor != 0 else {}
