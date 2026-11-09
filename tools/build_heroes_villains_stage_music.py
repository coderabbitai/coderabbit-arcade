"""Original CC0 stage music for Heroes vs. Villains stages 1 and 3.

Rebuild from the repository root with
`python3 tools/build_heroes_villains_stage_music.py --stage generation_floor` (or
`agentic_core`), then encode the WAV with `oggenc -q 6` (see the audio folder's
PROMPTS.md). Both take their energy and instruments from Code City Brawl's Genesis FM
street-brawler music (FM slap bass, brass stabs, breakbeat drums, square arpeggios) but
keep the Heroes vs. Villains identity: the heroes' F major for stage 1 and the villains'
F minor for stage 3, with the three-note motif rising (F-A-C) for the heroes and falling
(C-Ab-F) for the core, and their own tunes.

- The Generation Floor (124 BPM): a heroic brawler groove for the bright white and
  orange expo hall. Syncopated FM slap bass, brass stabs, a high square sparkle
  arpeggio, a breakbeat with ghost snares and a brassy FM lead that opens on the motif.
- The Agentic Core (134 BPM): a dark, driving brawler for the red and green machine
  core, the game's fastest stage. A gritty 16th-note FM bass, a heavy break with
  metallic hits, brass hits, a scanning arpeggio that sweeps across the stereo field,
  cold FM leads on the falling motif and short data-glitch stutters.

Each file is a 4-bar intro that plays once, then a 32-bar body that loops to the file
end (the `.import` sets `loop_offset` to the intro length). The engine is a small
NES/Genesis-style synth: anti-aliased pulse waves, a triangle, 2-operator FM, and a
15-bit LFSR noise channel for drums. Every voice, echo and stutter that runs past the
file end wraps around to the loop start, so the seam has no gap, fade or click.
No samples, network, random state or dependencies.
The generated compositions and recordings are dedicated to the public domain under CC0 1.0.
"""

import argparse
from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
import struct
import wave


OUT = (
    Path(__file__).resolve().parents[1]
    / "hoppys-adventure-arcade/Assets/Audio/Beat'em Up/Hero vs Villian"
)
RATE = 44100
METER = 4
INTRO_BARS = 4
TAU = 2 * math.pi
MAX_PEAK = 0.84  # about -1.5 dBFS before encoding
KNEE = 0.6  # the soft limiter leaves samples below this untouched


def chord(root: int, *tones: int) -> tuple[int, tuple[int, ...]]:
    """A bass root (MIDI, octave 2) and its chord tones (MIDI, around middle C)."""
    return root, tones


# F major.
F = chord(41, 57, 60, 65)
DM = chord(38, 57, 62, 65)
BB = chord(46, 58, 62, 65)
C = chord(36, 55, 60, 64)
AM = chord(45, 57, 60, 64)
GM = chord(43, 55, 58, 62)
# F minor (C major is the harmonic-minor dominant).
FM = chord(41, 56, 60, 65)
DB = chord(37, 56, 61, 65)
BBM = chord(46, 58, 61, 65)
EB = chord(39, 55, 58, 63)
CMAJ = chord(36, 55, 60, 64)


@dataclass
class Stage:
    """One stage song: chords and lead per 8-bar section, form and arrangement."""

    name: str
    chords: dict[str, list]
    melody: dict[str, list]  # per bar: (beat, midi, beats)
    intro: list  # chords for the intro bars
    form: list[str]  # body sections, with "+harm", "+sparse" or "+glitch" variations
    bpm: float
    lowpass: float  # one-pole coefficient; lower is warmer
    rms: float  # body loudness before the soft limiter; tuned to about -14 LUFS


