# Orbital Ops music

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. The soundtrack plan is [`docs/soundtrack.md`](../../../../../docs/soundtrack.md). The folder keeps its existing spelling, `Obital Ops`.

| File | Plays | Suno song | Measured tempo and key | Loop |
|---|---|---|---|---|
| `orbital_ops_level.ogg` | Traversal, fresh retries and after the boss | [`890b2c7b-a996-47c5-9433-aa7be6e33401`](https://suno.com/song/890b2c7b-a996-47c5-9433-aa7be6e33401) | 145.1 BPM; E minor with chromatic FM colour | Intro 0–59.617 s plays once, then 36 bars (59.5 s) repeat to the file end at 119.134 s |
| `orbital_ops_boss.ogg` | The Deprecated API, from its 1.8 s intro through the fight | [`60dd3680-5dca-406a-9f73-e5b3f8e21a84`](https://suno.com/song/60dd3680-5dca-406a-9f73-e5b3f8e21a84) | 150.0 BPM; E minor, the level's key | Opening 0–8.022 s plays once, then 32 bars (51.2 s) repeat to the file end at 59.217 s |

## orbital_ops_level: "Zero-G Deploy"

Styles:

```text
FM synthesis chiptune, Genesis-style space station stage, instrumental, 145 BPM, E minor lifting to G major, buoyant cosmic adventure, sparkling FM bell arpeggios, slap FM bass, bright square-wave lead melody, gated noise hi-hats, floating half-time zero-gravity breakdown, three-note rising motif, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `08beb3db-7a5a-45cf-898b-967254f4206f`. This one keeps a straight 145 BPM grid (348 of 352 tracked beats within 40 ms of it, against 90 of 355 for the other), which makes a clean loop, and it scored higher on production quality; enjoyment was level. Audiobox-aesthetics: content enjoyment 7.18, production quality 8.13.

Delivery: +1.0 dB to about −14 LUFS (linear gain); the OGG measures -14.3 LUFS and -3.2 dBTP. Seam over three decoded cycles: step 0.021 against a 99th-percentile step of 0.119; flux 1.13× the same downbeat heard uncut.

## orbital_ops_boss: "The Deprecated API"

Styles:

```text
Genesis-style FM chiptune boss battle, instrumental, 150 BPM, E minor, glitchy obsolete-robot menace, stuttering FM bass riff, sharp square-wave lead, laser-zap arpeggios, gated noise snare, alarm stabs, rising tension, huge downbeat in the first second, stays in E minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 40%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `732b9156-e9f2-4366-9975-6efbfb930649`. Both sit in E minor; this one scored higher on content enjoyment (6.80 against 6.56) and production quality (7.70 against 7.53). Audiobox-aesthetics: content enjoyment 6.8, production quality 7.7.

Delivery: +0.8 dB to about −14 LUFS (linear gain); the OGG measures -14.3 LUFS and -3.8 dBTP. Seam over three decoded cycles: step 0.012 against a 99th-percentile step of 0.124; flux 1.26× the same downbeat heard uncut.

## How these files were made

From Suno's 48 kHz WAV, each track was normalized as a whole to about −14 LUFS integrated and −1 dBTP (gain, plus a lookahead limiter only where peaks would pass the ceiling), resampled to 44.1 kHz, and cut on bar lines. The loop start and length were chosen by matching the bars around the loop end with the bars around the loop start (chroma, MFCC and level), the end sample was aligned to the start by waveform correlation, and an 8 ms equal-power crossfade into the audio just before the loop start was baked into the last samples. Files were encoded with `oggenc -q 6` (reference libvorbis), keeping Suno's embedded comment with the song ID and creation time.

The `.import` files set `loop`, `loop_offset`, `bpm` and `bar_beats`. `beat_count` stays 0 so Godot loops at the sample-accurate file end (see `docs/soundtrack.md`).
