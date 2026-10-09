extends RefCounted
## Mode-local tuning. Shared resources are never mutated during a run.
const Shared = preload("res://modes/beatem_up/catalog.gd")
const TITLES := ["THE GENERATION FLOOR", "THE REVIEW GAUNTLET", "THE AGENTIC CORE"]
const THEMES := ["generation_floor", "review_gauntlet", "agentic_core"]
const KITS := ["generation_kit", "review_kit", "core_kit"]
const STORIES := ["Untrusted code floods the conference. Defeat AI SLOP to deploy REVIEW.", "Break the pipeline. Face the Coding Agent Army and the 10,000-Line PR together.", "Expose the attack surface. Stop the AI-Augmented Hacker at machine speed."]
const MUSIC_ROOT := "res://Assets/Audio/Beat'em Up/Hero vs Villian/"
const MUSIC := [preload(MUSIC_ROOT+"Hero Immortal.mp3"), preload(MUSIC_ROOT+"frivolous_hero.ogg"), preload(MUSIC_ROOT+"synth_type_mix2.ogg")]
const BOSS_MUSIC := [preload(MUSIC_ROOT+"8-bit_slay_the_evil.ogg"), preload(MUSIC_ROOT+"Heavy Concept A Bass Master.wav"), preload(MUSIC_ROOT+"Zodik - Lord of Zorg I.ogg")]
const CUE_ROOT := "res://Assets/heroes-vs-villains-assets-only/audio/"
const CUES := {
	"reveal_ai_slop": preload(CUE_ROOT+"reveal_ai_slop.wav"),
	"reveal_agent_army": preload(CUE_ROOT+"reveal_agent_army.wav"),
	"reveal_ten_thousand_line_pr": preload(CUE_ROOT+"reveal_ten_thousand_line_pr.wav"),
	"reveal_ai_augmented_hacker": preload(CUE_ROOT+"reveal_ai_augmented_hacker.wav"),
	"spawn": preload(CUE_ROOT+"agent_spawn.wav"), "collapse": preload(CUE_ROOT+"pr_stack_collapse.wav"),
	"whoosh": preload(CUE_ROOT+"machine_speed_whoosh.wav"), "unlock": preload(CUE_ROOT+"capability_unlock.wav")}
const WEAPONS := {
	"review_stamp": {"uses":6,"damage":1.0,"reach":155.0,"depth":88.0,"knock":100.0,"time":.44},
	"triage_hammer": {"uses":4,"damage":4.0,"reach":135.0,"depth":55.0,"knock":190.0,"time":.67},
	"change_stack_baton": {"uses":5,"damage":2.0,"reach":200.0,"depth":52.0,"knock":155.0,"time":.42},
	"security_scanner": {"uses":8,"damage":1.0,"reach":230.0,"depth":70.0,"knock":75.0,"time":.4},
	"pr_merger": {"uses":1,"damage":2.0,"reach":170.0,"depth":65.0,"knock":230.0,"time":.55}}
const ENEMIES := {
	"slop_sprite": {"hp":1,"speed":115.0,"tell":.65},
	"hallucinated_api_gremlin": {"hp":2,"speed":85.0,"tell":.85},
	"duplicate_logic_clone": {"hp":2,"speed":95.0,"tell":.75},
	"broken_test_bot": {"hp":3,"speed":58.0,"tell":1.0},
	"agent_spawner": {"hp":4,"speed":0.0,"tell":1.1},
	"change_stack_soldier": {"hp":3,"speed":72.0,"tell":.85},
	"review_blocker": {"hp":2,"speed":0.0,"tell":.75},
	"merge_request_mob": {"hp":1,"speed":140.0,"tell":.6},
	"ai_hacker_drone": {"hp":2,"speed":155.0,"tell":.32},
	"security_gap_crawler": {"hp":2,"speed":120.0,"tell":.6},
	"vulnerability_injector": {"hp":2,"speed":90.0,"tell":.9},
	"zero_day_phantom": {"hp":4,"speed":100.0,"tell":.6}}
const WAVES := [
	[["slop_sprite","slop_sprite","hallucinated_api_gremlin"], ["duplicate_logic_clone","broken_test_bot","hallucinated_api_gremlin","slop_sprite"], []],
	[["agent_spawner","change_stack_soldier","merge_request_mob","merge_request_mob","merge_request_mob"], ["review_blocker","change_stack_soldier","agent_spawner","merge_request_mob","merge_request_mob","merge_request_mob"], []],
	[["ai_hacker_drone","security_gap_crawler","vulnerability_injector"], ["zero_day_phantom","security_gap_crawler","vulnerability_injector","ai_hacker_drone"], []]]
