"""Mechanically slice and package generated Code City artwork; does not paint art."""
from pathlib import Path
import json, shutil
import numpy as np
from PIL import Image, ImageDraw

# Reviewed source-coordinate gutters exclude disconnected pixels belonging to
# neighboring poses. These only constrain extraction; masters are untouched.
SOURCE_BOUNDS = {
    ('conflict_spawner', 2): (0, 0, 1090, 1024),
    ('merge_chaos', 2): (0, 0, 1152, 1024),
    ('merge_chaos', 7): (1220, 0, 1536, 1024),
    ('security_enemies', 18): (0, 1100, 1024, 1536),
    ('security_enemies', 15): (0, 815, 1024, 1536),
    ('hq_enemies', 18): (0, 1065, 1024, 1536),
    ('hq_kit', 10): (0, 565, 1536, 1024),
}

def seam(alpha, center, radius):
    """Find a transparent, possibly curved gutter without cutting solid art."""
    # Axis 0 follows the seam; axis 1 is the allowed cross-section.
    lo=max(1,round(center-radius)); hi=min(alpha.shape[1]-1,round(center+radius))
    core=alpha>32
    blocked=core.copy()
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            blocked |= np.roll(np.roll(core,dy,axis=0),dx,axis=1)
    cost=blocked[:,lo:hi].astype(float)*1e7 + np.abs(np.arange(lo,hi)-center)[None,:]*.01
    prev=cost[0].copy(); back=np.zeros(cost.shape,dtype=np.int16)
    for y in range(1,len(cost)):
        candidates=np.stack([np.r_[np.full(max(0,d),np.inf),prev[max(0,-d):len(prev)-max(0,d)],np.full(max(0,-d),np.inf)] for d in (-2,-1,0,1,2)])
        best=candidates.argmin(axis=0)
        back[y]=np.arange(len(prev))-(best-2)
        prev=cost[y]+candidates[best,np.arange(len(prev))]
    path=np.zeros(len(cost),dtype=int);path[-1]=prev.argmin()
    for y in range(len(cost)-1,0,-1): path[y-1]=back[y,path[y]]
    path+=lo
    assert not blocked[np.arange(len(path)),path].any(), f'No transparent gutter: center={center}, dimensions={alpha.shape}'
    return path

def slices(im, rows, name):
    a=np.array(im)[:,:,3]; h,w=a.shape; yy,xx=np.indices((h,w))
    horizontal=[np.zeros(w,dtype=int)]+[seam(a.T,i*h/rows,h/rows*.30) for i in range(1,rows)]+[np.full(w,h)]
    result=[]
    for row in range(rows):
        band=(yy>=horizontal[row][None,:]) & (yy<horizontal[row+1][None,:])
        ra=np.where(band,a,0)
        vertical=[np.zeros(h,dtype=int)]+[seam(ra,i*w/4,w/4*.46) for i in range(1,4)]+[np.full(h,w)]
        for col in range(4):
            mask=band & (xx>=vertical[col][:,None]) & (xx<vertical[col+1][:,None])
            if (name,row*4+col) in SOURCE_BOUNDS:
                left,top,right,bottom=SOURCE_BOUNDS[(name,row*4+col)]
                mask &= (xx>=left) & (xx<right) & (yy>=top) & (yy<bottom)
            alpha=np.where(mask,a,0).astype('uint8')
            strong=Image.fromarray(alpha).point(lambda v:255 if v>128 else 0)
            box=strong.getbbox();assert box,(row,col)
            # Retain a small transparent/soft-alpha margin around the silhouette.
            rect=(max(0,box[0]-4),max(0,box[1]-4),min(w,box[2]+4),min(h,box[3]+4))
            frame=im.copy();frame.putalpha(Image.fromarray(alpha))
            result.append((frame.crop(rect),rect))
    return result

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'hoppys-adventure-arcade/Assets/code-city-brawl-assets-only'
OUT = PACK / 'code_city'
GEN = json.loads((PACK / 'generation.json').read_text())
MINI_GENERATION = json.loads((PACK / 'mini_boss_generation.json').read_text())
MINI_BOSSES = ('stack_overflow', 'zero_day')
for key, prompt in MINI_GENERATION['prompts'].items():
    GEN['specs'][key] = dict(rows=4, cell=256, prompt=prompt)
    GEN['sources'][key] = f'sources/{key}.png'

