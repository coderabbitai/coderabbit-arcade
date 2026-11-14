extends RefCounted
## Heroes vs. Villains colours shared with the how-to-play demo (app/how_to_play_demo.gd). They live
## here so the demo, which the hub loads at startup, needs none of the gameplay scripts: player.gd
## and enemy.gd preload the catalogs and with them every music track of both beat 'em ups.
const REVIEW_TINT := Color("79e0c4")
const REVIEW_GLOW := Color(0.8, 1.25, 1.1)
const STUNNED_TINT := Color(0.6, 0.8, 1.3)
