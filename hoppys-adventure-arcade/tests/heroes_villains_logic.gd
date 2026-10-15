extends SceneTree
const Catalog = preload("res://modes/beatem_up/reinvent/catalog.gd")
const DT := 1.0/60.0
const Facing = preload("res://tests/support/facing_checks.gd")
var game
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false);game.player.controlled=false
	for e in game.enemies+game.bosses:
		if is_instance_valid(e): e.set_physics_process(false)
func clear_enemies() -> void:
	for e in game.enemies:
		if is_instance_valid(e): e.free()
	game.enemies.clear()
func enemy(kind: String, pos: Vector2, split := true):
	var e=game.spawn_enemy(kind,pos,split)
	if e!=null: e.set_physics_process(false)
	return e
func finish_cards() -> void:
	if game.state=="boss_victory": game._physics_process(game.VICTORY_DURATION)
	var guard := 0
	while game.state=="cards" and guard<12:
		game.next_card();guard+=1
	if game.state=="stage_enter": game.begin_play()
func stage(index: int) -> void:
	game.start_stage(index)
	await process_frame
	freeze();game.begin_play()
func swing(p, kind := "", step := 1) -> void:
	p.attack_weapon=kind;p.combo=step;p.swing_serial+=1
	game.resolve_swing(p)

func advance_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode=KEY_ENTER;key.pressed=true
	return key
func accept_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action="ui_accept";event.pressed=true
	return event
func press_pause() -> void:
	var event := InputEventAction.new()
	event.action="pause";event.pressed=true
	game._unhandled_input(event)
func snapshot() -> Array:
	return [game.flow.phase,game.flow.clock,game.flow.veil.color.a,game.music.volume_db,game.player.position]
func steps(limit: int, until: Callable) -> void:
	var guard := 0
	while not until.call() and guard<limit:
		game._physics_process(1.0/60.0);guard+=1
## Plays the three ending cards out so win() arrives by the automatic transition.
func auto_win() -> void:
	game.overlay.hide();game.state="combat";game.playing=false
	game.show_cards(Catalog.ENDING_CARDS.duplicate(),game.win)
	for i in Catalog.ENDING_CARDS.size():
		game._physics_process(4.95)
		check(game.state=="cards","Ending card %d still holds at 4.95 s" % (i+1))
		game._physics_process(.1)
	check(game.state=="won" and game.victory.visible,"The ending cards auto-advance into the results screen")