def clip(name, frames, fps=6, loop=False):
    return dict(name=name, frames=frames, fps=fps, loop=loop)

def states(names):
    return [clip(n,[i],1,n.endswith('idle') or n.endswith('intact')) for i,n in enumerate(names.split())]


def mini_boss_clips():
    return [clip('idle', [0, 1], 3, True), clip('walk', [2, 3, 4, 5], 6, True),
            clip('slam_warning', [6, 7], 5), clip('slam', [8, 9], 10),
            clip('dash_warning', [10], 1), clip('dash', [11, 12], 10),
            clip('recover', [13], 1), clip('hurt', [14], 1), clip('defeat', [15], 1)]

ROSTERS = {
 'district_enemies': ['cli_gremlin','syntax_error_sprite','linter_enforcer'],
 'security_enemies': ['cve_crawler','injection_attack_drone','dependency_bot'],
 'hq_enemies': ['merge_conflict_soldier','force_push_bandit','stale_branch_zombie'],
}
NAMES = {
 'cli_gremlin':'idle walk_a walk_b jab_warning jab recover hurt defeat',
 'syntax_error_sprite':'idle drift_a drift_b throw_warning throw recover hurt defeat',
 'linter_bare':'idle walk_a walk_b baton_warning baton recover hurt defeat',
 'linter_enforcer':'armored_idle armored_walk baton_warning baton armor_break bare_idle bare_hurt defeat',
 'cve_crawler':'idle walk_a walk_b roll pounce_warning pounce hurt defeat',
 'injection_attack_drone':'idle hover_a hover_b burst_warning burst cooldown hurt defeat',
 'dependency_bot':'idle walk_a walk_b lunge_warning lunge recover hurt defeat',
 'merge_conflict_soldier':'idle walk_a walk_b duplicate sword_warning sword hurt defeat',
 'force_push_bandit':'idle walk_a walk_b charge_warning charge recover hurt defeat',
 'stale_branch_zombie':'idle walk_a walk_b claw_warning claw first_fall resurrect final_defeat',
 'conflict_spawner':'idle_a idle_b summon_warning summon slam_warning slam sweep recover',
 'split_screen':'transition idle left_warning left_strike right_warning right_strike dual_impact recover',
 'merge_chaos':'idle storm_warning storm clone_summon hurt collapse rubble resolved_core',
 'district_kit':'street_slab tower_facade ide_cluster street_lamp kiosk_intact kiosk_cracked kiosk_break kiosk_rubble ide_intact ide_warning ide_break ide_fragments injection_bomb bomb_warning injection_blast encounter_gate',
 'security_kit':'floor_slab corridor_arch alert_beacon barrier server_intact server_cracked server_break server_rubble crate_intact crate_cracked crate_break crate_rubble laser_dormant laser_warning laser_active breach_shockwave',
 'hq_kit':'floor_slab hall_column commit_tree foreground_arch pillar_intact pillar_cracked pillar_break pillar_rubble scaffolding_intact scaffolding_warning scaffolding_break scaffolding_rubble rebase_projectile head_dormant head_warning head_active',
 'weapons':'debug_stick debug_stick_broken linter_staff linter_staff_broken api_key_whip api_key_whip_extended api_key_whip_broken git_branch git_branch_broken firewall_shield firewall_shield_cracked firewall_shield_broken refactor_hammer refactor_hammer_broken melee_sweep hammer_impact',
 'items_allies':'speed_boost attack_up damage_shield slow confused strength_down coffee commit_token cr_bot_idle cr_bot_gift linting_fairy_idle linting_fairy_gift senior_dev_idle senior_dev_walk senior_dev_gift merge_button',
 'combat_fx':'syntax_projectile injection_projectile duplicate_spawn resurrection slam_warning slam_impact left_shockwave right_shockwave split_seam cyan_projectile red_projectile clone_portal chaos_warning glitch_burst merge_radiance merge_press',
}
BOSSES = ('conflict_spawner','split_screen','merge_chaos')
for folder in ('code_city','sources','frames','individual','animations'):
    (PACK/folder).mkdir(parents=True,exist_ok=True)

