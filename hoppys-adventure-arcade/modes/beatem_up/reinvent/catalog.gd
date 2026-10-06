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

static func install_input() -> void:
	Shared.install_input()
	if InputMap.has_action("review_burst"): return
	InputMap.add_action("review_burst")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	InputMap.action_add_event("review_burst",key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_SHOULDER
	InputMap.action_add_event("review_burst",button)

static func looped(track: AudioStream) -> AudioStream:
	var result := track.duplicate() as AudioStream
	if result is AudioStreamMP3 or result is AudioStreamOggVorbis:
		result.loop = true
	elif result is AudioStreamWAV:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = roundi(result.get_length()*result.mix_rate)
	return result