GENERATION_FLOOR = Stage(
    name="generation_floor",
    chords={
        "A": [F, F, DM, BB, F, C, BB, C],
        "B": [BB, C, AM, DM, BB, C, GM, C],
    },
    melody={
        "A": [
            [(0, 65, 0.5), (0.5, 69, 0.5), (1, 72, 1), (2.5, 72, 0.5), (3, 74, 0.5), (3.5, 72, 0.5)],
            [(0, 77, 1.5), (1.5, 76, 0.5), (2, 72, 1), (3, 69, 1)],
            [(0, 74, 0.5), (0.5, 77, 0.5), (1, 81, 1), (2.5, 79, 0.5), (3, 77, 0.5), (3.5, 74, 0.5)],
            [(0, 77, 1.5), (1.5, 74, 0.5), (2, 70, 1.5), (3.5, 72, 0.5)],
            [(0, 65, 0.5), (0.5, 69, 0.5), (1, 72, 1), (2.5, 77, 0.5), (3, 76, 0.5), (3.5, 77, 0.5)],
            [(0, 79, 1.5), (1.5, 76, 0.5), (2, 72, 1), (3, 79, 0.5), (3.5, 81, 0.5)],
            [(0, 82, 1), (1, 81, 0.5), (1.5, 79, 0.5), (2, 77, 1), (3, 74, 1)],
            [(0, 76, 2), (2.5, 72, 0.5), (3, 74, 0.5), (3.5, 76, 0.5)],
        ],
        "B": [
            [(0, 74, 1), (1, 77, 1), (2, 82, 1.5), (3.5, 81, 0.5)],
            [(0, 79, 1.5), (1.5, 76, 0.5), (2, 72, 2)],
            [(0, 72, 1), (1, 76, 1), (2, 81, 1.5), (3.5, 79, 0.5)],
            [(0, 77, 1.5), (1.5, 74, 0.5), (2, 69, 2)],
            [(0, 70, 0.5), (0.5, 74, 0.5), (1, 77, 1), (2, 82, 0.5), (2.5, 81, 0.5), (3, 79, 0.5), (3.5, 77, 0.5)],
            [(0, 76, 1), (1, 79, 1), (2, 84, 2)],
            [(0, 82, 0.5), (0.5, 81, 0.5), (1, 79, 1), (2, 74, 0.5), (2.5, 77, 0.5), (3, 79, 1)],
            [(0, 76, 1), (1, 72, 1), (2, 67, 0.5), (2.5, 69, 0.5), (3, 70, 0.5), (3.5, 76, 0.5)],
        ],
    },
    intro=[F, BB, F, C],
    bpm=124,
    form=["A", "A+harm", "B", "B+harm"],
    lowpass=0.62,
    rms=0.181,
)

AGENTIC_CORE = Stage(
    name="agentic_core",
    chords={
        "A": [FM, FM, DB, DB, BBM, BBM, CMAJ, CMAJ],
        "B": [DB, EB, FM, FM, DB, EB, CMAJ, CMAJ],
    },
    melody={
        "A": [
            [(0, 72, 0.5), (0.5, 68, 0.5), (1, 65, 1.5), (3, 67, 0.5), (3.5, 68, 0.5)],
            [(0, 72, 1), (1, 75, 0.5), (1.5, 72, 0.5), (2, 77, 2)],
            [(0, 77, 0.5), (0.5, 73, 0.5), (1, 68, 1.5), (3, 70, 0.5), (3.5, 72, 0.5)],
            [(0, 73, 1.5), (1.5, 72, 0.5), (2, 68, 1), (3, 65, 1)],
            [(0, 70, 0.5), (0.5, 73, 0.5), (1, 77, 1), (2, 82, 0.5), (2.5, 80, 0.5), (3, 77, 1)],
            [(0, 73, 1.5), (1.5, 77, 0.5), (2, 75, 1), (3, 73, 1)],
            [(0, 72, 1), (1, 76, 0.5), (1.5, 79, 0.5), (2, 84, 1), (3, 82, 0.5), (3.5, 79, 0.5)],
            [(0, 76, 2), (2, 79, 0.5), (2.5, 76, 0.5), (3, 72, 1)],
        ],
        "B": [
            [(0, 80, 1.5), (1.5, 77, 0.5), (2, 73, 1), (3, 77, 1)],
            [(0, 79, 1.5), (1.5, 75, 0.5), (2, 70, 1), (3, 75, 1)],
            [(0, 84, 0.5), (0.5, 80, 0.5), (1, 77, 1.5), (3, 80, 0.5), (3.5, 84, 0.5)],
            [(0, 85, 1), (1, 84, 1), (2, 80, 1), (3, 77, 1)],
            [(0, 77, 0.5), (0.5, 80, 0.5), (1, 85, 1), (2, 84, 0.5), (2.5, 80, 0.5), (3, 77, 1)],
            [(0, 79, 1), (1, 82, 1), (2, 87, 1.5), (3.5, 84, 0.5)],
            [(0, 84, 1), (1, 79, 0.5), (1.5, 76, 0.5), (2, 72, 1), (3, 76, 1)],
            [(0, 79, 2), (2.5, 76, 0.5), (3, 72, 1)],
        ],
    },
    intro=[FM, FM, DB, CMAJ],
    bpm=134,
    form=["A+sparse", "A", "B+harm", "B+glitch"],
    lowpass=0.55,
    rms=0.199,
)

