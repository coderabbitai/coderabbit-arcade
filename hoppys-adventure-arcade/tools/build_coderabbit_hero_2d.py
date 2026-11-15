"""Pack the retained, reference-matched hero masters without repainting them.

Run from any directory:
  uv run --no-project --with pillow --with numpy python PATH/TO/THIS_FILE

The image tool authors anatomy, costume and pixels. This builder only extracts,
scales with nearest sampling, registers, and packs. Original masters are immutable.
Source landmarks in sources/layout.json are measured per cel, not inherited from
Hoppy. Runtime clips retain their original names, indices, durations and rates.
"""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Assets/Character/CodeRabbit/2D/heroes_villains'
SOURCES = OUT / 'sources'
OLD = ROOT / 'Assets/heroes-vs-villains-assets-only/heroes_villains'
ARMED = ROOT / 'Assets/hoppy-armed/heroes'
RES = 'res://Assets/Character/CodeRabbit/2D/heroes_villains/'
PREVIEWS = ROOT.parent / 'docs/previews/hero-reference'


def bounds(image: Image.Image, threshold=128):
    return image.getchannel('A').point(lambda a: 255 if a >= threshold else 0).getbbox()


def nearest(image, point, limit=8):
    a = np.asarray(image)[..., 3]
    yy, xx = np.where(a >= 128)
    distances = (xx - point[0]) ** 2 + (yy - point[1]) ** 2
    best = int(distances.argmin())
    if distances[best] > limit ** 2:
        raise ValueError(f'Anchor {point} misses painted pixels by {distances[best] ** .5:.1f}px')
    return [int(xx[best]), int(yy[best])]


def body_mean(image, foot, hand, height):
    a = np.asarray(image)[max(0, foot-height):foot+1, :max(1, hand-2), 3]
    _, xx = np.where(a >= 128)
    return float(xx.mean())


def resource(source, target, png):
    text = source.read_text()
    text, n = re.subn(r'(\[ext_resource type="Texture2D" path=")[^"]+(\")',
                     lambda m: m[1] + RES + png + m[2], text)
    assert n == 1
    target.write_text(text)


