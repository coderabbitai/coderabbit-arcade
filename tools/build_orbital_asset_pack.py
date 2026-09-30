"""Mechanically pack generated Orbital Ops masters; no art is painted here."""
from pathlib import Path
import json
import shutil
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'hoppys-adventure-arcade/Assets/orbital-ops-assets-only'
OUT = PACK / 'orbital_ops'
GEN = json.loads((PACK / 'generation.json').read_text())

def clip(name, frames, fps=8, loop=True):
    return dict(name=name, frames=frames, fps=fps, loop=loop)

SPECS = {
 'deprecated_api': (192, 6, .64, [clip('idle', [0,1,2,3],5), clip('cannon_warning',[4,5],5,False),clip('cannon_fire',[6],10,False),clip('cannon_recover',[7],5,False),clip('slam_warning',[8,9],4,False),clip('slam',[10],10,False),clip('slam_stalled',[11],4,False),clip('dash_warning',[12],4,False),clip('dash',[13,14],10,False),clip('dash_brake',[15],5,False),clip('overheat',[16],5,False),clip('vulnerable',[17,18],4),clip('reboot',[19],5,False),clip('hurt',[20,21],10,False),clip('defeat',[22,23],5,False)]),
 'rogue_ai': (96,4,.24,[clip('idle',[0,1,2,3],5),clip('walk',[4,5,6,7],9),clip('attack_warning',[8,9],6,False),clip('attack',[10],10,False),clip('recover',[11],6,False),clip('hurt',[12,13],10,False),clip('defeat',[14,15],6,False)]),
 'security_drone': (96,4,.24,[clip('hover',[0,1,2,3],7),clip('patrol',[4,5,6,7],8),clip('ambush_warning',[8,9],5,False),clip('dive',[10],10,False),clip('recover',[11],6,False),clip('hurt',[12,13],10,False),clip('defeat',[14,15],6,False)]),
 'hazards': (128,4,.34,[clip('laser_off',[0],1),clip('laser_warning',[1],1),clip('laser_active',[2],1),clip('laser_cooldown',[3],1),clip('vent_closed',[4],1),clip('vent_warning',[5],1),clip('vent_active',[6,7],7),clip('zero_g_beacon',[8,9,10,11],6),clip('plasma_bolt',[12,13],10),clip('slam_impact',[14],8,False),clip('dash_trail',[15],8,False)]),
 'station_kit': (128,4,.34,[clip(n,[i],1) for i,n in enumerate(['floor_slab','ledge_left','ledge_right','one_way_platform','hull_panel','wall_block','scaffold_vertical','scaffold_horizontal','solar_array','bulkhead_door','terminal','cargo_crate','orbital_ring','foreground_strut','warning_lamp','service_platform'])])
}

def cuts(proj, count):
    proj=np.maximum.reduce([proj,np.roll(proj,1),np.roll(proj,-1)])
    size=len(proj); result=[0]
    for i in range(1,count):
        c=round(i*size/count);d=round(size/count*.18)
        v=proj[c-d:c+d+1]; choices=np.where(v==v.min())[0]+c-d
        result.append(int(choices[np.argmin(abs(choices-c))]))
    return result+[size]

