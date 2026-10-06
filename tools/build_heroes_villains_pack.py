"""Package generated art without repainting it. Run from any working directory.

Requires Pillow and NumPy. Sources and exact prompts stay in the pack.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'hoppys-adventure-arcade/Assets/heroes-vs-villains-assets-only'
OUT = PACK / 'heroes_villains'
GEN = json.loads((PACK / 'generation.json').read_text())
BASE = 'res://Assets/heroes-vs-villains-assets-only/'

NAMES = {
    'hoppy': 'idle run_a run_b jump jab_warning jab swing_warning swing kick_warning kick hurt defeat pickup block victory scanner',
    'ai_slop': 'idle summon melee_warning melee burst_warning burst rush barrage shield_raise shield shield_crack shield_break hurt weakened melt shell',
    'agent_army': 'idle jab_warning jab hurt formation formation_warning formation_attack formation_weakened merge_warning merge fused_idle fused_attack recover damaged kneel defeat',
    'ten_thousand_line_pr': 'idle walk_a walk_b drop slam_warning slam recover hurt nightmare_warning nightmare open_guard cracking angry topple defeat shell',
    'ai_augmented_hacker': 'idle dash_warning dash recover injection_warning injection summon hurt machine_mode dual_vectors vector_attack vector_revealed teleport_out teleport_in defeat shell',
    'generation_kit': 'terminal_intact terminal_cracked terminal_destroyed loot_crate kiosk_intact kiosk_cracked kiosk_destroyed barrier api_banner expo_truss light_pillar display_cabinet code_dump api_fog dump_warning code_debris',
    'review_kit': 'monolith_intact monolith_cracked monolith_destroyed falling_stack assembly_intact assembly_cracked assembly_destroyed conveyor gantry clone_pods overflow_beacon warning_lamp nightmare_wave overflow_portal slam_warning paper_debris',
    'core_kit': 'rack_intact rack_cracked rack_destroyed data_cache node_intact node_cracked node_destroyed cables scan_emitter scan_beam scan_warning surface_portal injector_projectile reveal_ring vent foreground_rail',
    'items_allies': 'review_stamp triage_hammer change_stack_baton security_scanner pr_merger health_capsule score_coin speed_surge lead_engineer lead_engineer_gift security_analyst security_analyst_gift devops_defender devops_defender_strike review_shield random_buff',
    'capabilities_fx': 'review triage change_stack security speed_surge confused strength_down overwhelmed review_burst change_stack_zone triage_marker scanner_cone api_projectile tracking_projectile spawn_burst unlock_sparkle',
}
ROSTERS = {
    'generation_enemies': ['slop_sprite', 'hallucinated_api_gremlin', 'duplicate_logic_clone', 'broken_test_bot'],
    'review_enemies': ['agent_spawner', 'change_stack_soldier', 'review_blocker', 'merge_request_mob'],
    'core_enemies': ['ai_hacker_drone', 'security_gap_crawler', 'vulnerability_injector', 'zero_day_phantom'],
}
BACKGROUNDS = ['generation_floor', 'review_gauntlet', 'agentic_core']
BOSSES = ['ai_slop', 'agent_army', 'ten_thousand_line_pr', 'ai_augmented_hacker']

# Reviewed extraction windows where effects cross a nominal grid gutter.
# These select complete poses from the untouched master, not painted repairs.
SOURCE_WINDOWS = {
    ('ai_slop', 0): (0, 0, 350, 285),
    ('ai_slop', 4): (0, 285, 355, 540),
    ('core_enemies', 9): (390, 450, 695, 710),
    ('core_enemies', 10): (700, 450, 1152, 710),
    ('core_enemies', 12): (0, 695, 384, 1024),
    ('core_enemies', 13): (390, 700, 768, 1024),
    ('core_enemies', 14): (768, 700, 1152, 1024),
    ('core_enemies', 15): (1152, 695, 1536, 1024),
    ('generation_kit', 8): (0, 515, 380, 751),
    ('generation_kit', 10): (890, 526, 1080, 765),
    ('core_kit', 9): (390, 620, 800, 795),
    ('core_kit', 10): (800, 620, 1218, 790),
    ('items_allies', 14): (875, 750, 1130, 1024),
}


def seam(alpha, center, radius):
    """Find a clear curved gutter; fail instead of cutting through opaque art."""
    lo = max(1, round(center - radius))
    hi = min(alpha.shape[1] - 1, round(center + radius))
    core = alpha > 32
    blocked = core.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            blocked |= np.roll(np.roll(core, dy, axis=0), dx, axis=1)
    cost = blocked[:, lo:hi].astype(float) * 1e7
    cost += np.abs(np.arange(lo, hi) - center)[None, :] * .01
    prev = cost[0].copy()
    back = np.zeros(cost.shape, dtype=np.int16)
    for y in range(1, len(cost)):
        candidates = np.stack([
            np.r_[np.full(max(0, d), np.inf),
                  prev[max(0, -d):len(prev) - max(0, d)],
                  np.full(max(0, -d), np.inf)] for d in (-2, -1, 0, 1, 2)
        ])
        best = candidates.argmin(axis=0)
        back[y] = np.arange(len(prev)) - (best - 2)
        prev = cost[y] + candidates[best, np.arange(len(prev))]
    path = np.zeros(len(cost), dtype=int)
    path[-1] = prev.argmin()
    for y in range(len(cost) - 1, 0, -1):
        path[y - 1] = back[y, path[y]]
    path += lo
    assert not blocked[np.arange(len(path)), path].any(), f'No gutter at {center}'
    return path


def slices(im, name):
    a = np.array(im)[:, :, 3]
    h, w = a.shape
    yy, xx = np.indices((h, w))
    horizontal = [np.zeros(w, dtype=int)] + [
        seam(a.T, i * h / 4, h / 4 * .40) for i in range(1, 4)
    ] + [np.full(w, h)]
    result = []
    for row in range(4):
        band = (yy >= horizontal[row][None, :]) & (yy < horizontal[row + 1][None, :])
        ra = np.where(band, a, 0)
        vertical = [np.zeros(h, dtype=int)] + [
            seam(ra, i * w / 4, w / 4 * .46) for i in range(1, 4)
        ] + [np.full(h, w)]
        for col in range(4):
            mask = band & (xx >= vertical[col][:, None]) & (xx < vertical[col + 1][:, None])
            if (name, row * 4 + col) in SOURCE_WINDOWS:
                left, top, right, bottom = SOURCE_WINDOWS[(name, row * 4 + col)]
                mask = (xx >= left) & (xx < right) & (yy >= top) & (yy < bottom)
            alpha = np.where(mask, a, 0).astype('uint8')
            box = Image.fromarray(alpha).point(lambda v: 255 if v > 32 else 0).getbbox()
            assert box, (row, col)
            rect = (max(0, box[0]-2), max(0, box[1]-2), min(w, box[2]+2), min(h, box[3]+2))
            frame = im.copy()
            frame.putalpha(Image.fromarray(alpha))
            result.append((frame.crop(rect), rect))
    return result


def clip(name, frames, fps=1, loop=False):
    return dict(name=name, frames=frames, fps=fps, loop=loop)


def pack(name, cuts, names, source, actor=False, boss=False):
    cell = 256 if boss else 128 if actor else 192
    pivot = [cell // 2, round(cell * .9)] if actor else [cell // 2, cell // 2]
    # One scale for an actor's entire sheet preserves relative pose size.
    common = min((cell - 12) / max(c.width for c, _ in cuts),
                 cell * .78 / max(c.height for c, _ in cuts))
    atlas = Image.new('RGBA', (cell * 4, cell * ((len(cuts) + 3) // 4)))
    frames = []
    for i, (cut, rect) in enumerate(cuts):
        scale = common if actor else min((cell - 16) / cut.width, (cell - 16) / cut.height)
        cut = cut.resize((max(1, round(cut.width * scale)), max(1, round(cut.height * scale))), Image.Resampling.NEAREST)
        x = (cell - cut.width) // 2
        y = pivot[1] - cut.height if actor else (cell - cut.height) // 2
        frame = Image.new('RGBA', (cell, cell))
        frame.alpha_composite(cut, (x, y))
        dest = PACK / 'frames' / name
        dest.mkdir(parents=True, exist_ok=True)
        frame.save(dest / f'{names[i]}.png')
        atlas.alpha_composite(frame, ((i % 4) * cell, (i // 4) * cell))
        frames.append(dict(name=names[i], source_rect_ltrb=list(rect), scale=scale))
    clips = [clip(n, [i], loop=n in ('idle', 'formation', 'fused_idle', 'shield', 'machine_mode') or n.endswith('_intact')) for i, n in enumerate(names)]
    cycles = {
        'hoppy': [('run', [1, 2], 8, True), ('jab_action', [4, 5, 0], 10, False), ('swing_action', [6, 7, 0], 8, False), ('kick_action', [8, 9, 0], 8, False)],
        'ai_slop': [('melee_action', [2, 3, 12], 6, False), ('burst_action', [4, 5, 0], 6, False), ('shield_action', [8, 9], 4, False), ('shield_break_action', [10, 11, 12], 7, False), ('defeat', [12, 13, 14, 15], 4, False)],
        'agent_army': [('formation_action', [5, 6, 7], 6, False), ('merge_action', [8, 9, 10], 4, False), ('fused_action', [10, 11, 12], 6, False), ('defeat_action', [13, 14, 15], 4, False)],
        'ten_thousand_line_pr': [('walk', [1, 2], 4, True), ('slam_action', [4, 5, 6], 5, False), ('nightmare_action', [8, 9, 10], 5, False), ('defeat_action', [11, 13, 14, 15], 4, False)],
        'ai_augmented_hacker': [('dash_action', [1, 2, 3], 12, False), ('injection_action', [4, 5, 3], 8, False), ('teleport', [12, 13], 8, False), ('defeat_action', [7, 14, 15], 4, False)],
    }
    for n, ids, fps, loop in cycles.get(name, []):
        clips.append(clip(n, ids, fps, loop))
    if len(names) == 4:
        clips.append(clip('attack_action', [1, 2, 0], 6))
    if name.endswith('_kit'):
        clips += [clip('primary_break', [0, 1, 2], 6), clip('secondary_break', [4, 5, 6], 6)]
    atlas.save(OUT / f'{name}.png')
    lines = [f'[gd_resource type="SpriteFrames" load_steps={len(cuts)+2} format=3]', f'[ext_resource type="Texture2D" path="{name}.png" id="1"]']
    for i in range(len(cuts)):
        lines += [f'[sub_resource type="AtlasTexture" id="F{i}"]', 'atlas = ExtResource("1")', f'region = Rect2({i%4*cell}, {i//4*cell}, {cell}, {cell})']
    animations = []
    for c in clips:
        refs = ', '.join('{"duration": 1.0, "texture": SubResource("F%d")}' % i for i in c['frames'])
        animations.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}' % (refs, str(c['loop']).lower(), c['name'], float(c['fps'])))
    lines += ['[resource]', 'animations = [\n' + ',\n'.join(animations) + '\n]']
    (OUT / f'{name}.tres').write_text('\n'.join(lines) + '\n')
    return dict(file=f'{name}.png', resource=f'{name}.tres', cell=[cell, cell], pivot=pivot,
                facing='right' if name == 'hoppy' else 'mixed front/left' if boss else 'left/three-quarter' if actor else 'fixed',
                source=source, frames=frames, clips=clips, animation_quality='key poses; no interpolated in-betweens')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = dict(version=1, mode='heroes_vs_villains', engine='4.7.1', atlases={}, backgrounds={})
    for name, spec in GEN['specs'].items():
        im = Image.open(PACK / spec['source']).convert('RGBA')
        if name in BACKGROUNDS:
            im.resize((1280, 720), Image.Resampling.NEAREST).save(OUT / f'{name}.png')
            manifest['backgrounds'][name] = dict(file=f'{name}.png', size=[1280, 720], seamless=False)
            continue
        print('Slicing', name, flush=True)
        cuts = slices(im, name)
        if name in ROSTERS:
            for i, enemy in enumerate(ROSTERS[name]):
                manifest['atlases'][enemy] = pack(enemy, cuts[i*4:i*4+4], ['idle', 'attack_warning', 'attack', 'defeat'], spec['source'], actor=True)
        else:
            manifest['atlases'][name] = pack(name, cuts, NAMES[name].split(), spec['source'], actor=name in BOSSES + ['hoppy'], boss=name in BOSSES)
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (PACK / 'PROMPTS.md').write_text('# Heroes vs. Villains generation prompts\n\nBuilt-in image_gen, October 6, 2026. Sources preserve alpha. Packing only extracts, registers and scales.\n\n' + '\n\n'.join('## ' + n + '\n\n' + s['prompt'] for n, s in GEN['specs'].items()) + '\n')
    template = (ROOT / 'tools/heroes_villains_gallery.html').read_text()
    (PACK / 'preview.html').write_text(template.replace('MANIFEST_DATA', json.dumps(manifest)))
    print('Packed', sum(len(a['frames']) for a in manifest['atlases'].values()), 'frames;', len(manifest['atlases']), 'SpriteFrames resources')


if __name__ == '__main__':
    main()
