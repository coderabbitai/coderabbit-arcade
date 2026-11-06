"""Original CC0 hub music: calm 8-bit loops that can play all day at a booth.

Rebuild from the repository root with `python3 tools/build_hub_chiptune.py` (the hub's
song) or `--song <name>` for another arrangement. Every song is in F major, the arcade's
key, and is built from an 8-bar A and B section arranged into a 32-bar or longer form:
the second A adds a harmony a diatonic third below, and the last A opens with the tune
an octave down on the triangle before the pulse lead returns.

The engine is a small NES-style synth: anti-aliased pulse waves (12.5/25/50% duty)
with delayed vibrato, a triangle, a 15-bit LFSR noise channel for soft drums and an
echo on the lead. Every voice and the echo wrap around the loop end, and the output
low-pass runs twice so its state is continuous across the seam: the loop has no gap,
fade or click. No samples, network, random state or dependencies.
The generated compositions and recordings are dedicated to the public domain under CC0 1.0.
"""

import argparse
from dataclasses import dataclass, field
import hashlib
import math
from pathlib import Path
import struct
import wave


OUT = (
    Path(__file__).resolve().parents[1]
    / "hoppys-adventure-arcade/Assets/Audio/Main Menu"
)
NAME = "hub_chiptune_loop.wav"
RATE = 22050
TAU = 2 * math.pi
TARGET_RMS = 0.11
MAX_PEAK = 0.5
SCALE = sorted(m for m in range(24, 108) if m % 12 in (5, 7, 9, 10, 0, 2, 4))  # F major

# Chords: (bass root in octave 2-3, chord tones around middle C).
F = (41, (57, 60, 65))
FMAJ7 = (41, (57, 60, 64))
DM = (38, (57, 62, 65))
DM7 = (38, (57, 60, 65))
BB = (46, (58, 62, 65))
BBMAJ7 = (46, (57, 62, 65))
C = (48, (55, 60, 64))
C7 = (48, (58, 60, 64))
AM = (45, (57, 60, 64))
AM7 = (45, (55, 60, 64))
GM = (43, (58, 62, 67))
GM7 = (43, (58, 62, 65))


@dataclass
class Song:
    bpm: float
    meter: int  # beats per bar
    swing: float  # where the offbeat eighth falls in the beat: 0.5 is straight
    chords: dict[str, list]
    melody: dict[str, list]  # per bar: (beat, midi, beats)
    form: list[str]  # section names, with "+harm" or "+low" variations
    lead_duty: float
    harm_duty: float
    lowpass: float  # one-pole coefficient; lower is warmer
    bass: str
    comp: str
    drums: str
    echo: tuple[float, float, float] = (0.75, 0.3, 0.3)  # delay in beats, feedback, wet
    gains: dict[str, float] = field(default_factory=dict)


