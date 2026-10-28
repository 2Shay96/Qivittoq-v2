#!/usr/bin/env python3
"""Eske's song: "Drømte mig en drøm i nat" (Codex Runicus, c. 1300).

Writes Eske's melody and the dead's refrain as MIDI files and renders one
WAV per night variant, using only the Python standard library (a
plucked-string lyre, a hummed choir, a drone, wind and a simple reverb).

    python3 make_song.py              # MIDI + every variant
    python3 make_song.py night07      # MIDI + just that variant
"""
import math
import random
import struct
import sys
import wave
from array import array
from pathlib import Path

HERE = Path(__file__).resolve().parent
SR = 44100

# Transcription from Danish Wikipedia: D minor, 6/4.
# (MIDI pitch, length in quarter notes, syllable)
MELODY = [
    (65, 2, "Drøm-"), (69, 1, "te "), (67, 2, "mig "), (69, 1, "en "),
    (65, 2, "drøm "), (64, 1, "i "), (62, 2, "nat, "), (65, 1, "om "),
    (69, 1, "sil-"), (69, 1, "ke "), (69, 1, "og "), (69, 2, "ær-"), (65, 1, "lig "),
    (62, 4, "pæl."),
]
END_REST = 2  # quarters of rest that close the last bar

# The dead's refrain. The Codex keeps only the first two lines of the stanza,
# and the song may have had a refrain that was never written down. This is an
# original one in the same mode and rhythm. Its words are lost, so it is hummed.
REFRAIN = [
    (69, 2, ""), (74, 1, ""), (72, 2, ""), (69, 1, ""),
    (72, 2, ""), (69, 1, ""), (67, 2, ""), (65, 1, ""),
    (67, 1, ""), (67, 1, ""), (65, 1, ""), (64, 2, ""), (60, 1, ""),
    (62, 4, ""),
]

# How the song sounds on each night. cents = pitch drift from start to end,
# wow = (depth in cents, speed in Hz) of a slow warble, drop = chance a note
# goes missing (grows each pass), unresolved = leave out the final note,
# answer = the dead hum their refrain after each of Eske's passes,
# dead_fade = how much the wind swallows them between lulls.
VARIANTS = {
    "night01": dict(bpm=120, passes=2, cents=(0, 0), wow=(0, 0), jitter=0.02,
                    drop=0.0, unresolved=False, reverb_mix=0.25, drone_level=0.45,
                    beat=0.0, wind_level=0.25, damping=0.996, seed=1),
    # Eske can't finish his song. The dead, far off in the fog, finish it for him.
    "night07": dict(bpm=84, passes=2, cents=(0, -70), wow=(18, 0.35), jitter=0.12,
                    drop=0.3, unresolved=True, reverb_mix=0.55, drone_level=0.7,
                    beat=1.3, wind_level=0.9, damping=0.998, seed=7,
                    answer=True, dead_bpm=66, dead_level=0.5, dead_cutoff=1100),
    # The refrain alone, near and clear, for judging the melody itself.
    "dead_refrain": dict(bpm=66, passes=2, cents=(0, 0), wow=(0, 0), jitter=0.0,
                         drop=0.0, unresolved=False, reverb_mix=0.3, drone_level=0.3,
                         beat=0.0, wind_level=0.15, damping=0.996, seed=3,
                         eske=False, answer=True, dead_bpm=66, dead_level=1.0,
                         dead_cutoff=4000, dead_wet=0.35, dead_fade=0.0),
}


# --- MIDI ---------------------------------------------------------------

def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def meta(kind, data):
    return b"\xff" + bytes([kind]) + vlq(len(data)) + data


