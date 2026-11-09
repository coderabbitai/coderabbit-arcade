# Heroes vs. Villains music

Stage 2 and the three boss tracks are music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. Stages 1 and 3 are original procedural chiptunes, CC0 1.0, built by `tools/build_heroes_villains_stage_music.py` ([below](#stages-1-and-3-procedural)); Erik's earlier takes for those stages are kept in the credits and recorded under [Retired takes](#retired-takes). These cues belong to the theme family in [`docs/soundtrack.md`](../../../../../docs/soundtrack.md) section B: about 116 BPM, F major for the heroes' first stage and F minor for the villains, with the three-note motif rising for heroes and inverted for villains. The theme itself, "Send in the Rabbit", measured F major at 118.3 BPM (`Assets/Audio/Main Menu/PROMPTS.md`).

| File | Plays | Source | Measured tempo and key | Loop |
|---|---|---|---|---|
| `heroes_villains_generation_floor.ogg` | Stage 1 and the Heroes vs. Villains menu | Procedural: `python3 tools/build_heroes_villains_stage_music.py --stage generation_floor`. Original, CC0 1.0 | 124 BPM; F major, the theme's key | Intro 0–7.742 s (4 bars) plays once, then 32 bars (61.9 s) repeat to the file end at 69.677 s |
| `heroes_villains_review_gauntlet.ogg` | Stage 2 | [`66efb6fe-d2df-4880-9da0-395638783b62`](https://suno.com/song/66efb6fe-d2df-4880-9da0-395638783b62) | 116.0 BPM; F minor | Intro 0–16.324 s plays once, then 32 bars (66.2 s) repeat to the file end at 82.492 s |
| `heroes_villains_agentic_core.ogg` | Stage 3 | Procedural: `python3 tools/build_heroes_villains_stage_music.py --stage agentic_core`. Original, CC0 1.0 | 134 BPM; F minor | Intro 0–7.164 s (4 bars) plays once, then 32 bars (57.3 s) repeat to the file end at 64.478 s |
| `heroes_villains_boss_ai_slop.ogg` | AI SLOP, stage 1's boss | [`5b0c85b7-6ce7-4e6e-898e-5305512e202e`](https://suno.com/song/5b0c85b7-6ce7-4e6e-898e-5305512e202e) | 117.4 BPM; F minor | Opening 0–13.572 s plays once, then 24 bars (49.0 s) repeat to the file end at 62.622 s |
| `heroes_villains_boss_agent_army.ogg` | The Coding Agent Army and the 10,000-Line PR, stage 2's bosses | [`0a633def-4f1b-4f92-9800-bc85ba997204`](https://suno.com/song/0a633def-4f1b-4f92-9800-bc85ba997204) | 116.0 BPM; F (minor and major), on the theme's tonic | Opening 0–10.182 s plays once, then 32 bars (66.2 s) repeat to the file end at 76.382 s |
| `heroes_villains_boss_hacker.ogg` | The AI-Augmented Hacker, the final boss | [`650e1d9a-5772-4220-ab3e-3c9ac4779c20`](https://suno.com/song/650e1d9a-5772-4220-ab3e-3c9ac4779c20) | 116.7 BPM; F minor | Opening 0–10.310 s plays once, then 24 bars (49.4 s) repeat to the file end at 59.665 s |

## Stages 1 and 3 (procedural)

Issue #98: Erik's Suno takes for these two stages fit them less well than the Review Gauntlet track fits stage 2. Both were replaced with original chiptunes written for their stages. At the user's direction, they take their energy and instruments from Code City Brawl's Genesis FM street-brawler music: FM slap bass, brass-like FM stabs, breakbeat drums and square arpeggios. They keep this game's identity, though: the F major and F minor keys, the heroes' rising and the villains' falling motif, and their own tunes. The two games don't share material. The boss tracks stay at about 116 BPM; the dip-and-swap fades the stage track out before the boss track starts, so the tempo change lands cleanly.

- **The Generation Floor** (stage 1, a bright white and orange expo hall with the easiest enemies), 124 BPM: a heroic brawler groove, not a toy commercial. Syncopated FM slap bass popping the octave, brass stabs (on the one and the anticipation in A, on the offbeats in B), a high 25% square sparkle arpeggio sweeping left to right, and a breakbeat with ghost snares and claps. The brassy FM lead is doubled an octave up on a square and opens every A section on the rising F-A-C motif, with a dotted-eighth ping-pong echo. In the intro, brass hits ring the motif twice, the break kicks in, and a snare roll leads into bar 1. Form: A, A with a harmony, B, B with harmony (F–F–Dm–B♭–F–C–B♭–C; B♭–C–Am–Dm–B♭–C–Gm–C).
- **The Agentic Core** (stage 3, a dark red and green machine core and the fastest stage, with 0.32 s drone tells), 134 BPM: a dark, driving brawler that gets going at once. The old take's 27.9 s intro is now 7.2 s. It has a relentless, gritty 16th-note FM bass with a triangle sub, a heavy break with metallic hits on the "and" of four, brass hits, and a scanning arpeggio that pans across the stereo field. The cold FM lead plays the villains' falling C-A♭-F motif. Short 6-bit data-glitch stutters close the phrases of the last section. Form: A sparse (motif only), A, B with harmony, B with glitches (Fm–Fm–D♭–D♭–B♭m–B♭m–C–C; D♭–E♭–Fm–Fm–D♭–E♭–C–C).

Both are 44.1 kHz stereo. Every voice, echo and stutter that runs past the file end wraps to the loop start, and the output low-pass starts the body in its settled loop state, so the seam has no gap, fade or click: after encoding, the wrap step is 396 and 306 against a 99th-percentile step of about 4,000. A soft limiter above 0.6 holds the peaks.

Rebuild from the repository root, then encode with reference libvorbis (`brew install vorbis-tools`):

```sh
python3 tools/build_heroes_villains_stage_music.py --stage generation_floor --out /tmp/hvv
python3 tools/build_heroes_villains_stage_music.py --stage agentic_core --out /tmp/hvv
oggenc -q 6 -o "hoppys-adventure-arcade/Assets/Audio/Beat'em Up/Hero vs Villian/heroes_villains_generation_floor.ogg" /tmp/hvv/heroes_villains_generation_floor.wav
oggenc -q 6 -o "hoppys-adventure-arcade/Assets/Audio/Beat'em Up/Hero vs Villian/heroes_villains_agentic_core.ogg" /tmp/hvv/heroes_villains_agentic_core.wav
```

The WAVs are byte-for-byte reproducible (SHA-256 `91a2c18b…ebe5` and `23bb2a71…6961`). The OGGs measure −14.0 and −13.9 LUFS integrated and −1.3 and −1.5 dBTP, and decode to exactly 3,072,774 and 2,843,463 frames.

## heroes_villains_review_gauntlet: "The Review Gauntlet"

Styles:

```text
grinding heavy 16-bit chiptune, beat-em-up gauntlet stage, instrumental, 116 BPM half-time march, F minor, three-note motif in minor, stacking tension, FM brass, chugging FM bass, noise-channel snare rolls, determined and gritty, stays in F minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `2b7a81e1-004a-4bb2-8879-d4f779b45ea1`. Both hold F minor at 116 BPM; this one scored higher on enjoyment (7.04 against 6.93) and production quality (7.78 against 7.69). Audiobox-aesthetics: content enjoyment 7.04, production quality 7.78.

Delivery: +0.4 dB to about −14 LUFS (linear gain); the OGG measures -14.1 LUFS and -3.9 dBTP. Seam over three decoded cycles: step 0.000 against a 99th-percentile step of 0.127; flux 1.16× the same downbeat heard uncut.

## heroes_villains_boss_ai_slop: "AI SLOP"

Styles:

```text
Saturday-morning cartoon villain battle, 16-bit FM chiptune, instrumental, 116 BPM with a frantic double-time feel, F minor, campy goopy menace, wobbly detuned square lead, sloppy pitch-bend slides, orchestra-hit stabs, chromatic runs, three-note motif in minor, huge downbeat in the first second, stays in F minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 45%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `d94c532c-6c7b-4aba-952e-22b6c374d25e`. This one keeps F minor and a tight grid, and scored higher on enjoyment (7.10 against 6.91) and production quality (7.69 against 7.50). Audiobox-aesthetics: content enjoyment 7.1, production quality 7.69.

Delivery: +1.6 dB to about −14 LUFS (linear gain); the OGG measures -14.0 LUFS and -3.1 dBTP. Seam over three decoded cycles: step 0.053 against a 99th-percentile step of 0.086; flux 1.13× the same downbeat heard uncut.

## heroes_villains_boss_agent_army: "Agent Army and the 10,000-Line PR"

Styles:

```text
Saturday-morning cartoon villain battle, 16-bit FM chiptune, instrumental, 116 BPM with a double-time feel, F minor, marching mechanical robot legion, relentless sixteenth-note FM sequencer bass, stacked brass stabs, snare-roll march, towering orchestra hits, three-note motif in minor, huge downbeat in the first second, stays in F minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 40%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `b1db0377-4964-4985-a2dd-1758d2d97632`. This was the highest-scoring take of the whole soundtrack (enjoyment 7.67, production quality 8.45); the other drifted to D minor and faded out. Audiobox-aesthetics: content enjoyment 7.67, production quality 8.45.

Delivery: +3.1 dB to about −14 LUFS (linear gain); the OGG measures -13.9 LUFS and -2.2 dBTP. Seam over three decoded cycles: step 0.055 against a 99th-percentile step of 0.056; flux 1.04× the same downbeat heard uncut.

## heroes_villains_boss_hacker: "Machine-Speed Hacker"

Styles:

```text
Saturday-morning cartoon villain battle, 16-bit FM chiptune, instrumental, 116 BPM with a 232 BPM double-time feel, F minor, machine-speed hacker menace, rapid-fire glitch arpeggios, bitcrushed stutter edits, sawtooth FM lead, breakneck noise drums, orchestra hits, inverted three-note motif, huge downbeat in the first second, stays in F minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 45%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `ab00eb2c-ed61-409b-b068-2560d122916e`. Both hold F minor; this one scored higher on enjoyment (6.97 against 6.78) and production quality (7.89 against 7.74). Audiobox-aesthetics: content enjoyment 6.97, production quality 7.89.

Delivery: +1.6 dB to about −14 LUFS (linear gain); the OGG measures -14.3 LUFS and -3.8 dBTP. Seam over three decoded cycles: step 0.015 against a 99th-percentile step of 0.117; flux 1.21× the same downbeat heard uncut.

## Retired takes

Erik Thorelli's Suno takes for stages 1 and 3 were removed from the build in issue #98 and stay in the credits. Their prompts are kept here for the record.

### heroes_villains_generation_floor (retired): "The Generation Floor"

Styles:

```text
hyperactive 16-bit chiptune, Saturday-morning cartoon brawler stage, instrumental, 116 BPM, F major, comically busy bouncy arpeggios, square-wave lead with a big singable chorus melody, hopping triangle bass in octaves, noise-channel drums, handclap samples, three-note rising glockenspiel-like chime motif, toy-commercial energy, stays in F major, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `b5f8613e-32cb-4c2f-a925-b35093f2b1aa`. This one lands in F major (the other sits in C major), keeps a tight 116.9 BPM grid, and scored higher on enjoyment (6.90 against 6.69) and production quality (8.12 against 7.83). Audiobox-aesthetics: content enjoyment 6.9, production quality 8.12.

Delivery: +1.2 dB to about −14 LUFS (linear gain); the OGG measures -14.1 LUFS and -2.8 dBTP. Seam over three decoded cycles: step 0.031 against a 99th-percentile step of 0.115; flux 1.03× the same downbeat heard uncut.


### heroes_villains_agentic_core (retired): "The Agentic Core"

Styles:

```text
tense techno-chiptune, machine core stage, instrumental, 116 BPM, F minor, pulsing square-wave bass, cold FM leads, scanning arpeggios, inverted three-note motif, four-on-the-floor noise kick, data-stream glitches, rising dread, stays in F minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 40%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `5b24787f-eb75-4003-a378-e4f827d3e450`. The two scored the same on enjoyment and production quality; this one stays in F minor throughout (the other slides into E♭ minor) and has the wider dynamic range for the stage's rising dread. Audiobox-aesthetics: content enjoyment 7.16, production quality 8.12.

Delivery: +1.0 dB to about −14 LUFS (linear gain); the OGG measures -14.7 LUFS and -2.9 dBTP. Seam over three decoded cycles: step 0.050 against a 99th-percentile step of 0.124; flux 0.98× the same downbeat heard uncut.

## How these files were made

This covers the Suno tracks. From Suno's 48 kHz WAV, each track was normalized as a whole to about −14 LUFS integrated and −1 dBTP (gain, plus a lookahead limiter only where peaks would pass the ceiling), resampled to 44.1 kHz, and cut on bar lines. The loop start and length were chosen by matching the bars around the loop end with the bars around the loop start (chroma, MFCC and level), the end sample was aligned to the start by waveform correlation, and an 8 ms equal-power crossfade into the audio just before the loop start was baked into the last samples. Files were encoded with `oggenc -q 6` (reference libvorbis), keeping Suno's embedded comment with the song ID and creation time.

The `.import` files set `loop`, `loop_offset`, `bpm` and `bar_beats`. `beat_count` stays 0 so Godot loops at the sample-accurate file end (see `docs/soundtrack.md`). These shared imports keep `loop` off: `modes/beatem_up/reinvent/catalog.gd` loops a private copy (`Catalog.looped`), which inherits `loop_offset`.