SONGS = {
    # Lo-fi: lazy swung eighths, jazzy seventh chords, a brushed kit, a flute-like lead.
    "lofi": Song(
        bpm=84,
        meter=4,
        swing=0.6,
        chords={
            "A": [BBMAJ7, AM7, GM7, C7, FMAJ7, DM7, GM7, C7],
            "B": [DM7, GM7, C7, FMAJ7, BBMAJ7, AM7, GM7, C7],
        },
        melody={
            "A": [
                [(0.5, 69, 0.5), (1, 72, 1), (2.5, 74, 1.5)],
                [(0.5, 72, 0.5), (1, 69, 0.5), (1.5, 67, 1.5), (3.5, 64, 0.5)],
                [(0, 65, 1), (1, 67, 0.5), (1.5, 70, 1), (2.5, 69, 1.5)],
                [(0, 67, 2), (3, 64, 0.5), (3.5, 65, 0.5)],
                [(0, 69, 1.5), (1.5, 72, 0.5), (2, 76, 2)],
                [(0.5, 74, 0.5), (1, 72, 0.5), (1.5, 69, 1), (2.5, 65, 1.5)],
                [
                    (0, 67, 0.5),
                    (0.5, 70, 0.5),
                    (1, 74, 1),
                    (2, 72, 0.5),
                    (2.5, 70, 0.5),
                    (3, 69, 1),
                ],
                [(0, 67, 3)],
            ],
            "B": [
                [(0, 77, 1.5), (1.5, 76, 0.5), (2, 74, 2)],
                [(0.5, 70, 0.5), (1, 74, 1), (2, 77, 1), (3, 74, 1)],
                [(0, 76, 1), (1, 72, 1), (2, 70, 2)],
                [(0, 69, 3)],
                [(0.5, 74, 0.5), (1, 77, 1), (2, 81, 1), (3, 77, 1)],
                [(0, 76, 1.5), (1.5, 72, 0.5), (2, 67, 2)],
                [(0, 70, 1), (1, 69, 1), (2, 67, 1), (3, 65, 1)],
                [(0, 64, 2), (2, 67, 2)],
            ],
        },
        form=["A", "A+harm", "B", "A+low"],
        lead_duty=0.5,
        harm_duty=0.25,
        lowpass=0.32,
        bass="walk",
        comp="pad",
        drums="brush",
        gains={
            "lead": 0.2,
            "harm": 0.08,
            "bass": 0.3,
            "comp": 0.045,
            "kick": 0.35,
            "snare": 0.05,
            "hat": 0.02,
        },
    ),
    # Waltz: a cozy 3/4 village tune, oom-pah-pah bass and chords, a shaker and no kick.
    "waltz": Song(
        bpm=108,
        meter=3,
        swing=0.5,
        chords={
            "A": [F, F, BB, F, DM, GM, C, C],
            "B": [BB, C, AM, DM, GM, C, F, C],
        },
        melody={
            "A": [
                [(0, 72, 2), (2, 69, 1)],
                [(0, 65, 1), (1, 69, 1), (2, 72, 1)],
                [(0, 74, 2), (2, 77, 1)],
                [(0, 77, 1), (1, 76, 1), (2, 72, 1)],
                [(0, 74, 2), (2, 69, 1)],
                [(0, 70, 1), (1, 74, 1), (2, 72, 1)],
                [(0, 67, 1), (1, 70, 1), (2, 72, 1)],
                [(0, 76, 3)],
            ],
            "B": [
                [(0, 77, 2), (2, 74, 1)],
                [(0, 76, 2), (2, 72, 1)],
                [(0, 72, 1), (1, 76, 1), (2, 81, 1)],
                [(0, 77, 3)],
                [(0, 74, 1), (1, 77, 1), (2, 74, 1)],
                [(0, 72, 1), (1, 70, 1), (2, 67, 1)],
                [(0, 69, 1), (1, 72, 1), (2, 77, 1)],
                [(0, 76, 2), (2, 74, 1)],
            ],
        },
        form=["A", "A+harm", "B", "A+low", "B+harm", "A"],
        lead_duty=0.5,
        harm_duty=0.25,
        lowpass=0.42,
        bass="oompah",
        comp="oompah",
        drums="shaker",
        echo=(1.0, 0.25, 0.25),
        gains={
            "lead": 0.2,
            "harm": 0.08,
            "bass": 0.3,
            "comp": 0.04,
            "kick": 0.0,
            "snare": 0.0,
            "hat": 0.02,
        },
    ),
    # Arcade: a gentle straight-eighths groove, octave-bouncing bass, offbeat chord chips.
    "arcade": Song(
        bpm=100,
        meter=4,
        swing=0.5,
        chords={
            "A": [F, C, DM, BB, F, C, BB, C],
            "B": [DM, BB, F, C, DM, BB, GM, C],
        },
        melody={
            "A": [
                [
                    (0, 72, 0.5),
                    (0.5, 74, 0.5),
                    (1, 72, 1),
                    (2, 69, 0.5),
                    (2.5, 72, 1.5),
                ],
                [(0, 67, 1), (1, 72, 1), (2, 76, 2)],
                [(0, 74, 0.5), (0.5, 72, 0.5), (1, 69, 1), (2, 74, 1), (3, 72, 1)],
                [(0, 70, 1.5), (1.5, 69, 0.5), (2, 65, 2)],
                [(0, 72, 0.5), (0.5, 74, 0.5), (1, 72, 1), (2, 77, 1), (3, 76, 1)],
                [(0, 74, 1), (1, 72, 1), (2, 67, 1), (3, 72, 1)],
                [(0, 74, 1), (1, 77, 1), (2, 74, 1), (3, 70, 1)],
                [(0, 72, 3)],
            ],
            "B": [
                [(0, 69, 1), (1, 74, 1), (2, 77, 1.5), (3.5, 76, 0.5)],
                [(0, 74, 2), (2, 70, 2)],
                [(0, 72, 1), (1, 77, 1), (2, 81, 2)],
                [(0, 79, 1), (1, 76, 1), (2, 72, 2)],
                [(0, 74, 1), (1, 77, 1), (2, 74, 1), (3, 72, 1)],
                [(0, 70, 1), (1, 74, 1), (2, 77, 2)],
                [(0, 79, 1), (1, 77, 1), (2, 74, 1), (3, 70, 1)],
                [(0, 72, 2), (2, 67, 2)],
            ],
        },
        form=["A", "A+harm", "B", "A+low"],
        lead_duty=0.25,
        harm_duty=0.125,
        lowpass=0.5,
        bass="bounce",
        comp="offbeat",
        drums="kit",
        gains={
            "lead": 0.19,
            "harm": 0.07,
            "bass": 0.24,
            "comp": 0.035,
            "kick": 0.3,
            "snare": 0.05,
            "hat": 0.018,
        },
    ),
}
DEFAULT_SONG = "lofi"


