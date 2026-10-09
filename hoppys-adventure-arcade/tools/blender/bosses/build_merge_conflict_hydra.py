"""Braided branch serpents. Coordinates are Godot metres, facing +Z."""
import argparse
import bpy
import hashlib
import json
import math
from pathlib import Path
import sys
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_kit import BossBuilder, Part, xform, B2G

RECIPE_REVISION = 6
HEADS = [(-2,2.02,.06),(0,1.72,.04),(2,2.02,.06),(0,3.02,-.40)]
ROOTS = [(-.95,.17,-.22),(0,.35,-.25),(.95,.17,-.22),(0,.12,-.56)]
HEAD_PITCH = math.radians(15)
DURATIONS = dict(intro=2.4,idle=3.2,telegraph=.8,attack=.5,hurt=.35,phase_change=1.2,defeat=1.8,retreat=1.0)


def smooth(a,b,t):
    q=max(0,min(1,(t-a)/(b-a)))
    return q*q*(3-2*q)


def neck_path(i):
    x,y,z=HEADS[i]
    if i in (0,2):
        sign=-1 if i==0 else 1
        controls=[ROOTS[i],(sign*1.65,.65,-.15),(sign*2.28,1.15,-.34),
                  (sign*2.14,y+.10,z-.60),(.95*x,y+.30,z-.64),(x,y+.05,z-.34)]
    elif i==1:
        controls=[ROOTS[i],(-.36,.83,-.25),(.30,1.35,-.38),
                  (-.18,y+.12,z-.60),(0,y+.30,z-.64),(x,y+.05,z-.34)]
    else:
        controls=[ROOTS[i],(-.22,.92,-.66),(.24,1.77,-.75),
                  (-.15,2.70,-.88),(0,y+.30,z-.59),(x,y+.05,z-.32)]
    # A forward hanging skull emerges from a cobra arc above and behind it.
    controls=list(map(Vector,controls))
    result=[]
    for k in range(31):
        u=k/30*(len(controls)-1)
        seg=min(int(u),len(controls)-2); t=u-seg
        a=controls[max(seg-1,0)]; b=controls[seg]
        c=controls[seg+1]; d=controls[min(seg+2,len(controls)-1)]
        result.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
    return result


