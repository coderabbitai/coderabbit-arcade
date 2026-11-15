extends RefCounted
## The six games the hub shows as tiles, in grid order (three columns, two rows). Each entry names
## its AppRouter route, the family eyebrow, a one-line tagline, the preview.gd indices its tile and
## the showcase cycle through (the first is the tile's art), and the Hoppy reaction it triggers
## (hoppy.gd: 0 platformer jump, 1 runner 3D, 2 brawler jab).
const GAMES: Array[Dictionary] = [
	{"route": "bay_area_blitz", "title": "BAY AREA BLITZ", "family": "PLATFORMER",
		"tagline": "Cable cars. Code critters. Chaos.", "previews": [0], "reaction": 0},
	{"route": "orbital_ops", "title": "ORBITAL OPS", "family": "PLATFORMER",
		"tagline": "Zero gravity. Broken legacy routines.", "previews": [1], "reaction": 0},
	{"route": "enchanted_repo", "title": "THE ENCHANTED REPO", "family": "PLATFORMER",
		"tagline": "Ancient armor. Unstable branches.", "previews": [2], "reaction": 0},
	{"route": "runner_game", "title": "ENDLESS RUNNER", "family": "ENDLESS RUNNER",
		"tagline": "Outrun the unreviewed backlog.", "previews": [3, 4, 5, 6], "reaction": 1},
	{"route": "code_city_brawl", "title": "CODE CITY BRAWL", "family": "BEAT'EM UP",
		"tagline": "Three districts. One final merge.", "previews": [7, 8, 9], "reaction": 2},
	{"route": "heroes_vs_villains", "title": "HEROES VS. VILLAINS", "family": "BEAT'EM UP",
		"tagline": "Four villains. Review, triage, secure.", "previews": [10, 11, 12], "reaction": 2},
]
const COLUMNS := 3

## The preview indices each tile cycles through, in grid order (the showcase's groups).
static func preview_groups() -> Array:
	return GAMES.map(func(game: Dictionary) -> Array: return game.previews)
