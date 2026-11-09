# Hub music

| File | Plays | Source | Measured | Loop |
|---|---|---|---|---|
| `hub_chiptune_loop.wav` | The hub (title screen), in normal and booth mode | Procedural: `python3 tools/build_hub_chiptune.py` (song `lofi`) from the repository root. Original, CC0 1.0 | F major, 84 BPM swung, 32 bars, 91.429 s; mono 16-bit 22,050 Hz; −20.8 LUFS integrated, −6.4 dBTP | Whole file, forward (`edit/loop_mode=2` in the `.import`) |

The hub plays it at `AudioService.HUB_MUSIC_DB` (−15 dB), 5 dB under the games' −10 dB. With the file's lower loudness, that's about 10 dB below the "Send in the Rabbit" title loop it replaced. Booth visitors found the old music too loud and tiring.

## Why it sounds the way it does

A booth screen runs this for hours, so the loop is written to stay in the background:

- **Lo-fi groove.** 84 BPM with swung eighths, jazzy seventh chords (B♭maj7–Am7–Gm7–C7, then Fmaj7–Dm7–Gm7–C7) and a brushed kit: a soft sine kick, a quiet noise snare and faint hats.
- **Soft voices.** The lead is a flute-like 50%-duty pulse with a slight delayed vibrato and a dotted-eighth echo. The chords are triangle pads, and a triangle bass walks root, fifth and octave. A one-pole low-pass (about 1.2 kHz) warms everything.
- **Long form.** A (8 bars), A with a harmony a third below, B, then A opening on the triangle an octave down. The tune comes back unchanged only every 91 seconds.

Every voice and the echo wrap past the end of the loop to its start, and the low-pass runs twice so its state is continuous. The seam has no gap, fade or click.

The build is deterministic: SHA-256 `abd652f3958b5599054d3eb1a97b2f66df90d81fe5d6e2dd32005156062972a1`. `--song waltz` and `--song arcade` build the two alternatives that were auditioned. `--out <dir>` and `--name <file>` write somewhere else for comparison. Like the Code City victory cues, this is a procedural WAV, an intentional exception to the OGG delivery target in `docs/soundtrack.md`.

## Retired: "Send in the Rabbit"

Until November 2026 the hub played Erik Thorelli's "Send in the Rabbit" (Suno song `a524c188-de47-4bd1-b870-e8ad7a2e5323`): the instrumental title loop on the hub and the vocal take in booth mode. Those files were removed, and the theme stays in the game's credits. Its prompts, lyrics and delivery notes are in this file's git history.
