extends SceneTree
const ForestEnemy = preload("res://modes/platformer/enchanted_enemy.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func run() -> void:
	change_scene_to_file("res://scenes/platformer/enchanted_repo.tscn")
	await frames(12)
	var level=current_scene
	var player=level.player
	await process_frame
	level._resume()
	# Hold the player inside a missing platform's future shape.
	player.set_physics_process(false)
	var branch=level.branches[2]
	branch.state="gone"
	branch.clock=4
	branch.collider.disabled=true
	player.position=branch.position+Vector2(0,30)
	await frames(5)
	check(branch.state=="gone" and branch.collider.disabled,"Occupied branch delays regrowth")
	player.position.x+=200
	await frames(5)
	check(branch.state=="intact" and not branch.collider.disabled,"Branch regrows once Hoppy clears it")
	# Gnome's quill attack reaches beyond body contact and honors its tell.
	var gnome
	for child in level.get_children():
		if child is ForestEnemy and child.kind=="nitpick_gnome":
			gnome=child
			break
	gnome.set_physics_process(false)
	gnome.position=Vector2(700,600)
	gnome.attack_clock=0.1
	gnome.direction=-1
	player.position=Vector2(630,600)
	player.hp=3
	player.invulnerable=0
	await frames(3)
	gnome._physics_process(.01)
	check(player.hp==3,"Quill warning outside contact range is safe")
	gnome.attack_clock=.61
	gnome._physics_process(.01)
	check(player.hp==2,"Quill active phase reaches its indicated side")
	player.invulnerable=0
	player.position=Vector2(770,600)
	await frames(3)
	gnome._physics_process(.01)
	check(player.hp==2,"Committed jab does not turn toward Hoppy mid-attack")
	# Recovery contact is safe and Auto-Fix uses inherited enemy type without touching boss.
	player.invulnerable=999
	gnome.attack_clock=1.0
	player.position=gnome.position
	player.invulnerable=0
	await frames(3)
	gnome._physics_process(.01)
	check(player.hp==2,"Gnome recovery allows safe melee contact")
	player.invulnerable=999
	player.position=level.boss.position
	level._pickup("auto_fix",player.position)
	var enemy=ForestEnemy.new()
	enemy.player=player
	enemy.kind="bloat_troll"
	enemy.position=player.position+Vector2(150,0)
	level.add_child(enemy)
	await frames(5)
	check(enemy.dead and level.boss.hp==12,"Auto-Fix defeats nearby ordinary enemies and excludes Monolith")
	# Both attack/core art and independent instance health are restored on a fresh scene.
	level.boss.active=true
	level.boss.armor_stage=2
	level.boss.hp=6
	level.boss._enter_state(5)
	level.boss._physics_process(.01)
	check(level.boss.sprite.animation=="bare_sweep_warning","Bare attack retains stripped armor")
	change_scene_to_file("res://scenes/platformer/enchanted_repo.tscn")
	await frames(8)
	check(current_scene.boss.hp==12 and current_scene.boss.armor_stage==0,"Actor state never mutates shared SpriteFrames")
	change_scene_to_file("res://scenes/platformer/platformer_menu.tscn")
	await frames(3)
	await root.get_node("AudioService").settle()
	quit(failures)
