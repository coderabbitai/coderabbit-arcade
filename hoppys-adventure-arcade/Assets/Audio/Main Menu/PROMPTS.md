# "Send in the Rabbit", the arcade's theme

Music by Erik Thorelli, made with Suno v6 on his Premier plan for Hoppy's Adventure Arcade. Erik holds the rights and grants their use in the game and in this repository. The soundtrack plan is [`docs/soundtrack.md`](../../../../docs/soundtrack.md) (section A); the lyrics are Erik's draft from that plan, with the edits listed below.

| File | Plays | Source | Measured | Loop |
|---|---|---|---|---|
| `send_in_the_rabbit_title_loop.ogg` | The hub (title screen), whenever booth mode is off | Instrumental: every stem of the vocal take except lead and backing vocals, summed at unity | F major, 118.3 BPM | Intro (verse 1, chorus 1) 0–54.021 s plays once, then 20 bars (verse 2, pre-chorus, chorus 2; 40.6 s) repeat to the file end at 94.593 s |
| `send_in_the_rabbit.ogg` | Booth attract mode, first in `booth_attract.tres` | The vocal take, whole | F major, 118.3 BPM; the last chorus steps up a semitone to F♯ major | None; the playlist plays it once, then the title loop, and repeats |

Suno song: [`a524c188-de47-4bd1-b870-e8ad7a2e5323`](https://suno.com/song/a524c188-de47-4bd1-b870-e8ad7a2e5323). Stems: Suno's 12-instrument auto split of that song (lead vocals, backing vocals, drums, bass, guitar, keyboard, percussion, synth, brass, woodwinds, FX), downloaded as WAV with MIDI on October 15, 2026.

## Styles

```text
80s Saturday-morning cartoon theme song meets vintage soul-pop, 116 BPM, F major, bouncy hopping octave bassline, tight funky drums, handclaps, bright brass stabs, three-note rising glockenspiel motif, warm soulful female alto lead, big gang-vocal chorus with call-and-response shouts, toy-commercial bombast, glossy synth pads under the horns, punchy modern hi-fi mix, catchy and singable, key change up into the last chorus, ends on a hard stop on the last beat
```

Exclude styles: `fade out, metal, trap, dubstep, EDM drop, autotune, rap`

Settings: model v6, Advanced, Max Mode on, Variety off, Weirdness 30%, Style Influence 75%, vocal gender female, lyrics manual, duration auto. Generated and downloaded as WAV on October 15, 2026.

## Lyrics

Changes from the plan's draft: the intro shouts the game's name; verse 2 replaces the night/tonight rhyme; the bridge chant gains a two-line payoff that names Hoppy. The chorus is unchanged.

```text
[Intro | glockenspiel motif, brass stab, handclaps]
(Hop! Hop!)
Hoppy's Adventure Arcade!

[Verse 1]
Ten thousand lines landed right before lunch
Three agents wrote it and nobody knows which one
The build is green but the logic is grey
And the slop keeps piling up all day

[Pre-Chorus | drums build]
Who reads the change when the changes don't stop?
Who sorts the stack when it's stacked to the top?

[Chorus | big gang vocals, call and response]
New era (new era!), new villains (new villains!)
Send in the rabbit! (Send in the rabbit!)
Review it, sort it, see what it's doing
Ship it secure, send in the rabbit!

[Verse 2]
An army of agents is coding all night
A hacker at machine speed is picking a fight
Phantom functions in a pull request tower
Somebody's gotta trust it, hour after hour

[Pre-Chorus | drums build]
Who reads the change when the changes don't stop?
Who sorts the stack when it's stacked to the top?

[Chorus | big gang vocals, call and response]
New era (new era!), new villains (new villains!)
Send in the rabbit! (Send in the rabbit!)
Review it, sort it, see what it's doing
Ship it secure, send in the rabbit!

[Bridge | breakdown, handclaps, gang chant]
Review! (Review!) Triage! (Triage!)
Understand! (Understand!) Secure! (Secure!)
Ears up, Hoppy, it's your time to hop
One little rabbit and the slop's gonna stop

[Final Chorus | key change up, full band, belted]
New era (new era!), new villains (new villains!)
Send in the rabbit! (Send in the rabbit!)
Review it, sort it, see what it's doing
Ship it secure, send in the rabbit!

[Outro | gang vocals, glockenspiel motif]
(Hop! Hop!) Reviewed by Code Rabbit!
[End]
```

## Choosing the take

Four takes came from these settings: `c2da0554-f84c-4c7c-b69f-f45640657522`, `378cb7a7-e49e-4ffd-b395-cd75149b73e5`, `c0e2562a-1488-494c-bfbf-588d2120c8ed` and this one. A Whisper (medium.en) transcript of each was matched word by word against the intended lyrics. This take matched 97.8% in order, the best of the four. It also has the only clearly sung game name in the intro, the only "Hop, hop, reviewed by Code Rabbit" outro as written, and a real key change into the last chorus, which the plan asked for. On Meta's audiobox-aesthetics model it scored 7.41 for content enjoyment and 8.12 for production quality, level with the other takes. Runner-up: `c0e2562a` (95.2%; stays in F throughout, but its intro and outro tags are garbled).

## Delivery

- **Title loop.** The instrumental stems were summed, then raised by 6.2 dB with a lookahead limiter holding the peaks. It measures about −14.7 LUFS for the whole song and −15.7 LUFS for the file, which stops before the louder last chorus. It was resampled to 44.1 kHz and cut at bar lines found from the vocal stem's section timing: verse 2 starts at 54.021 s and the bridge at 94.593 s. The loop end was aligned to the loop start by waveform correlation, with an 8 ms equal-power crossfade baked in. Three decoded cycles show the seam step below the track's 99th-percentile step, and seam flux at 1.19× the same downbeat heard uncut.
- **Vocal theme.** The whole take, raised 2.3 dB to −14 LUFS integrated, peaks at −1.7 dBTP, resampled to 44.1 kHz.
- Both were encoded with `oggenc -q 6` and keep Suno's embedded comment with the song ID. The `.import` files set `bpm` 118.338 and `bar_beats` 4, and the title loop also sets `loop` and `loop_offset`. `beat_count` stays 0, as in the other music, so Godot loops at the file end (see `docs/soundtrack.md`).
- `booth_attract.tres` is an `AudioStreamPlaylist`: the vocal theme, then the title loop, repeating with the default 0.3 s fade between them.
