"""Native Godot asset staging and editable action-figure card layouts."""
import json
from build_heroes_villains_pack import PACK, BASE

MANIFEST = json.loads((PACK/'heroes_villains/manifest.json').read_text())
DEST = PACK/'presentation'
DEST.mkdir(exist_ok=True)


class Scene:
    def __init__(self, name, control=False):
        self.ext = []
        self.nodes = [f'[node name="{name}" type="{"Control" if control else "Node2D"}"]', 'texture_filter = 1']
        if control:
            self.nodes += ['layout_mode = 3', 'anchors_preset = 15', 'anchor_right = 1.0', 'anchor_bottom = 1.0', 'grow_horizontal = 2', 'grow_vertical = 2']

    def resource(self, type, path, root=BASE):
        id = str(len(self.ext)+1)
        self.ext.append(f'[ext_resource type="{type}" path="{root}{path}" id="{id}"]')
        return f'ExtResource("{id}")'

    def node(self, name, type, props, parent='.'):
        self.nodes += [f'[node name="{name}" type="{type}" parent="{parent}"]', *props]

    def rect(self, name, x, y, w, h, color, parent='.'):
        self.node(name, 'ColorRect', [f'offset_left = {float(x)}', f'offset_top = {float(y)}', f'offset_right = {float(x+w)}', f'offset_bottom = {float(y+h)}', f'color = Color({color})', 'mouse_filter = 2'], parent)

    def label(self, name, text, x, y, w, h, size=24, color='1, 0.94, 0.86, 1'):
        self.node(name, 'Label', [f'offset_left = {float(x)}', f'offset_top = {float(y)}', f'offset_right = {float(x+w)}', f'offset_bottom = {float(y+h)}', 'theme_override_colors/font_color = Color('+color+')', f'theme_override_font_sizes/font_size = {size}', 'text = '+json.dumps(text,ensure_ascii=False), 'autowrap_mode = 2', 'mouse_filter = 2'])

    def sprite(self, name, resource, animation, x, y, scale=1, parent='.'):
        a = MANIFEST['atlases'][resource]
        ref = self.resource('SpriteFrames', f'heroes_villains/{resource}.tres')
        self.node(name, 'AnimatedSprite2D', [f'position = Vector2({x}, {y})', f'scale = Vector2({scale}, {scale})', f'sprite_frames = {ref}', f'animation = &"{animation}"', 'centered = false', f'offset = Vector2({-a["pivot"][0]}, {-a["pivot"][1]})'], parent)

    def save(self, name):
        (DEST/(name+'.tscn')).write_text('\n\n'.join([f'[gd_scene load_steps={len(self.ext)+1} format=3]', *self.ext, '\n'.join(self.nodes)])+'\n')


stages = [
    ('generation_floor','THE GENERATION FLOOR','generation_kit','expo_truss','barrier',
     [('hoppy','idle',260,606,2),('slop_sprite','idle',460,596,1.4),('hallucinated_api_gremlin','attack_warning',645,580,1.7),('ai_slop','idle',1040,620,1.7)]),
    ('review_gauntlet','THE REVIEW GAUNTLET','review_kit','gantry','conveyor',
     [('hoppy','idle',245,620,2),('change_stack_soldier','idle',480,622,1.7),('agent_army','fused_idle',737,610,1.35),('ten_thousand_line_pr','idle',1045,626,1.6)]),
    ('agentic_core','THE AGENTIC CORE','core_kit','cables','foreground_rail',
     [('hoppy','scanner',245,622,2),('security_gap_crawler','idle',465,620,1.3),('vulnerability_injector','attack_warning',690,604,1.6),('ai_augmented_hacker','idle',1035,629,1.75)]),
]
for id, title, kit, mid, near, actors in stages:
    s=Scene(title.replace(' ',''))
    s.node('Far','Parallax2D',['scroll_scale = Vector2(0.1, 0.1)'])
    ref=s.resource('Texture2D',f'heroes_villains/{id}.png')
    s.node('Panorama','Sprite2D',[f'texture = {ref}', 'centered = false'],'Far')
    s.node('Mid','Parallax2D',['scroll_scale = Vector2(0.3, 0.3)'])
    s.sprite('MidDecoration',kit,mid,110,230,1.1,'Mid')
    s.node('Actors','Node2D',['y_sort_enabled = true'])
    for actor,anim,x,y,scale in actors:
        s.sprite(actor,actor,anim,x,y,scale,'Actors')
    s.node('Near','Parallax2D',['scroll_scale = Vector2(0.6, 0.6)'])
    s.sprite('Foreground',kit,near,1130,696,1.5,'Near')
    s.rect('TitleBack',0,0,1280,111,'0.025, 0.025, 0.035, 0.92')
    s.label('Eyebrow','HEROES vs. VILLAINS / ASSET STAGING',36,18,1180,25,17,'1, 0.42, 0.1, 1')
    s.label('Title',title,34,46,1180,52,36)
    s.rect('FooterBack',0,677,950,43,'0.025, 0.025, 0.035, 0.88')
    s.label('Footer','ART PREVIEW  •  No combat, collisions, waves or progression',34,685,940,30,17)
    s.save(id)

