"""Original deterministic arcade cue sketches; no sampled or third-party audio."""
from pathlib import Path
import json
import math
import random
import struct
import wave

PACK = Path(__file__).resolve().parents[1]/'hoppys-adventure-arcade/Assets/heroes-vs-villains-assets-only'
OUT = PACK/'audio'
OUT.mkdir(exist_ok=True)
RATE = 44100
CUES = {
    'reveal_ai_slop': ([98, 116.54, 87.31, 196], .18, .18),
    'reveal_agent_army': ([220, 220, 329.63, 220, 440], .11, .05),
    'reveal_ten_thousand_line_pr': ([65.41, 65.41, 49, 130.81], .23, .22),
    'reveal_ai_augmented_hacker': ([392, 622.25, 415.30, 783.99, 196], .10, .12),
    'agent_spawn': ([220, 440, 880], .07, .10),
    'pr_stack_collapse': ([130.81, 98, 65.41, 49], .12, .65),
    'machine_speed_whoosh': ([1760, 1174.66, 587.33, 293.66], .045, .55),
    'capability_unlock': ([261.63, 329.63, 392, 523.25, 783.99], .14, 0),
}
manifest = {}
for index, (name, (notes, length, noise)) in enumerate(CUES.items()):
    rng = random.Random(index)
    samples = []
    for note in notes:
        count = round(length*RATE)
        for i in range(count):
            t = i/RATE
            envelope = min(1, t/.008) * max(0, 1-i/count)**1.5
            tone = (math.sin(2*math.pi*note*t)+.25*math.sin(2*math.pi*note*2*t)+.12*math.sin(2*math.pi*note*3*t)) / 1.37
            samples.append(.65*envelope*((1-noise)*tone+noise*rng.uniform(-1,1)))
    samples.extend([0.0]*round(.06*RATE))
    with wave.open(str(OUT/(name+'.wav')), 'wb') as wav:
        wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(b''.join(struct.pack('<h',round(s*32767)) for s in samples))
    manifest[name] = dict(file=name+'.wav', seconds=len(samples)/RATE, peak=max(abs(s) for s in samples),
                          status='Original synthesized v1 cue; mix/playtest with combat later.')
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Built 8 mono 44.1kHz original WAV cues')