def mtof(midi: float) -> float:
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


class Track:
    """A loop-length buffer; every write wraps past the end back to the start."""

    def __init__(self, song: Song, bars: int) -> None:
        self.song = song
        self.beat = 60 / song.bpm
        self.samples = [0.0] * round(bars * song.meter * self.beat * RATE)

    def at(self, beat: float) -> float:
        """Seconds for a beat position, with swung offbeat eighths."""
        whole = math.floor(beat)
        frac = beat - whole
        s = self.song.swing
        frac = frac / 0.5 * s if frac < 0.5 else s + (frac - 0.5) / 0.5 * (1 - s)
        return (whole + frac) * self.beat

    def tone(
        self,
        buf: list[float],
        kind: str,
        midi: float,
        beat: float,
        beats: float,
        gain: float,
        duty: float = 0.5,
        vibrato: float = 0.0,
        attack: float = 0.012,
        release: float = 0.07,
        decay: float = 0.6,
        sustain: float = 0.55,
    ) -> None:
        start = self.at(beat)
        length = self.at(beat + beats) - start
        first, count, size = round(start * RATE), round(length * RATE), len(buf)
        base = mtof(midi)
        offset = 2 * duty - 1  # the naive pulse's DC level
        phase = 0.0
        for index in range(count):
            t = index / RATE
            frequency = base
            if vibrato and t > 0.2:
                frequency *= 1 + vibrato * min(1.0, (t - 0.2) * 4) * math.sin(
                    TAU * 5.2 * (t - 0.2)
                )
            step = frequency / RATE
            phase += step
            if phase >= 1.0:
                phase -= 1.0
            if kind == "pulse":
                value = (1.0 if phase < duty else -1.0) - offset
                value += blep(phase, step) - blep((phase - duty) % 1.0, step)
            else:
                value = 4 * abs(phase - 0.5) - 1
            envelope = min(1.0, t / attack, (count - 1 - index) / (RATE * release))
            envelope *= sustain + (1 - sustain) * math.exp(-t / decay)
            buf[(first + index) % size] += value * envelope * gain

    def drum(
        self, buf: list[float], kind: str, beat: float, gain: float, lfsr: list[int]
    ) -> None:
        if gain <= 0:
            return
        first, size = round(self.at(beat) * RATE), len(buf)
        seconds, fall = {
            "kick": (0.25, 0.11),
            "snare": (0.22, 0.08),
            "hat": (0.06, 0.018),
        }[kind]
        phase = 0.0
        for index in range(round(seconds * RATE)):
            t = index / RATE
            if kind == "kick":
                phase += (48 + 80 * math.exp(-t / 0.03)) / RATE
                value = math.sin(TAU * phase)
            else:
                tap = 6 if kind == "hat" else 1  # NES short mode sounds metallic
                bit = (lfsr[0] ^ (lfsr[0] >> tap)) & 1
                lfsr[0] = (lfsr[0] >> 1) | (bit << 14)
                value = 1.0 if lfsr[0] & 1 else -1.0
            attack = min(1.0, t / 0.002)
            buf[(first + index) % size] += value * attack * math.exp(-t / fall) * gain


def harmony_below(midi: int) -> int:
    return SCALE[SCALE.index(midi) - 2]


