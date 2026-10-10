extends RefCounted
## Which controller each player role owns, kept stable across disconnects and reconnects.
##
## Roles are names you choose ("p1", "p2", ...). A pad that disconnects leaves its role vacant but
## reserved for it. Godot device ids are not stable across reconnects, and a GUID identifies a
## model and transport rather than one physical unit, so a returning pad gets its role back
## automatically only when exactly one reserved role waits for its GUID and name and exactly one
## newly connected pad matches. Anything ambiguous waits for claim(), for example when the
## player presses Start. New pads fill roles nobody has used yet, in order, unless auto_assign is
## off; they never take a reserved role.
##
## The roster reads hardware only through `hardware`, so tests can pass a fake with the same
## four methods as Hardware. Call refresh() once at start and whenever Input reports a
## connection change (connect Input.joy_connection_changed to on_joy_connection_changed).

const Family := preload("controller_family.gd")

## A pad connected (after the roster recorded its name, GUID and family).
signal device_connected(device: int)
## A pad disconnected. role_lost follows when it owned a role.
signal device_disconnected(device: int)
## A pad took a role through auto-assignment, claim() or assign().
signal role_assigned(role: StringName, device: int)
## A role's pad disconnected. The role stays reserved for that pad.
signal role_lost(role: StringName, device: int)
## A reserved role's pad came back and took the role again automatically.
signal role_restored(role: StringName, device: int)
## A role became vacant without a reservation (release(), or its pad moved by assign()).
signal role_released(role: StringName)
## swap() exchanged two roles' owners and reservations. Read the new owners with device_for().
signal roles_swapped(first: StringName, second: StringName)


## The roster's only access to Input. Replace it with a fake in tests.
class Hardware extends RefCounted:
	func devices() -> Array[int]:
		return Input.get_connected_joypads()

	func name(device: int) -> String:
		return Input.get_joy_name(device)

	func guid(device: int) -> String:
		return Input.get_joy_guid(device)

	func info(device: int) -> Dictionary:
		return Input.get_joy_info(device)


var hardware: RefCounted
## New pads fill never-used roles in order. Turn off to assign every role with claim().
var auto_assign := true

var _roles: Array[StringName] = []
var _owners := {}  # role -> device id, -1 when vacant
var _reserved := {}  # role -> identity of the pad it waits for, "" for none
var _connected: Array[int] = []
var _identities := {}  # device -> "guid:lowercase name"
var _names := {}  # device -> reported name
var _families := {}  # device -> controller family
var _reported_gone: Array[int] = []  # disconnects the device list has not caught up with


func _init(role_names: Array = [&"p1"], source: RefCounted = null) -> void:
	assert(not role_names.is_empty(), "A roster needs at least one role.")
	for role: Variant in role_names:
		var key := StringName(role)
		assert(not _roles.has(key), "Duplicate roster role: %s" % key)
		_roles.append(key)
		_owners[key] = -1
		_reserved[key] = ""
	hardware = source if source != null else Hardware.new()


## Reconciles the roster with the connected pads and emits what changed. Safe to call any time.
func refresh() -> void:
	var listed: Array[int] = hardware.devices()
	for device: int in _reported_gone.duplicate():
		if not listed.has(device):
			_reported_gone.erase(device)
	_reconcile(listed)


## Connect Input.joy_connection_changed here. A pad reported as disconnected stays gone, even if
## the device list still names it, until the list drops it or a connection is reported again.
func on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_reported_gone.erase(device)
	elif not _reported_gone.has(device):
		_reported_gone.append(device)
	refresh()


func roles() -> Array[StringName]:
	return _roles.duplicate()


## The device that owns a role, or -1 when the role is vacant.
func device_for(role: StringName) -> int:
	return _owners.get(role, -1)


## The role a device owns, or &"" when it owns none.
func role_of(device: int) -> StringName:
	for role: StringName in _roles:
		if _owners[role] == device and device >= 0:
			return role
	return &""


## True when a role's pad disconnected and the role is waiting for it.
func is_waiting(role: StringName) -> bool:
	return _owners.get(role, -1) < 0 and not str(_reserved.get(role, "")).is_empty()


## Roles waiting for a disconnected pad, in role order.
func waiting_roles() -> Array[StringName]:
	var waiting: Array[StringName] = []
	for role: StringName in _roles:
		if is_waiting(role):
			waiting.append(role)
	return waiting


