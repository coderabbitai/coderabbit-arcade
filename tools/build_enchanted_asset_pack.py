"""Mechanically pack generated Enchanted Repo masters; no art is painted here."""
from pathlib import Path
import json
import shutil
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'hoppys-adventure-arcade/Assets/enchanted-repo-assets-only'
OUT = PACK / 'enchanted_repo'
GEN = json.loads((PACK / 'generation.json').read_text())

def clip(name, frames, fps=8, loop=True):
    return dict(name=name, frames=frames, fps=fps, loop=loop)

SPECS = {
 'legacy_monolith': (192,6,None,[clip('idle',[0,1,2,3],4),clip('slam_warning',[4,5],4,False),clip('slam',[6],10,False),clip('slam_recover',[7],4,False),clip('sweep_warning',[8],4,False),clip('sweep',[9,10],8,False),clip('sweep_recover',[11],4,False),clip('stomp_warning',[12],4,False),clip('stomp',[13],10,False),clip('stomp_recover',[14,15],4,False),clip('armor_hit',[16],8,False),clip('armor_crack',[17],5,False),clip('armor_break',[18],5,False),clip('exposed',[19],4),clip('core_hurt',[20],8,False),clip('defeat',[21,22,23],4,False)]),
 'monolith_armor': (256,4,None,[clip(prefix+n,[base+i],4,n in ('idle','exposed')) for prefix,base in [('cracked_',0),('bare_',8)] for i,n in enumerate(['idle','slam_warning','slam','sweep_warning','sweep','stomp_warning','stomp','exposed'])]),
 'nitpick_gnome': (96,4,None,[clip('idle',[0,1,2,3],5),clip('walk',[4,5,6,7],8),clip('jab_warning',[8,9],5,False),clip('jab',[10],10,False),clip('recover',[11],5,False),clip('hurt',[12,13],9,False),clip('defeat',[14,15],5,False)]),
 'bloat_troll': (144,4,None,[clip('idle',[0,1,2,3],4),clip('walk',[4,5,6,7],5),clip('club_warning',[8,9],4,False),clip('club',[10],10,False),clip('recover',[11],4,False),clip('hurt',[12,13],8,False),clip('defeat',[14,15],4,False)]),
 'hazards': (128,4,None,[clip(n,[i],5,i in (0,4,8)) for i,n in enumerate(['branch_intact','branch_warning','branch_break','branch_fall','comment_dormant','comment_warning','comment_burst','comment_spent','vine_idle','vine_warning','vine_whip','vine_cut','impact_warning','slam_burst','shockwave','armor_chunk'])]),
 'forest_kit': (128,4,None,[clip(n,[i],1) for i,n in enumerate(['ground_slab','ledge_left','ledge_right','root_platform','castle_wall','castle_pillar','castle_arch','arena_slab','rune_tree','castle_spire','scroll_banner','root_bridge','foreground_flora','foreground_trunk','rune_lantern','rubble'])])
}

def seam(alpha, center, radius):
    """Find a transparent, possibly curved gutter without cutting solid art."""
    # Axis 0 follows the seam; axis 1 is the allowed cross-section.
    lo=max(1,round(center-radius)); hi=min(alpha.shape[1]-1,round(center+radius))
    core=alpha>128
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
    assert not blocked[np.arange(len(path)),path].any(), 'No transparent gutter; regenerate source'
    return path

def slices(im, rows, name):
    a=np.array(im)[:,:,3]; h,w=a.shape; yy,xx=np.indices((h,w))
    horizontal=[np.zeros(w,dtype=int)]+[seam(a.T,i*h/rows,h/rows*.30) for i in range(1,rows)]+[np.full(w,h)]
    result=[]
    for row in range(rows):
        band=(yy>=horizontal[row][None,:]) & (yy<horizontal[row+1][None,:])
        ra=np.where(band,a,0)
        vertical=[np.zeros(h,dtype=int)]+[seam(ra,i*w/4-(24 if name=='legacy_monolith' and row==2 and i==1 else 0),w/4*.30) for i in range(1,4)]+[np.full(h,w)]
        for col in range(4):
            mask=band & (xx>=vertical[col][:,None]) & (xx<vertical[col+1][:,None])
            alpha=np.where(mask,a,0).astype('uint8')
            strong=Image.fromarray(alpha).point(lambda v:255 if v>128 else 0)
            box=strong.getbbox();assert box,(row,col)
            # Retain a small transparent/soft-alpha margin around the silhouette.
            rect=(max(0,box[0]-4),max(0,box[1]-4),min(w,box[2]+4),min(h,box[3]+4))
            frame=im.copy();frame.putalpha(Image.fromarray(alpha))
            result.append((frame.crop(rect),rect))
    return result

