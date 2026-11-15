extends RefCounted
## What each game's how-to-play card (app/how_to_play.gd) says: one entry per gameplay route
## (ControllerService.GAMEPLAY_ROUTES). The card is read standing at a booth, so each page's text is
## a line or two.
##
## A card is a few pages. A page is either the controls table (`"controls": true`) or a line of text
## over a short looping scene that app/how_to_play_demo.gd plays from the game's own sprites
## (`"scene": {"id": ...}`; the demo lists the ids and what each takes).
##
## Each control row names the input actions it describes, the keys it shows and the pad inputs it
## shows. tests/how_to_play.gd fails when a shown key or pad input is not bound to one of the row's
## actions, so the card can't drift from project.godot or a mode's install_input(). A row doesn't
## have to list every binding, only true ones. A row's `icon` names one of the game's `poses`: the
## sprite sheet, clip and optional motion ("slide", "rise", "sink", "spin", "pulse") of the little
## Hoppy acting it out beside the row.
##
## Pad entries are JoyButton values or one of the stick constants below.

## The left stick, any direction the row's actions use.
const STICK := -1
const STICK_UP := -2
const STICK_DOWN := -3

const BAY := "res://Assets/bay-area-blitz-assets-only/bay_area/"
const ORBIT := "res://Assets/orbital-ops-assets-only/orbital_ops/"
const FOREST := "res://Assets/enchanted-repo-assets-only/enchanted_repo/"
const CITY := "res://Assets/code-city-brawl-assets-only/code_city/"
const HEROES := "res://Assets/heroes-vs-villains-assets-only/heroes_villains/"
## Heroes vs. Villains' player sheets (modes/beatem_up/reinvent/player.gd).
const HERO := "res://Assets/Character/CodeRabbit/2D/heroes_villains/coderabbit_hero.tres"
const HERO_MOTION := "res://Assets/Character/CodeRabbit/2D/heroes_villains/coderabbit_hero_locomotion.tres"
const RUNNER := "res://Assets/runner/menu_previews/"
const PLATFORMER_HOPPY := BAY + "hoppy/platformer.tres"
const BRAWL_HOPPY := "res://Assets/code-city-brawl-player/combat.tres"

const _PAUSE := {"label": "Pause", "actions": ["pause"],
	"keys": [KEY_ESCAPE, KEY_P], "pad": [JOY_BUTTON_START]}

const _PLATFORMER_ROWS := [
	{"label": "Move", "icon": "move", "actions": ["move_left", "move_right"],
		"keys": [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT], "pad": [STICK, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]},
	{"label": "Jump", "hint": "hold for higher", "icon": "jump", "actions": ["jump"],
		"keys": [KEY_SPACE, KEY_W, KEY_UP], "pad": [JOY_BUTTON_A]},
	{"label": "Swipe", "icon": "attack", "actions": ["attack"], "keys": [KEY_J, KEY_X], "pad": [JOY_BUTTON_X]},
	_PAUSE,
]

const _PLATFORMER_POSES := {
	"move": [PLATFORMER_HOPPY, "run"],
	"jump": [PLATFORMER_HOPPY, "jump"],
	"attack": [PLATFORMER_HOPPY, "attack"],
	"rise": [PLATFORMER_HOPPY, "jump_rise", "rise"],
	"sink": [PLATFORMER_HOPPY, "jump_fall", "sink"],
}

const _BRAWL_ROWS := [
	{"label": "Move", "hint": "up/down = lane", "icon": "move", "actions": ["move_left", "move_right", "move_up", "move_down"],
		"keys": [KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN],
		"pad": [STICK, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]},
	{"label": "Jump", "icon": "jump", "actions": ["brawl_jump"], "keys": [KEY_SPACE], "pad": [JOY_BUTTON_A]},
	{"label": "Attack", "hint": "3-hit combo", "icon": "attack", "actions": ["brawl_attack"],
		"keys": [KEY_J, KEY_X], "pad": [JOY_BUTTON_X]},
	{"label": "Pick up weapon", "icon": "pickup", "actions": ["brawl_pickup"], "keys": [KEY_E, KEY_K], "pad": [JOY_BUTTON_Y]},
]

const _CONTROLS := {"heading": "Controls", "controls": true}

