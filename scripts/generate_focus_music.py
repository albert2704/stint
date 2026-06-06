#!/usr/bin/env python3
"""Generate Stint's original instrumental loops using only synthesized audio.

Requires Python 3 and NumPy: install with `python3 -m pip install numpy` in a virtual
environment. Run from any directory; outputs go to ../assets/music beside this script. No samples,
network access, audio plug-ins, or random system state are used. All notes and room
reflections wrap around the loop, so sustain tails continue over its boundary.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import wave

import numpy as np


RATE = 22050
OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "music"
TAU = math.tau


def hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def release_window(t: np.ndarray, length: float, fade: float = 0.10) -> np.ndarray:
    """A cosine release has zero slope at the truncated end of every voice."""
    u = np.clip((length - t) / fade, 0, 1)
    return 0.5 - 0.5 * np.cos(np.pi * u)


def voice(kind: str, note: float, length: float, seed: int) -> np.ndarray:
    t = np.arange(round(length * RATE), dtype=np.float64) / RATE
    frequency = hz(note)
    angle = TAU * frequency * t
    rng = np.random.default_rng(seed)
    if kind == "keys":
        # A soft, slightly inharmonic tine attack with a rounded sustained body.
        body = np.sin(angle + 0.32 * np.exp(-t / 0.16) * np.sin(2 * angle))
        body += 0.19 * np.sin(angle * 2.0003) * np.exp(-t / 0.62)
        body += 0.075 * np.sin(angle * 3.0008) * np.exp(-t / 0.42)
        body += 0.018 * np.sin(angle * 6.0015) * np.exp(-t / 0.12)
        envelope = (1 - np.exp(-t / 0.012)) * np.exp(-t / (1.55 + 18 / frequency))
    elif kind == "pad":
        # Close detuning, varied starting phases, and a slow envelope create a
        # gentle ensemble. The envelope hides each voice's oscillator onset.
        body = np.zeros_like(t)
        for detune, level in ((-0.0009, 0.36), (0, 0.42), (0.0008, 0.36)):
            phase = rng.uniform(0, TAU)
            a = angle * (1 + detune) + phase
            body += level * (np.sin(a) + 0.12 * np.sin(2 * a) + 0.025 * np.sin(3 * a))
        attack = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / 1.05, 0, 1))
        envelope = attack * release_window(t, length, 2.6)
        envelope *= 0.94 + 0.06 * np.sin(TAU * 0.17 * t + rng.uniform(0, TAU))
    elif kind == "pluck":
        # A felt-muted string: higher partials decay before the warm fundamental.
        body = np.sin(angle)
        for partial, level, decay in ((2, 0.24, .28), (3, .13, .16), (4, .035, .10)):
            body += level * np.sin(angle * partial) * np.exp(-t / decay)
        envelope = (1 - np.exp(-t / 0.008)) * np.exp(-t / 0.92)
    elif kind == "bell":
        body = np.sin(angle) + .10 * np.sin(angle * 2.002) * np.exp(-t / .8)
        envelope = (1 - np.exp(-t / .025)) * np.exp(-t / 1.8)
    elif kind == "bass":
        body = np.sin(angle) + .09 * np.sin(2 * angle) + .025 * np.sin(3 * angle)
        envelope = (1 - np.exp(-t / .08)) * np.exp(-t / 2.1)
    else:
        raise ValueError(kind)
    return body * envelope * release_window(t, length)


class Loop:
    def __init__(self, seconds: float, seed: int):
        self.seconds = seconds
        self.samples = round(seconds * RATE)
        self.audio = np.zeros((self.samples, 2), dtype=np.float64)
        self.seed = seed
        self.notes = 0

    def add(self, kind: str, note: float, start: float, length: float,
            gain: float, pan: float = 0) -> None:
        self.notes += 1
        sound = voice(kind, note, length, self.seed + self.notes * 97)
        # Constant-power stereo placement, with the bass held in the center.
        angle = (np.clip(pan, -1, 1) + 1) * np.pi / 4
        stereo = sound[:, None] * gain * np.array([np.cos(angle), np.sin(angle)])
        start_sample = round(start * RATE) % self.samples
        offset = 0
        while offset < len(stereo):
            count = min(self.samples - start_sample, len(stereo) - offset)
            self.audio[start_sample:start_sample + count] += stereo[offset:offset + count]
            offset += count
            start_sample = 0

    def finish(self, warmth: float, room: float, target_rms: float = .071) -> np.ndarray:
        dry = self.audio
        wet = np.zeros_like(dry)
        # Periodic short room reflections add space without a wash of noise.
        taps = ((.079, .18), (.137, .14), (.223, .12), (.347, .09),
                (.491, .075), (.683, .055), (.947, .035), (1.277, .022))
        for i, (delay, gain) in enumerate(taps):
            source = dry[:, ::-1] if i % 2 else dry
            wet += np.roll(source, round(delay * RATE), axis=0) * gain
        sound = dry + room * wet
        # Circular spectral filtering preserves the loop boundary. Remove DC
        # and soften treble using a gentle fourth-order low-pass shape.
        frequencies = np.fft.rfftfreq(self.samples, 1 / RATE)
        response = 1 / np.sqrt(1 + (frequencies / warmth) ** 8)
        response *= 1 - np.exp(-(frequencies / 25) ** 4)
        sound = np.fft.irfft(np.fft.rfft(sound, axis=0) * response[:, None],
                            n=self.samples, axis=0)
        sound -= np.mean(sound, axis=0)
        rms = float(np.sqrt(np.mean(sound ** 2)))
        sound *= target_rms / max(rms, 1e-12)
        # A linked gain ceiling avoids clipping without pumping or distortion.
        peak = float(np.max(np.abs(sound)))
        if peak > .64:
            sound *= .64 / peak
        return sound


def quiet_keys() -> np.ndarray:
    loop = Loop(32, 1207)
    chords = [
        [50, 57, 61, 64, 66],  # Dmaj9
        [47, 54, 57, 61, 62],  # Bm9
        [43, 54, 57, 59, 62],  # Gmaj9
        [45, 52, 54, 59, 61],  # A6/9
        [42, 50, 57, 61, 64],  # Dmaj9/F#
        [47, 54, 57, 62, 64],  # Bm11
        [40, 55, 59, 62, 66],  # Em9
        [45, 55, 59, 62, 66],  # A13sus
    ]
    motif = [73, 69, 71, 76, 73, 69, 71, 69]
    for bar, chord in enumerate(chords):
        start = bar * 4
        loop.add("bass", chord[0] - 12, start, 5.0, .040)
        for i, note in enumerate(chord[1:]):
            loop.add("keys", note, start + i * .055, 5.0, .047,
                     -.32 + i * .20)
        # Small answers at the ends of phrases; plenty of silence to think.
        loop.add("keys", chord[2], start + 1.5, 3.4, .026, -.28)
        loop.add("keys", motif[bar], start + 2.5, 4.0, .025, .30)
        if bar in (1, 3, 5, 7):
            loop.add("keys", motif[bar] - 2, start + 3.25, 3.8, .019, .12)
    return loop.finish(3600, .80, .068)


def warm_drift() -> np.ndarray:
    loop = Loop(30, 2113)
    chords = [
        [48, 55, 59, 62, 64], [47, 55, 59, 62, 64],
        [45, 55, 59, 60, 64], [41, 53, 57, 60, 64],
        [40, 55, 60, 64, 67], [43, 55, 59, 62, 64],
        [50, 57, 60, 64, 65], [43, 55, 59, 62, 64],
    ]
    accents = [76, 74, 71, 72, 76, 74, 72, 71]
    for bar, chord in enumerate(chords):
        start = bar * 3.75
        for i, note in enumerate(chord):
            loop.add("pad", note, start + i * .065, 6.9, .032,
                     -.62 + i * .31)
        loop.add("bass", chord[0] - 12, start + .1, 4.8, .014)
        loop.add("bell", accents[bar], start + 1.9, 4.6, .017, .38 if bar % 2 else -.38)
        if bar in (3, 7):
            loop.add("bell", accents[bar] + 5, start + 2.85, 4.2, .010, -.15)
    return loop.finish(2350, 1.15, .063)


def night_study() -> np.ndarray:
    loop = Loop(28, 3301)
    chords = [
        [41, 57, 60, 64, 67], [40, 55, 60, 64, 67],
        [38, 53, 57, 60, 64], [46, 53, 57, 60, 65],
        [45, 53, 57, 60, 64], [43, 53, 57, 58, 62],
        [48, 55, 58, 62, 65], [48, 55, 57, 62, 64],
    ]
    # An unhurried 6-note broken-chord pulse, with a small phrase variation.
    pattern = [(0, 1), (.5, 3), (1.25, 2), (2, 4), (2.5, 3), (3.25, 2)]
    beat = .875
    for bar, chord in enumerate(chords):
        start = bar * 3.5
        loop.add("bass", chord[0] - (12 if chord[0] > 45 else 0), start, 4.3, .039)
        for i, (position, index) in enumerate(pattern):
            note = chord[index] + (12 if i == 3 and bar in (2, 6) else 0)
            gain = .047 if i == 0 else (.033 if i % 2 else .039)
            loop.add("pluck", note, start + position * beat, 3.3, gain,
                     [-.32, .24, -.08, .38, -.24, .10][i])
        for i, note in enumerate(chord[1:4]):
            loop.add("pad", note, start + .15, 5.6, .011, -.4 + i * .4)
    return loop.finish(2950, .72, .071)


TRACKS = {
    "quiet_keys": ("Quiet Keys", 32, quiet_keys),
    "warm_drift": ("Warm Drift", 30, warm_drift),
    "night_study": ("Night Study", 28, night_study),
}


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.rint(np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes(order="C"))


def validate(path: Path, expected_seconds: float) -> dict:
    with wave.open(str(path), "rb") as source:
        channels, width, rate, frames = (source.getnchannels(), source.getsampwidth(),
                                         source.getframerate(), source.getnframes())
        data = np.frombuffer(source.readframes(frames), dtype="<i2").reshape(-1, channels)
    samples = data.astype(np.float64) / 32768
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples ** 2)))
    differences = np.abs(np.diff(samples, axis=0))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    p99_step = float(np.quantile(differences, .99))
    # A loop boundary is a normal neighboring sample pair, not a fade to silence.
    seam_slope_change = float(np.max(np.abs((samples[1] - samples[0]) -
                                           (samples[0] - samples[-1]))))
    rms_start = float(np.sqrt(np.mean(samples[:RATE // 10] ** 2)))
    rms_end = float(np.sqrt(np.mean(samples[-RATE // 10:] ** 2)))
    stereo_difference_rms = float(np.sqrt(np.mean((samples[:, 0] - samples[:, 1]) ** 2)))
    assert (channels, width, rate) == (2, 2, RATE)
    assert frames == round(expected_seconds * RATE)
    assert np.isfinite(samples).all()
    assert 0.02 < rms < 0.15 and peak < .8, (path, peak, rms)
    assert np.max(np.abs(np.mean(samples, axis=0))) < 0.0001
    assert seam < max(.002, p99_step * 2), (path, "seam", seam, p99_step)
    assert seam_slope_change < .003, (path, "seam curvature", seam_slope_change)
    assert min(rms_start, rms_end) > .005, "Loop must not dip into silence at boundary"
    assert stereo_difference_rms > .001, "Expected a real stereo mix"
    return {
        "file": path.name, "seconds": frames / rate, "bytes": path.stat().st_size,
        "sample_rate": rate, "channels": channels, "pcm_bits": width * 8,
        "peak": round(peak, 6), "rms": round(rms, 6),
        "rms_dbfs": round(20 * math.log10(rms), 2),
        "seam_sample_step": round(seam, 7), "p99_sample_step": round(p99_step, 7),
        "seam_slope_change": round(seam_slope_change, 7),
        "first_100ms_rms": round(rms_start, 6), "last_100ms_rms": round(rms_end, 6),
        "stereo_difference_rms": round(stereo_difference_rms, 6),
        "validation": "passed",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if not args.validate_only:
        OUTPUT.mkdir(parents=True, exist_ok=True)
    for stem, (title, seconds, render) in TRACKS.items():
        path = OUTPUT / f"{stem}.wav"
        if not args.validate_only:
            write_wav(path, render())
        result = validate(path, seconds)
        print(json.dumps({"title": title, **result}), flush=True)


if __name__ == "__main__":
    main()
