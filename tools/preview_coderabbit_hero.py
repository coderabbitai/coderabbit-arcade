"""Create review contact sheets at native and 2x scale against a Git baseline.

uv run --with pillow python tools/preview_coderabbit_hero.py --baseline 27e2762
"""
import argparse
from io import BytesIO
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
HERO = Path('hoppys-adventure-arcade/Assets/Character/CodeRabbit/2D/heroes_villains')
OUT = ROOT / 'docs/previews/hero-reference'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', '--verify', args.baseline+'^{commit}'], cwd=ROOT, text=True).strip()
    keys = ['coderabbit_hero','coderabbit_hero_locomotion'] + ['armed/'+n for n in ['review_stamp','triage_hammer','change_stack_baton','security_scanner','pr_merger']]
    for key in keys:
        path = HERO/(key+'.png')
        before = Image.open(BytesIO(subprocess.check_output(['git','show',f'{revision}:{path.as_posix()}'],cwd=ROOT))).convert('RGBA')
        after = Image.open(ROOT/path).convert('RGBA')
        for scale in (1,2):
            w,h=after.width*scale,after.height*scale
            contact=Image.new('RGB',(w*2,h+28),'#202632')
            draw=ImageDraw.Draw(contact)
            draw.text((10,8),'BEFORE / '+key,fill='white')
            draw.text((w+10,8),'REFERENCE HERO / '+key,fill='white')
            for j,im in enumerate((before,after)):
                im=im.resize((w,h),Image.Resampling.NEAREST)
                contact.paste(im,(j*w,28),im)
            contact.save(OUT/f'{key.replace("/","-")}-comparison-{scale}x.png')
    print('Wrote seven before/after sheets at native and 2x scale')


if __name__=='__main__': main()