STAGES = {stage.name: stage for stage in (GENERATION_FLOOR, AGENTIC_CORE)}


def mtof(midi: float) -> float:
    """Frequency in Hz of a MIDI note number (A4 = 69 = 440 Hz)."""
    return 440 * 2 ** ((midi - 69) / 12)


def blep(phase: float, step: float) -> float:
    """Smooth the pulse's discontinuities over a sample to tame high-frequency aliasing."""
    if phase < step:
        x = phase / step
        return x + x - x * x - 1
    if phase > 1 - step:
        x = (phase - 1) / step
        return x * x + x + x + 1
    return 0.0


def harmony_below(midi: int, tones: tuple[int, ...]) -> int:
    """The highest chord tone at least a minor third below `midi`."""
    classes = {tone % 12 for tone in tones}
    candidate = midi - 3
    while candidate % 12 not in classes:
        candidate -= 1
    return candidate


class Score:
    """A stereo intro + loop buffer; writes past the end wrap to the loop start."""

    def __init__(self, body_bars: int, bpm: float) -> None:
        """Allocate the 4-bar intro and a `body_bars` loop of silence at `bpm`."""
        self.beat = 60 / bpm
        self.loop_start = round(INTRO_BARS * METER * self.beat * RATE)
        self.size = round((INTRO_BARS + body_bars) * METER * self.beat * RATE)
        self.body = self.size - self.loop_start
        self.left = [0.0] * self.size
        self.right = [0.0] * self.size
        self.send = [0.0] * self.size  # the lead's echo send (mono)
        self.lfsr = 1

    def wrap(self, index: int) -> int:
        """The buffer index for a sample position, wrapping past the end into the loop."""
        if index < self.size:
            return index
        return self.loop_start + (index - self.loop_start) % self.body

    def add(self, index: int, value: float, pan: float, send: float) -> None:
        """Mix `value` at `index`, panned -1 (left) to 1 (right), plus an echo send."""
        i = self.wrap(index)
        angle = (pan + 1) * math.pi / 4
        self.left[i] += value * math.cos(angle)
        self.right[i] += value * math.sin(angle)
        if send:
            self.send[i] += value * send

    def tone(
        self,
        kind: str,
        midi: float,
        beat: float,
        beats: float,
        gain: float,
        pan: float = 0.0,
        duty: float = 0.5,
        vibrato: float = 0.0,
        attack: float = 0.006,
        release: float = 0.04,
        decay: float = 0.5,
        sustain: float = 0.6,
        send: float = 0.0,
        ratio: float = 2.0,
        index: float = 1.5,
        bright: float = 0.0,
        feedback: float = 0.0,
    ) -> None:
        """Add one note starting on `beat` (from the file start) for `beats` beats.

        `kind` is "pulse" (with `duty`), "tri", or "fm": a Genesis-style pair, a sine
        carrier modulated at `ratio` times its pitch by an operator with self-`feedback`
        (brassy and gritty as it rises). The modulation `index` follows the note's decay,
        or, with `bright` seconds, falls fast to a quarter for a slap or pluck.
        The envelope rises over `attack` seconds, decays toward `sustain` with time
        constant `decay` and releases over the last `release` seconds.
        """
        first = round(beat * self.beat * RATE)
        count = round(beats * self.beat * RATE)
        base = mtof(midi)
        offset = 2 * duty - 1
        phase = modulator = previous = 0.0
        for n in range(count):
            t = n / RATE
            frequency = base
            if vibrato and t > 0.18:
                frequency *= 1 + vibrato * min(1.0, (t - 0.18) * 4) * math.sin(
                    TAU * 5.5 * (t - 0.18)
                )
            step = frequency / RATE
            phase += step
            if phase >= 1.0:
                phase -= 1.0
            envelope = min(1.0, t / attack, (count - 1 - n) / (RATE * release))
            shape = sustain + (1 - sustain) * math.exp(-t / decay)
            envelope *= shape
            if kind == "pulse":
                value = (1.0 if phase < duty else -1.0) - offset
                value += blep(phase, step) - blep((phase - duty) % 1.0, step)
            elif kind == "tri":
                value = 4 * abs(phase - 0.5) - 1
            else:
                modulator += step * ratio
                if modulator >= 1.0:
                    modulator -= 1.0
                previous = math.sin(TAU * modulator + feedback * previous)
                depth = shape if not bright else 0.25 + 0.75 * math.exp(-t / bright)
                value = math.sin(TAU * phase + index * depth * previous)
            self.add(first + n, value * envelope * gain, pan, send)

    def drum(self, kind: str, beat: float, gain: float, pan: float = 0.0) -> None:
        """Add a "kick" (pitch-swept sine), "snare", "clap" or "hat" (LFSR noise)."""
        if gain <= 0:
            return
        first = round(beat * self.beat * RATE)
        seconds, fall = {
            "kick": (0.3, 0.12),
            "snare": (0.2, 0.07),
            "clap": (0.22, 0.06),
            "hat": (0.05, 0.014),
            "open": (0.16, 0.05),
        }[kind]
        phase = 0.0
        for n in range(round(seconds * RATE)):
            t = n / RATE
            if kind == "kick":
                phase += (46 + 110 * math.exp(-t / 0.025)) / RATE
                value = math.sin(TAU * phase) + 0.3 * math.exp(-t / 0.004)
                level = math.exp(-t / fall)
            else:
                tap = 6 if kind in ("hat", "open") else 1  # NES short mode sounds metallic
                bit = (self.lfsr ^ (self.lfsr >> tap)) & 1
                self.lfsr = (self.lfsr >> 1) | (bit << 14)
                value = 1.0 if self.lfsr & 1 else -1.0
                if kind == "snare":
                    value = 0.7 * value + 0.5 * math.sin(TAU * 190 * t) * math.exp(-t / 0.04)
                level = math.exp(-t / fall)
                if kind == "clap":  # three quick bursts, then the tail
                    burst = t % 0.011
                    level = math.exp(-burst / 0.003) if t < 0.033 else math.exp(-(t - 0.033) / fall)
            level *= min(1.0, t / 0.0015)
            self.add(first + n, value * level * gain, pan, 0.0)

    def echo(self, delay_beats: float, feedback: float, wet: float) -> None:
        """Ping-pong the lead's echo send, run twice so its tail carries over the seam."""
        delay = round(delay_beats * self.beat * RATE)
        size, send = self.size, self.send
        echo = [0.0] * size
        for _ in range(2):
            for i in range(size):
                j = i - delay
                if i >= self.loop_start and j < self.loop_start:
                    j += self.body
                echo[i] = send[i] + feedback * (echo[j] if j >= 0 else 0.0)
        half = delay // 2
        for i in range(size):
            j = i - half
            if i >= self.loop_start and j < self.loop_start:
                j += self.body
            late = echo[j] - send[j] if j >= 0 else 0.0
            self.left[i] += wet * (echo[i] - send[i])
            self.right[i] += wet * late

    def stutter(self, beat: float, slice_beats: float, repeats: int) -> None:
        """Repeat a short slice of the mix (a data glitch), crushed to 6 bits."""
        first = round(beat * self.beat * RATE)
        length = round(slice_beats * self.beat * RATE)
        for channel in (self.left, self.right):
            grain = [channel[self.wrap(first + n)] for n in range(length)]
            for r in range(1, repeats + 1):
                for n in range(length):
                    i = self.wrap(first + r * length + n)
                    edge = min(1.0, n / 40, (length - 1 - n) / 40)
                    crushed = round(grain[n] * 32) / 32
                    channel[i] = channel[i] * (1 - edge) + crushed * edge


