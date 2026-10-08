extends RefCounted
const TITLES := ["CLI / IDE DISTRICT", "SECURITY SECTOR", "GIT REPOSITORY HQ"]
const THEMES := ["district", "security", "hq"]
const STORIES := ["The terminals have gone dark. Rogue commands are running wild.", "The firewall is down. Injection attacks are flooding the corridors.", "The source repo is under siege. Face the conflict and ship the fix."]
const MUSIC := [
	preload("res://Assets/Audio/Beat'em Up/Zodik - Future Travel.ogg"),
	preload("res://Assets/Audio/Beat'em Up/helldrake(extended).ogg"),
	preload("res://Assets/Audio/Beat'em Up/kim_lightyear_-_angel_eyes_vision_ii.mp3")]
const BOSS_MUSIC = preload("res://Assets/Audio/Beat'em Up/Kim Lightyear - The Final.mp3")
const SOUND_ROOT := "res://Assets/Audio/The Essential Retro Video Game Sound Effects Collection [512 sounds] By Juhani Junkala/"
const SOUNDS := {
	"jab": preload(SOUND_ROOT + "Weapons/Melee/sfx_wpn_punch1.wav"),
	"swing": preload(SOUND_ROOT + "Weapons/Melee/sfx_wpn_punch2.wav"),
	"kick": preload(SOUND_ROOT + "Weapons/Melee/sfx_wpn_punch4.wav"),
	"hurt": preload(SOUND_ROOT + "General Sounds/Negative Sounds/sfx_sounds_damage1.wav"),
	"break": preload(SOUND_ROOT + "General Sounds/Negative Sounds/sfx_sounds_damage3.wav"),
	"pickup": preload(SOUND_ROOT + "General Sounds/Coins/sfx_coin_double1.wav"),
	"jump": preload(SOUND_ROOT + "Movement/Jumping and Landing/sfx_movement_jump13.wav"),
	"phase": preload(SOUND_ROOT + "General Sounds/Fanfares/sfx_sounds_fanfare2.wav"),
	"win": preload(SOUND_ROOT + "General Sounds/Fanfares/sfx_sounds_fanfare3.wav")}
const WEAPONS := {
	"debug_stick": {"uses":5,"damage":2.0,"reach":105.0,"depth":45.0,"knock":100.0,"time":.34},
	"linter_staff": {"uses":8,"damage":1.0,"reach":155.0,"depth":85.0,"knock":110.0,"time":.46},
	"api_key_whip": {"uses":6,"damage":1.0,"reach":235.0,"depth":42.0,"knock":100.0,"time":.42},
	"git_branch": {"uses":4,"damage":1.0,"reach":125.0,"depth":50.0,"knock":320.0,"time":.42},
	"firewall_shield": {"uses":3,"damage":1.0,"reach":100.0,"depth":45.0,"knock":100.0,"time":.34},
	"refactor_hammer": {"uses":3,"damage":4.0,"reach":115.0,"depth":48.0,"knock":190.0,"time":.72}}
const ENEMIES := {
	"cli_gremlin": {"hp":1,"speed":125.0,"tell":.6,"warning":"jab_warning","attack":"jab"},
	"syntax_error_sprite": {"hp":2,"speed":78.0,"tell":.9,"warning":"throw_warning","attack":"throw"},
	"linter_enforcer": {"hp":3,"speed":55.0,"tell":1.05,"warning":"baton_warning","attack":"baton"},
	"cve_crawler": {"hp":2,"speed":140.0,"tell":.65,"warning":"pounce_warning","attack":"pounce"},
	"injection_attack_drone": {"hp":2,"speed":85.0,"tell":1.0,"warning":"burst_warning","attack":"burst"},
	"dependency_bot": {"hp":1,"speed":100.0,"tell":.7,"warning":"lunge_warning","attack":"lunge"},
	"merge_conflict_soldier": {"hp":3,"speed":78.0,"tell":.85,"warning":"sword_warning","attack":"sword"},
	"force_push_bandit": {"hp":2,"speed":85.0,"tell":1.0,"warning":"charge_warning","attack":"charge"},
	"stale_branch_zombie": {"hp":2,"speed":46.0,"tell":1.0,"warning":"claw_warning","attack":"claw"}}
const WAVES := [
	[["cli_gremlin","cli_gremlin","syntax_error_sprite"], ["cli_gremlin","linter_enforcer","syntax_error_sprite"], ["linter_enforcer","cli_gremlin","syntax_error_sprite","cli_gremlin"]],
	[["cve_crawler","injection_attack_drone"], ["dependency_bot","dependency_bot","dependency_bot","injection_attack_drone"], ["cve_crawler","cve_crawler","injection_attack_drone","dependency_bot"]],
	[["merge_conflict_soldier","force_push_bandit"], ["stale_branch_zombie","force_push_bandit","merge_conflict_soldier"], []]]
## InputMap's "any device" id. A new InputEventJoypadButton defaults to device 0, so a code-made
## binding would answer only the first pad; booths and reconnected controllers use other ids.
const ANY_DEVICE := -1
const PAD_BUTTONS := {"brawl_jump":JOY_BUTTON_A,"brawl_pickup":JOY_BUTTON_Y,"brawl_attack":JOY_BUTTON_X}
static func joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = ANY_DEVICE
	event.button_index = button
	return event
static func install_input() -> void:
	for action in ["brawl_jump","brawl_pickup","brawl_attack"]:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var keys: Array = {"brawl_jump":[KEY_SPACE],"brawl_pickup":[KEY_E,KEY_K],"brawl_attack":[KEY_J,KEY_X]}[action]
		for key in keys:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)
		InputMap.action_add_event(action,joy_button(PAD_BUTTONS[action]))
static func looped(track: AudioStream) -> AudioStream:
	var result := track.duplicate() as AudioStream
	if result is AudioStreamMP3 or result is AudioStreamOggVorbis: result.loop = true
	return result
