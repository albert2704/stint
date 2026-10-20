#!/usr/bin/env python3
"""Generate Stint's original synthetic ambience; no recordings or samples.

Requires NumPy, as does generate_focus_music.py. Circular filtering and wrapped
events make the 24 second stereo PCM loops seamless. Café hum is an abstract
room of indistinct synthetic voices and small ceramic clinks, not recorded speech.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import wave

import numpy as np

RATE = 22050
SECONDS = 24
COUNT = RATE * SECONDS
ROOT = Path(__file__).resolve().parent.parent / "assets" / "music"
T = np.arange(COUNT) / RATE
F = np.fft.rfftfreq(COUNT, 1 / RATE)


def filtered_noise(rng, response):
    white = rng.normal(size=(COUNT, 2))
    return np.fft.irfft(np.fft.rfft(white, axis=0) * response[:, None],
                        n=COUNT, axis=0)


def wrap_event(output, signal, start, gain, pan):
    indices = (np.arange(len(signal)) + round(start * RATE)) % COUNT
    angle = (pan + 1) * math.pi / 4
    output[indices] += signal[:, None] * gain * [math.cos(angle), math.sin(angle)]


def brown_noise():
    rng = np.random.default_rng(10411)
    response = 1 / np.maximum(F, 28)
    response *= 1 - np.exp(-(F / 28) ** 4)
    response *= 1 / np.sqrt(1 + (F / 2800) ** 6)
    return filtered_noise(rng, response)


def rain():
    rng = np.random.default_rng(91021)
    response = (1 - np.exp(-(F / 210) ** 2)) / np.sqrt(1 + (F / 5100) ** 6)
    output = filtered_noise(rng, response) * .09
    # Broad, gently moving rain bed with irregular droplets hitting a sill.
    output *= (1 + .10 * np.sin(math.tau * T / 24) +
               .06 * np.sin(math.tau * T / 8))[:, None]
    for _ in range(230):
        duration = rng.uniform(.012, .065)
        t = np.arange(round(duration * RATE)) / RATE
        frequency = rng.uniform(1200, 4400)
        envelope = (1 - np.exp(-t / .0008)) * np.exp(-t / (duration / 6))
        droplet = (np.sin(math.tau * frequency * t) +
                   .35 * rng.normal(size=len(t))) * envelope
        wrap_event(output, droplet, rng.uniform(0, SECONDS),
                   rng.uniform(.015, .09), rng.uniform(-1, 1))
    return output


def cafe():
    rng = np.random.default_rng(53179)
    response = (1 - np.exp(-(F / 100) ** 4)) / np.sqrt(1 + (F / 1800) ** 8)
    output = filtered_noise(rng, response) * .018
    # Overlapping, low voices: randomized pitch, syllable envelopes and vocal
    # resonances imply a distant room without any words or recorded identity.
    for _ in range(180):
        duration = rng.uniform(.25, 1.15)
        t = np.arange(round(duration * RATE)) / RATE
        pitch = rng.uniform(95, 205)
        phase = math.tau * (pitch * t + 1.8 * np.sin(math.tau * 2.1 * t))
        voice = np.zeros_like(t)
        vowel = rng.choice([0, 1, 2])
        formants = [(500, 1200), (380, 1800), (700, 1350)][vowel]
        for harmonic in range(1, 20):
            frequency = pitch * harmonic
            strength = sum(np.exp(-((frequency - center) / 220) ** 2)
                           for center in formants)
            voice += np.sin(phase * harmonic) * (.12 + strength) / harmonic
        envelope = np.sin(math.pi * t / duration) ** 2
        envelope *= .55 + .45 * np.sin(math.tau * rng.uniform(2, 5) * t) ** 2
        wrap_event(output, voice * envelope, rng.uniform(0, SECONDS),
                   rng.uniform(.018, .035), rng.uniform(-.8, .8))
    # Sparse cup and saucer resonances with softened attacks.
    for _ in range(18):
        t = np.arange(round(.45 * RATE)) / RATE
        frequency = rng.uniform(1600, 2500)
        clink = (np.sin(math.tau * frequency * t) +
                 .4 * np.sin(math.tau * frequency * 1.43 * t))
        clink *= (1 - np.exp(-t / .0018)) * np.exp(-t / .07)
        wrap_event(output, clink, rng.uniform(0, SECONDS), .018,
                   rng.uniform(-.7, .7))
    # Circular room reflections soften the crowd.
    return output + .22 * np.roll(output[:, ::-1], round(.13 * RATE), axis=0)


GENERATORS = {"rain": rain, "cafe": cafe, "brown_noise": brown_noise}


def prepare(sound):
    sound -= np.mean(sound, axis=0)
    sound *= .065 / max(float(np.sqrt(np.mean(sound ** 2))), 1e-12)
    # Three full layers peak at .30 together; native music reserves another
    # .65 when the mix is active, including for full-scale imported audio.
    sound *= min(1, .10 / max(float(np.max(np.abs(sound))), 1e-12))
    return sound


def validate(path):
    with wave.open(str(path), "rb") as source:
        assert (source.getnchannels(), source.getsampwidth(),
                source.getframerate(), source.getnframes()) == (2, 2, RATE, COUNT)
        audio = np.frombuffer(source.readframes(COUNT), "<i2").reshape(-1, 2) / 32768
    rms = float(np.sqrt(np.mean(audio ** 2)))
    seam = float(np.max(np.abs(audio[0] - audio[-1])))
    p99 = float(np.quantile(np.abs(np.diff(audio, axis=0)), .99))
    assert .008 < rms < .10
    assert np.max(np.abs(audio)) <= .101
    assert np.max(np.abs(np.mean(audio, axis=0))) < .0001
    assert seam < max(.003, 2 * p99), (path, seam, p99)
    assert min(np.sqrt(np.mean(audio[:RATE // 10] ** 2)),
               np.sqrt(np.mean(audio[-RATE // 10:] ** 2))) > .003
    return {"file": path.name, "seconds": SECONDS, "rms": round(rms, 5),
            "peak": round(float(np.max(np.abs(audio))), 5),
            "loop_seam": round(seam, 6), "validation": "passed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    for name, generate in GENERATORS.items():
        path = ROOT / f"ambient_{name}.wav"
        if not args.validate_only:
            audio = prepare(generate())
            pcm = np.rint(audio * 32767).astype("<i2")
            with wave.open(str(path), "wb") as target:
                target.setnchannels(2)
                target.setsampwidth(2)
                target.setframerate(RATE)
                target.writeframes(pcm.tobytes())
        print(json.dumps(validate(path)), flush=True)


if __name__ == "__main__":
    main()
