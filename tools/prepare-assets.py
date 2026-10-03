#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Generate authored sound. Copy two OFL fonts from the pinned build inputs."""

import math
from pathlib import Path
import random
import shutil
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
FONT_INPUTS = {
    "Alegreya-Regular.ttf": "/nix/store/jk415xksw1avfs9q41sn4h5aiiv601sf-alegreya-2.008/share/fonts/ttf/Alegreya-Regular.ttf",
    "Lato-Regular.ttf": "/nix/store/qjrc2qs2v4f274qiqgk877vr390ck4d8-lato-2.0/share/fonts/lato/Lato-Regular.ttf",
}


def generate(name, seconds, sample):
    rate = 32000
    target = ROOT / "assets" / "audio" / (name + ".wav")
    target.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(717)
    with wave.open(str(target), "wb") as output:
        output.setparams((2, 2, rate, 0, "NONE", "not compressed"))
        data = bytearray()
        for index in range(int(rate * seconds)):
            t = index / rate
            left, right = sample(t, rng)
            data.extend(
                struct.pack(
                    "<hh",
                    int(max(-0.9, min(0.9, left)) * 32767),
                    int(max(-0.9, min(0.9, right)) * 32767),
                )
            )
        output.writeframes(data)


def ambience(t, rng):
    # Quiet root/fifth drone with wind, exact integer periods and seamless envelope.
    swell = 0.025 + 0.012 * math.sin(math.tau * t / 16)
    base = (
        sum(
            math.sin(math.tau * f * t) * a
            for f, a in [(110, 0.38), (165, 0.2), (220, 0.07)]
        )
        * swell
    )
    wind = rng.uniform(-1, 1) * 0.007 * math.sin(math.pi * t / 16) ** 2
    bird = 0.0
    phase = t % 5.0
    if 1 < phase < 1.28:
        u = phase - 1
        bird = (
            0.025
            * math.sin(math.tau * (1800 * u + 1000 * u * u))
            * math.sin(math.pi * u / 0.28) ** 2
        )
    return base + wind + bird, base - wind + bird * 0.4


def rain(t, rng):
    env = math.sin(math.pi * t / 3.5) ** 2
    noise = rng.uniform(-1, 1) * 0.18
    drops = math.sin(math.tau * (900 * t + 220 * math.sin(t * 6))) * 0.018
    return env * (noise + drops), env * (rng.uniform(-1, 1) * 0.15 + drops)


def bell(t, rng):
    tone = 0.0
    for delay, frequency in [(0, 330), (0.14, 440), (0.3, 550), (0.48, 660)]:
        u = t - delay
        if u >= 0:
            tone += (
                0.12
                * math.sin(math.tau * frequency * u)
                * math.exp(-u * 4)
                * min(1, u * 120)
            )
    return tone, tone * 0.85


def click(t, rng):
    value = 0.08 * math.sin(math.tau * 440 * t) * math.exp(-t * 32) * min(1, t * 200)
    return value, value


if __name__ == "__main__":
    fonts = ROOT / "assets" / "fonts"
    fonts.mkdir(parents=True, exist_ok=True)
    for name, source in FONT_INPUTS.items():
        destination = fonts / name
        if not destination.exists():
            shutil.copyfile(source, destination)
    generate("ambience", 16, ambience)
    generate("rain", 3.5, rain)
    generate("food", 2.5, bell)
    generate("touch", 0.3, click)
    print("Generated deterministic original audio and prepared fonts.")
