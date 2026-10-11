extends RefCounted
## Camera keys use the boss shot schema: [p, distance, height, orbit, fov, look_bias].
## Focus is Hoppy's world position. The front approach reveals their victory pose before
## a tight orbit through the corridor hands back to the normal follow camera.
const SHOTS := {
	&"full": {
		"cut": 0.0,
		"ret": 0.82,
		"keys": [
			[0.0, 24.0, 3.6, -180.0, 68.0, 1.0],
			[0.167, 5.3, 2.2, -180.0, 56.0, 1.0],
			[0.33, 5.1, 2.2, -174.0, 56.0, 1.0],
			[0.40, 3.4, 2.5, -125.0, 60.0, 1.0],
			[0.445, 3.4, 3.0, -65.0, 60.0, 1.7],
			[0.495, 8.0, 4.0, 0.0, 60.0, 2.5],
			[0.82, 8.0, 4.0, 0.0, 60.0, 2.5],
			[1.0, 8.0, 4.0, 0.0, 60.0, 2.5],
		],
	},
	&"short": {
		"cut": 0.10,
		"ret": 0.73,
		"keys": [
			[0.0, 8.0, 4.0, 0.0, 60.0, 2.5],
			[0.45, 6.8, 3.3, 0.0, 56.0, 1.7],
			[0.73, 8.0, 4.0, 0.0, 60.0, 2.5],
			[1.0, 8.0, 4.0, 0.0, 60.0, 2.5],
		],
	},
}
