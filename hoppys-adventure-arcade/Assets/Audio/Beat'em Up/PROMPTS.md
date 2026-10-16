# Code City Brawl music

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. The soundtrack plan is [`docs/soundtrack.md`](../../../../docs/soundtrack.md). Juan's MERGE SUCCESSFUL jingle and victory loop in this folder are separate procedural cues (`tools/build_code_city_victory_music.py`) and are unchanged.

| File | Plays | Suno song | Measured tempo and key | Loop |
|---|---|---|---|---|
| `code_city_cli_ide_district.ogg` | Stage 1 and the Beat 'em Up menu | [`765780d8-51aa-4f76-bbd0-1583756c15e8`](https://suno.com/song/765780d8-51aa-4f76-bbd0-1583756c15e8) | 132.4 BPM; E (minor and major colour) | Intro 0–36.618 s plays once, then 32 bars (58.0 s) repeat to the file end at 94.644 s |
| `code_city_security_sector.ogg` | Stage 2 | [`977d1196-ba53-43c3-9a0b-81302c63dd0b`](https://suno.com/song/977d1196-ba53-43c3-9a0b-81302c63dd0b) | 138.2 BPM; F♯ minor (phrygian), as asked | Intro 0–36.966 s plays once, then 56 bars (97.2 s) repeat to the file end at 134.213 s |
| `code_city_git_hq.ogg` | Stage 3 | [`9e64dc05-72c1-459e-a2a5-0cd91bab25be`](https://suno.com/song/9e64dc05-72c1-459e-a2a5-0cd91bab25be) | 125.0 BPM; B♭ (mixolydian), as asked | Intro 0–36.629 s plays once, then 40 bars (76.8 s) repeat to the file end at 113.423 s |
| `code_city_district_boss.ogg` | Stack Overflow and Zero-Day, the district bosses | [`8a61a3b4-6bd5-4471-a8f9-5c90bb1d186a`](https://suno.com/song/8a61a3b4-6bd5-4471-a8f9-5c90bb1d186a) | 150.0 BPM; E minor, the first district's key | Opening 0–8.227 s plays once, then 32 bars (51.2 s) repeat to the file end at 59.437 s |
| `code_city_grand_merge_conflict.ogg` | The final boss | [`4b912fce-3f9f-4d6c-bab4-c161a6edda17`](https://suno.com/song/4b912fce-3f9f-4d6c-bab4-c161a6edda17) | 161.0 BPM; C minor throughout | Opening 0–6.362 s plays once, then 64 bars (95.4 s) repeat to the file end at 101.773 s |

## code_city_cli_ide_district: "CLI / IDE District"

Styles:

```text
neon cyberpunk chiptune beat-em-up stage, Genesis FM street brawler, instrumental, 128 BPM, E minor, punchy kick and snare, FM slap bass, cyan square-wave arpeggios, terminal beep accents, gritty brawler groove, heroic lead hook, stays in E minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `40116614-d124-408b-86ef-5b15f7993578`. This one stays centred on E (the other climbs to F minor for its last third), and the two scored within 0.05 of each other on enjoyment and production quality. Audiobox-aesthetics: content enjoyment 7.19, production quality 8.16.

Delivery: +1.6 dB to about −14 LUFS (linear gain); the OGG measures -14.5 LUFS and -2.1 dBTP. Seam over three decoded cycles: step 0.020 against a 99th-percentile step of 0.124; flux 1.0× the same downbeat heard uncut.

## code_city_security_sector: "Security Sector"

Styles:

```text
dark industrial chiptune beat-em-up stage, instrumental, 136 BPM, F# phrygian, siren-like pulse lead, distorted FM bass, heavy breakbeat, metallic noise hits, firewall alarm tension, driving and tense, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 40%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `1e7ace3a-1e29-41ae-a28f-43c0b389d651`. This one holds F♯ minor from start to finish (the other wanders between F, F minor and F♯ minor); enjoyment was level and its 56-bar loop is the longest in the mode. Audiobox-aesthetics: content enjoyment 6.65, production quality 7.56.

Delivery: +1.3 dB to about −14 LUFS (linear gain); the OGG measures -14.2 LUFS and -2.2 dBTP. Seam over three decoded cycles: step 0.058 against a 99th-percentile step of 0.112; flux 0.99× the same downbeat heard uncut.

## code_city_git_hq: "Git Repository HQ"

Styles:

```text
regal funk chiptune beat-em-up stage, Genesis FM, instrumental, 124 BPM, Bb mixolydian, brass-like FM stabs, strutting hopping bassline, wah square-wave lead, tight funk drums, triumphant headquarters swagger, stays in Bb, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:30, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `14da28d1-feea-4d7b-ade1-0750446ee5ca`. This one keeps B♭ as home and a dead-straight 125 BPM grid (every tracked beat within 40 ms), and scored slightly higher on enjoyment. Audiobox-aesthetics: content enjoyment 7.27, production quality 8.04.

Delivery: +1.3 dB to about −14 LUFS (linear gain); the OGG measures -14.3 LUFS and -3.6 dBTP. Seam over three decoded cycles: step 0.035 against a 99th-percentile step of 0.117; flux 1.23× the same downbeat heard uncut.

## code_city_district_boss: "District Boss"

Styles:

```text
16-bit beat-em-up mini-boss battle, Genesis FM, instrumental, 150 BPM, E minor, alarm-like square-wave arpeggios, galloping slap FM bass, punchy breakbeat drums, brass-like FM stabs, urgent street-fight menace, huge downbeat in the first second, stays in E minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 35%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `150d0c26-97bb-44ff-ad30-e7b9b15c1d3d`. Both sit around E; this one reads more clearly as E minor and scored higher on enjoyment (7.06 against 6.96) and production quality. The beat tracker heard its 150 BPM as 200, so its bars were cut on a fixed 149.96 BPM grid fitted to the beats. Audiobox-aesthetics: content enjoyment 7.06, production quality 7.78.

Delivery: +1.7 dB to about −14 LUFS (linear gain); the OGG measures -14.2 LUFS and -3.3 dBTP. Seam over three decoded cycles: step 0.027 against a 99th-percentile step of 0.131; flux 1.05× the same downbeat heard uncut.

## code_city_grand_merge_conflict: "The Grand Merge Conflict"

Styles:

```text
epic final boss chiptune, two clashing melodies in counterpoint, instrumental, 160 BPM, C minor, colliding square-wave phrases that resolve together, heavy FM bass, double-time drums, orchestra hits, pipe organ swells, high stakes, huge downbeat in the first second, stays in C minor, seamless loop
```

Exclude styles: `vocals, singing, humming, choir, vocal chops, spoken word, fade out, lo-fi hiss, key change`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 40%, Style Influence 75%, duration 2:00, lyrics empty (instrumental). Generated and downloaded as WAV on October 15, 2026.

Takes compared: this one and `4c419668-38ce-4eee-a682-2cbc8e743daa`. This one stays in C minor (the other keeps flipping to C major), has the tightest grid of any take (every beat within 4 ms of 161 BPM), and its 64-bar loop covers nearly the whole track. Audiobox-aesthetics: content enjoyment 6.8, production quality 7.38.

Delivery: +2.1 dB to about −14 LUFS (linear gain); the OGG measures -14.1 LUFS and -1.6 dBTP. Seam over three decoded cycles: step 0.040 against a 99th-percentile step of 0.112; flux 0.99× the same downbeat heard uncut.

## How these files were made

From Suno's 48 kHz WAV, each track was normalized as a whole to about −14 LUFS integrated and −1 dBTP (gain, plus a lookahead limiter only where peaks would pass the ceiling), resampled to 44.1 kHz, and cut on bar lines. The loop start and length were chosen by matching the bars around the loop end with the bars around the loop start (chroma, MFCC and level), the end sample was aligned to the start by waveform correlation, and an 8 ms equal-power crossfade into the audio just before the loop start was baked into the last samples. Files were encoded with `oggenc -q 6` (reference libvorbis), keeping Suno's embedded comment with the song ID and creation time.

The `.import` files set `loop`, `loop_offset`, `bpm` and `bar_beats`. `beat_count` stays 0 so Godot loops at the sample-accurate file end (see `docs/soundtrack.md`). These shared imports keep `loop` off: `modes/beatem_up/catalog.gd` loops a private copy (`Catalog.looped`), which inherits `loop_offset`.