const PROPS := [["terminal","kiosk"],["monolith","assembly"],["rack","node"]]
const BOSS_NAMES := {"ai_slop":"AI SLOP", "agent_army":"CODING AGENT ARMY", "ten_thousand_line_pr":"10,000-LINE PR", "ai_augmented_hacker":"AI-AUGMENTED HACKER"}
## Hands-free stage flow and presentation-card timing. stage_flow.gd consumes its default
## tuning keys; game.gd uses boss_dip, exit_banner, and the per-card holds below.
const FLOW := {
	"run_speed":300.0, "exit_min":.6, "exit_max":1.6, "exit_margin":60.0,
	"fade_out":.35, "fade_in":.35, "music_floor_db":-40.0,
	"enter_from_x":-60.0, "enter_to_x":180.0, "enter_max":1.6,
	"stage_banner":2.8, "banner_slide":.3, "banner_fade":.6,
	"exit_banner":2.0, "boss_dip":.6}
## The opening cards (presentation/opening_*.tscn) are story scenes (story_scene.gd): each one
## shows STORY[story_index]. image is the painted scene; until it is imported, the stage art in
## fallback stands in. from/to frame the Ken Burns move as Vector3(focus x, focus y, zoom).
const STORY_ROOT := "res://Assets/beatemup-story/heroes/"
const STAGE_ART := "res://Assets/heroes-vs-villains-assets-only/heroes_villains/"
const STORY_ACCENT := Color("ffab54")
const STORY_SERIES := "HEROES vs. VILLAINS / re:Invent EDITION"
const STORY := [
	{"image":STORY_ROOT+"situation.png", "fallback":STAGE_ART+"generation_floor.png",
		"kicker":"SITUATION",
		"caption":"10,284 additions. 147 files. AI is shipping at machine speed.\nNobody knows what any of it does.",
		"from":Vector3(.5,.4,1.25), "to":Vector3(.62,.3,1.45)},
	{"image":STORY_ROOT+"complication.png", "fallback":STAGE_ART+"review_gauntlet.png",
		"kicker":"COMPLICATION",
		"caption":"Slop floods the floor. Agents multiply.\nThe attack surface grows.",
		"from":Vector3(.34,.36,1.4), "to":Vector3(.66,.4,1.4)},
	{"image":STORY_ROOT+"send_in_the_rabbit.png", "fallback":STAGE_ART+"agentic_core.png",
		"kicker":"SEND IN THE RABBIT",
		"caption":"NEW ERA. NEW VILLAINS.\nThe CodeRabbit answers the alert.",
		"from":Vector3(.55,.32,1.6), "to":Vector3(.5,.44,1.25)}]
const CARD_HOLD := {
	"opening_situation":4.5, "opening_complication":4.5, "opening_resolution":4.5,
	"boss_ai_slop":3.0, "boss_agent_army":3.0, "boss_ten_thousand_line_pr":3.0, "boss_ai_augmented_hacker":3.0,
	"unlock_review":4.5, "unlock_triage":4.5, "unlock_change_stack":4.5, "unlock_security":4.5,
	"victory":6.0}

static func install_input() -> void:
	Shared.install_input()
	if not InputMap.has_action("heroes_popup_advance"):
		InputMap.add_action("heroes_popup_advance")
		for code in [KEY_ENTER, KEY_KP_ENTER]:
			var enter := InputEventKey.new()
			enter.physical_keycode=code
			InputMap.action_add_event("heroes_popup_advance",enter)
		InputMap.action_add_event("heroes_popup_advance",Shared.joy_button(JOY_BUTTON_BACK))
	if InputMap.has_action("review_burst"): return
	InputMap.add_action("review_burst")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	InputMap.action_add_event("review_burst",key)
	InputMap.action_add_event("review_burst",Shared.joy_button(JOY_BUTTON_LEFT_SHOULDER))

static func looped(track: AudioStream) -> AudioStream:
	var result := track.duplicate() as AudioStream
	if result is AudioStreamMP3 or result is AudioStreamOggVorbis:
		result.loop = true
	elif result is AudioStreamWAV:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = roundi(result.get_length()*result.mix_rate)
	return result
