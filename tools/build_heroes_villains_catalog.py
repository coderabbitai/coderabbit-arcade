"""Build source-grounded asset links and proposed moveset data, not runtime AI."""
import json
from build_heroes_villains_pack import PACK, ROSTERS


def art(resource, animation):
    return {'resource': resource, 'animation': animation}


enemy_specs = [
    (1, 'Swarm rush; despawn with owning spawner.', 'rush', None),
    (2, 'Ranged projectile applies Confused for 3 seconds.', 'throw', 'capabilities_fx/api_projectile'),
    (2, 'First hit replaces original with two 1-HP copies; split pose is the attack key pose.', 'split', None),
    (3, 'First hit breaks armor; periodic self-damage; attack pose depicts armor failure.', 'self_damage', None),
    (4, 'Stationary; spawn Slop Sprites until destroyed; high TRIAGE priority.', 'spawn', 'capabilities_fx/spawn_burst'),
    (3, 'PR shield blocks frontal hits; flank or combo finisher breaks it.', 'shield_bash', None),
    (2, 'Plants in lane; immune to knockback.', 'block_lane', None),
    (1, 'Fast swarm in groups of 3–5.', 'rush', None),
    (2, 'Very fast dash; minimal telegraph.', 'dash', None),
    (2, 'Hidden flank ambusher; SECURITY or scanner reveals.', 'pounce', None),
    (2, 'Ranged Strength Down for 5 seconds; additional spawns on player damage.', 'inject', 'core_kit/injector_projectile'),
    (4, 'Hidden; teleports to dodge below 50% HP.', 'teleport_slash', None),
]
enemies = {}
for i, (name, spec) in enumerate(zip(sum(ROSTERS.values(), []), enemy_specs)):
    hp, behavior, action, effect = spec
    stage = i // 4 + 1
    enemies[name] = dict(hp=hp, stages=[1, 2] if name == 'slop_sprite' else [stage], behavior=behavior,
                         art=art(name, 'idle'), moves=[dict(id=action, warning=art(name, 'attack_warning'),
                         active=art(name, 'attack'), recovery=art(name, 'idle'),
                         preview=art(name, 'attack_action'), effect=art(*effect.split('/')) if effect else None)],
                         defeat=art(name, 'defeat'))


def move(resource, id, warning, active, recovery, note, effect=None):
    return dict(id=id, warning=art(resource, warning), active=art(resource, active),
                recovery=art(resource, recovery), design=note,
                effect=art(*effect.split('/')) if effect else None)


