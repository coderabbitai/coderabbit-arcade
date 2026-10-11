"""Original CC0 Code City victory music. No samples, network, random state or dependencies.

Rebuild from the repository root with `python3 tools/build_code_city_victory_music.py`.
F major, 116 BPM, square-wave lead/chords and an octave-hopping pulse bass. Notes have
short attack/release envelopes; both ends of the loop taper to an exact zero sample.
The generated compositions and recordings are dedicated to the public domain under CC0 1.0.
"""

import argparse
import hashlib
import math
from pathlib import Path
import struct
import wave


OUT = (
    Path(__file__).resolve().parents[1]
    / "hoppys-adventure-arcade/Assets/Audio/Beat'em Up"
)
RATE = 44100
BPM = 116
BEAT = 60 / BPM
JINGLE_SECONDS = 3.5
LOOP_BEATS = 32


def blep(phase: float, step: float) -> float:
    """Smooth the square's discontinuities over a sample to tame high-frequency aliasing."""
    if phase < step:
        x = phase / step
        return x + x - x * x - 1
    if phase > 1 - step:
        x = (phase - 1) / step
        return x * x + x + x + 1
    return 0.0


def note(
    samples: list[float], midi: int, start: float, beats: float, gain: float
) -> None:
    first = round(start * BEAT * RATE)
    count = min(round(beats * BEAT * RATE), len(samples) - first)
    frequency = 440 * 2 ** ((midi - 69) / 12)
    step = frequency / RATE
    for index in range(count):
        phase = (index * step) % 1.0
        pulse = (
            (1.0 if phase < 0.5 else -1.0)
            + blep(phase, step)
            - blep((phase + 0.5) % 1, step)
        )
        attack = min(1.0, index / (RATE * 0.006))
        release = min(1.0, (count - 1 - index) / (RATE * 0.022))
        envelope = attack * release * (0.82 + 0.18 * (1 - index / count))
        samples[first + index] += pulse * envelope * gain


def jingle() -> list[float]:
    samples = [0.0] * round(JINGLE_SECONDS * RATE)
    # F-A-C rises through the triad, peaks at F, then the dominant resolves to the tonic.
    melody = [
        (0, 65, 0.46),
        (0.5, 69, 0.46),
        (1, 72, 0.46),
        (1.5, 77, 0.46),
        (2, 76, 0.46),
        (2.5, 72, 0.46),
        (3, 79, 0.85),
        (4, 77, 2.65),
    ]
    for start, midi, length in melody:
        note(samples, midi, start, length, 0.25)
    for start, root in [(0, 41), (1, 53), (2, 48), (3, 60), (4, 41), (5, 53)]:
        note(samples, root, start, 0.8, 0.15)
    for start, chord in [(0, (53, 57, 60)), (2, (55, 60, 64)), (4, (53, 57, 60))]:
        for midi in chord:
            note(samples, midi, start, 1.8, 0.045)
    return samples


def victory_loop() -> list[float]:
    samples = [0.0] * round(LOOP_BEATS * BEAT * RATE)
    # Eight bars: I, vi, IV, V, I, vi, ii, V. The seam returns V to I on the downbeat.
    chords = [
        (41, 57, 60, 65),
        (38, 57, 62, 65),
        (46, 58, 62, 65),
        (48, 55, 60, 64),
        (41, 57, 60, 65),
        (38, 57, 62, 65),
        (43, 58, 62, 67),
        (48, 55, 60, 64),
    ]
    melody = [
        (65, 69, 72, 77, 76, 72),
        (74, 72, 69, 65, 69, 72),
        (70, 74, 77, 74, 72, 70),
        (67, 72, 76, 79, 76, 72),
        (77, 76, 72, 69, 72, 77),
        (74, 77, 81, 77, 74, 69),
        (67, 70, 74, 77, 74, 70),
        (72, 76, 79, 76, 72, 67),
    ]
    for bar, chord in enumerate(chords):
        offset = bar * 4
        for beat in range(4):
            note(samples, chord[0] + (12 if beat % 2 else 0), offset + beat, 0.72, 0.14)
        for eighth in range(8):
            note(samples, chord[1 + eighth % 3], offset + eighth * 0.5, 0.34, 0.065)
        for start, midi, length in zip(
            (0, 0.5, 1, 2, 2.5, 3), melody[bar], (0.42, 0.42, 0.8, 0.42, 0.42, 0.85)
        ):
            note(samples, midi, offset + start, length, 0.23)
    return samples


def pcm(samples: list[float]) -> bytes:
    # A gentle output low-pass rounds the pulse edges, preserving the square-wave timbre.
    output = []
    previous = 0.0
    taper = round(RATE * 0.008)
    for index, sample in enumerate(samples):
        previous += 0.62 * (sample - previous)
        edge = min(1.0, index / taper, (len(samples) - 1 - index) / taper)
        window = 0.5 - 0.5 * math.cos(math.pi * edge)
        output.append(round(max(-0.95, min(0.95, previous)) * window * 32767))
    assert output[0] == output[-1] == 0
    return struct.pack(f"<{len(output)}h", *output)


def build(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, samples in [("jingle", jingle()), ("loop", victory_loop())]:
        path = out / f"code_city_victory_{name}.wav"
        with wave.open(str(path), "wb") as stream:
            stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            stream.writeframes(pcm(samples))
        print(
            f"{path.name}: {len(samples) / RATE:.6f}s SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=OUT,
        help="Destination directory for deterministic rebuild checks",
    )
    build(parser.parse_args().out)