cards = [
    ('ai_slop','AI SLOP','NOW WITH 300% MORE CODE!','ai_slop','idle','INCLUDES\nHallucination Burst\nTracking API barrage\nLGTM force field','DEFEAT REWARD / REVIEW'),
    ('agent_army','THE CODING AGENT ARMY','THE GENERATION DOES NOT STOP.','agent_army','formation','INCLUDES\nSynchronized clone strikes\n50% HP merge transition\nA commander that keeps fighting','PAIRED ENCOUNTER / TRIAGE + CHANGE STACK'),
    ('ten_thousand_line_pr','THE 10,000-LINE PR','147 FILES. ONE VERY BAD DAY.','ten_thousand_line_pr','idle','INCLUDES\nFalling PR-stack slams\nReviewer Nightmare\nOne active merged commander','DEFEAT BOTH / TRIAGE + CHANGE STACK'),
    ('ai_augmented_hacker','THE AI-AUGMENTED HACKER','NOW ATTACKS AT MACHINE SPEED!','ai_augmented_hacker','idle','INCLUDES\nMachine-speed dashes\nInjection Mode\nTwo simultaneous attack vectors','DEFEAT REWARD / SECURITY'),
]


def card_base(title, subtitle):
    s=Scene('BlisterCard',True)
    s.rect('Backdrop',0,0,1280,720,'0.02, 0.02, 0.025, 1')
    s.rect('OrangeCard',36,22,1208,676,'1, 0.25, 0.035, 1')
    s.rect('InkCard',44,30,1192,660,'0.065, 0.06, 0.07, 1')
    s.rect('HangSlot',567,40,146,14,'0.01, 0.01, 0.015, 1')
    s.label('Brand','HOPPY’S ADVENTURE ARCADE   /   VILLAIN COLLECTION',76,66,1110,30,18,'1, 0.47, 0.15, 1')
    s.label('Title',title,74,100,1120,70,42)
    s.rect('BurstBand',64,178,1152,49,'1, 0.25, 0.035, 1')
    s.label('Tagline',subtitle,82,187,1120,38,24,'0.04, 0.03, 0.03, 1')
    s.rect('BlisterBorder',78,247,560,351,'0.55, 0.62, 0.65, 0.8')
    s.rect('BlisterInterior',82,251,552,343,'0.11, 0.12, 0.14, 1')
    s.rect('PlasticHighlight',87,257,6,319,'0.9, 0.96, 1, 0.35')
    s.rect('PlasticTop',93,257,529,3,'0.9, 0.96, 1, 0.22')
    return s


for id,title,tagline,resource,pose,copy,reward in cards:
    s=card_base(title,tagline)
    s.sprite('Figure',resource,pose,355,577,1.45)
    s.label('Accessories',copy,686,273,494,251,27)
    s.label('ProductCopy','COLLECT THE PROBLEM.\nDEPLOY THE SOLUTION.',686,521,494,74,22,'1, 0.48, 0.18, 1')
    s.label('Reward',reward,80,625,1120,42,22)
    s.save('boss_'+id)