manifest={'version':1,'generated_on':'2026-09-30','filter':'nearest','atlases':{},'backgrounds':{},'source':'Built-in image generation; see PROMPTS.md.'}
for name, source in GEN['sources'].items():
    dest=PACK/'sources'/f'{name}.png'
    if not dest.exists(): shutil.copy2(source,dest)
    im=Image.open(dest).convert('RGBA')
    if name not in SPECS:
        im=im.resize((960,540),Image.Resampling.NEAREST)
        im.save(OUT/f'{name}.png')
        manifest['backgrounds'][name]={'file':f'{name}.png','size':[960,540],'seamless':False,'transparent':name=='station_hull'}
        continue
    cell,rows,scale,clips=SPECS[name]
    a=np.array(im)[:,:,3]
    assert (a==0).any(), f'{name}: missing transparent alpha'
    ys=cuts((a>128).sum(axis=1),rows)
    atlas=Image.new('RGBA',(cell*4,cell*rows))
    frames=[];frame_data=[];source_rects=[]
    for row in range(rows):
        xs=cuts((a[ys[row]:ys[row+1],:]>128).sum(axis=0),4)
        for col in range(4):
            rect=[xs[col],ys[row],xs[col+1],ys[row+1]]
            crop=im.crop(rect)
            strong=crop.getchannel('A').point(lambda v:255 if v>128 else 0)
            box=strong.getbbox(); assert box, (name,row,col)
            # Core silhouettes must not intersect internal slicing boundaries.
            ca=np.array(strong)
            assert not (col>0 and ca[:,0].any()), (name,row,col,'left cut')
            assert not (col<3 and ca[:,-1].any()), (name,row,col,'right cut')
            resized=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST)
            # Ground actors share a foot anchor; flying actors/props use cell centers.
            x=round((cell-resized.width)/2)
            y=round(cell*.90-box[3]*scale) if name in ('deprecated_api','rogue_ai') else round((cell-resized.height)/2)
            y=max(0,min(y,cell-resized.height))
            assert x>=0 and y>=0 and x+resized.width<=cell and y+resized.height<=cell,(name,row,col,'packing overflow')
            frame=Image.new('RGBA',(cell,cell));frame.alpha_composite(resized,(x,y))
            idx=len(frames);frames.append(frame);atlas.alpha_composite(frame,(col*cell,row*cell))
            fd=PACK/'frames'/name;fd.mkdir(exist_ok=True);frame.save(fd/f'{idx:02}.png')
            frame_data.append({'index':idx,'rect':[col*cell,row*cell,cell,cell],'visible_bounds':list(frame.getchannel('A').point(lambda v:255 if v>128 else 0).getbbox())})
            source_rects.append(rect)
    atlas.save(OUT/f'{name}.png')
    pivot=[cell//2,round(cell*.90)] if name in ('deprecated_api','rogue_ai') else [cell//2,cell//2]
    manifest['atlases'][name]={'file':f'{name}.png','resource':f'{name}.tres','cell':[cell,cell],'grid':[4,rows],'pivot':pivot,'facing':'left' if name in ('deprecated_api','rogue_ai','security_drone') else 'fixed','frames':frame_data,'clips':clips,'source_rects_ltrb':source_rects,'source_scale':scale}
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
prompts=['# Orbital Ops generation prompts','Built-in image generation, September 30, 2026. Bay Area request_reviewer.png supplied as the style reference for sheets and station hull. Source PNGs retain generated alpha. Mechanical packing: tools/build_orbital_asset_pack.py. No third-party stock art used.']
for n,p in GEN['prompts'].items():prompts += [f'## {n}',p]
for n,p in GEN['corrections'].items():prompts += [f'## {n} correction',p]
(PACK/'PROMPTS.md').write_text('\n\n'.join(prompts)+'\n')

html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Orbital Ops · Asset Gallery</title><style>body{margin:0;background:#080e1d;color:#dfecff;font:16px system-ui}main{max-width:1200px;margin:auto;padding:40px}h1{font-size:40px;margin-bottom:8px}p{color:#9eacc8;line-height:1.6}button,select{font:inherit;background:#192a44;color:#dffaff;padding:10px;border:1px solid #47758b;border-radius:6px}header{margin-bottom:32px}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:20px}.card{background:#111d32;padding:20px;border:1px solid #283c59;border-radius:12px}canvas{display:block;width:100%;image-rendering:pixelated;background:repeating-conic-gradient(#152039 0% 25%,#1a2842 0% 50%) 50%/24px 24px;margin:16px 0}img{max-width:100%;image-rendering:pixelated}h2{text-transform:capitalize}.badge{color:#63e1e8;font-size:13px;letter-spacing:3px}</style><main><header><div class="badge">HOPPY'S ADVENTURE ARCADE / ART PASS 01</div><h1>Orbital Ops</h1><p>Station construction kit, enemies, hazards, and the Deprecated API. Asset preview only; moves and timings are proposals for later gameplay implementation.</p><button id="pause">Pause animation</button> <label>Speed <select id="speed"><option value="0.5">0.5×</option><option selected value="1">1×</option><option value="2">2×</option></select></label></header><div class="gallery" id="gallery"></div><h2>Parallax plates</h2><p>Far starfield + transparent mid station. Use the kit's foreground_strut and orbital_ring independently. Finite plates, not seamless tiles.</p><div style="position:relative"><img src="orbital_ops/starfield.png"><img style="position:absolute;inset:0;width:100%" src="orbital_ops/station_hull.png"></div></main><script>const data=MANIFEST;let paused=false,t=0,prev=0;const cards=[];for(const [name,a] of Object.entries(data.atlases)){const card=document.createElement('div');card.className='card';const title=document.createElement('h2');title.textContent=name.replaceAll('_',' ');card.append(title);const select=document.createElement('select');select.setAttribute('aria-label',name+' animation');for(const c of a.clips){const o=document.createElement('option');o.value=c.name;o.textContent=c.name.replaceAll('_',' ');select.append(o)}card.append(select);const canvas=document.createElement('canvas');canvas.width=a.cell[0];canvas.height=a.cell[1];card.append(canvas);const meta=document.createElement('p');meta.textContent=`${a.cell[0]} × ${a.cell[1]} cells · ${a.frames.length} frames`;card.append(meta);document.getElementById('gallery').append(card);const im=new Image();im.src='orbital_ops/'+a.file;cards.push({a,select,canvas,im})}document.getElementById('pause').onclick=()=>{paused=!paused;document.getElementById('pause').textContent=paused?'Resume animation':'Pause animation'};function tick(now){if(!paused)t+=(now-prev)/1000*Number(document.getElementById('speed').value);prev=now;for(const {a,select,canvas,im} of cards){if(!im.complete)continue;const c=a.clips.find(c=>c.name===select.value);const i=c.frames[Math.floor(t*c.fps)%c.frames.length],r=a.frames[i].rect,ctx=canvas.getContext('2d');ctx.clearRect(0,0,...a.cell);ctx.imageSmoothingEnabled=false;ctx.drawImage(im,...r,0,0,...a.cell)}requestAnimationFrame(tick)}requestAnimationFrame(tick);</script></html>'''
(PACK/'preview.html').write_text(html.replace('MANIFEST',json.dumps(manifest)))
print('Packed',sum(len(a['frames']) for a in manifest['atlases'].values()),'frames;',sum(len(a['clips']) for a in manifest['atlases'].values()),'named clips.')