def write_midi(path, melody, title, bpm, program, ppq=480):
    """Single-track MIDI, with lyrics where the melody has them."""
    events = [
        (0, meta(0x03, title.encode("latin-1"))),
        (0, meta(0x58, bytes([6, 2, 24, 8]))),  # 6/4
        (0, meta(0x59, bytes([0xFF, 1]))),      # D minor
        (0, meta(0x51, (60_000_000 // bpm).to_bytes(3, "big"))),
        (0, bytes([0xC0, program])),
    ]
    for pitch, beats, syllable in melody:
        if syllable:
            events.append((0, meta(0x05, syllable.encode("latin-1"))))
        events.append((0, bytes([0x90, pitch, 80])))
        events.append((beats * ppq, bytes([0x80, pitch, 0])))
    events.append((END_REST * ppq, meta(0x2F, b"")))
    track = b"".join(vlq(delta) + data for delta, data in events)
    path.write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, ppq)
                     + b"MTrk" + struct.pack(">I", len(track)) + track)


# --- Sound sources ------------------------------------------------------

def zeros(n):
    return array("f", bytes(4 * n))


def midi_hz(pitch):
    return 440.0 * 2 ** ((pitch - 69) / 12)


def pluck(freq, seconds, damping, rng):
    """Karplus-Strong string. Returns samples and the pitch they actually have."""
    period = max(2, int(SR / freq))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    mean = sum(buf) / period
    buf = [v - mean for v in buf]
    for _ in range(2):  # soften the attack
        buf = [(buf[i] + buf[i - 1]) * 0.5 for i in range(period)]
    out = zeros(int(seconds * SR))
    idx = 0
    for i in range(len(out)):
        a = buf[idx]
        nxt = idx + 1 if idx + 1 < period else 0
        out[i] = a
        buf[idx] = damping * 0.5 * (a + buf[nxt])
        idx = nxt
    return out, SR / (period - 0.5)  # the two-point average adds half a sample less delay


TABLE_N = 2048
TABLE = array("f", [
    sum(amp * math.sin(2 * math.pi * h * i / TABLE_N)
        for h, amp in ((1, 1), (2, .5), (3, .3), (4, .15), (5, .08)))
    for i in range(TABLE_N)
])


def drone(n, beat):
    """D2 and A2, plus a slightly-off second D when beat > 0 (it throbs)."""
    voices = [(midi_hz(38), 1.0), (midi_hz(45), 0.6)]
    if beat:
        voices.append((midi_hz(38) + beat, 0.8))
    out = zeros(n)
    for freq, amp in voices:
        step = freq * TABLE_N / SR
        phase = 0.0
        for i in range(n):
            out[i] += TABLE[int(phase)] * amp
            phase += step
            if phase >= TABLE_N:
                phase -= TABLE_N
    for i in range(n):  # slow breathing swell
        out[i] *= 0.75 + 0.25 * math.sin(2 * math.pi * 0.06 * i / SR)
    return out


def wind(n, rng):
    """Band-limited noise whose brightness and loudness drift in gusts.
    Also returns the gust strength per sample (0.15 calm to 1.0 howling)."""
    out, gusts = zeros(n), zeros(n)
    lp1 = lp2 = 0.0
    gust = target = 0.5
    for i in range(n):
        if i % 4410 == 0:
            target = rng.uniform(0.15, 1.0)
        gust += (target - gust) * 0.00004
        c = 0.01 + 0.06 * gust
        lp1 += c * (rng.uniform(-1, 1) - lp1)
        lp2 += c * 0.5 * (lp1 - lp2)
        out[i] = (lp1 - lp2) * gust
        gusts[i] = gust
    return out, gusts


def hum_table(f_ref, formant_scale):
    """One cycle of a hummed 'oo', its overtones shaped by vowel formants."""
    formants = [(300 * formant_scale, 60, 1.0), (870 * formant_scale, 90, 0.45),
                (2240 * formant_scale, 150, 0.12)]
    harmonics = []
    h = 1
    while h * f_ref < 5000:
        f = h * f_ref
        gain = 0.08 + sum(a / (1 + ((f - F) / bw) ** 2) for F, bw, a in formants)
        harmonics.append((h, gain / math.sqrt(h)))
        h += 1
    return array("f", [sum(a * math.sin(2 * math.pi * h * i / TABLE_N) for h, a in harmonics)
                       for i in range(TABLE_N)])


# octave, detune cents, level, formant scale, vibrato Hz, delay s, falters
CHOIR = [
    (0, -7, 1.0, 1.0, 4.8, 0.00, False),   # women
    (0, 6, 0.9, 1.05, 5.3, 0.04, False),
    (-1, -4, 0.8, 0.85, 4.5, 0.02, False),  # men
    (-1, 5, 0.7, 0.9, 5.0, 0.06, False),
    (0, 12, 0.45, 1.3, 6.0, 0.03, True),    # the child: thin, a little sharp,
]                                           # and silent before the last notes


def choir(n, phrases, rng):
    """Hummed voices, gliding between notes, each phrase swelling in and out."""
    out = zeros(n)
    for octave, det, level, fscale, vib_hz, delay, falters in CHOIR:
        table = hum_table(midi_hz(67 + 12 * octave), fscale)
        phase = 0.0
        vib_phase = rng.uniform(0, 2 * math.pi)
        for k, phrase in enumerate(phrases):
            sung = phrase[:-2] if falters and k == len(phrases) - 1 else phrase
            p_start = sung[0][0] + delay
            p_end = sung[-1][0] + sung[-1][2] + delay
            freq = midi_hz(sung[0][1] + 12 * octave)
            for start, pitch, length in sung:
                target = midi_hz(pitch + 12 * octave) * 2 ** (det / 1200)
                s0 = int((start + delay) * SR)
                s1 = min(int((start + delay + length) * SR), n)
                for i in range(s0, s1):
                    freq += (target - freq) * 0.002  # ~10 ms glide
                    tn = (i - s0) / SR
                    tp = i / SR
                    vib = 1 + 0.006 * min(1.0, tn / 0.5) * math.sin(
                        vib_phase + 2 * math.pi * vib_hz * tp)
                    env = 0.7 + 0.3 * min(1.0, tn / 0.15, (s1 - i) / (0.12 * SR))
                    env *= min(1.0, (tp - p_start) / 0.8, (p_end - tp) / 1.5)
                    out[i] += table[int(phase)] * env * level
                    phase += freq * vib * TABLE_N / SR
                    if phase >= TABLE_N:
                        phase -= TABLE_N
    return out


def far_away(x, cutoff):
    """Two one-pole lowpasses: distant sounds lose their highs."""
    c = 1 - math.exp(-2 * math.pi * cutoff / SR)
    a = b = 0.0
    out = zeros(len(x))
    for i, v in enumerate(x):
        a += c * (v - a)
        b += c * (a - b)
        out[i] = b
    return out


def reverb(x):
    """Freeverb-style: parallel damped combs into series allpasses."""
    n = len(x)
    acc = zeros(n)
    for d in (1116, 1188, 1277, 1356, 1422, 1491):
        buf = zeros(d)
        idx = 0
        store = 0.0
        for i in range(n):
            y = buf[idx]
            store = y * 0.7 + store * 0.3
            buf[idx] = x[i] + store * 0.86
            acc[i] += y
            idx = idx + 1 if idx + 1 < d else 0
    for d in (556, 441, 341, 225):
        buf = zeros(d)
        idx = 0
        for i in range(n):
            b = buf[idx]
            buf[idx] = acc[i] + b * 0.5
            acc[i] = b - acc[i]
            idx = idx + 1 if idx + 1 < d else 0
    return acc


def rms(x):
    return math.sqrt(sum(v * v for v in x) / len(x)) or 1.0


def scaled(x, target):
    k = target / rms(x)
    return array("f", (v * k for v in x))


# --- Rendering ----------------------------------------------------------

def render(name, bpm, passes, cents, wow, jitter, drop, unresolved,
           reverb_mix, drone_level, beat, wind_level, damping, seed,
           eske=True, answer=False, dead_bpm=66, dead_level=0.5,
           dead_cutoff=1100, dead_wet=0.65, dead_fade=0.7):
    rng = random.Random(seed)
    q, dq = 60.0 / bpm, 60.0 / dead_bpm

    notes, phrases, t = [], [], 1.0  # a second of wind before anything plays
    for p in range(passes):
        last_pass = p == passes - 1
        if eske:
            for i, (pitch, beats, _) in enumerate(MELODY):
                length = beats * q * (1 + rng.uniform(-jitter, jitter))
                final = i == len(MELODY) - 1
                missing = i > 0 and rng.random() < drop * (p + 1) / passes
                if not missing and not (unresolved and last_pass and final):
                    notes.append((t, pitch, length))
                t += length
            t += END_REST * q  # finish the bar
        if answer:
            phrase = []
            for pitch, beats, _ in REFRAIN:
                phrase.append((t, pitch, beats * dq))
                t += beats * dq
            phrases.append(phrase)
            t += END_REST * dq
        t += 6 * q  # one silent bar
    total = t + 4.0  # room for the reverb tail
    n = int(total * SR)

    # Pitch multiplier at control rate (every 64 samples): drift + warble.
    (c0, c1), (depth, rate) = cents, wow
    ctrl = [2 ** ((c0 + (c1 - c0) * (k * 64 / SR) / total
                   + depth * math.sin(2 * math.pi * rate * k * 64 / SR)) / 1200)
            for k in range(n // 64 + 2)]

    lyre = zeros(n)
    fade = int(0.3 * SR)
    for start, pitch, length in notes:
        freq = midi_hz(pitch)
        s0 = int(start * SR)
        count = min(int((length + 1.8) * SR), n - s0)
        src, f0 = pluck(freq, count * 1.2 / SR, damping, rng)
        base = freq / f0
        vel = rng.uniform(0.8, 1.0)
        pos = 0.0
        for i in range(count):
            j = int(pos)
            if j + 1 >= len(src):
                break
            v = src[j] + (src[j + 1] - src[j]) * (pos - j)
            if i > count - fade:
                v *= (count - i) / fade
            k = s0 + i
            lyre[k] += v * vel
            pos += base * ctrl[k >> 6]

    lyre = scaled(lyre, 0.1)
    bed = scaled(drone(n, beat), 0.1 * drone_level)
    dry = array("f", (a + b for a, b in zip(lyre, bed)))
    wet = scaled(reverb(dry), rms(dry))
    air, gusts = wind(n, rng)
    air = scaled(air, 0.1 * wind_level)

    # The dead: distant, smeared by fog, surfacing only when the wind drops.
    sung = zeros(n)
    if phrases:
        near = far_away(choir(n, phrases, rng), dead_cutoff)
        echo = scaled(reverb(near), rms(near))
        sung = scaled(array("f", (d * (1 - dead_wet) + e * dead_wet
                                  for d, e in zip(near, echo))), 0.1 * dead_level)
        for i in range(n):
            lull = min(1.0, (1.0 - gusts[i]) / 0.85)
            sung[i] *= 1 - dead_fade * (1 - lull)

    fade_in, fade_out = SR, 3 * SR
    out = zeros(n)
    for i in range(n):
        v = dry[i] * (1 - reverb_mix) + wet[i] * reverb_mix + air[i] + sung[i]
        if i < fade_in:
            v *= i / fade_in
        elif i > n - fade_out:
            v *= (n - i) / fade_out
        out[i] = v

    peak = max(abs(v) for v in out) or 1.0
    pcm = array("h", (int(v / peak * 0.9 * 32767) for v in out))
    path = HERE / f"{name}_preview.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{path.name}: {total:.1f}s, {len(notes)} lyre notes, {len(phrases)} refrains")


if __name__ == "__main__":
    # General MIDI programs: 46 = harp (closest to a lyre), 52 = choir aahs
    write_midi(HERE / "dromte_mig_en_drom.mid", MELODY, "Dromte mig en drom i nat", 160, 46)
    write_midi(HERE / "the_dead_refrain.mid", REFRAIN, "The dead's refrain", 90, 52)
    print("MIDI files written")
    for name in sys.argv[1:] or VARIANTS:
        render(name, **VARIANTS[name])