const GAMES := {
	"bay_area_blitz": {
		"title": "Bay Area Blitz",
		"pages": [
			{"heading": "Your goal", "text": "Run across the city, defeat the Merge Conflict Monster, then land on or swipe the MERGE button.",
				"scene": {"id": "platformer_goal", "world": "bay", "boss": BAY + "merge_monster.tres"}},
			_CONTROLS,
			{"heading": "Tips", "text": "Swipe bugs to clear them; you can't stomp them. You have three hearts; grab tokens for points.",
				"scene": {"id": "blitz_tips", "world": "bay"}},
		],
		"rows": _PLATFORMER_ROWS,
		"poses": _PLATFORMER_POSES,
	},
	"orbital_ops": {
		"title": "Orbital Ops",
		"pages": [
			{"heading": "Your goal", "text": "Cross the space station, defeat the Deprecated API, then land on or swipe the MERGE button.",
				"scene": {"id": "platformer_goal", "world": "orbital", "boss": ORBIT + "deprecated_api.tres"}},
			_CONTROLS,
			{"heading": "Zero gravity", "text": "In the cyan zero-gravity bay you float. Hold Jump or Up to rise, Down to sink; let go to brake.",
				"scene": {"id": "zero_g", "world": "orbital"}},
			{"heading": "Tips", "text": "Amber lasers and vents are a warning: cross while they're off.",
				"scene": {"id": "orbital_tips", "world": "orbital"}},
		],
		"rows": _PLATFORMER_ROWS + [
			{"label": "Zero-G rise", "hint": "hold", "icon": "rise", "actions": ["jump", "move_up"],
				"keys": [KEY_SPACE, KEY_W, KEY_UP], "pad": [JOY_BUTTON_A, STICK_UP]},
			{"label": "Zero-G sink", "hint": "hold", "icon": "sink", "actions": ["move_down"],
				"keys": [KEY_S, KEY_DOWN], "pad": [STICK_DOWN, JOY_BUTTON_DPAD_DOWN]},
		],
		"poses": _PLATFORMER_POSES,
	},
	"enchanted_repo": {
		"title": "The Enchanted Repo",
		"pages": [
			{"heading": "Your goal", "text": "Cross the forest and castle, defeat the Legacy Monolith, then land on or swipe the MERGE button.",
				"scene": {"id": "platformer_goal", "world": "forest", "boss": FOREST + "legacy_monolith.tres", "boss_scale": 1.35}},
			_CONTROLS,
			{"heading": "Tips", "text": "Branches crumble under you, so keep moving. Hit the Monolith while it recovers.",
				"scene": {"id": "enchanted_tips", "world": "forest"}},
		],
		"rows": _PLATFORMER_ROWS,
		"poses": _PLATFORMER_POSES,
	},
	"runner_game": {
		"title": "Endless Runner",
		"pages": [
			{"heading": "Your goal", "text": "Outrun the backlog through the Codebase Corridor. Survive as long as you can for a high score.",
				"scene": {"id": "slideshow", "images": [RUNNER + "runner_gameplay.png", RUNNER + "runner_boss.png"]}},
			_CONTROLS,
			{"heading": "Tips", "text": "Dodge hazards and grab power-ups and tools. Two hits without recovering and the backlog catches you.",
				"scene": {"id": "slideshow", "images": [RUNNER + "runner_dodge.png", RUNNER + "runner_powerup.png"]}},
		],
		"rows": [
			{"label": "Change lane", "icon": "lane", "actions": ["move_left", "move_right"],
				"keys": [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT], "pad": [STICK, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]},
			{"label": "Jump", "icon": "jump", "actions": ["jump", "move_up"],
				"keys": [KEY_SPACE, KEY_W, KEY_UP], "pad": [JOY_BUTTON_A, JOY_BUTTON_DPAD_UP]},
			{"label": "Roll", "icon": "roll", "actions": ["roll", "move_down"],
				"keys": [KEY_S, KEY_CTRL, KEY_DOWN], "pad": [JOY_BUTTON_B, JOY_BUTTON_DPAD_DOWN]},
			_PAUSE,
		],
		"poses": {
			"lane": [PLATFORMER_HOPPY, "run", "slide"],
			"jump": [PLATFORMER_HOPPY, "jump"],
			"roll": [PLATFORMER_HOPPY, "jump_apex", "spin"],
		},
	},
	"code_city_brawl": {
		"title": "Code City Brawl",
		"pages": [
			{"heading": "Your goal", "text": "Fight through three districts of bugs and beat the Grand Merge Conflict.",
				"scene": {"id": "brawl_goal", "world": "city"}},
			_CONTROLS,
			{"heading": "Tips", "text": "Clear every enemy, then walk right. Jump or change lanes to dodge attacks. Coffee heals.",
				"scene": {"id": "brawl_tips", "world": "city"}},
		],
		"rows": _BRAWL_ROWS + [_PAUSE],
		"poses": {
			"move": [PLATFORMER_HOPPY, "run"],
			"jump": [BRAWL_HOPPY, "jump"],
			"attack": [BRAWL_HOPPY, "jab"],
			"pickup": [BRAWL_HOPPY, "pickup"],
		},
	},
	"heroes_vs_villains": {
		"title": "Heroes vs. Villains",
		"pages": [
			{"heading": "Your goal", "text": "Defeat four villains and unlock CodeRabbit's capabilities to save the expo.",
				"scene": {"id": "heroes_goal", "world": "heroes"}},
			_CONTROLS,
			{"heading": "Tips", "text": "Clear each room, then walk through the right gate. Beating AI Slop unlocks REVIEW: hold Q / LB to stun nearby threats.",
				"scene": {"id": "heroes_review", "world": "heroes"}},
		],
		"rows": _BRAWL_ROWS + [
			{"label": "REVIEW", "hint": "hold, once unlocked", "icon": "review", "actions": ["review_burst"],
				"keys": [KEY_Q], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
			{"label": "Skip card", "actions": ["heroes_popup_advance"],
				"keys": [KEY_ENTER], "pad": [JOY_BUTTON_BACK]},
			_PAUSE,
		],
		"poses": {
			"move": [HERO_MOTION, "walk_down"],
			"jump": [HERO, "jump"],
			"attack": [HERO, "jab_action"],
			"pickup": [HERO, "pickup"],
			"review": [HEROES + "capabilities_fx.tres", "review_burst", "pulse"],
		},
	},
}


static func has_game(route: String) -> bool:
	return GAMES.has(route)


static func game(route: String) -> Dictionary:
	return GAMES.get(route, {})


static func pages(route: String) -> Array:
	return game(route).get("pages", [])