def bar_chords(stage: Stage) -> list:
    """(section name, variation, bar within the section) for every body bar, in order."""
    bars = []
    for section in stage.form:
        name, _, variation = section.partition("+")
        for bar in range(8):
            bars.append((name, variation, bar))
    return bars


def slap(score: Score, midi: int, beat: float, beats: float, gain: float) -> None:
    """A Genesis-style FM slap-bass note with a triangle under it for weight."""
    score.tone("fm", midi, beat, beats, gain, ratio=1.0, index=3.2, bright=0.035,
               feedback=0.35, decay=0.12, sustain=0.35, release=0.02)
    score.tone("tri", midi, beat, beats, gain * 0.5, release=0.02)


def brass(score: Score, tones, beat: float, beats: float, gain: float, lift: int = 12) -> None:
    """A brass-like FM chord stab, spread across the stereo field."""
    for k, midi in enumerate(tones):
        score.tone("fm", midi + lift, beat, beats, gain, pan=(-0.45, 0.0, 0.45)[k], ratio=1.0,
                   index=1.6, feedback=0.7, attack=0.015, decay=0.18, sustain=0.45, release=0.05)


def breakbeat(score: Score, o: float, kicks, last: bool, snare: float, fill_from: float) -> None:
    """Punchy brawler drums: `kicks`, a hard backbeat with ghost notes and 16th hats."""
    for beat in kicks:
        score.drum("kick", o + beat, 0.72)
    score.drum("snare", o + 1, snare, -0.05)
    score.drum("clap", o + 1, snare * 0.45, 0.1)
    if last:
        steps = round((4 - fill_from) * 4)
        for k in range(steps):
            score.drum("snare", o + fill_from + k * 0.25, 0.07 + 0.16 * k / steps, -0.15 + 0.3 * k / steps)
    else:
        score.drum("snare", o + 3, snare, -0.05)
        score.drum("clap", o + 3, snare * 0.45, 0.1)
        for ghost in (1.75, 2.25, 3.75):
            score.drum("snare", o + ghost, snare * 0.2, -0.2)
    for sixteenth in range(16):
        if sixteenth % 2:
            score.drum("hat", o + sixteenth * 0.25, 0.022, 0.35)
        else:
            score.drum("hat", o + sixteenth * 0.25, 0.055 if sixteenth % 4 else 0.04, 0.3)