manifest = dict(version=1,generated_on='2026-10-02',filter='nearest',atlases={},backgrounds={},source='Built-in image generation; see PROMPTS.md')
extractions={}
for name,spec in GEN['specs'].items():
    dest=PACK/'sources'/f'{name}.png'
    if not dest.exists(): shutil.copy2(GEN['sources'][name],dest)
    im=Image.open(dest).convert('RGBA')
    if name.endswith('_background'):
        im=im.resize((1280,720),Image.Resampling.NEAREST)
        im.save(OUT/f'{name}.png')
        manifest['backgrounds'][name]=dict(file=f'{name}.png',size=[1280,720],seamless=False)
        continue
    assert np.any(np.array(im)[:,:,3]==0),f'{name}: missing transparency'
    print('Slicing',name,flush=True)
    cuts=slices(im,spec['rows'],name)
    if name in ROSTERS:
        for i,actor in enumerate(ROSTERS[name]):
            extractions[actor]=(name,cuts[i*8:(i+1)*8],128,True)
    else:
        extractions[name]=(name,cuts,spec['cell'],name in BOSSES or name in MINI_BOSSES or name=='linter_bare')

boss_scales={}
for name in BOSSES:
    _,cuts,cell,_=extractions[name]
    cap=min(cell*.86/max(c.width for c,_ in cuts),cell*.79/max(c.height for c,_ in cuts))
    # Match neutral full-body heights across phases; phase 2 uses its split idle.
    neutral=cuts[1 if name=='split_screen' else 0][0]
    h=neutral.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()
    boss_scales[name]=(cap,h[3]-h[1])
boss_height=min(cap*h for cap,h in boss_scales.values())

