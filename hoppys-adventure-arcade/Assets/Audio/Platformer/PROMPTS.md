# Platformer stage-clear stinger

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. The soundtrack plan is [`docs/soundtrack.md`](../../../../docs/soundtrack.md); level music has its own `PROMPTS.md` in each level's folder.

| File | Plays | Suno song | Measured | Length |
|---|---|---|---|---|
| `stinger_stage_clear.ogg` | Once, when any platformer level finishes and the MERGE SUCCESSFUL results open (`modes/platformer/level.gd`, `_finish(true)`) | [`73fc8220-4010-43da-b82f-95e63862062e`](https://suno.com/song/73fc8220-4010-43da-b82f-95e63862062e) | F major, the theme's key, at 116 BPM | 4.74 s, one-shot |

## Prompt

Suno Sounds, One-Shot, BPM 116, key F major:

```text
chiptune level-clear jingle, bouncy two-bar fanfare, three-note rising motif F A C then a held tonic chord hit, square-wave lead with triangle bass and a noise-channel drum fill, cheerful arcade stage clear, ends cleanly, about 4 seconds
```

Generated and downloaded as WAV on October 15, 2026. Takes compared: this one and `4cc54a58-bf2a-44a4-8e24-ae2010b2de84`. This one is clearly in F major (Krumhansl fit 0.94; the other reads as C major) and scored higher on Meta's audiobox-aesthetics model (content enjoyment 6.38 against 6.08, production quality 7.59 against 7.12).

## Delivery

Suno returned an 8.2 s phrase. It was raised 1.5 dB to −14 LUFS and cut to its closing phrase, the two bars before the final decay (3.415–8.154 s in the take), keeping the natural decay. A 4 ms fade-in and a 30 ms fade-out were applied, then the cut was encoded with `oggenc -q 6`, keeping Suno's embedded comment with the song ID. The `.import` leaves `loop` off.
