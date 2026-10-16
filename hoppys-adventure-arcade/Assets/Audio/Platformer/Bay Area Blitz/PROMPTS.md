# Bay Area Blitz music

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. The soundtrack plan is [`docs/soundtrack.md`](../../../../../docs/soundtrack.md).

| File | Plays | Suno song | Measured tempo and key | Loop |
|---|---|---|---|---|
| `bay_area_blitz_level.ogg` | Traversal, a fresh retry and after the boss | [`a8e41f8f-b51e-4183-bfb1-ce443b45a9f1`](https://suno.com/song/a8e41f8f-b51e-4183-bfb1-ce443b45a9f1) | 132.2 BPM; G major | Intro 0–16.533 s plays once, then 32 bars (58.3 s) repeat to the file end at 74.789 s |
| `bay_area_blitz_boss.ogg` | The Merge Conflict Monster, from its 1.8 s intro through the fight | [`39eb48db-aa22-457e-b132-a1c1e302fe99`](https://suno.com/song/39eb48db-aa22-457e-b132-a1c1e302fe99) | 160.9 BPM; G minor, the level key's parallel minor | Opening 0–10.670 s plays once, then 36 bars (53.7 s) repeat to the file end at 64.358 s |

## bay_area_blitz_level: "Cable Car Hop"

Styles:

```text
sunny 16-bit platformer chiptune, SNES-era first-stage music, instrumental, 128 BPM, G major, bouncy square-wave lead with a catchy whistleable hook, hopping triangle bassline in octaves, crisp noise-channel snare and hi-hats, cable-car bell sparkles, light FM brass stabs, carefree Saturday-morning optimism, three-note rising motif, steady groove, stays in G major, seamless loop, ends on the downbeat
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `f3999d43-434c-4a44-8451-09027f9c4042`. This one holds G major almost throughout (the other drifts between D major and B minor) and scored higher on both content enjoyment and production quality. Audiobox-aesthetics: content enjoyment 7.19, production quality 8.24.

Delivery: +1.8 dB to about −14 LUFS (linear gain); the OGG measures -14.1 LUFS and -3.7 dBTP. Seam over three decoded cycles: step 0.009 against a 99th-percentile step of 0.106; flux 0.94× the same downbeat heard uncut.

## bay_area_blitz_boss: "Merge Conflict Monster"

Styles:

```text
16-bit chiptune boss battle, SNES-era action fight, instrumental, 160 BPM, G minor, two rival square-wave leads arguing in call and response, crashing FM bass ostinato, orchestra hits, pounding noise-channel toms, urgent playful menace, huge downbeat in the first second, stays in G minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `df4d7099-49f9-4ce9-b902-346b2ffb014f`. Both stay in G minor; this one runs 89 s against 70 s, so the loop can be longer, and it scored higher on enjoyment and production quality. Audiobox-aesthetics: content enjoyment 6.81, production quality 7.68.

Delivery: +1.5 dB to about −14 LUFS (linear gain); the OGG measures -14.2 LUFS and -3.2 dBTP. Seam over three decoded cycles: step 0.037 against a 99th-percentile step of 0.107; flux 1.31× the same downbeat heard uncut.

## How these files were made

From Suno's 48 kHz WAV, each track was normalized as a whole to about −14 LUFS integrated and −1 dBTP (gain, plus a lookahead limiter only where peaks would pass the ceiling), resampled to 44.1 kHz, and cut on bar lines. The loop start and length were chosen by matching the bars around the loop end with the bars around the loop start (chroma, MFCC and level), the end sample was aligned to the start by waveform correlation, and an 8 ms equal-power crossfade into the audio just before the loop start was baked into the last samples. Files were encoded with `oggenc -q 6` (reference libvorbis), keeping Suno's embedded comment with the song ID and creation time.

The `.import` files set `loop`, `loop_offset`, `bpm` and `bar_beats`. `beat_count` stays 0 so Godot loops at the sample-accurate file end (see `docs/soundtrack.md`).
