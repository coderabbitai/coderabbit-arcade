# Soundtrack plan

How the arcade's music should sound and how it gets made. The plan has two layers:

- **One core theme song**: high-fidelity, with vocals, and catchy enough to carry the booth and the brand.
- **A family of 8-bit derivatives** built from that theme's melody and motifs. These become the game's menu loop, stage themes, boss music and stingers, so the game sounds like a miniature extension of the theme.

The plan also covers replacing the tracks marked in [`ASSETS_LICENSES.md`](../ASSETS_LICENSES.md) with music we generate. Licensing decisions for generated audio are handled separately; this document records how each track was made, so those decisions have the facts.

## The vibe

A bright, cheeky cabinet game in which a rabbit fights the everyday pain of the agentic era: AI slop, 10,000-line PRs, agent armies, machine-speed hackers, legacy monoliths. The booth frames those villains as absurd blister-pack action figures, so the music borrows **80s Saturday-morning cartoon and toy-commercial energy** and grounds it in CodeRabbit's existing sound.

That existing sound comes from [CodeRabbit × Suno](https://github.com/esthor/coderabbit-suno): vintage soul-pop at 116 BPM, a bouncy hopping bassline, handclaps, horn stabs, a warm alto lead with call-and-response backing, and a **three-note glockenspiel motif**. Inside the game, the same ideas become SNES-era chiptune and Genesis-style FM synthesis.

Every track shares two threads:

- **The motif:** the three-note rising figure.
  - In major for heroes, wins and capability unlocks.
  - In minor or inverted for villains, failures and bosses.
- **The hop:** a bouncy octave bassline under the groove.

## Musical constants

| | Value | Why |
|---|---|---|
| Tempo | **116 BPM** for the theme family | Matches the CodeRabbit sound. Level tracks may differ; boss tracks can double-time (232 feel). |
| Key | **Pick from the chosen theme take** (measure it; F major is the target) | Every derivative reuses the theme's key, so stingers and loops drop in without clashing. |
| Motif | Three rising notes (scale degrees 1–3–5 of the key) | It has to survive being played on a square wave. |
| Bar length | 2.069 s at 116 BPM (8 bars is about 16.55 s) | Loop points are cut on bar lines. |

After the theme take is chosen, write its measured key and tempo here and use them in every derivative prompt.

## Track list

### A. Core theme: "Send in the Rabbit" (vocal, high fidelity)

The anthem. It plays on the booth floor, in reels and in the Heroes vs. Villains opening. It also seeds every derivative.

- **Suno:** model v6, Advanced mode, **Max Mode on**, **Variety Off**, Weirdness 30%, Style Influence 75%, Vocal Gender Female, Duration about 2:00. Use the "Code Rabbit" Style Persona if one exists (Voices menu).
- **Styles** (462 characters; the limit is 1,000):

  ```text
  80s Saturday-morning cartoon theme energy meets vintage soul-pop, 116 BPM, F major, bouncy hopping octave bassline, handclaps, bright brass stabs, three-note rising glockenspiel motif, warm soulful alto lead, big gang-vocal chorus with call-and-response, toy-commercial bombast, punchy modern hi-fi mix, tight drums, glossy synth pads under the horns, catchy and singable, key change into the last chorus, ends on a hard stop on the last beat after the outro tag
  ```

- **Exclude styles:** `fade out, metal, trap, dubstep, EDM drop, autotune`
- **Lyrics** (draft; Theresa and Amanda, who own the booth narrative, should approve the wording before public use):

  ```text
  [Intro | three-note glockenspiel motif, brass stab, handclaps]
  (Hop! Hop!)

  [Verse 1]
  Ten thousand lines landed right before lunch
  Three agents wrote it and nobody knows which one
  The build is green but the logic is grey
  The slop keeps piling up all day

  [Pre-Chorus | drums build]
  Who reads the change when the changes don't stop
  Who sorts the stack when it's stacked to the top

  [Chorus | big gang vocals, call and response]
  New era (new era), new villains (new villains)
  Send in the rabbit (send in the rabbit)
  Review it, sort it, see what it's doing
  Ship it secure, send in the rabbit

  [Verse 2]
  An army of agents is coding all night
  A hacker is moving at machine-speed tonight
  Phantom functions and a pull request tower
  Somebody still has to trust it by the hour

  [Pre-Chorus | drums build]
  Who reads the change when the changes don't stop
  Who sorts the stack when it's stacked to the top

  [Chorus | big gang vocals, call and response]
  New era (new era), new villains (new villains)
  Send in the rabbit (send in the rabbit)
  Review it, sort it, see what it's doing
  Ship it secure, send in the rabbit

  [Bridge | breakdown, handclaps, chant]
  Review (review!) Triage (triage!)
  Understand (understand!) Secure (secure!)

  [Final Chorus | key change up, full band]
  New era (new era), new villains (new villains)
  Send in the rabbit (send in the rabbit)
  Review it, sort it, see what it's doing
  Ship it secure, send in the rabbit

  [Outro | gang vocals, glockenspiel motif]
  (Hop! Hop!) Reviewed by Code Rabbit
  [End]
  ```

- **Keep:** two or three takes. Pick by chorus hook, vocal and motif clarity. Then make a Style Persona from the winner, so later vocal cuts stay in the same voice.
- **Cut-downs** from the chosen take, edited on bar lines: 14 bars (about 0:29) and 7 bars (about 0:14.5), so they fit 30- and 15-second reel slots and end on a downbeat. Add an instrumental **booth loop** made by splitting out the vocal stem.

### B. 8-bit derivatives (instrumental, game-ready)

Same tempo and key as the theme, and the same motif and chorus melody, re-voiced for a sound chip. In order of faithfulness:

1. **Stems → MIDI → chiptune (Premier, Suno Studio).** Split the theme into stems, transcribe the lead vocal, glockenspiel and bass to MIDI, and play them on square, triangle and noise voices: Studio's synth, or a tracker such as Furnace. This is the only route that keeps the exact notes. Expect to clean up the transcription.
2. **MIDI clip as the prompt in Studio**, with a chiptune style. The melody comes from the MIDI; the sound is generated.
3. **Cover with an audio upload.** Render the melody MIDI as a plain square wave, upload it, and Cover it with the chiptune styles below (Max Mode, Audio Influence about 50%, Style Influence about 40%). Don't Cover the vocal mix: that re-sings the lyrics.

Shared settings: Instrumental on, Variety Off. The lyrics field holds section tags only (`[Intro]`, `[Instrumental]`, `[Outro]`, `[End]`). Exclude `vocals, humming, choir, vocal chops, fade out`.

| Cue | Use in game | Length / loop | Styles (add the measured key) |
|---|---|---|---|
| **Main menu attract loop** | `AudioService` default track (replaces `happy_adveture.mp3`) | 8–16 bars, seamless | `chiptune and FM synthesis arrangement of an upbeat theme, 116 BPM, NES square-wave lead plays the chorus melody, triangle-wave hopping bassline, noise-channel drums, three-note rising chime motif, arcade attract mode, inviting, loopable steady groove, no intro, no outro` |
| **Heroes vs. Villains: The Generation Floor** | Stage 1 | 1:30+ loop | `hyperactive 16-bit chiptune variation of the theme, 116 BPM, comically busy bouncy arpeggios, square lead quoting the chorus, triangle bass, noise drums, toy-commercial energy, loopable` |
| **Heroes vs. Villains: The Review Gauntlet** | Stage 2 | 1:30+ loop | `grinding heavy 16-bit chiptune, 116 BPM half-time march, motif in minor, stacking tension, FM brass, noise-channel snare rolls, loopable` |
| **Heroes vs. Villains: The Agentic Core** | Stage 3 | 1:30+ loop | `tense techno-chiptune, 116 BPM, pulsing square-wave bass, cold FM leads, scanning arpeggios, inverted three-note motif, loopable` |
| **Villain boss theme** (shared, as the GDD specifies) | All Heroes vs. Villains bosses | 1:00+ loop, strong hit in the first second | `Saturday-morning cartoon villain battle, 16-bit FM chiptune, 232 BPM double-time feel, minor key, campy menace, orchestra-hit stabs, chromatic runs, motif in minor, huge downbeat in the first second, loopable` |
| **Opening fanfare** | Heroes vs. Villains intro | 10–15 s, hard stop | Not 8-bit: the theme's chorus and gang shout, cut from track A. |
| **MERGE SUCCESSFUL** | Code City finale, ending and results | 3.5 s one-shot, then a 16.552 s loop | Delivered: original F-major square-wave synthesis at 116 BPM; rising F-A-C motif resolving to F. See the reproducible build below. |
| **BUILD FAILED** | Lose results | 2–3 s, one-shot | Sounds, One-Shot: `8-bit comic fail sting, three-note motif descending in minor, wobbly square lead` |
| **Capability unlocked** (×4) | REVIEW / TRIAGE / CHANGE STACK / SECURITY cards | 1–2 s, one-shot | Sounds, One-Shot: `chiptune power-up chime, three-note glockenspiel-like square arpeggio` (one take per capability, rising in pitch) |
| **BOSS DOWN!** | Boss defeat | about 2 s | Keep Juhani Junkala's CC0 `fanfare3`, or a Sounds one-shot of the motif. |

The results screens pause the game, so their stinger player needs `process_mode = PROCESS_MODE_ALWAYS`.

### Delivered: Code City victory music

`python3 tools/build_code_city_victory_music.py` builds the following original mono 44.1 kHz, 16-bit PCM files in `hoppys-adventure-arcade/Assets/Audio/Beat'em Up/`:

| File | Duration | Role |
|---|---|---|
| `code_city_victory_jingle.wav` | 3.500 s | Once after the Force Merge finisher: the F-A-C figure rises to F, then a dominant phrase resolves to the tonic. |
| `code_city_victory_loop.wav` | 16.551723 s | Eight bars at 116 BPM. Square lead, pulsing arpeggios and an octave-hopping bass carry the ending pages and results. |

The builder is deterministic and uses only Python's standard library. These are original compositions and recordings with no third-party samples or Suno source. Both are dedicated to the public domain under CC0 1.0. The square voices use smoothed discontinuities, short note attack/release envelopes and a gentle output low-pass. An 8 ms cosine taper at each outer boundary lands the loop at exact zero samples, avoiding a seam discontinuity. The final dominant bar returns to the first tonic bar.

The celebration lasts 5.2 s. It ducks the boss track by 18 dB, starts the jingle at 0.3 s and switches the stage-flow music player to the loop at 3.8 s. The loop survives the celebration callback and plays through the epilogue and results. Cancelling for a stage rebuild or leaving stops only the celebration's own track. The jingle follows the music bus and pauses with the game; all visual timing follows the same unpaused owner clock. Loop settings are applied to a private resource copy, leaving the imported WAV unchanged. These short procedural WAV cues are an intentional exception to the OGG delivery target below.

To verify a rebuild without touching game assets, pass `--out <directory>` and compare the WAV bytes. The loop's first and last PCM samples are zero.

### C. Level music (instrumental, outside the theme family)

These replace or upgrade tracks under `hoppys-adventure-arcade/Assets/Audio/`. Each keeps its level's character, with an optional motif quote. The current files, and the code that plays them, are listed for drop-in replacement.

| Track (current file) | Plays | Styles |
|---|---|---|
| **Enchanted Repo level** (delivered: `enchanted_repo_level.ogg`) | Traversal, retry, after the boss (`scenes/platformer/enchanted_repo.gd`) | `16-bit fantasy chiptune, SNES-era adventure stage, instrumental, 90 BPM, D dorian, mysterious enchanted forest and ruined castle, soft square lead, harp-like pulse arpeggios, breathy ocarina patch, warm triangle bass, light noise shuffle, bell sparkles, steady energy, loopable, ends on the downbeat` |
| **Enchanted Repo boss** (delivered: `enchanted_repo_boss.ogg`) | The Legacy Monolith; starts in the 1.8 s intro, fading in over 0.55 s | `16-bit chiptune boss battle, SNES-era RPG fight, instrumental, 172 BPM, D minor, menacing ancient stone guardian, driving FM bass ostinato, aggressive square lead, pipe organ patch, orchestra hits, pounding noise toms, huge downbeat in the first second, loopable` |
| **Orbital Ops level** (`tipa16.mp3`) | Traversal, retries, after the boss (`scenes/platformer/orbital_ops.gd`) | `FM synthesis chiptune, Genesis-style space station stage, instrumental, 145 BPM, E minor lifting to G major, buoyant cosmic adventure, sparkling FM bell arpeggios, slap FM bass, square lead, gated noise hi-hats, floating half-time zero-gravity breakdown, loopable` |
| **Code City Brawl: CLI/IDE District** (delivered: `code_city_cli_ide_district.ogg`) | Stage 1 and the mode menu (`modes/beatem_up/catalog.gd`) | `neon cyberpunk chiptune beat-em-up stage, 128 BPM, E minor, punchy kick and snare, FM slap bass, cyan square arpeggios, terminal beep accents, street brawler groove, loopable` |
| **Code City Brawl: Security Sector** (delivered: `code_city_security_sector.ogg`) | Stage 2 | `dark industrial chiptune, 136 BPM, F# phrygian, siren-like pulse lead, distorted FM bass, heavy breakbeat, tense, loopable` |
| **Code City Brawl: Git HQ** (delivered: `code_city_git_hq.ogg`) | Stage 3 | `regal funk chiptune, 124 BPM, Bb mixolydian, brass-like FM stabs, strutting hopping bassline, triumphant headquarters, loopable` |
| **Code City Brawl: district bosses** (delivered: `code_city_district_boss.ogg`) | Stack Overflow and Zero-Day, via `Catalog.MINI_BOSS_MUSIC` and `flow.swap_music` | `16-bit beat-em-up mini-boss battle, Genesis FM, instrumental, 150 BPM, E minor, alarm-like square-wave arpeggios, galloping slap FM bass, punchy breakbeat drums, brass-like FM stabs, urgent street-fight menace, huge downbeat in the first second, loopable`. The stage exit cancels the swap; the next stage starts its district track. The Grand Merge Conflict keeps its separate final-boss track. |
| **Code City Brawl: The Grand Merge Conflict** (delivered: `code_city_grand_merge_conflict.ogg`) | Boss | `two clashing chiptune melodies in counterpoint, 160 BPM, C minor, colliding phrases resolving together, heavy FM bass, double-time drums, epic final boss, loopable` |
| **Heroes vs. Villains stage and boss tracks** (six files in `Assets/Audio/Beat'em Up/Hero vs Villian/`) | `modes/beatem_up/reinvent/catalog.gd` | Replaced by the theme-family cues in section B. |

## Producing in Suno v6

- **Plan:** commercial use requires a counted download on a paid plan. Pro allows 20 downloads a month; Premier allows 60 and adds Studio, MIDI export and all stem types. The theme family's MIDI route needs **Premier**. Budget against downloads, not credits.
- **Model:** v6, not v6-mini, for every final take.
- **Prompting:**
  - Styles stay under 1,000 characters, most important first: genre, mood, instruments, vocal, production, then BPM and key.
  - Describe endings positively ("ends on a hard stop") and put "fade out" in Exclude.
  - Bar counts in section tags help, e.g. `[Intro - glockenspiel motif, 4 bars]`.
- **Provenance:** for every kept file, record the Suno song ID, model, plan, download date and full prompt. Use a `PROMPTS.md` beside the audio, following the art packs' convention. Keep Suno's embedded metadata intact.

## Delivering to Godot

- **Format:** OGG Vorbis at quality 6, 44.1 kHz stereo, encoded from Suno's WAV download. Don't use MP3 for loops (encoder padding leaves a gap) or WAV for music (size).
- **Loudness:** normalize music to **about −14 LUFS integrated, −1 dBTP**, using ffmpeg two-pass `loudnorm`. The current tracks range from −20 to −7 LUFS, but they all play at the same fixed volume.
- **Loops:**
  - Cut on bar lines, with a 5–10 ms crossfade or a zero crossing at the seam.
  - Listen to at least three cycles.
  - Set `loop=true` (and `loop_offset` to skip an intro) in the `.import` file, not at runtime: shared resources must not be mutated.
  - Fill in `bpm` and `bar_beats`, so `AudioStreamInteractive` can switch on the bar later. Leave `beat_count` at 0 for these file-end loops: when `bpm` and `beat_count` are both set, Godot 4.7's Ogg player loops after `beat_count` beats counted from the start of the file, not at the loop end.
- **Boss swaps:** the platformer fades the level track down and the boss track in (`modes/platformer/level.gd`). Generating each boss track at its level track's key keeps that swap musical. For bar-synced intensity layers, use tempo-locked stems with `AudioStreamSynchronized`.
- **Naming:** lowercase snake case by role, e.g. `enchanted_repo_level.ogg`, `heroes_villains_boss.ogg`, `stinger_merge_successful.ogg`.
- **Licensing:** in the PR that commits a replacement file and its provenance record, add its `ASSETS_LICENSES.md` row and remove the row of the track it replaces. Until a replacement ships, the current rows stay, because those files are still in the game.
