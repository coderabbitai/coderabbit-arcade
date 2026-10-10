extends RefCounted
const TITLES := ["CLI / IDE DISTRICT", "SECURITY SECTOR", "GIT REPOSITORY HQ"]
const THEMES := ["district", "security", "hq"]
const STORIES := ["The terminals have gone dark. Rogue commands are running wild.", "The firewall is down. Injection attacks are flooding the corridors.", "The source repo is under siege. Face the conflict and ship the fix."]
const MUSIC := [
	preload("res://Assets/Audio/Beat'em Up/Zodik - Future Travel.ogg"),
	preload("res://Assets/Audio/Beat'em Up/helldrake(extended).ogg"),
	preload("res://Assets/Audio/Beat'em Up/kim_lightyear_-_angel_eyes_vision_ii.mp3")]
const BOSS_MUSIC = preload("res://Assets/Audio/Beat'em Up/Kim Lightyear - The Final.mp3")
## Hands-free stage flow (seconds, world px, px/s, dB). stage_flow.gd reads its DEFAULTS keys;
## the rest are game.gd's: intro page hold, room-0 telegraph grace, boss-music dip, exit banner,
## and the hold of each victory-epilogue page.
const FLOW := {
	"run_speed":300.0, "exit_min":.6, "exit_max":1.6, "exit_margin":60.0,
	"fade_out":.35, "fade_in":.35, "music_floor_db":-40.0,
	"enter_from_x":-60.0, "enter_to_x":180.0, "enter_max":1.6,
	"stage_banner":2.8, "banner_slide":.3, "banner_fade":.6,
	"exit_banner":2.0, "intro_hold":4.5, "enemy_grace":.8, "boss_dip":.6, "ending_hold":5.0}
const FX_ROOT := "res://Assets/code-city-brawl-assets-only/code_city/"
## Last-life knockout (knockout.gd DEFAULTS keys; seconds since the hit, world px, radians, dB).
## Hoppy recoils facing the hit, then turns with the blow and the death clip does the tipping
## over: slumping through the climb, folding on the way down, flat at touchdown, a rebound, the
## settled heap, head first along the throw.
const KNOCKOUT := {
	"hit_stop":.12, "launch_end":.75, "land_end":1.0, "length":2.2,
	"distance":140.0, "height":70.0, "bounce":10.0, "tip":.45, "pivot":40.0, "turn":.12,
	"hit_pose":"hurt", "clip":"death", "clip_starts":[.12,.24,.42,.75,.84,.93],
	"hit_fx":{"frames":FX_ROOT+"weapons.tres",
		"pose":"hammer_impact","scale":.75,"rise":50.0,"front":true},
	"dust_fx":{"frames":FX_ROOT+"combat_fx.tres",
		"pose":"slam_impact","scale":1.2,"squash":.5,"rise":20.0,"front":false},
	"land_sound":"kick", "head":Vector2(20,-40), "star_size":8.0, "callout_color":Color("ffd36b")}
const SOUND_ROOT := "res://Assets/Audio/The Essential Retro Video Game Sound Effects Collection [512 sounds] By Juhani Junkala/"
## The opening: three story scenes (story_scene.gd), each held for FLOW.intro_hold. image is the
## painted scene; until it is imported, the district art in fallback stands in. from/to frame the
## Ken Burns move as Vector3(focus x, focus y, zoom).
const STORY_ROOT := "res://Assets/beatemup-story/code_city/"
const STAGE_ART := "res://Assets/code-city-brawl-assets-only/code_city/"
const STORY_ACCENT := Color("79e0c4")
const STORY_SERIES := ""
const STORY := [
	{"image":STORY_ROOT+"under_siege.png", "fallback":STAGE_ART+"district_background.png",
		"kicker":"CODE CITY: UNDER SIEGE",
		"caption":"Rogue Code and Slop Code have escaped the review pipeline.\nThe terminals go dark.",
		"from":Vector3(.5,.45,1.0), "to":Vector3(.6,.36,1.22)},
	{"image":STORY_ROOT+"pipeline_breached.png", "fallback":STAGE_ART+"security_background.png",
		"kicker":"REVIEW PIPELINE: BREACHED",
		"caption":"The firewall is failing. Conflicting branches have taken over Git HQ.",
		"from":Vector3(.64,.44,1.14), "to":Vector3(.36,.46,1.2)},
	{"image":STORY_ROOT+"hoppy_clocks_in.png", "fallback":STAGE_ART+"hq_background.png",
		"kicker":"HOPPY CLOCKS IN",
		"caption":"The codebase needs a review. And Hoppy delivers.\nClear three districts and force the final merge.",
		"from":Vector3(.5,.38,1.25), "to":Vector3(.5,.48,1.0)}]
## The victory epilogue after the Force Merge: three more story scenes, each held for
## FLOW.ending_hold, then the results screen (victory_screen.gd). Same shape as STORY.
const ENDING := [
	{"image":STORY_ROOT+"merge_resolved.png", "fallback":STAGE_ART+"hq_background.png",
		"kicker":"CONFLICT RESOLVED",
		"caption":"The Grand Merge Conflict collapses.\nEvery branch folds into one clean history.",
		"from":Vector3(.5,.42,1.22), "to":Vector3(.5,.5,1.0)},
	{"image":STORY_ROOT+"city_back_online.png", "fallback":STAGE_ART+"district_background.png",
		"kicker":"CODE CITY: BACK ONLINE",
		"caption":"District by district, the terminals light back up.\nThe review pipeline holds.",
		"from":Vector3(.36,.46,1.18), "to":Vector3(.62,.42,1.08)},
	{"image":STORY_ROOT+"hoppy_ships_it.png", "fallback":STAGE_ART+"security_background.png",
		"kicker":"SHIPPED.",
		"caption":"Merged, shipped and saved.\nCode City owes Hoppy one.",
		"from":Vector3(.5,.5,1.0), "to":Vector3(.5,.4,1.25)}]
## The results screen after the epilogue.
const VICTORY := {"title":"MERGED. SHIPPED. SAVED.", "line":"Code City is back online."}
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
const PAD_BUTTONS := {
	"brawl_jump":JOY_BUTTON_A,"brawl_pickup":JOY_BUTTON_Y,"brawl_attack":JOY_BUTTON_X}
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
