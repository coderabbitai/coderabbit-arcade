# The Enchanted Repo music

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik grants their use in the game. The soundtrack plan is [`docs/soundtrack.md`](../../../../../docs/soundtrack.md).

| File | Plays | Suno song | Measured tempo and key | Loop |
|---|---|---|---|---|
| `enchanted_repo_level.ogg` | Traversal, a fresh retry and after the boss | [`bdf91076-2a2d-436e-b63a-5e0b9ce120a7`](https://suno.com/song/bdf91076-2a2d-436e-b63a-5e0b9ce120a7) | 94.6 BPM; opens in D minor, settles in C minor | Intro 0–38.545 s plays once, then 40 bars (101.4 s) repeat to the file end at 139.952 s |
| `enchanted_repo_boss.ogg` | The Legacy Monolith, from its 1.8 s intro through the fight | [`d862d240-6c51-4948-bac5-c5966c59f822`](https://suno.com/song/d862d240-6c51-4948-bac5-c5966c59f822) | 176.0 BPM; D minor throughout | Opening hit 0–6.641 s plays once, then 44 bars (60.0 s) repeat to the file end at 66.658 s |

## enchanted_repo_level: "The Enchanted Repo"

Styles:

```text
16-bit fantasy chiptune, SNES-era adventure stage, instrumental, 90 BPM, D dorian, mysterious enchanted forest and ruined castle, soft square-wave lead with a wistful singable melody, harp-like pulse arpeggios, breathy ocarina patch, warm triangle bass, light noise-channel shuffle, bell sparkles, three-note rising motif, steady energy, loopable, ends on the downbeat
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration auto, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Four takes were compared: two from this prompt (`cf2ff1d8-a0f9-48ac-8891-ea899106824e` and this one) and two from a variant that also asked for "D dorian from start to finish with no key change" at a 2:30 length (`848dcea0-7492-43dd-86ca-45daee7efa64`, `ef9846cc-8488-4ddb-b669-61a60f9f37df`). This take scored highest on Meta's audiobox-aesthetics model (content enjoyment 7.22, production quality 8.15), holds a steady 94.6 BPM, and its long C-minor second half gives the cleanest loop.

## enchanted_repo_boss: "The Legacy Monolith"

Styles:

```text
16-bit chiptune boss battle, SNES-era RPG fight, instrumental, 172 BPM, D minor, menacing ancient stone guardian awakening, driving FM bass ostinato, aggressive square-wave lead, pipe organ patch, orchestra hits, pounding noise-channel toms, heroic counter-melody, huge downbeat in the first second, relentless energy, loopable
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration auto, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Two takes were compared (the other is `87329abf-d859-44be-ae17-6c685e7713ac`). This one stays in D minor, the key the level opens in; its beat grid is the tightest of any take (every tracked beat within 8 ms of a straight 176 BPM line); and it scored higher on content enjoyment (6.86 against 6.73) and production quality (7.54 against 7.35). The other take drifts to E minor after two minutes.

## Delivery

From Suno's 48 kHz WAV, each track was:

1. normalized as a whole to about −14 LUFS integrated and −1 dBTP with ffmpeg's two-pass `loudnorm` (linear gain), then resampled to 44.1 kHz stereo, before any cut;
2. cut on bar lines: the loop start and length were chosen by matching the bars around the loop end with the bars around the loop start (chroma, MFCC and level), the end sample was aligned to the start by waveform correlation, and an 8 ms equal-power crossfade into the audio just before the loop start was baked into the last samples;
3. encoded with `oggenc -q 6` (reference libvorbis), keeping Suno's embedded comment with the song ID and creation time.

Three decoded loop cycles were checked for a seam click: the sample step at the seam is below the 99th percentile of the track's own steps, and the seam's spectral flux is within 15% of the same downbeat heard without a cut (level 1.04×, boss 0.89×).

The `.import` files set `loop`, `loop_offset`, `bpm` and `bar_beats`. `beat_count` stays 0 on purpose: when both `bpm` and `beat_count` are set, Godot 4.7's Ogg player loops after `beat_count` beats measured from the start of the file (`modules/vorbis/audio_stream_ogg_vorbis.cpp`), which would override the sample-accurate loop end.