def marker_part(i,at):
    # Monospace font contours make these literal merge-conflict tokens, not icon arrows.
    # Fonts are converted to original mesh contours; the font file is not distributed.
    font_path=Path(bpy.utils.system_resource('DATAFILES')) / 'fonts/DejaVuSansMono.woff2'
    curve=bpy.data.curves.new('conflict_marker','FONT')
    if not font_path.is_file(): raise RuntimeError('Blender bundled DejaVu Sans Mono is missing: '+str(font_path))
    curve.font=bpy.data.fonts.load(str(font_path))
    curve.body=['<<<<<<<','=======','>>>>>>>','--force'][i]
    if i==1: curve.space_character=.75
    curve.align_x='CENTER'; curve.align_y='CENTER'
    curve.size=1; curve.extrude=.035; curve.offset=.006; curve.resolution_u=1
    obj=bpy.data.objects.new('marker_type',curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.object.convert(target='MESH')
    obj=bpy.context.object
    part=Part(f'literal_marker_{i}')
    part.bm.from_mesh(obj.data)
    extent=max(v.co.x for v in part.bm.verts)-min(v.co.x for v in part.bm.verts)
    low=min(v.co.y for v in part.bm.verts); high=max(v.co.y for v in part.bm.verts)
    # Independent height normalization keeps the seven equals signs as paired bars.
    for v in part.bm.verts:
        v.co=Vector(at)+Vector((v.co.x*.94/extent,(v.co.y-(low+high)/2)*.22/(high-low),v.co.z*.35))
    for face in part.bm.faces: face.material_index=part.slot('lilac')
    bpy.data.objects.remove(obj,do_unlink=True)
    return part


def weight_neck(obj,i,points):
    obj.vertex_groups.clear()
    groups=[obj.vertex_groups.new(name=f'{n}_{i}') for n in ('neck_lo','neck_hi','head')]
    samples=list(map(Vector,points))
    for v in obj.data.vertices:
        g=B2G@v.co
        t=min(range(len(samples)),key=lambda k:(g-samples[k]).length_squared)/(len(samples)-1)
        lo=1-smooth(.18,.55,t)
        head=smooth(.70,.98,t)
        for group,w in zip(groups,(lo,1-lo-head,head)):
            if w>.00001: group.add([v.index],w,'REPLACE')


def pose(kit,action,t):
    pulse=math.sin(math.pi*t)
    fourth=smooth(.20,.78,t) if action=='phase_change' else .001
    kit.pose('branch_3',scale=(max(.001,fourth),)*3)
    if action=='idle': kit.pose('knot',rotation=(0,.022*math.sin(t*math.tau),0))
    elif action=='intro': kit.pose('knot',scale=(.88+.12*smooth(0,.7,t),)*3)
    elif action=='phase_change': kit.pose('knot',rotation=(.035*math.sin(t*math.tau*3)*pulse,0,.045*math.sin(t*math.tau*4)*pulse))
    elif action=='defeat':
        q=smooth(.12,1,t)
        kit.pose('root',location=(0,-.12*q,0),scale=(1-.12*q,)*3)
        kit.pose('knot',rotation=(0,.18*q,0))
    elif action=='retreat':
        q=smooth(0,1,t)
        kit.pose('root',location=(0,-.16*q,-.15*q),scale=(1-.65*q,)*3)
    for i,(x,y,z) in enumerate(HEADS):
        side=-1 if x<0 else 1
        ph=t*math.tau+i*1.7
        lo,hi,head,jaw=(f'{n}_{i}' for n in ('neck_lo','neck_hi','head','jaw'))
        if action=='idle':
            kit.pose(lo,rotation=(.022*math.sin(ph),0,.065*math.sin(ph)))
            kit.pose(hi,rotation=(-.02*math.sin(ph),.025*math.cos(ph),-.12*math.sin(ph)))
            kit.pose(head,rotation=(.025*math.sin(ph),.08*math.sin(ph),0))
            kit.pose(jaw,rotation=(.025+.018*math.sin(ph),0,0))
        elif action=='intro':
            rise=smooth(.04+i*.15,.40+i*.15,t)
            roar=smooth(.57,.82,t)
            kit.pose(lo,rotation=(0,0,side*.58*(1-rise)),scale=(1,.30+.70*rise,1))
            kit.pose(hi,rotation=(.22*(1-rise),0,-side*.65*(1-rise)))
            kit.pose(head,rotation=(.20*roar,(-1 if i==0 else 1 if i==2 else 0)*math.radians(8)*roar,0))
            kit.pose(jaw,rotation=(.70*roar,0,0))
        elif action=='telegraph':
            q=smooth(0,.85,t)
            kit.pose(hi,rotation=(-.10*q,0,0))
            kit.pose(head,location=(0,(.06 if i==3 else .30)*q,-.40*q),rotation=(-.45*q,0,0))
            kit.pose(jaw,rotation=(.75*q,0,0))
        elif action=='attack':
            s=math.sin(math.pi*smooth(0,.50,t)); r=math.sin(math.pi*smooth(.42,1,t))
            kit.pose(hi,rotation=(.10*s-.08*r,0,0))
            kit.pose(head,location=(0,-.35*s,.30*s-.14*r),rotation=(.50*s-.10*r,0,0))
            kit.pose(jaw,rotation=(.56*(1-smooth(.08,.38,t))+.12*r,0,0))
        elif action=='hurt':
            kit.pose(head,location=(0,.05*pulse,-.30*pulse),rotation=(-.45*pulse,side*.25*pulse,0))
            kit.pose(hi,rotation=(-.05*pulse,0,side*.06*pulse))
            kit.pose(jaw,rotation=(.25*pulse,0,0))
        elif action=='phase_change':
            kit.pose(lo,rotation=(0,0,.06*math.sin(t*math.tau*3+i)*pulse))
            kit.pose(head,rotation=(-.12*pulse,0,0))
            kit.pose(jaw,rotation=(.48*pulse,0,0))
        elif action=='defeat':
            q=smooth(.34+i*.025,1,t)
            cross=smooth(.04+i*.025,.54,t)
            # Cross the branches first, then compress the interleaved heap.
            direction=-1 if i in (0,1) else 1
            kit.pose(lo,rotation=(.08*q,0,direction*.16*cross),scale=(1,1-.60*q,1))
            kit.pose(hi,location=(-x*.65*cross,.08*cross,(.10 if i%2 else -.10)*cross),rotation=(.12*q,0,direction*.90*cross))
            kit.pose(head,location=(-x*.20*cross,-.16*q,0),rotation=(.25*q,0,direction*.16*cross))
            kit.pose(jaw,rotation=(.28*(1-q),0,0))
        elif action=='retreat':
            q=smooth(i*.035,1,t)
            kit.pose(lo,scale=(1,1-.83*q,1),rotation=(0,side*.25*q,0))
            kit.pose(hi,rotation=(.25*q,0,side*.35*q))
            kit.pose(head,rotation=(.38*q,0,0))


def build(out_dir,quick=False):
    kit=BossBuilder('merge_conflict_hydra',__file__,revision=RECIPE_REVISION,quick=quick)
    kit.material('plum','673d78',roughness=.38,metallic=.15,grunge=.04)
    kit.material('magenta','d46ad4',roughness=.36,metallic=.15,grunge=.03)
    kit.material('dark','182336',roughness=.44,metallic=.5,grunge=.05)
    kit.material('lilac','c2b8ff',finish='plain',roughness=.28,metallic=.12,emission='a99bff',emission_energy=.65,grunge=0)
    kit.material('commit','a99bff',finish='plain',roughness=.4,metallic=.08,emission='a99bff',emission_energy=.20,grunge=0)
    kit.material('throat','702d49',finish='plain',roughness=.6,metallic=0,emission='ff7185',emission_energy=.3,grunge=0)
    kit.bone('root',(0,0,0),(0,.2,0))
    kit.bone('knot',(0,.05,-.3),(0,.4,-.3),'root')
    knot=Part('braided_merge_knot')
    # One continuous (2,3) trefoil with alternating over/under crossings.
    angles=[k*math.tau/72 for k in range(73)]
    points=[(.45*(2+math.cos(3*a))*math.cos(2*a),
             .08+.42*math.sin(3*a),-.10+.18*(2+math.cos(3*a))*math.sin(2*a)) for a in angles]
    knot.tube('plum',points,.285,sides=10)
    knot.tube('magenta',[(a,b,c+.24) for a,b,c in points],.055,sides=6)
    knot.cylinder('magenta',.32,.12,xform((0,.16,.40),(math.pi/2,0,0)),segments=12,bevel=.025)
    knot.ring('commit',.23,.032,xform((0,.16,.49),(math.pi/2,0,0)),segments=16,sides=4)
    kit.add_part(knot,'knot')
    for i,(x,y,z) in enumerate(HEADS):
        points=neck_path(i); mid=points[15]
        crown=1.05 if i==3 else 1.0
        # Geometry and jaw hinge share a rest pitch; animations add to that pose.
        head_xform=xform((x,y,z),(HEAD_PITCH-(.12 if i==3 else 0),0,0),(crown,)*3)
        def hp(p): return head_xform @ Vector(p)
        def mount(part,bone):
            for v in part.bm.verts: v.co=hp(v.co)
            return kit.add_part(part,bone)
        gate,lo,hi,head,jaw=(f'{n}_{i}' for n in ('branch','neck_lo','neck_hi','head','jaw'))
        for name,origin,parent in [(gate,ROOTS[i],'knot'),(lo,ROOTS[i],gate),(hi,mid,lo),(head,(x,y,z),hi),(jaw,hp((0,-.17,-.10)),head)]:
            kit.bone(name,origin,(origin[0],origin[1]+.2,origin[2]),parent)
        neck=Part(f'branch_tube_{i}')
        neck.tube('plum',points,.29,sides=12,radius_end=.20)
        neck.tube('magenta',[(a,b,c+.255) for a,b,c in points],.06,sides=6,radius_end=.045)
        weight_neck(kit.add_part(neck,lo),i,points)
        for k in (4,9,14,19,24):
            p=Vector(points[k])+Vector((0,0,.255-k*.001))
            node=Part(f'commit_{i}_{k}')
            node.cylinder('commit',.12,.048,xform(p,(math.pi/2,0,0)),segments=10)
            node.cylinder('dark',.044,.018,xform(p+Vector((0,0,.03)),(math.pi/2,0,0)),segments=8)
            # The nodes use the same smooth weights as their underlying branch.
            weight_neck(kit.add_part(node,lo),i,points)
        skull=Part(f'serpent_head_{i}')
        skull.prism('plum',[(-.48,-.16),(-.55,.04),(-.46,.30),(-.28,.41),(.28,.41),(.46,.30),(.55,.04),(.48,-.16)],.57,bevel=.055,segments=3)
        snout=Part(f'wedge_snout_{i}')
        snout.prism('magenta',[(-.36,-.12),(-.43,.04),(-.26,.21),(.26,.21),(.43,.04),(.36,-.12)],.86,xform((0,-.01,.52)),bevel=.045,segments=2)
        for v in snout.bm.verts:
            taper=max(0,min(1,(v.co.z-.09)/.86))
            v.co.x*=1-.50*taper
            v.co.y-=.12*taper
        mount(snout,head)
        for sign in [-1,1]:
            # Pupil-free slits under inward-descending brows keep the open roar hostile.
            eye=xform((sign*.265,.235,.61),(-.22,sign*.13,sign*math.radians(25)))
            skull.prism('dark',[(-.15,-.048),(-.14,.063),(.14,.063),(.15,-.048)],.045,eye,bevel=.012)
            skull.prism('lilac',[(-.13,-.0225),(-.12,.0225),(.12,.0225),(.13,-.0225)],.025,eye@xform((0,0,.03)),bevel=.006)
            skull.box('plum',(.289 if i==3 else .34,.08,.10),eye@xform((0,.054,.025)),bevel=.018,segments=2)
            skull.tube('plum',[(sign*.44,.24,-.12),(sign*.60,.46,-.31),(sign*.59,.57,-.44)],.10,sides=8,radius_end=.012)
            skull.box('dark',(.022,.014,.10),xform((sign*.125,.096,.835),(.12,sign*math.radians(30),0)),bevel=.005,segments=1)
            for k in range(3):
                skull.cylinder('lilac',.040,.18,xform((sign*(.34-k*.05),-.21-k*.035,.31+k*.225),(math.pi+.18,0,0)),segments=6,radius_top=.004)
        # A dark seam separates the crown armour from the facial shell.
        skull.box('dark',(.88,.024,.59),xform((0,.27,-.015)),bevel=.007,segments=1)
        plates=[ [(-.64,.02),(-.40,-.15),(.53,-.15),(.53,.19),(-.40,.19)],
                 [(-.52,-.14),(.52,-.14),(.58,.04),(.45,.25),(-.45,.25),(-.58,.04)],
                 [(-.53,-.15),(.40,-.15),(.64,.02),(.40,.19),(-.53,.19)],
                 [(-.53,-.14),(.53,-.14),(.54,.12),(.24,.15),(0,.23),(-.24,.15),(-.54,.12)] ]
        skull.prism('plum',plates[i],.13,xform((0,.52 if i==3 else .53,.03)),bevel=.025,segments=2)
        skull.box('dark',(1.0,.30,.025),xform((0,.54 if i==3 else .55,.11)),bevel=.024)
        skull.box('lilac',(.94,.025,.018),xform((0,.72 if i==3 else .715,.12)),bevel=.006,segments=1)
        mount(marker_part(i,(0,.54 if i==3 else .55,.135)),head)
        mount(skull,head)
        lower=Part(f'articulated_jaw_{i}')
        lower.prism('plum',[(-.40,-.04),(-.34,-.14),(.34,-.14),(.40,-.04),(.38,.055),(-.38,.055)],.91,xform((0,-.235,.46)),bevel=.038,segments=3)
        for v in lower.bm.verts:
            taper=max(0,min(1,(v.co.z-.04)/.91))
            v.co.x*=1-.35*taper
            v.co.y-=.10*taper
        lower.box('throat',(.50,.03,.70),xform((0,-.185,.45)),bevel=.012)
        for sign in [-1,1]: lower.cylinder('lilac',.042,.22,xform((sign*.245,-.115,.73)),segments=6,radius_top=.007)
        mount(lower,jaw)
        if i<3:
            kit.socket(f'muzzle_{i}',jaw,hp((0,-.20,.94)))
            kit.socket(f'fx_{i*2}',lo,points[7]); kit.socket(f'fx_{i*2+1}',hi,points[21])
    kit.socket('fx_core','knot',(0,.16,.49))
    kit.bake_actions(DURATIONS,pose)
    report=kit.export(out_dir)
    font_path=Path(bpy.utils.system_resource('DATAFILES')) / 'fonts/DejaVuSansMono.woff2'
    report['glyph_font']={'name':'DejaVu Sans Mono','source':'Blender DATAFILES/fonts/DejaVuSansMono.woff2',
                          'license':'Bitstream Vera and DejaVu Fonts License',
                          'sha256':hashlib.sha256(font_path.read_bytes()).hexdigest(),
                          'usage':'Converted glyph outlines only; font file is not redistributed.'}
    report_path=Path(out_dir)/kit.kind/(kit.kind+'.build.json')
    report_path.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir',type=Path,default=Path('Assets/runner/bosses'))
    parser.add_argument('--quick',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    build(args.out_dir,args.quick)