for folder in ('enchanted_repo','sources','frames','individual','animations'):
    (PACK/folder).mkdir(parents=True,exist_ok=True)

manifest={'version':1,'generated_on':'2026-10-01','filter':'nearest','atlases':{},'backgrounds':{},'source':'Built-in image generation; see PROMPTS.md.'}
for name, source in GEN['sources'].items():
    dest=PACK/'sources'/f'{name}.png'
    if not dest.exists(): shutil.copy2(source,dest)
    im=Image.open(dest).convert('RGBA')
    if name not in SPECS:
        im=im.resize((960,540),Image.Resampling.NEAREST)
        im.save(OUT/f'{name}.png')
        manifest['backgrounds'][name]={'file':f'{name}.png','size':[960,540],'seamless':False,'transparent':name=='treeline'}
        continue
    cell,rows,scale,clips=SPECS[name]
    a=np.array(im)[:,:,3]
    assert (a==0).any(), f'{name}: missing transparent alpha'
    extracted=slices(im,rows,name)
    # Uniform sheet scale preserves relative pose proportions; tight slices remove gutters.
    scale=min(cell*.88/max(c.width for c,_ in extracted),cell*.82/max(c.height for c,_ in extracted))
    if name=='monolith_armor':
        # Match neutral standing height to the primary boss atlas.
        primary=manifest['atlases']['legacy_monolith']['frames'][0]['visible_bounds']
        source_idle=extracted[0][0].getchannel('A').point(lambda v:255 if v>128 else 0).getbbox()
        scale=min(scale,(primary[3]-primary[1])/(source_idle[3]-source_idle[1]))
    atlas=Image.new('RGBA',(cell*4,cell*rows))
    frames=[];frame_data=[];source_rects=[]
    for idx,(crop,rect) in enumerate(extracted):
        row,col=divmod(idx,4)
        strong=crop.getchannel('A').point(lambda v:255 if v>128 else 0)
        box=strong.getbbox()
        resized=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST)
        x=round((cell-resized.width)/2)
        y=round(cell*.90-box[3]*scale) if name in ('legacy_monolith','monolith_armor','nitpick_gnome','bloat_troll') else round((cell-resized.height)/2)
        assert x>=0 and y>=0 and x+resized.width<=cell and y+resized.height<=cell,(name,row,col,'packing overflow')
        frame=Image.new('RGBA',(cell,cell));frame.alpha_composite(resized,(x,y))
        frames.append(frame);atlas.alpha_composite(frame,(col*cell,row*cell))
        fd=PACK/'frames'/name;fd.mkdir(exist_ok=True);frame.save(fd/f'{idx:02}.png')
        frame_data.append({'index':idx,'rect':[col*cell,row*cell,cell,cell],'visible_bounds':list(frame.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox())})
        source_rects.append(list(rect))
    atlas.save(OUT/f'{name}.png')
    pivot=[cell//2,round(cell*.90)] if name in ('legacy_monolith','monolith_armor','nitpick_gnome','bloat_troll') else [cell//2,cell//2]
    manifest['atlases'][name]={'file':f'{name}.png','resource':f'{name}.tres','cell':[cell,cell],'grid':[4,rows],'pivot':pivot,'facing':'left' if name in ('legacy_monolith','monolith_armor','nitpick_gnome','bloat_troll') else 'fixed','frames':frame_data,'clips':clips,'source_rects_ltrb':source_rects,'source_scale':scale,'source_slicing':'Transparent curved gutters; source rectangles may overlap in empty areas'}
    text=[f'[gd_resource type="SpriteFrames" load_steps={len(frames)+2} format=3]',f'\n[ext_resource type="Texture2D" path="{name}.png" id="1"]']
    for i in range(len(frames)):
        text += [f'\n[sub_resource type="AtlasTexture" id="F{i}"]','atlas = ExtResource("1")',f'region = Rect2({i%4*cell}, {i//4*cell}, {cell}, {cell})','filter_clip = true']
    anims=[]
    for c in clips:
        refs=', '.join('{"duration": 1.0, "texture": SubResource("F%d")}'%i for i in c['frames'])
        anims.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(refs,str(c['loop']).lower(),c['name'],float(c['fps'])))
        d=PACK/'individual'/name;d.mkdir(exist_ok=True);frames[c['frames'][0]].save(d/f'{c["name"]}.png')
        # GIFs use a dark review background; runtime PNG alpha is untouched.
        if len(c['frames'])>1:
            imgs=[]
            for i in c['frames']:
                bg=Image.new('RGBA',(cell,cell),'#10192d');bg.alpha_composite(frames[i]);imgs.append(bg.convert('RGB').resize((cell*2,cell*2),Image.Resampling.NEAREST))
            imgs[0].save(PACK/'animations'/f'{name}-{c["name"]}.gif',save_all=True,append_images=imgs[1:],duration=round(1000/c['fps']),loop=0)
    text += ['\n[resource]','animations = [\n'+',\n'.join(anims)+'\n]']
    (OUT/f'{name}.tres').write_text('\n'.join(text)+'\n')
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
prompts=['# Enchanted Repo generation prompts','Built-in image generation, October 1, 2026. Original fantasy art; monolith_armor uses legacy_monolith as a character reference. Source PNGs retain generated alpha. Mechanical packing: tools/build_enchanted_asset_pack.py. No third-party stock art used.']
for n,p in GEN['prompts'].items():prompts += [f'## {n}',p]
for n,p in GEN['corrections'].items():prompts += [f'## {n} correction',p]
(PACK/'PROMPTS.md').write_text('\n\n'.join(prompts)+'\n')