bosses = {
    'ai_slop': dict(stage=1, thresholds=[.60, .30], unlocks=['review'],
        phases=[dict(hp_range='100–60%', behavior='Spawn Slop waves, melee, spread Hallucination Burst.'),
                dict(hp_range='60–30%', behavior='Stop spawning; aggressive rush and tracking API barrage.'),
                dict(hp_range='30–0%', behavior='LGTM force field; clear remaining Slop Sprites to break invulnerability.')],
        moves=[move('ai_slop', 'melee', 'melee_warning', 'melee', 'hurt', 'Heavy melee.'),
               move('ai_slop', 'hallucination_burst', 'burst_warning', 'burst', 'idle', 'Spread of Confused projectiles.', 'capabilities_fx/api_projectile'),
               move('ai_slop', 'rush', 'weakened', 'rush', 'hurt', 'Aggressive direct rush; warning pose reused.'),
               move('ai_slop', 'tracking_barrage', 'burst_warning', 'barrage', 'idle', 'Rapid tracking projectiles.', 'capabilities_fx/tracking_projectile'),
               move('ai_slop', 'force_field', 'shield_raise', 'shield', 'shield_break', 'Clear minions; cracked and break key poses included.')],
        defeat=art('ai_slop', 'defeat')),
    'army_and_pr': dict(stage=2, thresholds=[.50], unlocks=['triage', 'change_stack'],
        actors=['agent_army', 'ten_thousand_line_pr'],
        phases=[dict(hp_range='100–50%', behavior='Synchronized clone formation; each defeated clone reduces survivors attack speed.'),
                dict(hp_range='50% transition', behavior='Clones merge; PR monolith drops in. Keep merged commander active.'),
                dict(hp_range='simultaneous', behavior='Commander and PR remain separate active opponents. Both must die before reward.')],
        moves=[move('agent_army', 'formation', 'formation_warning', 'formation_attack', 'formation_weakened', 'Synchronized squad strike.'),
               move('agent_army', 'merge', 'merge_warning', 'merge', 'fused_idle', 'Transition at 50%; presentation must not remove surviving commander.'),
               move('agent_army', 'fused_strike', 'fused_idle', 'fused_attack', 'recover', 'Merged commander keeps attacking during PR fight.'),
               move('ten_thousand_line_pr', 'stack_slam', 'slam_warning', 'slam', 'recover', 'Falling stacks; AoE impact.', 'review_kit/falling_stack'),
               move('ten_thousand_line_pr', 'reviewer_nightmare', 'nightmare_warning', 'nightmare', 'open_guard', 'Ground shockwave.', 'review_kit/nightmare_wave')],
        defeat=[art('agent_army', 'defeat_action'), art('ten_thousand_line_pr', 'defeat_action')]),
    'ai_augmented_hacker': dict(stage=3, thresholds=[.60, .30], unlocks=['security'],
        phases=[dict(hp_range='100–60%', behavior='Machine-speed dash; Gap Crawlers flank.'),
                dict(hp_range='60–30%', behavior='Injection Mode: hits on Hoppy spawn Injector; hidden Phantom appears.'),
                dict(hp_range='30–0%', behavior='Machine Mode: two simultaneous attack vectors; second hidden until revealed.')],
        moves=[move('ai_augmented_hacker', 'dash', 'dash_warning', 'dash', 'recover', 'Minimal warning window.'),
               move('ai_augmented_hacker', 'injection', 'injection_warning', 'injection', 'recover', 'Spawn Injector on successful hit.', 'core_kit/injector_projectile'),
               move('ai_augmented_hacker', 'summon', 'injection_warning', 'summon', 'idle', 'Phase support spawn.', 'core_kit/surface_portal'),
               move('ai_augmented_hacker', 'dual_vector', 'machine_mode', 'vector_attack', 'teleport_in', 'Use separate actors/hitboxes; dual_vectors is presentation only. Second vector uses vector_revealed when visible.'),
               move('ai_augmented_hacker', 'teleport', 'teleport_out', 'teleport_in', 'idle', 'Glitch transition presentation.')],
        defeat=art('ai_augmented_hacker', 'defeat_action')),
}
weapon_specs = [
    ('review_stamp', 6, 'Wide frontal AoE; brief stagger.'),
    ('triage_hammer', 4, 'Massive single-target damage; mark target for combo AoE follow-ups.'),
    ('change_stack_baton', 5, 'Extended reach; instantly destroys Agent Spawner on hit.'),
    ('security_scanner', 8, 'Reveal hidden enemies for 10 seconds; bonus damage vs. Hackers.'),
    ('pr_merger', 1, 'Execute enemy below 25% HP; brief screen-wide stagger on bosses.'),
]
stages = {}
stage_specs = [
    ('generation_floor', 'The Generation Floor', 'generation_kit', ['ai_slop'],
     [('terminal', 'weapons or health'), ('kiosk', 'Review Stamp or random buff')],
     [('code_dump', 'dump_warning', 'Falling code area denial'), ('api_fog', 'api_fog', 'Briefly invert controls')]),
    ('review_gauntlet', 'The Review Gauntlet', 'review_kit', ['agent_army', 'ten_thousand_line_pr'],
     [('monolith', 'score plus screen-clear shockwave'), ('assembly', 'stop lane spawns; Speed Surge')],
     [('falling_stack', 'slam_warning', 'AoE impact'), ('overflow_portal', 'overflow_beacon', 'Periodic density spike; Overwhelmed')]),
    ('agentic_core', 'The Agentic Core', 'core_kit', ['ai_augmented_hacker'],
     [('rack', 'high-tier weapon'), ('node', 'score; remove one active hazard')],
     [('scan_beam', 'scan_warning', 'Periodic screen-wide scan sweep'), ('surface_portal', 'scan_emitter', 'Player damage spawns additional Injector')]),
]
for i, (id, title, kit, villains, breakables, hazards) in enumerate(stage_specs):
    stages[id] = dict(title=title, stage=i+1, palette=['white/orange/blue', 'amber/dark orange', 'black/red/neon green'][i],
        preview_scene=f'presentation/{id}.tscn', background=f'heroes_villains/{id}.png',
        enemies=ROSTERS[list(ROSTERS)[i]], bosses=villains,
        destructibles=[dict(id=n, intact=art(kit,n+'_intact'), damaged=art(kit,n+'_cracked'), destroyed=art(kit,n+'_destroyed'), drops=drop) for n,drop in breakables],
        hazards=[dict(id=n, warning=art(kit,w), active=art(kit,n), effect=desc) for n,w,desc in hazards])