for name,(source,cuts,cell,actor) in extractions.items():
    rows=(len(cuts)+3)//4
    scale=min(cell*.88/max(c.width for c,_ in cuts),cell*.80/max(c.height for c,_ in cuts))
    if name in BOSSES: scale=boss_height/boss_scales[name][1]
    if name in MINI_BOSSES:
        neutral = cuts[0][0].getchannel('A').point(lambda v: 255 if v > 128 else 0).getbbox()
        linter = manifest['atlases']['linter_enforcer']['frames'][0]['visible_bounds']
        scale = (linter[3] - linter[1]) * 1.6 / (neutral[3] - neutral[1])
    if name=='linter_bare':
        b=manifest['atlases']['linter_enforcer']['frames'][5]['visible_bounds']
        neutral=cuts[0][0].getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()
        scale=min(scale,(b[3]-b[1])/(neutral[3]-neutral[1]))
    atlas=Image.new('RGBA',(cell*4,cell*rows))
    frames=[];fd=[]
    for i,(crop,rect) in enumerate(cuts):
        # Generated walk B faces right. Normalize those two whole poses while
        # preserving the immutable master and the published facing:left contract.
        if name == 'zero_day' and i in (4, 5):
            crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        strong=crop.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()
        resized=crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),Image.Resampling.NEAREST)
        x=round((cell-resized.width)/2)
        y=round(cell*.90-strong[3]*scale) if actor else round((cell-resized.height)/2)
        if name in MINI_BOSSES:
            # Use the sampled sole, not the pre-resize box, to avoid a rounding
            # texel below the foot pivot. A consistent origin prevents bobbing.
            sampled = resized.getchannel('A').point(lambda v: 255 if v > 128 else 0).getbbox()
            y = round(cell * .9) - sampled[3] + 1
        assert x>=0 and y>=0 and x+resized.width<=cell and y+resized.height<=cell,(name,i,'overflow')
        frame=Image.new('RGBA',(cell,cell));frame.alpha_composite(resized,(x,y))
        atlas.alpha_composite(frame,((i%4)*cell,(i//4)*cell));frames.append(frame)
        d=PACK/'frames'/name;d.mkdir(exist_ok=True);frame.save(d/f'{i:02}.png')
        fd.append(dict(index=i,rect=[i%4*cell,i//4*cell,cell,cell],visible_bounds=list(frame.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()),source_rect_ltrb=list(rect)))
    clips=mini_boss_clips() if name in MINI_BOSSES else states(NAMES[name])
    assert (len(frames) == 16 if name in MINI_BOSSES else len(clips)==len(frames)),(name,'state count')
    if actor and name not in BOSSES and name not in MINI_BOSSES and name!='linter_enforcer':
        motion='hover' if name=='injection_attack_drone' else 'drift' if name=='syntax_error_sprite' else 'walk'
        clips.append(clip(motion,[1,2],6,True))
    if name=='conflict_spawner':clips.append(clip('idle',[0,1],3,True))
    if name in ('district_kit','security_kit','hq_kit'):
        for base,label in ((4,'primary_break'),(8,'secondary_break')):clips.append(clip(label,[base+1,base+2,base+3],7))
    if name=='merge_chaos':clips.append(clip('defeat',[5,6,7],3))
    atlas.save(OUT/f'{name}.png')
    pivot=[cell//2,round(cell*.9)] if actor else [cell//2,cell//2]
    manifest['atlases'][name]=dict(file=f'{name}.png',resource=f'{name}.tres',cell=[cell,cell],grid=[4,rows],pivot=pivot,facing='mixed' if name in BOSSES else 'left' if actor else 'fixed',source=source,source_scale=scale,frames=fd,clips=clips)
    if name in MINI_BOSSES:
        manifest['atlases'][name]['source_flip_h'] = [4, 5] if name == 'zero_day' else []
        manifest['atlases'][name]['standing_height_ratio'] = 1.6
        manifest['atlases'][name]['display_name'] = 'STACK OVERFLOW' if name == 'stack_overflow' else 'ZERO-DAY'
        preview = Image.new('RGBA', (cell * 4, len(clips) * (cell + 24)), '#11192d')
        draw = ImageDraw.Draw(preview)
        for row, c in enumerate(clips):
            top = row * (cell + 24)
            draw.text((8, top + 4), f"{name} / {c['name']} / {c['fps']} fps", fill='#e1edfa')
            for column, index in enumerate(c['frames']):
                preview.alpha_composite(frames[index], (column * cell, top + 24))
                draw.line((column * cell, top + 24 + pivot[1], (column + 1) * cell - 1, top + 24 + pivot[1]), fill='#61ecd3')
        preview.save(PACK / f'{name}_preview.png')
    lines=[f'[gd_resource type="SpriteFrames" load_steps={len(frames)+2} format=3]',f'\n[ext_resource type="Texture2D" path="{name}.png" id="1"]']
    for i in range(len(frames)):
        lines += [f'\n[sub_resource type="AtlasTexture" id="Frame_{i}"]','atlas = ExtResource("1")',f'region = Rect2({i%4*cell}, {i//4*cell}, {cell}, {cell})']
    anims=[]
    for c in clips:
        refs=', '.join('{"duration": 1.0, "texture": SubResource("Frame_%d")}'%i for i in c['frames'])
        anims.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(refs,str(c['loop']).lower(),c['name'],float(c['fps'])))
        d=PACK/'individual'/name;d.mkdir(exist_ok=True);frames[c['frames'][0]].save(d/f'{c["name"]}.png')
        if len(c['frames'])>1:
            imgs=[]
            for i in c['frames']:
                bg=Image.new('RGBA',(cell,cell),'#11192d');bg.alpha_composite(frames[i]);imgs.append(bg.convert('RGB').resize((cell*2,cell*2),Image.Resampling.NEAREST))
            imgs[0].save(PACK/'animations'/f'{name}-{c["name"]}.gif',save_all=True,append_images=imgs[1:],duration=round(1000/c['fps']),loop=0)
    lines += ['\n[resource]','animations = [\n'+',\n'.join(anims)+'\n]']
    (OUT/f'{name}.tres').write_text('\n'.join(lines)+'\n')

(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(PACK/'PROMPTS.md').write_text('# Code City Brawl generation prompts\n\nBuilt-in image generation, October 2, 2026; mini-boss additions October 10, 2026. Phase sheets reference the original boss design. Sources preserve generated alpha; packing only slices, registers, and scales artwork.\n\n'+'\n\n'.join('## '+n+'\n\n'+s['prompt'] for n,s in GEN['specs'].items())+'\n\n## Stack Overflow refinement\n\n'+(PACK/'stack-refinement.txt').read_text()+'\n\nZero-day source cells 5 and 6 face right; the builder mirrors those complete poses before packing to enforce facing left. Original generated sources are preserved. Final mini-boss cells are 256 square with pivot (128,230), allowing the full dash cloak at about 98px standing height.\n')
template=(ROOT/'tools/code_city_gallery.html').read_text()
(PACK/'preview.html').write_text(template.replace('MANIFEST_DATA',json.dumps(manifest)))
print('Packed',sum(len(a['frames']) for a in manifest['atlases'].values()),'frames,',sum(len(a['clips']) for a in manifest['atlases'].values()),'states,',len(manifest['atlases']),'resources.')
