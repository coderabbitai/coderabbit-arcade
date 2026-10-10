# CodeRabbit Kit

Runtime helpers for Godot 4.5 and newer. Copy this directory into a game unchanged, at a release tag. Nothing registers globally: no `class_name`, autoloads or project settings. Preload what you use. MIT licensed; see `LICENSE`.

```gdscript
const CrInput := preload("res://addons/cr_kit/input.gd")
```

## Input

Godot's `JoyButton` constants are positions, not labels. `JOY_BUTTON_A` is always the bottom face button: Cross on PlayStation, A on Xbox, B on Nintendo.

### `CrInput.Family`: which labels a pad wears

```gdscript
var family := CrInput.Family.detect(Input.get_joy_name(device), CrInput.Family.vendor_id(Input.get_joy_info(device)))
# "playstation", "xbox", "nintendo" or "neutral"
```

A first-party USB vendor id (Sony, Microsoft, Nintendo) decides the family. Otherwise name fragments do ("DualSense", "Xbox", "Switch", ...). Unknown pads are `neutral` and get position names. `vendor_id()` accepts the decimal string SDL-backed platforms report.

### `CrInput.Labels`: what to print

| Position | `Labels.button(...)` | PlayStation | Xbox | Nintendo | neutral |
| --- | --- | --- | --- | --- | --- |
| South | `JOY_BUTTON_A` | Cross | A | B | South |
| East | `JOY_BUTTON_B` | Circle | B | A | East |
| West | `JOY_BUTTON_X` | Square | X | Y | West |
| North | `JOY_BUTTON_Y` | Triangle | Y | X | North |
| Start | `JOY_BUTTON_START` | Options | Menu | + | Start |
| Back | `JOY_BUTTON_BACK` | Share / Create | View | - | Back |
| Shoulders | `JOY_BUTTON_LEFT_SHOULDER` | L1 | LB | L | Left shoulder |
| Triggers | `Labels.axis(JOY_AXIS_TRIGGER_LEFT, ...)` | L2 | LT | ZL | Left trigger |

```gdscript
CrInput.Labels.button(JOY_BUTTON_A, "nintendo")                 # "B"
CrInput.Labels.axis(JOY_AXIS_LEFT_X, "xbox", -1.0)              # "Left stick left"
CrInput.Labels.action(&"jump", "playstation")                   # first pad binding of "jump": "Cross"
CrInput.Labels.action(&"jump", "xbox", CrInput.Labels.Source.KEYBOARD)  # "Space"
CrInput.Labels.action_labels(&"move_left", "xbox")              # ["D-pad left", "Left stick left"]
```

`action()` reads the live `InputMap`, so prompts follow rebinding. Keyboard labels include modifiers ("Ctrl+S") and name a physical key by its US QWERTY position.

### `CrInput.Bindings`: bindings that answer every pad

A new `InputEventJoypadButton` answers device 0 only. These helpers bind to device `-1`:

```gdscript
CrInput.Bindings.install({
	&"jump": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_A]},
	&"move_left": {"keys": [KEY_A], "buttons": [JOY_BUTTON_DPAD_LEFT], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
})
CrInput.Bindings.widen_to_any_device()        # rebind any single-device pad event to every pad
CrInput.Bindings.single_device_pad_events()   # audit: [] when every pad binding answers every pad
```

Godot 4.5 ships its built-in `ui_*` pad bindings for device 0 only, so menus ignore a second pad unless you call `widen_to_any_device()` at startup. Godot 4.7 binds them to every device.

### `CrInput.Roster`: who owns which pad

```gdscript
var roster := CrInput.Roster.new([&"p1", &"p2"])
Input.joy_connection_changed.connect(roster.on_joy_connection_changed)
roster.role_lost.connect(func(role, device): pause_game())
roster.role_restored.connect(func(role, device): resume_game())
roster.refresh()
roster.device_for(&"p1")             # -1 while vacant
roster.family(roster.device_for(&"p1"))
```

- Each newly connected pad fills the first vacant, unreserved role (`auto_assign`, on by default); that includes a role freed by `release()`, never one waiting for its pad. A pad that is already connected but owns no role, for example after `release()` or after `assign()` displaced it, waits for `claim()` or `assign()`.
- A disconnected pad leaves its role vacant but reserved (`is_waiting()`); `role_lost` fires, unless a `device_disconnected` listener already handed the role to another pad or called `release()` on it.
- The same pad (GUID and name) reconnecting takes the role back and fires `role_restored`, even under a new device id. If several waiting roles or new pads match, nothing is guessed.
- `claim(device)` gives an unowned pad the first waiting role (for "press Start to continue"), `assign(role, device)` moves a pad into a role (for "the pad you last used is player one"), and `release(role)` forgets a reservation. `swap()` exchanges two roles and emits `roles_swapped`.
- A disconnect reported through `on_joy_connection_changed()` stays in effect even if the device list still names the pad, until the list drops it or a connection callback reports it back.

The roster reads devices only through its `hardware` object. Pass a fake with `devices()`, `name()`, `guid()` and `info()` to test without controllers.

Device detection follows Godot's SDL-based gamepad support on desktop platforms. Check new families on real hardware; the web platform reports fewer details, so pads there often read as `neutral`.