for i,(id,title,copy) in enumerate([
    ('review','REVIEW','Trust what ships.\nBlock a hit. Hold to activate a stun burst.'),
    ('triage','TRIAGE','Find the highest threat.\nPut force where it matters.'),
    ('change_stack','CHANGE STACK','Understand what changed.\nCombo finishers leave an impact zone.'),
    ('security','SECURITY','Reveal the hidden attack surface.\nThe codebase is trusted.')]):
    s=card_base(title+' UNLOCKED','THE CODERABBIT / BUILT FOR THE AGENTIC ERA')
    s.sprite('Capability','capabilities_fx',id,350,420,1.8)
    s.label('Description',copy,684,284,493,210,27)
    for j,cap in enumerate(['review','triage','change_stack','security']):
        s.sprite('Light'+str(j),'capabilities_fx',cap,725+j*128,558,.5)
        # Stage 2 grants both capabilities together.
        if j > (2 if i in (1,2) else i):
            s.nodes.append('modulate = Color(0.2, 0.2, 0.2, 1)')
    s.label('Footer','REVIEW. TRIAGE. UNDERSTAND. SECURE.',80,625,1100,45,24)
    s.save('unlock_'+id)

# The opening cards are cinematic story scenes. story_scene.gd shows the catalog's STORY entry
# (illustration, kicker, caption, Ken Burns framing), so the copy lives in reinvent/catalog.gd.
for i,id in enumerate(['opening_situation','opening_complication','opening_resolution']):
    s=Scene('StoryScene',True)
    script=s.resource('Script','res://modes/beatem_up/story_scene.gd',root='')
    catalog=s.resource('Script','res://modes/beatem_up/reinvent/catalog.gd',root='')
    s.nodes += ['mouse_filter = 2', f'script = {script}', f'catalog = {catalog}', f'story_index = {i}']
    s.save(id)

# The victory epilogue after the final boss: the same story scenes over the catalog's ENDING pages.
for i,id in enumerate(['ending_hacker_falls','ending_trust_restored','ending_rabbit_stands']):
    s=Scene('StoryScene',True)
    script=s.resource('Script','res://modes/beatem_up/story_scene.gd',root='')
    catalog=s.resource('Script','res://modes/beatem_up/reinvent/catalog.gd',root='')
    s.nodes += ['mouse_filter = 2', f'script = {script}', f'catalog = {catalog}', f'story_index = {i}', 'pages = "ENDING"']
    s.save(id)

# The victory card uses native text over stage art; no rasterized typography.
for id,title,copy,bg in [
    ('victory','THE CODERABBIT','BUILT FOR THE AGENTIC ERA\nThe CodeRabbit is live. The codebase is trusted.','generation_floor')]:
    s=Scene('StoryPanel',True)
    ref=s.resource('Texture2D',f'heroes_villains/{bg}.png')
    s.node('Background','TextureRect',['offset_right = 1280.0','offset_bottom = 720.0',f'texture = {ref}'])
    s.rect('Dim',0,0,1280,720,'0.025, 0.025, 0.035, 0.86')
    s.rect('Accent',65,103,8,482,'1, 0.25, 0.035, 1')
    s.label('Mode','HEROES vs. VILLAINS / re:Invent EDITION',105,110,1040,40,22,'1, 0.45, 0.13, 1')
    s.label('Title',title,103,185,1050,85,52)
    s.label('Copy',copy,106,306,720,234,31)
    s.sprite('Hoppy','hoppy','victory' if id=='victory' else 'idle',1060,605,3)
    if id=='victory':
        for j,cap in enumerate(['review','triage','change_stack','security']):
            s.sprite(cap,'capabilities_fx',cap,180+j*167,606,.55)
    s.save(id)
print('Built 3 stage previews, 4 villain cards, 4 capability cards, 3 story scenes, 3 ending scenes, 1 victory card')