html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Enchanted Repo · Asset Gallery</title><style>body{margin:0;background:#080e1d;color:#dfecff;font:16px system-ui}main{max-width:1200px;margin:auto;padding:40px}h1{font-size:40px;margin-bottom:8px}p{color:#9eacc8;line-height:1.6}button,select{font:inherit;background:#192a44;color:#dffaff;padding:10px;border:1px solid #47758b;border-radius:6px}header{margin-bottom:32px}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:20px}.card{background:#111d32;padding:20px;border:1px solid #283c59;border-radius:12px}canvas{display:block;width:100%;image-rendering:pixelated;background:repeating-conic-gradient(#152039 0% 25%,#1a2842 0% 50%) 50%/24px 24px;margin:16px 0}img{max-width:100%;image-rendering:pixelated}h2{text-transform:capitalize}.badge{color:#63e1e8;font-size:13px;letter-spacing:3px}</style><main><header><div class="badge">HOPPY'S ADVENTURE ARCADE / ART PASS 01</div><h1>Enchanted Repo</h1><p>Forest and castle construction kit, enemies, hazards, and the Legacy Monolith. Asset preview only; moves and timings are proposals for later gameplay implementation.</p><button id="pause">Pause animation</button> <label>Speed <select id="speed"><option value="0.5">0.5×</option><option selected value="1">1×</option><option value="2">2×</option></select></label></header><div class="gallery" id="gallery"></div><h2>Parallax plates</h2><p>Far twilight sky + transparent treeline. Use foreground flora and trunk independently. Finite plates, not seamless tiles.</p><div style="position:relative"><img src="enchanted_repo/sky.png"><img style="position:absolute;inset:0;width:100%" src="enchanted_repo/treeline.png"></div></main><script>const data=MANIFEST;let paused=false,t=0,prev=0;const cards=[];for(const [name,a] of Object.entries(data.atlases)){const card=document.createElement('div');card.className='card';const title=document.createElement('h2');title.textContent=name.replaceAll('_',' ');card.append(title);const select=document.createElement('select');select.setAttribute('aria-label',name+' animation');for(const c of a.clips){const o=document.createElement('option');o.value=c.name;o.textContent=c.name.replaceAll('_',' ');select.append(o)}card.append(select);const canvas=document.createElement('canvas');canvas.width=a.cell[0];canvas.height=a.cell[1];card.append(canvas);const meta=document.createElement('p');meta.textContent=`${a.cell[0]} × ${a.cell[1]} cells · ${a.frames.length} frames`;card.append(meta);document.getElementById('gallery').append(card);const im=new Image();im.src='enchanted_repo/'+a.file;cards.push({a,select,canvas,im})}document.getElementById('pause').onclick=()=>{paused=!paused;document.getElementById('pause').textContent=paused?'Resume animation':'Pause animation'};function tick(now){if(!paused)t+=(now-prev)/1000*Number(document.getElementById('speed').value);prev=now;for(const {a,select,canvas,im} of cards){if(!im.complete)continue;const c=a.clips.find(c=>c.name===select.value);const i=c.frames[Math.floor(t*c.fps)%c.frames.length],r=a.frames[i].rect,ctx=canvas.getContext('2d');ctx.clearRect(0,0,...a.cell);ctx.imageSmoothingEnabled=false;ctx.drawImage(im,...r,0,0,...a.cell)}requestAnimationFrame(tick)}requestAnimationFrame(tick);</script></html>'''
(PACK/'preview.html').write_text(html.replace('MANIFEST',json.dumps(manifest)))
print('Packed',sum(len(a['frames']) for a in manifest['atlases'].values()),'frames;',sum(len(a['clips']) for a in manifest['atlases'].values()),'named clips.')