def compose_generation_floor(score: Score, stage: Stage) -> None:
    """Stage 1: a heroic F major Genesis FM street-brawler groove for the expo hall."""
    # Intro: brass hits ring the rising F-A-C motif, the break kicks in, a roll leads in.
    for bar, (root, tones) in enumerate(stage.intro):
        o = bar * METER
        if bar in (0, 2):
            lift = 0 if bar == 0 else 12
            for k, midi in enumerate((65, 69, 72)):
                score.tone("fm", midi + lift, o + k * 0.5, 1.5 if k == 2 else 0.45, 0.13,
                           pan=0.25 * (k - 1), ratio=1.0, index=1.6, feedback=0.7,
                           attack=0.015, decay=0.3, sustain=0.5, release=0.08, send=0.5)
            score.drum("kick", o, 0.8)
            score.drum("open", o, 0.1, -0.3)
        if bar >= 1:
            breakbeat(score, o, (0, 1.75, 2.5), bar == 3, 0.2, 2.0)
            for beat, interval, beats in ((0, 0, 0.35), (0.75, 0, 0.2), (1.5, 12, 0.3), (2.5, 0, 0.3)):
                slap(score, root + interval, o + beat, beats, 0.2)
    # Body.
    for index, (name, variation, bar) in enumerate(bar_chords(stage)):
        o = (INTRO_BARS + index) * METER
        root, tones = stage.chords[name][bar]
        last = bar == 7
        # Slap bass: syncopated 16ths, popping the octave.
        for beat, interval, beats in ((0, 0, 0.35), (0.75, 0, 0.2), (1.5, 12, 0.3), (2, 0, 0.3),
                                      (2.5, 0, 0.2), (2.75, 12, 0.2), (3.5, 7, 0.35)):
            slap(score, root + interval, o + beat, beats, 0.26)
        # Brass stabs: on the one and the anticipation in A, on the offbeats in B.
        for beat, beats in ((0, 0.4), (1.5, 0.3)) if name == "A" else ((0.5, 0.3), (2.5, 0.3)):
            brass(score, tones, o + beat, beats, 0.04)
        # Square arpeggio sparkle high up, sweeping left to right.
        arp = [tones[0] + 24, tones[1] + 24, tones[2] + 24, tones[0] + 36]
        for sixteenth in range(16):
            score.tone("pulse", arp[(0, 1, 2, 3, 2, 1, 0, 1)[sixteenth % 8]], o + sixteenth * 0.25,
                       0.18, 0.016, pan=-0.5 + sixteenth / 15, duty=0.25, decay=0.05, sustain=0.1)
        breakbeat(score, o, (0, 1.75, 2.5) if bar % 2 == 0 else (0, 0.75, 2.5, 3.25), last, 0.22, 2.5)
        if bar == 0:
            score.drum("open", o, 0.1, -0.3)
        # Heroic lead: brassy FM with a square an octave up, echoing.
        for beat, midi, beats in stage.melody[name][bar]:
            score.tone("fm", midi, o + beat, beats * 0.9, 0.12, ratio=1.0, index=1.3, feedback=0.6,
                       vibrato=0.006, attack=0.012, decay=0.4, sustain=0.65, send=0.5)
            score.tone("pulse", midi + 12, o + beat, beats * 0.9, 0.03, pan=0.2, duty=0.25,
                       vibrato=0.006, decay=0.3, sustain=0.4)
            if variation == "harm":
                score.tone("fm", harmony_below(midi, tones), o + beat, beats * 0.9, 0.07, pan=-0.4,
                           ratio=1.0, index=1.1, feedback=0.6, vibrato=0.006, decay=0.4, sustain=0.6)
    score.echo(0.75, 0.28, 0.25)