func connected_devices() -> Array[int]:
	return _connected.duplicate()


## The controller family of a connected device ("neutral" when unknown or disconnected).
func family(device: int) -> String:
	return _families.get(device, Family.NEUTRAL)


func device_name(device: int) -> String:
	return _names.get(device, "")


## Gives a connected, unowned pad a vacant role: `role` if given, else the first waiting role,
## else the first role nobody has used. Never displaces a connected owner. Returns success.
func claim(device: int, role: StringName = &"") -> bool:
	if not _connected.has(device) or not role_of(device).is_empty():
		return false
	var target := role
	if target.is_empty():
		var waiting := waiting_roles()
		target = waiting[0] if not waiting.is_empty() else _first_unused_role()
	if target.is_empty() or not _owners.has(target) or _owners[target] >= 0:
		return false
	_assign(target, device)
	role_assigned.emit(target, device)
	return true


## Moves a connected pad into a role, displacing its current owner (whose reservation is
## dropped). If the pad owned another role, that role is released. For "the pad you last
## touched is player one" behavior.
func assign(role: StringName, device: int) -> bool:
	if not _owners.has(role) or not _connected.has(device):
		return false
	if _owners[role] == device:
		return true
	var previous_role := role_of(device)
	if not previous_role.is_empty():
		_vacate(previous_role)
		role_released.emit(previous_role)
	_assign(role, device)
	role_assigned.emit(role, device)
	return true


## Makes a role vacant and forgets the pad it was waiting for.
func release(role: StringName) -> void:
	if not _owners.has(role):
		return
	_vacate(role)
	role_released.emit(role)


## Exchanges two roles' owners and reservations.
func swap(first: StringName, second: StringName) -> void:
	if not _owners.has(first) or not _owners.has(second) or first == second:
		return
	var owner: int = _owners[first]
	_owners[first] = _owners[second]
	_owners[second] = owner
	var reserved: String = _reserved[first]
	_reserved[first] = _reserved[second]
	_reserved[second] = reserved
	roles_swapped.emit(first, second)


func _reconcile(listed: Array[int]) -> void:
	var now: Array[int] = []
	for device: int in listed:
		if not _reported_gone.has(device) and not now.has(device):
			now.append(device)
	var arrivals: Array[int] = []
	for device: int in now:
		if not _connected.has(device):
			arrivals.append(device)
	var departures: Array[int] = []
	for device: int in _connected:
		if not now.has(device):
			departures.append(device)
	_connected = now
	for device: int in departures:
		var role := role_of(device)
		if not role.is_empty():
			_owners[role] = -1  # The reservation stays, so the same pad can come back.
		_identities.erase(device)
		_names.erase(device)
		_families.erase(device)
		device_disconnected.emit(device)
		if not role.is_empty():
			role_lost.emit(role, device)
	for device: int in arrivals:
		var device_name_text: String = hardware.name(device)
		_names[device] = device_name_text
		_identities[device] = "%s:%s" % [hardware.guid(device), device_name_text.to_lower()]
		_families[device] = Family.detect(device_name_text, Family.vendor_id(hardware.info(device)))
		device_connected.emit(device)
	_restore(arrivals)
	if auto_assign:
		for device: int in now:
			if not role_of(device).is_empty():
				continue
			var role := _first_unused_role()
			if role.is_empty():
				break
			_assign(role, device)
			role_assigned.emit(role, device)


func _restore(arrivals: Array[int]) -> void:
	for role: StringName in waiting_roles():
		var identity: String = _reserved[role]
		var rivals := 0
		for other: StringName in waiting_roles():
			if _reserved[other] == identity:
				rivals += 1
		var matches: Array[int] = []
		for device: int in arrivals:
			if _identities.get(device, "") == identity and role_of(device).is_empty():
				matches.append(device)
		if rivals == 1 and matches.size() == 1:
			_assign(role, matches[0])
			role_restored.emit(role, matches[0])


func _first_unused_role() -> StringName:
	for role: StringName in _roles:
		if _owners[role] < 0 and str(_reserved[role]).is_empty():
			return role
	return &""


func _assign(role: StringName, device: int) -> void:
	_owners[role] = device
	_reserved[role] = _identities.get(device, "")


func _vacate(role: StringName) -> void:
	_owners[role] = -1
	_reserved[role] = ""