catalog = dict(schema_version=1, status='Asset integration definitions, NOT implemented gameplay or final balance.',
    sources=dict(gdd='GDD (October 2, 2026 revision; internal reference)',
                 read_date='2026-10-06', baseline_version='0.1; predates Mode 2'),
    hoppy=dict(art=art('hoppy','idle'), style='New armored 2D variant requested by user; separate from shared base.',
               combo=[art('hoppy','jab_action'),art('hoppy','swing_action'),art('hoppy','kick_action')],
               missing_polish=['Dedicated up/down walk poses', 'Full in-between animation', 'Individual weapon-held attack animations']),
    stages=stages, enemies=enemies, bosses=bosses,
    weapons={n:dict(durability=d,effect=e,art=art('items_allies',n)) for n,d,e in weapon_specs},
    capabilities={n:dict(art=art('capabilities_fx',n),card=f'presentation/unlock_{n}.tscn', effect=e) for n,e in [
        ('review','Free-hit block plus held activation invincibility burst and nearby stun; recharge unresolved.'),
        ('triage','Highest-threat marker; +1 damage per buff table.'),
        ('change_stack','Combo finisher creates temporary ground AoE at knockback point; proposed 2 seconds.'),
        ('security','Reveal hidden enemies; final victory unlock.')]},
    statuses={n:dict(art=art('capabilities_fx',icon),duration_seconds=duration,effect=effect) for n,icon,duration,effect in [
        ('review_shield','review',None,'One blocked hit; recharge unresolved'),('triage_focus','triage',None,'Highest threat marked; +1 damage'),
        ('speed_surge','speed_surge',8,'Movement boost'),('confused','confused',3,'Invert controls'),
        ('strength_down','strength_down',5,'Combo damage -1'),('overwhelmed','overwhelmed',None,'Slow until surge ends or spawner destroyed')]},
    allies={n:dict(art=art('items_allies',n),action=art('items_allies',pose),stages=st,effect=e) for n,pose,st,e in [
        ('lead_engineer','lead_engineer_gift',[1,2,3],'Restore 1 HP; says ship it'),
        ('security_analyst','security_analyst_gift',[3],'Reveal one hidden enemy; drop Security Scanner'),
        ('devops_defender','devops_defender_strike',[2],'Destroy Agent Spawner; drop Speed Surge')]},
    pickups={n:art('items_allies',n) for n in ['health_capsule','score_coin','speed_surge','review_shield','random_buff']},
    open_decisions=[
        'REVIEW: per-life charge, once-per-stage refresh and timed recharge all appear in GDD. Do not silently pick one.',
        'SECURITY unlock follows final boss; scanner/analyst can offer earlier reveal. Hidden damaging enemies need fair telegraphs.',
        'AI SLOP shield must handle zero remaining minions without an invulnerability softlock.',
        'Exact boss HP, attack timings, damage, hitboxes and phase-transition damage carryover are unspecified.',
        'PR Merger execute versus boss exception and durability per AoE swing versus per target require tuning.',
        'Main Menu still specifies seven Code City-inclusive backgrounds. New previews are supplied without changing hub routing.',
        'GDD invisible-enemy collision-disable suggestion conflicts with damaging ambushes; separate visibility from authoritative hitboxes.'
    ])
(PACK/'content_catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
print('Catalog: 12 enemies, 3 encounters / 4 villains, 5 weapons, 4 capabilities, 3 stages')