def compose_agentic_core(score: Score, stage: Stage) -> None:
    """Stage 3: a dark, driving F minor FM brawler for the machine core."""
    # Intro: the gritty bass locks in, the falling motif sounds as an alarm, a roll.
    for bar, (root, tones) in enumerate(stage.intro):
        o = bar * METER
        for sixteenth in range(16):
            octave = 12 if sixteenth % 4 == 2 else 0
            score.tone("fm", root + octave, o + sixteenth * 0.25, 0.2, 0.1 + 0.02 * bar, ratio=1.0,
                       index=2.4, feedback=0.9, decay=0.05, sustain=0.35, release=0.015)
        for beat in range(4):
            score.drum("kick", o + beat, 0.7)
        if bar >= 1:
            for sixteenth in range(16):
                score.drum("hat", o + sixteenth * 0.25, 0.05 if sixteenth % 2 else 0.02, 0.25)
        if bar in (0, 2):
            for k, midi in enumerate((84, 80, 77)):
                score.tone("fm", midi, o + k * 0.75, 0.7, 0.11, pan=0.3 * (1 - k),
                           ratio=1.0, index=2.5, decay=0.3, sustain=0.3, send=0.7)
        if bar == 3:
            for k in range(16):
                score.drum("snare", o + k * 0.25, 0.05 + 0.011 * k, 0.1)
    # Body.
    for index, (name, variation, bar) in enumerate(bar_chords(stage)):
        o = (INTRO_BARS + index) * METER
        root, tones = stage.chords[name][bar]
        last = bar == 7
        # Gritty FM bass: relentless 16ths, the octave on each "and-a", a fifth to turn.
        for sixteenth in range(16):
            interval = (0, 0, 12, 0)[sixteenth % 4]
            if sixteenth == 15:
                interval = 7
            score.tone("fm", root + interval, o + sixteenth * 0.25, 0.2, 0.13, ratio=1.0,
                       index=2.4, feedback=0.9, decay=0.05, sustain=0.35, release=0.015)
            if sixteenth % 4 == 0:
                score.tone("tri", root - 12, o + sixteenth * 0.25, 0.9, 0.2, release=0.03)
        # Scanning arpeggio: up two octaves and back, sweeping left to right and back.
        arp = sorted({t + 12 * k for t in tones for k in (0, 1)})
        scan = arp + arp[-2:0:-1]
        for sixteenth in range(16):
            step = index * 16 + sixteenth
            pan = math.sin(TAU * step / 32) * 0.7
            score.tone("pulse", scan[step % len(scan)] + 12, o + sixteenth * 0.25, 0.18,
                       0.02 if variation == "sparse" else 0.026, pan=pan, duty=0.125,
                       decay=0.05, sustain=0.15)
        # Brass hits: a stab every bar, a second push before the turnaround.
        brass(score, tones, o, 0.5, 0.045, lift=0)
        if bar % 2:
            brass(score, tones, o + 2.75, 0.35, 0.04, lift=0)
        # Drums: a heavy break with metallic hits on the "and" of four.
        breakbeat(score, o, (0, 0.75, 1.5, 2.5, 2.75) if bar % 2 == 0 else (0, 1.5, 2, 2.75),
                  last, 0.24, 2.0)
        if not last:
            score.drum("open", o + 3.5, 0.09, 0.4)
        # Lead: cold FM; the sparse first section only quotes the motif.
        for beat, midi, beats in stage.melody[name][bar]:
            if variation == "sparse" and bar % 2:
                continue
            score.tone("fm", midi, o + beat, beats * 0.9, 0.12, ratio=2.0, index=1.6,
                       vibrato=0.003, decay=0.35, sustain=0.55, send=0.55)
            score.tone("pulse", midi + 12, o + beat, beats * 0.9, 0.025, pan=0.25,
                       duty=0.125, decay=0.2, sustain=0.3)
            if variation == "harm":
                score.tone("fm", harmony_below(midi, tones), o + beat, beats * 0.9, 0.07,
                           pan=-0.4, ratio=3.0, index=1.0, decay=0.35, sustain=0.5)
    score.echo(0.75, 0.35, 0.28)
    # Data glitches: stutter the last half-beat of the glitch section's phrases.
    for index, (name, variation, bar) in enumerate(bar_chords(stage)):
        o = (INTRO_BARS + index) * METER
        if variation == "glitch" and bar in (1, 3, 5):
            score.stutter(o + 3.5, 0.0625, 7)