func reload_game() -> void:
	# The router fades on a clock; a stuck route must fail the suite, not hang it.
	var deadline: int=Time.get_ticks_msec()+5000
	while root.get_node("AppRouter").busy:
		if Time.get_ticks_msec()>deadline:
			check(false,"AppRouter finishes routing within 5 s")
			quit(1)
			return
		await process_frame
	change_scene_to_file("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	await process_frame;await process_frame
	game=current_scene;game.test_mode=true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused=false
	if game.state=="paused": game.resume()
	freeze()
	steps(1200,func(): return game.state=="combat")
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	await process_frame;await process_frame
	game=current_scene;game.test_mode=true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused=false
	if game.state=="paused": game.resume()
	freeze()
	check(game.state=="cards" and not game.playing,"Opening panels precede combat")
	finish_cards()
	check(game.playing and game.stage_index==0,"Opening completes into Generation Floor")
	var p=game.player
	clear_enemies()
	p.position=Vector2(400,550);p.facing=1
	p.jump();p.tick(.1)
	check(p.height>30 and is_equal_approx(p.position.y,550),"Belt depth remains separate from jump height")
	p.height=0;p.rise=0
	p.start_attack();check(p.combo==1,"Combo starts with jab")
	p.swing_left=.1;p.request_attack();p.tick(.11)
	check(p.combo==2 and not p.queued,"Buffered attack advances once")
	p.swing_left=.1;p.request_attack();p.tick(.11)
	check(p.combo==3,"Third attack reaches finisher")
	p.swing_left=0;p.combo_window=0;p.start_attack();check(p.combo==1,"Expired combo resets")
	Facing.check_facing(p,check,enemy,"hallucinated_api_gremlin",clear_enemies)
	p.swing_left=0;p.combo_window=0
	var a=enemy("hallucinated_api_gremlin",Vector2(475,550))
	var b=enemy("hallucinated_api_gremlin",Vector2(475,640))
	swing(p);game.resolve_swing(p)
	check(a.hp==1 and b.hp==2,"Attack serial deduplicates hits and respects depth")
	check(not game.melee_contains(Vector2(-80,0),1,130,50),"Forward attack excludes targets behind")
	clear_enemies()
	var clone=enemy("duplicate_logic_clone",Vector2(475,550))
	clone.take_hit(999,100,p.position,true)
	check(clone.dead and game.living_enemies()==2,"First clone hit replaces original with two living children")
	for e in game.enemies:
		if is_instance_valid(e) and not e.dead: check(e.hp==1 and not e.can_split,"Clone children are 1 HP and cannot split recursively")
	clear_enemies()
	var bot=enemy("broken_test_bot",Vector2(475,550))
	bot.take_hit(9,0,p.position)
	check(bot.hp==2 and not bot.armor,"First test-bot hit breaks armor and removes one HP")
	bot.self_damage_clock=.01;bot.tick(.02)
	check(bot.hp==1,"Broken test bot periodically damages itself")
	bot.self_damage_clock=.01;bot.tick(.02)
	check(bot.dead,"Broken test bot can self-destruct")
	clear_enemies()
	var soldier=enemy("change_stack_soldier",Vector2(475,550))
	soldier.facing=-1
	check(not soldier.take_hit(1,100,p.position,false) and soldier.hp==3,"PR shield blocks frontal non-finisher")
	check(soldier.take_hit(1,100,Vector2(550,550),false),"Flanking bypasses PR shield")
	check(soldier.take_hit(1,100,p.position,true) and not soldier.shield,"Combo finisher breaks PR shield")
	var blocker=enemy("review_blocker",Vector2(700,600))
	blocker.take_hit(1,500,p.position)
	check(blocker.knock==Vector2.ZERO,"Review Blocker ignores knockback")
	clear_enemies()
	var spawner=enemy("agent_spawner",Vector2(800,550))
	spawner.release_attack()
	check(game.count_kind("slop_sprite")==1,"Agent Spawner creates owned Slop")
	spawner.finish_death()
	check(game.count_kind("slop_sprite")==0,"Spawner death removes owned Slop without blocking gate")
	clear_enemies()
	var phantom=enemy("zero_day_phantom",Vector2(600,550))
	phantom.hp=1;phantom.state="chase"
	var before: Vector2=phantom.position
	check(not phantom.take_hit(1,0,p.position) and phantom.position!=before,"Low-HP Phantom teleports to dodge")
	phantom.state="chase";phantom.reveal_left=0;phantom.update_visual()
	check(phantom.body.modulate.a<.2,"Hidden enemy has a faint silhouette")
	phantom.start_tell();phantom.update_visual()
	check(phantom.body.modulate.a==1,"Hidden attack telegraph is readable")
	clear_enemies()
	p.weapon="";p.shield=false;p.hp=3;p.invulnerable=0
	check(p.take_hit(Vector2(350,550)) and not p.take_hit(Vector2(350,550)) and p.hp==2,"I-frames prevent same-frame multi-hit damage")
	p.invulnerable=0;p.shield=true
	check(not p.take_hit(Vector2(350,550)) and p.hp==2 and not p.shield,"REVIEW shield consumes one charge without HP loss")
	p.stagger=0;p.invulnerable=0
	p.apply_effect("confused");p.apply_effect("strength_down");p.apply_effect("speed_surge")
	check(p.effects.confused==3 and p.effects.strength_down==5 and p.effects.speed_surge==8,"Mode 2 status durations match design")
	p.effects.clear()
	game.capabilities.review=true
	var stunned=enemy("review_blocker",p.position+Vector2(80,0))
	check(p.activate_review() and stunned.state=="stunned" and not p.activate_review(),"REVIEW burst stuns and cannot bypass cooldown")
	check(p.invulnerable>=.8,"REVIEW burst grants brief invulnerability")
	p.review_cooldown=0;p.review_charge=0
	clear_enemies()
	p.position=Vector2(400,550);p.facing=1
	var c=enemy("hallucinated_api_gremlin",Vector2(475,550))
	var d=enemy("hallucinated_api_gremlin",Vector2(480,610))
	p.equip("review_stamp");swing(p,"review_stamp")
	check(c.hp==1 and d.hp==1 and p.durability==5,"Review Stamp hits a wide arc for one durability charge")
	clear_enemies()
	var hammer=enemy("zero_day_phantom",Vector2(475,550))
	var spare=enemy("zero_day_phantom",Vector2(485,550))
	p.equip("triage_hammer");swing(p,"triage_hammer")
	check(hammer.dead and spare.hp==4 and p.durability==3,"Triage Hammer is single-target")
	clear_enemies()
	spawner=enemy("agent_spawner",Vector2(570,550))
	p.equip("change_stack_baton");swing(p,"change_stack_baton")
	check(spawner.dead and p.durability==4,"Change Stack Baton destroys Spawner at extended reach")
	clear_enemies()
	p.equip("security_scanner");swing(p,"security_scanner")
	check(game.reveal_time==10 and p.durability==7,"Scanner spends one charge and reveals even when it misses")
	var hidden=enemy("security_gap_crawler",Vector2(750,600));hidden.update_visual()
	check(hidden.body.modulate.a==1,"Scan reveals hidden actors")
	clear_enemies()
	var execute=enemy("zero_day_phantom",Vector2(475,550));execute.hp=.5;execute.teleport_cooldown=5
	p.equip("pr_merger");swing(p,"pr_merger")
	check(execute.dead and p.weapon=="" and p.durability==0,"One-use PR Merger executes weakened enemy and breaks")
	game.capabilities.triage=true;game.capabilities.change_stack=true
	clear_enemies()
	spawner=enemy("agent_spawner",Vector2(900,600))
	var close=enemy("zero_day_phantom",Vector2(470,550))
	game._tick_capabilities(.01)
	check(game.triage_target==spawner and spawner.triage_marked,"TRIAGE prioritizes Spawner over nearby enemies")
	p.weapon="";swing(p,"",3)
	check(game.zones.size()>0,"Finisher creates Change Stack zone")
	game.clear_threats()
	close.position=Vector2(600,550);close.hp=4;close.teleport_cooldown=5
	game.create_zone(close.position);game._tick_capabilities(.05)
	var after: float=close.hp
	game._tick_capabilities(.05)
	check(close.hp==after and after<4,"Change Stack deduplicates damage per zone and target")
	game.clear_threats()
	# Environment, pause and source cleanup.
	game.spawn_prop("kiosk",Vector2(450,600),1)
	game.break_prop(game.props.back())
	check(game.pickups.any(func(item): return item.kind=="review_stamp"),"Kiosk drops a mode-specific weapon")
	game.player.height=0;game.player.invulnerable=0;game.player.hp=3
	game.ground_warning(p.position,Vector2(80,40),.5,.3,"code_dump")
	game._tick_threats(.2)
	check(p.hp==3,"Hazard warning is harmless before activation")
	p.height=80;game._tick_threats(.31)
	check(p.hp==3,"Jump clears active ground hazard")
	p.height=0;game._tick_threats(.02)
	check(p.hp==2,"Active warning area deals damage after telegraph")
	game.clear_threats()
	var pause := InputEventAction.new();pause.action="pause";pause.pressed=true
	game.state="combat";game.playing=true
	game._unhandled_input(pause)
	var cooldown: float=p.review_cooldown
	var elapsed: float=game.elapsed
	await physics_frame;await physics_frame
	check(paused and p.review_cooldown==cooldown and game.elapsed==elapsed,"Pause freezes gameplay and cooldowns")
	game.resume()
	# AI SLOP thresholds and field liveness.
	await stage(0);game.enter_room(2);finish_cards();freeze();clear_enemies()
	var slop=game.bosses[0]
	slop.take_hit(999,0,Vector2.ZERO)
	check(slop.phase==2 and slop.hp==18,"Large hit cannot skip SLOP phase two")
	slop.tick(1);slop.tick(2)
	var minion=enemy("slop_sprite",Vector2(game.room_start()+700,550))
	slop.take_hit(999,0,Vector2.ZERO)
	check(slop.phase==3 and slop.hp==9 and slop.shield_active,"SLOP phase three shields while minions remain")
	check(not slop.take_hit(99,0,Vector2.ZERO),"LGTM field blocks damage")
	minion.finish_death();slop.tick(.01)
	check(not slop.shield_active,"Clearing last Slop breaks field")
	slop.take_hit(99,0,Vector2.ZERO);game.check_boss_state()
	var victory_position: Vector2=game.player.position
	check(game.state=="boss_victory" and not game.playing and game.player.body.animation=="victory","Boss defeat freezes combat and starts Hoppy victory")
	game._physics_process(.3)
	check(game.player.body.position.y<0,"Victory animates a celebratory hop")
	game._unhandled_input(pause);var celebration_time: float=game.victory_clock
	game._physics_process(5)
	check(game.victory_clock==celebration_time,"Pause freezes victory animation")
	game.resume();check(game.state=="boss_victory" and not game.playing,"Resume continues victory without restarting combat")
	finish_cards()
	check(game.state=="stage_exit" and game.flow.active() and game.player.position==victory_position,"Claiming REVIEW flows straight into stage_exit without walking yet")
	check(game.capabilities.review and game.boss_rewarded,"SLOP grants REVIEW once")
	game.boss_defeated();check(game.state=="stage_exit","Duplicate boss completion does not replay reward")
	var score_before: int=game.score
	var caps_before: Dictionary=game.capabilities.duplicate()
	var guard := 0
	while game.stage_index==0 and guard<600:
		game._physics_process(1.0/60.0);guard+=1
	check(game.stage_index==1 and game.state=="stage_enter","Automatic stage change reaches stage_enter for stage 2")
	check(game.checkpoint_score==score_before and game.checkpoint_capabilities==caps_before and game.checkpoint_capabilities.review,"Checkpoint snapshots score and capabilities across the automatic change")
	guard=0
	while game.state=="stage_enter" and guard<600:
		game._physics_process(1.0/60.0);guard+=1
	check(game.state=="combat" and game.playing and not game.flow.active(),"stage_enter completes into combat")
	await stage(0);game.enter_room(2);finish_cards();freeze();clear_enemies()
	slop=game.bosses[0];slop.take_hit(99,0,Vector2.ZERO);slop.tick(1);slop.tick(2);slop.take_hit(99,0,Vector2.ZERO)
	check(not slop.shield_active,"Zero-minion phase three cannot softlock")
	# Army merge requires both independently tracked opponents to die.
	await stage(1);game.enter_room(2);finish_cards();freeze()
	check(game.bosses.size()==3 and game.army_health()==24,"Army starts with three damageable clones")
	game.bosses[0].take_hit(8,0,Vector2.ZERO)
	game.bosses[1].take_hit(4,0,Vector2.ZERO)
	game.check_boss_state();finish_cards();freeze()
	check(game.army_merged and game.bosses.size()==2,"50% total HP merges commander and introduces PR")
	game.flow.tick(Catalog.FLOW.boss_dip,game.player)
	check(game.music.stream is AudioStreamWAV and game.music.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"Army WAV loops through the dual encounter")
	game.bosses[0].take_hit(999,0,Vector2.ZERO);game.check_boss_state()
	check(not game.boss_rewarded and game.alive_bosses()==1,"One dual boss death cannot unlock exit")
	game.bosses[1].take_hit(999,0,Vector2.ZERO);game.check_boss_state();finish_cards()
	check(game.capabilities.triage and game.capabilities.change_stack and game.state=="stage_exit","Both deaths grant rewards and flow into stage_exit")
	# Hacker phases, two vectors, damage-triggered spawns and final victory.
	await stage(2);game.enter_room(2);finish_cards();freeze();clear_enemies()
	var hacker=game.bosses[0]
	hacker.take_hit(99,0,Vector2.ZERO)
	check(hacker.phase==2 and game.count_kind("zero_day_phantom")==1,"Injection phase introduces Phantom")
	game.player.hp=3;game.player.shield=false;game.player.invulnerable=0
	game.player.take_hit(game.player.position-Vector2(50,0))
	check(game.count_kind("vulnerability_injector")==1,"Successful damage triggers bounded Injector surge")
	game.player.take_hit(game.player.position)
	check(game.count_kind("vulnerability_injector")==1,"Rejected duplicate hit does not spawn another Injector")
	hacker.tick(1);hacker.tick(2);hacker.take_hit(99,0,Vector2.ZERO);hacker.update_visual()
	check(hacker.phase==3 and hacker.vector.visible and hacker.vector_body.modulate.a<.1,"Machine Mode has a separate hidden second vector")
	game.reveal_time=10;hacker.update_visual()
	check(hacker.vector_body.modulate.a==1,"Scanner reveals Hacker second vector")
	hacker.tick(1);hacker.tick(2);hacker.choose_attack();hacker.release_attack()
	var vector_before: Vector2=hacker.vector.position
	hacker.tick(.05)
	check(hacker.vector.position!=vector_before,"Second attack vector moves independently")
	hacker.take_hit(999,0,Vector2.ZERO);game.check_boss_state();finish_cards()
	check(game.state=="won" and game.capabilities.security and game.completion_count==1,"Hacker defeat grants SECURITY and completes once")
	game.boss_defeated();game.win();check(game.completion_count==1,"Victory callbacks are idempotent")
	# M1: the results and game-over overlays ignore the press that lands right after an auto-advance.
	auto_win()
	game._physics_process(1.0/60.0)
	game.victory._input(advance_key());game.victory._input(accept_event())
	check(game.state=="won" and not game.leaving and game.victory.visible and not game.victory.landed,"Dedicated advance / ui_accept one frame after the cards cannot leave or skip the results")
	check(game.victory.action.disabled,"The results button is disabled before the arming time")
	game.resume()
	check(game.state=="won" and not game.playing and game.victory.visible,"resume() outside paused cannot revive won")
	game.state="combat";game.overlay.hide();game.playing=true
	game.game_over()
	game._physics_process(1.0/60.0)
	game._input(advance_key());game._input(accept_event())
	check(game.state=="game_over" and game.overlay.visible,"Advance / ui_accept right after game over cannot retry")
	game.resume()
	check(game.state=="game_over" and not game.playing and game.overlay.visible,"resume() outside paused cannot revive game_over")
	game._physics_process(.6)
	game._input(advance_key())
	check(game.state=="stage_enter" and not game.overlay.visible,"Dedicated advance is accepted on game over after ~0.5 s and retry enters stage_enter")
	steps(1200,func(): return game.state=="combat")
	check(game.state=="combat" and game.playing and not game.flow.active() and not game.overlay.visible,"Retry's stage_enter completes into combat")
	# m2: shake decays while not playing.
	game.shake=8;game.playing=false;game.state="game_over"
	game._physics_process(1.0)
	check(game.shake==0,"Shake decays to zero outside combat")
	game.state="combat";game.playing=true
	# Pause / resume freezes stage_exit and stage_enter, then both complete normally.
	await stage(0)
	game.exit_stage()
	steps(240,func(): return game.flow.phase=="fade_out" and game.flow.clock>.1)
	check(game.state=="stage_exit" and game.flow.phase=="fade_out" and game.flow.veil.color.a>0,"Reached mid fade_out in stage_exit")
	var frozen := snapshot()
	press_pause()
	check(paused and game.state=="paused","Pause opens during stage_exit")
	for i in 120: game._physics_process(1.0/60.0)
	check(snapshot()==frozen,"Pause freezes flow clock, veil, music volume and player during stage_exit")
	press_pause()
	check(not paused and game.state=="stage_exit" and not game.overlay.visible,"Resume returns to stage_exit")
	steps(1200,func(): return game.state=="stage_enter")
	check(game.stage_index==1 and game.state=="stage_enter","stage_exit completes into stage_enter after resume")
	steps(20,func(): return false)
	frozen=snapshot()
	press_pause()
	for i in 120: game._physics_process(1.0/60.0)
	check(paused and snapshot()==frozen,"Pause freezes flow clock, veil, music volume and player during stage_enter")
	press_pause()
	check(game.state=="stage_enter" and not game.overlay.visible,"Resume returns to stage_enter")
	steps(1200,func(): return game.state=="combat")
	check(game.state=="combat" and game.playing and not game.flow.active(),"stage_enter completes into combat after resume")
	# M1: stage_enter clears the pickup line without hiding the label, so combat can show it again.
	var weapon_drop: Dictionary={}
	for item in game.pickups:
		if Catalog.WEAPONS.has(item.kind): weapon_drop=item
	check(not weapon_drop.is_empty(),"Stage change leaves a weapon on the floor")
	if not weapon_drop.is_empty():
		game.hazard_clock=30
		game.ally_clock=30
		game.player.set_physics_process(false)
		game.player.controlled=false
		game.player.height=0
		game.player.position=weapon_drop.node.position+Vector2(20,0)
		game._physics_process(1.0/60.0)
		# The prompt names the pickup key and, with a controller connected, its button.
		var pickup: String = preload("res://app/controller_prompts.gd").either("E", &"brawl_pickup", true)+" · PICK UP"
		check(game.prompt.is_visible_in_tree() and game.prompt.text.begins_with(pickup),"Pickup prompt shows within 85 px after a stage change (got '%s')" % game.prompt.text)
	var score_kept: int=game.score
	game.boss_defeated()
	check(game.prompt.visible,"boss_defeated clears the pickup line without hiding it (text '%s')" % game.prompt.text)
	game.exit_stage()
	check(game.prompt.visible,"exit_stage clears the pickup line without hiding it (text '%s')" % game.prompt.text)
	game.flow.cancel()
	game.score=score_kept
	game.boss_rewarded=false
	await stage(2)
	# Retry restores stage-entry score/capabilities and clears transient state.
	game.checkpoint_score=123;game.checkpoint_capabilities={"review":true,"triage":true,"change_stack":true,"security":false}
	game.retry_stage();await process_frame;freeze()
	check(game.state=="stage_enter" and game.flow.active(),"Retry enters stage_enter with the flow running")
	check(game.stage_index==2 and game.room==0 and game.player.hp==3 and game.score==123,"Retry starts current stage with fresh HP and checkpoint score")
	check(not game.capabilities.security and game.capabilities.review and game.player.shield,"Retry restores earned capabilities and one shield charge")
	check(game.zones.is_empty() and game.bullets.is_empty() and game.bosses.is_empty() and game.reveal_time==0,"Retry clears prior encounter threats and reveals")
	steps(1200,func(): return game.state=="combat")
	check(game.state=="combat" and game.playing and not game.flow.active(),"Retry's stage_enter completes into combat")
	# All six mapped tracks duplicate safely, including WAV loops.
	for track in Catalog.MUSIC+Catalog.BOSS_MUSIC:
		var looped := Catalog.looped(track)
		check(looped!=track and looped.get_length()>0,"Mapped music duplicates and loads: "+track.resource_path.get_file())
		if looped is AudioStreamWAV: check(looped.loop_end>0 and track.loop_mode==AudioStreamWAV.LOOP_DISABLED,"WAV loop does not mutate shared import")
	# Code-made bindings must answer every pad, not only device 0 (booths, reconnects).
	for binding in [["heroes_popup_advance",4],["review_burst",9]]:
		for device in [0,1,3]:
			var pad := InputEventJoypadButton.new()
			pad.device=device;pad.button_index=binding[1];pad.pressed=true
			check(InputMap.event_is_action(pad,binding[0]),"%s answers pad %d" % [binding[0],device])
	# Terminal paths last: they route away from the mode.
	await stage(0)
	game.exit_stage()
	steps(240,func(): return game.flow.phase=="fade_out" and game.flow.clock>.1)
	press_pause()
	var back: Button = null
	for child in game.panel.get_children():
		if child is Button and child.text=="Return to Beat'em Up menu": back=child
	check(back!=null and paused and game.state=="paused","Pause overlay offers Return during stage_exit")
	if back==null:
		quit(1)
		return
	back.pressed.emit()
	game.shake=8
	var stage_before: int=game.stage_index
	var held := true
	var frozen_pos: Vector2=game.player.position
	for i in 180:
		game._physics_process(1.0/60.0)
		if game.stage_index!=stage_before or game.flow.active() or game.player.position!=frozen_pos or game.music.playing: held=false
	check(not paused and game.leaving and game.state=="leaving" and held,"Leave through the pause overlay cancels the flow and changes no stage")
	check(game.shake==8,"A leaving owner returns early from _physics_process (shake, which decays unconditionally otherwise, stays frozen)")
	var disabled := true
	for child in game.panel.get_children():
		if child is BaseButton and not child.disabled: disabled=false
	check(disabled and back.disabled,"Overlay buttons are disabled while leaving")
	await reload_game()
	auto_win()
	game._physics_process(1.0/60.0)
	game.victory._input(advance_key())
	check(game.state=="won" and not game.leaving,"Results survive a press on the next frame")
	game._physics_process(.6)
	game.victory._input(advance_key())
	check(game.state=="won" and not game.leaving and game.victory.landed,"Dedicated advance after ~0.5 s lands the count first")
	game.victory._input(accept_event())
	check(game.state=="won" and not game.leaving,"ui_accept (jump on Space / A) does not press Return on the landed results")
	game.victory._input(advance_key())
	check(game.leaving,"Dedicated advance presses Return once the count has landed")
	game.queue_free();await process_frame
	await root.get_node("AudioService").settle()
	print("Heroes vs. Villains logic failures: ",failures)
	quit(0 if failures==0 else 1)