def pack(name, spec, height):
    master = Image.open(SOURCES / (name + '.png')).convert('RGBA')
    cols, rows = spec['grid']
    cw, ch = spec['cell']
    px, py = spec['pivot']
    ux, uy = spec['source_units']
    cells = []
    for index in range(cols * rows):
        x, y = index % cols, index // cols
        source = master
        if str(index) in spec.get('frame_sources', {}):
            source = Image.open(SOURCES/spec['frame_sources'][str(index)]).convert('RGBA')
        cells.append(source.crop((round(x*source.width/cols), round(y*source.height/rows),
                                  round((x+1)*source.width/cols), round((y+1)*source.height/rows))))
    idle = bounds(cells[0], 200)
    scale = height / (idle[3] - idle[1])
    frames, metadata = [], []
    for index, cell in enumerate(cells):
        box = bounds(cell, 200)
        if box is None:
            raise ValueError(f'{name}/{index}: empty source')
        size = (round(cell.width*scale), round(cell.height*scale))
        small = cell.resize(size, Image.Resampling.NEAREST)
        sx, sy = size[0]/ux, size[1]/uy
        foot_y = spec.get('foot_y', {}).get(str(index), box[3]*uy/cell.height - 1)
        origin = [round(px-spec['axis'][index]*sx), round(py-foot_y*sy)]
        image = Image.new('RGBA', (cw, ch))
        image.paste(small, tuple(origin))
        hand = None
        if 'hand' in spec:
            hand = [round(origin[0]+spec['hand'][index][0]*sx), round(origin[1]+spec['hand'][index][1]*sy)]
        frames.append(image)
        metadata.append({'source_cell':index, 'source':spec.get('frame_sources',{}).get(str(index),name+'.png'), 'source_bounds':list(box), 'scale':scale,
                         'origin':origin, 'hand_target':hand, 'source_to_cell':[sx,sy]})
    # Match the visible body across the four armed run cels, including the loop seam.
    # Measured without the weapon; do not register on a changing weapon silhouette.
    if 'hand' in spec:
        refs = [body_mean(frames[i],py,metadata[i]['hand_target'][0],height) for i in range(1,5)]
        center = sum(refs)/len(refs)
        for i, value in zip(range(1,5), refs):
            dx = round(center-value)
            if dx:
                shifted = Image.new('RGBA',(cw,ch)); shifted.paste(frames[i],(dx,0)); frames[i]=shifted
                metadata[i]['origin'][0] += dx
                metadata[i]['hand_target'][0] += dx
    atlas = Image.new('RGBA', (cw*cols,ch*rows))
    anchors = {'hand':{},'foot':{},'tip':{}}
    for i,(image,meta) in enumerate(zip(frames,metadata)):
        b = bounds(image)
        if b is None or b[0]<2 or b[1]<2 or b[2]>cw-2 or b[3]>ch-2:
            raise ValueError(f'{name}/{i}: clipped painted bounds {b}')
        meta['bounds']=list(b)
        a = np.asarray(image)[...,3]
        yy, xx = np.where((a >= 128) & (np.indices(a.shape)[0] >= py-2) & (abs(np.indices(a.shape)[1]-px) <= 35))
        if len(xx):
            best = int(((xx-px)**2 + (yy-py)**2).argmin())
            anchors['foot'][str(i)] = [int(xx[best]),int(yy[best])]
        else:
            raise ValueError(f'{name}/{i}: no grounded foot near pivot')
        if 'hand' in spec:
            anchors['hand'][str(i)] = nearest(image,meta['hand_target'])
            sx,sy=meta['source_to_cell']; ox,oy=meta['origin']
            tip=spec['tip'][i]

            try:
                anchors['tip'][str(i)] = nearest(image,(ox+tip[0]*sx,oy+tip[1]*sy))
            except ValueError as e:
                raise ValueError(f'{name}/{i}: {e}') from e
        atlas.paste(image,((i%cols)*cw,(i//cols)*ch))
    return atlas,frames,metadata,anchors


def previews(name, frames, cols, meta):
    cw,ch=frames[0].size
    sheet=Image.new('RGB',(cols*cw*2,((len(frames)+cols-1)//cols)*(ch*2+24)), '#202632')
    draw=ImageDraw.Draw(sheet)
    for i,frame in enumerate(frames):
        x=(i%cols)*cw*2; y=(i//cols)*(ch*2+24)
        sheet.paste(frame.resize((cw*2,ch*2),Image.Resampling.NEAREST),(x,y+24),frame.resize((cw*2,ch*2),Image.Resampling.NEAREST))
        draw.text((x+8,y+6),f'{name} / {i}',fill='white')
    sheet.save(PREVIEWS/(name+'.png'))
    cycles = {'run': list(range(1,5))} if name not in ('combat','locomotion') else (
        {'run':list(range(8)),'walk_up':list(range(8,16)),'walk_down':list(range(16,24))} if name=='locomotion' else {})
    if name not in ('combat','locomotion'):
        cycles.update({f'step{s+1}':list(range(5+s*3,8+s*3)) for s in range(3)})
    for clip,indices in cycles.items():
        for zoom in (1,4):
            gif=[]
            for i in indices:
                im=Image.new('RGB',(cw*zoom,ch*zoom),'#202632')
                sprite=frames[i].resize(im.size,Image.Resampling.NEAREST)
                im.paste(sprite,(0,0),sprite); gif.append(im)
            suffix='-native' if zoom==1 else ''
            gif[0].save(PREVIEWS/f'{name}-{clip}{suffix}.gif',save_all=True,append_images=gif[1:],
                        duration=72 if name=='locomotion' else 143 if clip=='run' else 110,loop=0)


def main():
    config=json.loads((SOURCES/'layout.json').read_text())
    legacy=json.loads((ARMED/'manifest.json').read_text())
    PREVIEWS.mkdir(parents=True,exist_ok=True)
    (OUT/'armed/carry').mkdir(parents=True,exist_ok=True)
    result={'version':2,'mode':'heroes','filter':'nearest','body_height':config['body_height'],
            'generated_from':'Reference-matched immutable image_gen masters; sources/provenance.json',
            'sheets':{},'weapons':{},'carry_hands':{}}
    all_frames={}
    for name,spec in config['sheets'].items():
        atlas,frames,meta,anchors=pack(name,spec,config['body_height'])
        all_frames[name]=frames
        filename={'combat':'coderabbit_hero','locomotion':'coderabbit_hero_locomotion'}.get(name,'armed/'+name)
        atlas.save(OUT/(filename+'.png'),optimize=True)
        template=OLD/('hoppy_locomotion.tres' if name=='locomotion' else 'hoppy.tres') if name in ('combat','locomotion') else ARMED/(name+'.tres')
        resource(template,OUT/(filename+'.tres'),filename+'.png')
        entry={'cell':spec['cell'],'pivot':spec['pivot'],'source':'sources/'+name+'.png',
               'sha256':hashlib.sha256((SOURCES/(name+'.png')).read_bytes()).hexdigest(),
               'frames':meta,'anchors':anchors}
        result['sheets'][name]=entry
        if name not in ('combat','locomotion'):
            weapon={'resource':name+'.tres','cell':spec['cell'],'pivot':spec['pivot'],
                    'body_height':config['body_height'],'unarmed_idle_height':config['body_height'],
                    'clips':legacy['weapons'][name]['clips'],'anchors':anchors}
            carry=Image.open(ARMED/'carry'/f'{name}.png').convert('RGBA')
            b=bounds(carry)
            ratio=spec['weapon_length']/max(b[2]-b[0],b[3]-b[1])
            carry=carry.resize((round(carry.width*ratio),round(carry.height*ratio)),Image.Resampling.NEAREST)
            carry.save(OUT/'armed/carry'/f'{name}.png',optimize=True)
            weapon['carry_calibration']={'target_length':spec['weapon_length'], 'scale_from_legacy':ratio}
            result['weapons'][name]=weapon
        previews(name,frames,spec['grid'][0],meta)
    # Authored carry locations measured on the packed base sheet. Per-frame directional
    # anchors follow the glove instead of a synthetic sine-wave bob.
    hands={'idle':('combat',[0],[(84,91)]),'jump':('combat',[3],[(84,85)]),
           'defeat':('combat',[11],[(104,110)]),'victory':('combat',[14],[(84,84)]),
           'walk_up':('locomotion',list(range(8,16)),[(82,89),(82,88),(82,89),(82,89),(82,87),(82,88),(82,89),(82,89)]),
           'walk_down':('locomotion',list(range(16,24)),[(82,90),(80,90),(81,90),(81,90),(82,91),(80,91),(81,90),(81,90)])}
    for pose,(sheet,indices,points) in hands.items():
        result['carry_hands'][pose]=[nearest(all_frames[sheet][i],point,20) for i,point in zip(indices,points)]
    (OUT/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Packed 120 hero cels and calibrated five weapons:',OUT)


if __name__=='__main__':
    main()