def compose(song: Song) -> list[float]:
    bars = 8 * len(song.form)
    track = Track(song, bars)
    size = len(track.samples)
    lead, other = [0.0] * size, [0.0] * size
    g = song.gains
    m = song.meter
    lfsr = [1]
    for section_index, section in enumerate(song.form):
        name, _, variation = section.partition("+")
        for bar in range(8):
            offset = (section_index * 8 + bar) * m
            root, chord = song.chords[name][bar]
            # Bass.
            if song.bass == "walk":
                for beat, interval, beats in [
                    (0, 0, 1.4),
                    (1.5, 7, 0.45),
                    (2, 0, 0.9),
                    (3, 12, 0.45),
                    (3.5, 7, 0.45),
                ]:
                    track.tone(
                        other,
                        "tri",
                        root + interval,
                        offset + beat,
                        beats,
                        g["bass"],
                        release=0.05,
                    )
            elif song.bass == "oompah":
                track.tone(
                    other, "tri", root + (7 if bar % 2 else 0), offset, 0.95, g["bass"]
                )
            else:
                for eighth in range(8):
                    track.tone(
                        other,
                        "tri",
                        root + 12 * (eighth % 2),
                        offset + eighth * 0.5,
                        0.42,
                        g["bass"],
                        release=0.04,
                    )
            # Chords.
            for tone in chord:
                if song.comp == "pad":
                    for beat, beats in [(0, 2.4), (2.5, 1.45)]:
                        track.tone(
                            other,
                            "tri",
                            tone + 12,
                            offset + beat,
                            beats,
                            g["comp"],
                            attack=0.04,
                            release=0.2,
                            decay=1.2,
                            sustain=0.5,
                        )
                elif song.comp == "oompah":
                    for beat in (1, 2):
                        track.tone(
                            other,
                            "pulse",
                            tone,
                            offset + beat,
                            0.55,
                            g["comp"],
                            duty=0.25,
                            release=0.06,
                            decay=0.25,
                            sustain=0.3,
                        )
                else:
                    for beat in (0.5, 1.5, 2.5, 3.5):
                        track.tone(
                            other,
                            "pulse",
                            tone,
                            offset + beat,
                            0.3,
                            g["comp"],
                            duty=0.125,
                            release=0.04,
                            decay=0.15,
                            sustain=0.3,
                        )
            # Drums.
            if song.drums in ("brush", "kit"):
                kicks = (0, 2.5) if song.drums == "brush" else (0, 2)
                for beat in kicks:
                    track.drum(other, "kick", offset + beat, g["kick"], lfsr)
                for beat in (1, 3):
                    track.drum(other, "snare", offset + beat, g["snare"], lfsr)
                for eighth in range(8):
                    track.drum(
                        other,
                        "hat",
                        offset + eighth * 0.5,
                        g["hat"] * (1.0 if eighth % 2 else 0.6),
                        lfsr,
                    )
            else:
                for beat in range(m):
                    track.drum(
                        other,
                        "hat",
                        offset + beat,
                        g["hat"] * (1.0 if beat else 0.5),
                        lfsr,
                    )
                    track.drum(other, "hat", offset + beat + 0.5, g["hat"] * 0.4, lfsr)
            # Melody.
            for beat, midi, beats in song.melody[name][bar]:
                low = variation == "low" and bar < 4
                if low:
                    track.tone(
                        other,
                        "tri",
                        midi - 12,
                        offset + beat,
                        beats * 0.95,
                        g["lead"] * 1.3,
                    )
                else:
                    track.tone(
                        lead,
                        "pulse",
                        midi,
                        offset + beat,
                        beats * 0.92,
                        g["lead"],
                        duty=song.lead_duty,
                        vibrato=0.005,
                    )
                if variation == "harm":
                    track.tone(
                        other,
                        "pulse",
                        harmony_below(midi),
                        offset + beat,
                        beats * 0.92,
                        g["harm"],
                        duty=song.harm_duty,
                        vibrato=0.005,
                    )
    # Echo on the lead, run twice around the loop so its tail carries over the seam.
    delay_beats, feedback, wet = song.echo
    delay = round(delay_beats * track.beat * RATE)
    echo = lead[:]
    for _ in range(2):
        for index in range(size):
            echo[index] = lead[index] + feedback * echo[index - delay]
    mix = [lead[i] + wet * (echo[i] - lead[i]) + other[i] for i in range(size)]
    # Hold the loudness, keep peaks well clear of clipping.
    rms = math.sqrt(sum(x * x for x in mix) / size)
    scale = min(TARGET_RMS / rms, MAX_PEAK / max(abs(x) for x in mix))
    return [x * scale for x in mix]


def pcm(samples: list[float], coefficient: float) -> bytes:
    # A one-pole low-pass rounds the pulse edges. A first pass settles the filter so the
    # second starts in the state the loop ends in: no step at the seam.
    previous = 0.0
    for sample in samples:
        previous += coefficient * (sample - previous)
    output = []
    for sample in samples:
        previous += coefficient * (sample - previous)
        output.append(round(max(-0.95, min(0.95, previous)) * 32767))
    return struct.pack(f"<{len(output)}h", *output)


def build(out: Path, name: str, filename: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    song = SONGS[name]
    samples = compose(song)
    path = out / filename
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(pcm(samples, song.lowpass))
    print(
        f"{path.name} ({name}): {len(samples)} frames, {len(samples) / RATE:.6f}s "
        f"SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=OUT,
        help="Destination directory for deterministic rebuild checks",
    )
    parser.add_argument(
        "--song",
        choices=sorted(SONGS),
        default=DEFAULT_SONG,
        help="Arrangement to build",
    )
    parser.add_argument("--name", default=NAME, help="Output file name")
    arguments = parser.parse_args()
    build(arguments.out, arguments.song, arguments.name)
