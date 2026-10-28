#!/usr/bin/env python3
"""Sound effects for Qivittoq, synthesized with the Python standard library.

Writes 16-bit mono WAVs into ../audio. Loops are made seamless by
crossfading their tail into their head.

    python3 tools/make_sfx.py
"""
import math
import random
import wave
from array import array
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "audio"
TAU = 2 * math.pi


# --- Building blocks -----------------------------------------------------

def zeros(n):
    return array("f", bytes(4 * n))


def noise(n, rng):
    return array("f", (rng.uniform(-1, 1) for _ in range(n)))


def biquad(x, kind, f, q=0.707):
    """RBJ cookbook filter: 'lp', 'hp' or 'bp' (constant peak gain)."""
    w = TAU * f / SR
    cw, alpha = math.cos(w), math.sin(w) / (2 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = zeros(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def resonator(x, freqs, bw):
    """Two-pole resonator whose centre frequency follows `freqs` (one per sample)."""
    out = zeros(len(x))
    r = math.exp(-math.pi * bw / SR)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        y = (1 - r) * v + 2 * r * math.cos(TAU * freqs[i] / SR) * y1 - r * r * y2
        y2, y1 = y1, y
        out[i] = y
    return out


def reverb(x, size=0.86, damp=0.3):
    """Freeverb-style: parallel damped combs into series allpasses."""
    n = len(x)
    acc = zeros(n)
    for d in (1116, 1188, 1277, 1356, 1422, 1491):
        buf, idx, store = zeros(d), 0, 0.0
        for i in range(n):
            y = buf[idx]
            store = y * (1 - damp) + store * damp
            buf[idx] = x[i] + store * size
            acc[i] += y
            idx = idx + 1 if idx + 1 < d else 0
    for d in (556, 441, 341, 225):
        buf, idx = zeros(d), 0
        for i in range(n):
            b = buf[idx]
            buf[idx] = acc[i] + b * 0.5
            acc[i] = b - acc[i]
            idx = idx + 1 if idx + 1 < d else 0
    return acc


def mix(*parts):
    n = max(len(p) for _, p in parts)
    out = zeros(n)
    for gain, p in parts:
        for i, v in enumerate(p):
            out[i] += v * gain
    return out


def wet(x, amount, tail=2.0, size=0.86):
    padded = x + zeros(int(tail * SR))
    r = reverb(padded, size)
    peak_x = max(abs(v) for v in padded) or 1.0
    peak_r = max(abs(v) for v in r) or 1.0
    k = peak_x / peak_r
    return array("f", (d * (1 - amount) + w * k * amount for d, w in zip(padded, r)))


def envelope(n, attack, release, hold_curve=1.0):
    a, r = int(attack * SR), int(release * SR)
    out = zeros(n)
    for i in range(n):
        g = 1.0
        if i < a:
            g = i / a
        elif i > n - r:
            g = max(0.0, (n - i) / r) ** hold_curve
        out[i] = g
    return out


def apply(x, env):
    return array("f", (a * b for a, b in zip(x, env)))


def seamless(x, length, fade):
    """Crossfade the part after `length` into the head, so the result loops."""
    L, F = int(length * SR), int(fade * SR)
    out = array("f", x[:L])
    for i in range(F):
        t = i / F
        out[i] = x[i] * t + x[L + i] * (1 - t)
    return out


def write(name, x, peak=0.89):
    top = max(abs(v) for v in x) or 1.0
    pcm = array("h", (int(v / top * peak * 32767) for v in x))
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name}: {len(x) / SR:.2f}s")


# --- Sounds ---------------------------------------------------------------

def wind_loop(rng, seconds=20.0):
    n = int((seconds + 2) * SR)
    gust, target = 0.5, 0.5
    gusts = zeros(n)
    for i in range(n):
        if i % 6000 == 0:
            target = rng.uniform(0.2, 1.0)
        gust += (target - gust) * 0.00003
        gusts[i] = gust
    raw = noise(n, rng)
    body = biquad(biquad(raw, "lp", 900), "hp", 60)
    howl_f = array("f", (260 + 240 * g + 40 * math.sin(TAU * 0.07 * i / SR) for i, g in enumerate(gusts)))
    howl = resonator(noise(n, rng), howl_f, 18)
    hiss = biquad(noise(n, rng), "bp", 3500, 0.6)
    out = zeros(n)
    hk = (max(abs(v) for v in howl) or 1.0)
    for i in range(n):
        g = gusts[i]
        out[i] = body[i] * (0.4 + 0.6 * g) + howl[i] / hk * 0.25 * g * g + hiss[i] * 0.05 * g
    return seamless(out, seconds, 2.0)


def fire_loop(rng, seconds=8.0):
    n = int((seconds + 1) * SR)
    rumble = biquad(noise(n, rng), "lp", 180)
    hiss = biquad(noise(n, rng), "bp", 4000, 0.5)
    crackle = zeros(n)
    t = 0.0
    while t < seconds + 1:
        t += rng.expovariate(14)
        start = int(t * SR)
        length = int(rng.uniform(0.001, 0.008) * SR)
        amp = min(1.0, rng.paretovariate(2.5) * 0.25)
        for k in range(length):
            if start + k < n:
                crackle[start + k] += rng.uniform(-1, 1) * amp * (1 - k / length) ** 2
    crackle = biquad(crackle, "hp", 1200)
    pops = zeros(n)
    t = 0.0
    while t < seconds + 1:
        t += rng.expovariate(1.2)
        start = int(t * SR)
        length = int(rng.uniform(0.02, 0.05) * SR)
        for k in range(length):
            if start + k < n:
                pops[start + k] += rng.uniform(-1, 1) * (1 - k / length) ** 3
    pops = biquad(pops, "lp", 900)
    out = mix((0.5, rumble), (0.04, hiss), (1.0, crackle), (0.6, pops))
    return seamless(out, seconds, 1.0)


def breath_loop(rng):
    def puff(dur, lo, hi):
        n = int(dur * SR)
        x = biquad(biquad(noise(n, rng), "hp", lo), "lp", hi)
        return array("f", (v * math.sin(math.pi * i / n) ** 1.5 for i, v in enumerate(x)))
    inhale = puff(1.1, 700, 2600)
    exhale = puff(1.5, 300, 1500)
    gap1, gap2 = zeros(int(0.25 * SR)), zeros(int(0.65 * SR))
    return array("f", list(inhale) + list(gap1) + [v * 1.3 for v in exhale] + list(gap2))


def step_snow(rng):
    n = int(0.32 * SR)
    x = zeros(n)
    for _ in range(420):
        t = abs(rng.gauss(0.04, 0.06))
        start = int(t * SR)
        length = int(rng.uniform(0.0004, 0.002) * SR)
        amp = rng.uniform(0.2, 1.0) * math.exp(-t * 9)
        for k in range(length):
            if start + k < n:
                x[start + k] += rng.uniform(-1, 1) * amp
    thud = apply(biquad(noise(n, rng), "lp", 220), envelope(n, 0.005, 0.25, 2))
    return mix((1.0, biquad(biquad(x, "hp", 900), "lp", 6000)), (0.6, thud))


def ice_crack(rng):
    n = int(5.0 * SR)
    out = zeros(n)
    for k in range(int(0.06 * SR)):  # the snap
        out[k] += rng.uniform(-1, 1) * (1 - k / (0.06 * SR)) ** 3
    for delay in (0.0, 0.11, 0.27):  # the dispersive 'pew' that sea ice makes
        start = int((0.02 + delay) * SR)
        length = int(0.45 * SR)
        phase = 0.0
        for k in range(length):
            f = 200 + 2600 * math.exp(-k / (0.09 * SR))
            phase += TAU * f / SR
            if start + k < n:
                out[start + k] += math.sin(phase) * 0.5 * math.exp(-k / (0.15 * SR)) * (1 - delay * 2)
    boom = zeros(n)
    for k in range(int(2.0 * SR)):
        boom[k] = math.sin(TAU * 55 * k / SR) * math.exp(-k / (0.5 * SR))
    groan = apply(biquad(noise(n, rng), "bp", 140, 2.0), envelope(n, 0.6, 2.5))
    return wet(mix((0.8, out), (0.6, boom), (1.5, groan)), 0.45, tail=2.5, size=0.9)


def ice_groan(rng):
    n = int(6.0 * SR)
    freqs = array("f", (55 + 30 * math.sin(math.pi * i / n) + 8 * math.sin(TAU * 0.7 * i / SR) for i in range(n)))
    tone = resonator(noise(n, rng), freqs, 6)
    tone = apply(tone, envelope(n, 1.2, 2.5))
    return wet(tone, 0.4, tail=2.0, size=0.9)


def oars_loop(rng, seconds=6.0):
    """Two oars dipping and pulling, about one stroke every 3 seconds."""
    n = int((seconds + 1) * SR)
    out = zeros(n)
    t = 0.2
    while t < seconds + 1:
        for side in (0.0, 0.05):
            start = int((t + side) * SR)
            length = int(0.5 * SR)
            for k in range(length):
                if start + k < n:
                    out[start + k] += rng.uniform(-1, 1) * math.sin(math.pi * k / length) ** 2 * 0.6
        t += 3.0
    splash = biquad(biquad(out, "bp", 900, 0.7), "lp", 2000)
    creak = zeros(n)
    t = 1.4
    while t < seconds + 1:  # the oarlock creaks on the pull
        start = int(t * SR)
        length = int(0.35 * SR)
        phase = 0.0
        for k in range(length):
            phase += TAU * (420 + 80 * math.sin(TAU * 3 * k / SR)) / SR
            if start + k < n:
                creak[start + k] += (1 if math.sin(phase) > 0.6 else -0.2) * math.sin(math.pi * k / length) * 0.15
        t += 3.0
    return seamless(wet(mix((1.0, splash), (1.0, biquad(creak, "lp", 1800))), 0.3, 0.3), seconds, 1.0)


def call_eske(rng, pitch):
    """A man shouting 'Eske!' far off over water: formant synthesis, then distance."""
    dur = 1.15
    n = int(dur * SR)
    # pitch contour: rises into the first syllable, falls away on the second
    f0 = array("f", (pitch * (1.0 + 0.18 * math.sin(math.pi * min(1, t / 0.3)) - 0.25 * max(0, t - 0.5)) for t in (i / SR for i in range(n))))
    src = zeros(n)
    phase = 0.0
    for i in range(n):
        phase += f0[i] * (1 + rng.uniform(-0.01, 0.01)) / SR
        if phase >= 1.0:
            phase -= 1.0
        src[i] = 1 - 2 * phase  # sawtooth: rich in harmonics, like a strained voice
    src = biquad(src, "lp", 3000)

    def seg(t):  # E (0-0.28) s (0.28-0.42) k (0.42-0.5) e (0.5-end)
        if t < 0.28:
            return (600, 1850, 2600), 1.0, 0.0
        if t < 0.42:
            return (600, 1850, 2600), 0.0, 1.0
        if t < 0.47:
            return (500, 1700, 2500), 0.0, 0.0
        if t < 0.5:
            return (500, 1700, 2500), 0.0, 2.0
        return (520, 1750, 2500), 1.0, 0.0

    voiced, hissy = zeros(n), zeros(n)
    f1, f2, f3 = zeros(n), zeros(n), zeros(n)
    sm = [600.0, 1850.0, 2600.0]
    vg = ng = 0.0
    for i in range(n):
        (a, b, c), v, h = seg(i / SR)
        sm[0] += (a - sm[0]) * 0.002
        sm[1] += (b - sm[1]) * 0.002
        sm[2] += (c - sm[2]) * 0.002
        vg += (v - vg) * 0.004
        ng += (h - ng) * 0.01
        f1[i], f2[i], f3[i] = sm
        voiced[i] = src[i] * vg
        hissy[i] = ng
    vowel = mix((1.0, resonator(voiced, f1, 90)), (0.6, resonator(voiced, f2, 120)), (0.25, resonator(voiced, f3, 160)))
    s = apply(biquad(noise(n, rng), "bp", 6000, 1.5), hissy)
    env = envelope(n, 0.04, 0.45)
    shout = apply(mix((1.0, vowel), (0.08, s)), env)
    far = biquad(biquad(shout, "lp", 1400), "hp", 150)
    return wet(far, 0.55, tail=2.5, size=0.9)


def candle_blow(rng):
    n = int(0.55 * SR)
    x = biquad(biquad(noise(n, rng), "hp", 500), "lp", 3000)
    return apply(x, envelope(n, 0.05, 0.4))


def carve(rng):
    parts = []
    for _ in range(6):
        n = int(rng.uniform(0.14, 0.22) * SR)
        grain = array("f", (rng.uniform(-1, 1) * (0.5 + 0.5 * math.sin(TAU * rng.uniform(40, 70) * i / SR)) for i in range(n)))
        stroke = apply(biquad(biquad(grain, "hp", 1800), "lp", 5500), envelope(n, 0.02, 0.06))
        parts.extend(stroke)
        parts.extend(zeros(int(rng.uniform(0.06, 0.14) * SR)))
    return array("f", parts)


def strike(rng):
    n = int(0.3 * SR)
    click = zeros(n)
    for k in range(int(0.004 * SR)):
        click[k] = rng.uniform(-1, 1)
    sparks = apply(biquad(noise(n, rng), "hp", 5000), envelope(n, 0.001, 0.25, 3))
    return mix((1.0, click), (0.5, sparks))


def wood_drop(rng):
    n = int(0.35 * SR)
    thump = array("f", (math.sin(TAU * 110 * i / SR) * math.exp(-i / (0.06 * SR)) for i in range(n)))
    knock = apply(biquad(noise(n, rng), "bp", 700, 1.2), envelope(n, 0.002, 0.3, 3))
    return mix((1.0, thump), (0.7, knock))


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    rng = random.Random(1424)
    write("wind_loop.wav", wind_loop(rng))
    write("fire_loop.wav", fire_loop(rng))
    write("breath_loop.wav", breath_loop(rng))
    for k in range(1, 5):
        write(f"step_snow_{k}.wav", step_snow(rng))
    write("ice_crack.wav", ice_crack(rng))
    write("ice_groan.wav", ice_groan(rng))
    write("oars_loop.wav", oars_loop(rng))
    for k, pitch in enumerate((118, 135, 152), start=1):
        write(f"call_eske_{k}.wav", call_eske(rng, pitch))
    write("candle_blow.wav", candle_blow(rng))
    write("carve.wav", carve(rng))
    write("strike.wav", strike(rng))
    write("wood_drop.wav", wood_drop(rng))
