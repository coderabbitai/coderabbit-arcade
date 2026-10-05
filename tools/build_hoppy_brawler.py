"""Pack the generated Hoppy combat sheet; preserve source alpha."""
from pathlib import Path
from PIL import Image
import json
root=Path(__file__).resolve().parents[1]/'hoppys-adventure-arcade/Assets/code-city-brawl-player'
im=Image.open(root/'source.png').convert('RGBA');cuts=[]
for i in range(16):
 c=im.crop((round(i%4*im.width/4),round(i//4*im.height/4),round((i%4+1)*im.width/4),round((i//4+1)*im.height/4)))
 b=c.getchannel('A').point(lambda x:255 if x>32 else 0).getbbox();assert b
 cuts.append(c.crop(b))
scale=68/max(c.height for c in cuts)
atlas=Image.new('RGBA',(384,384))
for i,c in enumerate(cuts):
 c=c.resize((round(c.width*scale),round(c.height*scale)),Image.Resampling.NEAREST)
 atlas.alpha_composite(c,(i%4*96+(96-c.width)//2,i//4*96+86-c.height))
atlas.save(root/'combat.png')
clips={'walk_up':([0,1],8,True),'walk_down':([2,3],8,True),'jab':([4,5],12,False),'swing':([6,7],9,False),'kick':([8,9,10],10,False),'pickup':([11,12],8,False),'hurt':([13],1,False),'jump':([14],1,False),'idle':([15],1,True)}
s=['[gd_resource type="SpriteFrames" load_steps=18 format=3]','[ext_resource type="Texture2D" path="combat.png" id="1"]']
for i in range(16):s += [f'[sub_resource type="AtlasTexture" id="F{i}"]','atlas = ExtResource("1")',f'region = Rect2({i%4*96}, {i//4*96}, 96, 96)']
a=[]
for n,(ids,fps,loop) in clips.items():
 refs=', '.join('{"duration":1.0,"texture":SubResource("F%d")}'%i for i in ids)
 a.append('{"frames":[%s],"loop":%s,"name":&"%s","speed":%s}'%(refs,str(loop).lower(),n,float(fps)))
s += ['[resource]','animations = ['+',\n'.join(a)+']'];(root/'combat.tres').write_text('\n'.join(s)+'\n')
(root/'manifest.json').write_text(json.dumps({'cell':[96,96],'pivot':[48,86],'facing':'right','clips':clips},indent=2))