def render(stage: Stage) -> tuple[list[int], int]:
    """Compose `stage`; return interleaved 16-bit samples and the loop start frame."""
    score = Score(8 * len(stage.form), stage.bpm)
    if stage.name == "generation_floor":
        compose_generation_floor(score, stage)
    else:
        compose_agentic_core(score, stage)
    channels = [score.left, score.right]
    # Low-pass: settle on the loop body first so the state at the seam is continuous.
    filtered = []
    for channel in channels:
        previous = 0.0
        for sample in channel[score.loop_start :]:
            previous += stage.lowpass * (sample - previous)
        previous_body = previous
        out = [0.0] * score.size
        previous = 0.0
        for i, sample in enumerate(channel):
            if i == score.loop_start:
                # The body starts in its settled loop state so the seam is continuous.
                # Ramp the difference into the intro's last 5 ms so the first pass
                # into the body has no step either.
                step = (1 - stage.lowpass) * (previous_body - previous)
                ramp = round(0.005 * RATE)
                for k in range(ramp):
                    out[i - ramp + k] += step * (k + 1) / (ramp + 1)
                previous = previous_body
            previous += stage.lowpass * (sample - previous)
            out[i] = previous
        filtered.append(out)
    body = [x for channel in filtered for x in channel[score.loop_start :]]
    rms = math.sqrt(sum(x * x for x in body) / len(body))
    scale = stage.rms / rms
    frames = []
    for left, right in zip(*filtered):
        frames.append(round(soft_limit(left * scale) * 32767))
        frames.append(round(soft_limit(right * scale) * 32767))
    return frames, score.loop_start


def soft_limit(x: float) -> float:
    """Pass the sample below KNEE; above it, bend smoothly toward MAX_PEAK."""
    size = abs(x)
    if size <= KNEE:
        return x
    room = MAX_PEAK - KNEE
    return math.copysign(KNEE + room * math.tanh((size - KNEE) / room), x)


def build(out: Path, name: str) -> None:
    """Write stage `name` to `out` as stereo WAV; print its loop offset and SHA-256."""
    out.mkdir(parents=True, exist_ok=True)
    frames, loop_start = render(STAGES[name])
    path = out / f"heroes_villains_{name}.wav"
    with wave.open(str(path), "wb") as stream:
        stream.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(struct.pack(f"<{len(frames)}h", *frames))
    print(
        f"{path.name}: {len(frames) // 2} frames, {len(frames) / 2 / RATE:.6f}s, "
        f"loop_offset {loop_start / RATE:.6f}s, bpm {STAGES[name].bpm}, "
        f"SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=sorted(STAGES), required=True)
    parser.add_argument(
        "--out",
        type=Path,
        default=OUT,
        help="Destination directory (encode the WAV to OGG from there)",
    )
    arguments = parser.parse_args()
    build(arguments.out, arguments.stage)
