extends RefCounted
## The input module's entry point. Preload this one script:
##
##     const CrInput := preload("res://addons/cr_kit/input.gd")
##     CrInput.Labels.button(JOY_BUTTON_A, CrInput.Family.NINTENDO)  # "B"

## Controller family detection: PlayStation, Xbox, Nintendo or neutral.
const Family := preload("input/controller_family.gd")
## Player-facing names for buttons, sticks, triggers and bound actions, per family.
const Labels := preload("input/button_labels.gd")
## InputMap bindings that answer every controller, plus audits for ones that don't.
const Bindings := preload("input/bindings.gd")
## Per-role controller ownership that survives disconnects and reconnects.
const Roster := preload("input/device_roster.gd")
