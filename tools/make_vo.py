#!/usr/bin/env python3
"""Placeholder voice-over for Qivittoq, made with macOS `say` and the Python standard library.

Reads every voiced line from data/lines.json and speaks it with a macOS voice, then treats it so it
sits in the world. Eske's lines are pitched down a little, get hoarse breath under the words, an
audible breath before and after, and EQ that takes the edge off the synthetic voice. Each of his
lines also gets a colder take in vo/cold/ (more breath, muffled, a shiver) that the game blends in
as he freezes. The men calling in the dream are made distant: thinned, pushed far out over the
water, with echoes off the shore.

Every line is made twice: in English into vo/ and vo/cold/, and in Danish into vo/da/ and
vo/da/cold/. The player picks the language in the settings. For Danish it uses Magnus, a man's
voice, if it is installed (System Settings > Accessibility > Spoken Content > System Voice >
Manage Voices); otherwise Sara, a woman's voice, set down to a man's pitch with `say`'s [[pbas]]
command, which keeps her voice natural where slowing the recording would not.

    python3 tools/make_vo.py                      # every line in both languages, then VO_SCRIPT.md
    python3 tools/make_vo.py --lang da            # only the Danish takes
    python3 tools/make_vo.py need_firewood relit  # only these ids
    python3 tools/make_vo.py --script             # only rewrite VO_SCRIPT.md
    python3 tools/make_vo.py --recordings DIR --lang da  # treat real takes instead of `say` (see VO_SCRIPT.md)

Needs macOS (`say`, `afconvert`) and Python 3. Writes 16-bit mono 44.1 kHz WAVs.
"""
import argparse
import json
import math
import random
import subprocess
import sys
import tempfile
import wave
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINES = ROOT / "data" / "lines.json"
OUT = {"en": ROOT / "vo", "da": ROOT / "vo" / "da"}
SR = 44100
TAU = 2 * math.pi

ESKE_VOICE = "Daniel (English (UK))"
ESKE_RATE = 135
CREW_RATE = 150
ESKE_STRETCH = 1.11  # slower and about 1.8 semitones lower

DA_RATE = 140          # Sara goes no slower than about this
SARA_ESKE_PITCH = 38   # [[pbas 38]]: about 120 Hz, 110 Hz after the stretch (she speaks at 193 Hz)
SARA_STRETCH = 1.08    # a little slower and lower, which also darkens her a little


def danish_voice():
    """Magnus (a man) if he is installed, the best quality first; else Sara (a woman)."""
    listing = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    names = [row.split(" da_DK")[0].strip() for row in listing.splitlines() if " da_DK" in row]
    magnus = sorted((n for n in names if n.startswith("Magnus")),
                    key=lambda n: ("Premium" not in n, "Enhanced" not in n))
    return magnus[0] if magnus else "Sara"


# --- Reading and writing ---------------------------------------------------

def zeros(n):
    return array("f", bytes(4 * n))


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        n, ch, width, rate = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if width != 2:
        raise SystemExit(f"{path}: only 16-bit WAV is supported")
    a = array("h")
    a.frombytes(raw)
    if sys.byteorder == "big":
        a.byteswap()
    x = array("f", (a[i * ch] / 32768.0 for i in range(n)))
    if rate != SR:
        x = stretch(x, SR / rate)
    return x


def write_wav(path, x, peak_db=-3.0):
    peak = max(1e-9, max(abs(v) for v in x))
    gain = 10 ** (peak_db / 20) / peak
    out = array("h", (int(max(-1.0, min(1.0, v * gain)) * 32767) for v in x))
    if sys.byteorder == "big":
        out.byteswap()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(out.tobytes())


def speak(text, voice, rate, tmp):
    aiff = Path(tmp) / "line.aiff"
    wav = Path(tmp) / "line.wav"
    subprocess.run(["say", "-v", voice, "-r", str(rate), "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", "-c", "1", str(aiff), str(wav)],
                   check=True)
    return read_wav(wav)


# --- Building blocks ---------------------------------------------------------

def biquad(x, kind, f, q=0.707, gain_db=0.0):
    """RBJ cookbook filter: 'lp', 'hp', 'bp' or 'peak'."""
    w = TAU * f / SR
    cw, alpha = math.cos(w), math.sin(w) / (2 * q)
    a_gain = 10 ** (gain_db / 40)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bp":
        b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    else:
        b0, b1, b2 = 1 + alpha * a_gain, -2 * cw, 1 - alpha * a_gain
        a0, a1, a2 = 1 + alpha / a_gain, -2 * cw, 1 - alpha / a_gain
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = zeros(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def stretch(x, factor):
    """Play `x` slower by `factor` (longer and lower), with linear interpolation."""
    n = int(len(x) * factor)
    out = zeros(n)
    last = len(x) - 1
    for i in range(n):
        p = i / factor
        k = int(p)
        if k >= last:
            out[i] = x[last]
        else:
            f = p - k
            out[i] = x[k] * (1 - f) + x[k + 1] * f
    return out


def envelope(x, attack=0.004, release=0.07):
    ga, gr = math.exp(-1 / (attack * SR)), math.exp(-1 / (release * SR))
    out = zeros(len(x))
    e = 0.0
    for i, v in enumerate(x):
        a = abs(v)
        g = ga if a > e else gr
        e = g * e + (1 - g) * a
        out[i] = e
    return out


def trim(x, threshold_db=-45.0, pad=0.03):
    t = 10 ** (threshold_db / 20) * max(1e-9, max(abs(v) for v in x))
    first = next((i for i, v in enumerate(x) if abs(v) > t), 0)
    last = next((i for i in range(len(x) - 1, -1, -1) if abs(x[i]) > t), len(x) - 1)
    p = int(pad * SR)
    return x[max(0, first - p):min(len(x), last + p)]


def mix(*parts):
    """Mix (signal, start_seconds, gain) parts into one signal."""
    n = max(int(s * SR) + len(x) for x, s, g in parts)
    out = zeros(n)
    for x, s, g in parts:
        o = int(s * SR)
        for i, v in enumerate(x):
            out[o + i] += v * g
    return out


def noise(n, rng):
    return array("f", (rng.uniform(-1, 1) for _ in range(n)))


def soft_clip(x, drive):
    k = math.tanh(drive)
    return array("f", (math.tanh(v * drive) / k for v in x))


def breath(seconds, rng, inhale, bright=1.0):
    """A breath through the mouth: filtered noise with the shape of an inhale or an exhale."""
    n = int(seconds * SR)
    raw = noise(n, rng)
    x = biquad(raw, "bp", 1100 * bright, 0.5)
    y = biquad(raw, "bp", 2600 * bright, 1.2)
    out = zeros(n)
    for i in range(n):
        t = i / n
        if inhale:
            env = math.sin(math.pi * 0.5 * min(1.0, t / 0.8)) ** 2 * (1 - max(0.0, (t - 0.85) / 0.15))
        else:
            env = min(1.0, t / 0.08) * (1 - t) ** 1.6
        out[i] = (x[i] + 0.45 * y[i]) * env
    return out


# --- Eske ----------------------------------------------------------------------

def treat_eske(speech, rng, cold):
    """Eske's voice: hoarse, tired, close. `cold` gives the breathier, muffled, shivering take."""
    x = biquad(speech, "hp", 85)
    x = biquad(x, "peak", 170, 0.9, 2.5)      # some chest
    x = biquad(x, "peak", 3300, 1.2, -5.0)    # less of the synthetic edge
    x = soft_clip(x, 1.6)                     # a little grit
    env = envelope(x)
    peak = max(1e-9, max(env))
    hiss = biquad(noise(len(x), rng), "bp", 2400, 0.7)
    hiss = biquad(hiss, "lp", 6000)
    air = 0.32 if cold else 0.14
    out = zeros(len(x))
    for i in range(len(x)):
        out[i] = x[i] * (0.72 if cold else 1.0) + hiss[i] * (env[i] / peak) * air
    if cold:
        phase = rng.uniform(0, TAU)
        for i in range(len(out)):  # a shiver in the voice
            t = i / SR
            out[i] *= 1.0 - 0.16 * (0.5 + 0.5 * math.sin(TAU * 6.5 * t + phase + 0.8 * math.sin(TAU * 0.9 * t)))
        out = biquad(out, "lp", 2600, 0.6)
    else:
        out = biquad(out, "lp", 7500)
    inhale = breath(0.32 if not cold else 0.36, rng, True, 0.9 if not cold else 0.8)
    exhale = breath(0.5 if not cold else 0.7, rng, False, 0.8)
    peak_v = max(1e-9, max(abs(v) for v in out))
    level_in = (0.09 if not cold else 0.2) * peak_v / max(1e-9, max(abs(v) for v in inhale))
    level_out = (0.07 if not cold else 0.18) * peak_v / max(1e-9, max(abs(v) for v in exhale))
    lead = 0.36  # the same in both takes, so the game can crossfade between them
    return mix((inhale, 0.0, level_in), (out, lead, 1.0), (exhale, lead + len(out) / SR - 0.05, level_out))


# --- The men in the dream ---------------------------------------------------------

def reverb(x, wet, seconds=2.6):
    """A plain Schroeder reverb: four damped combs into two allpasses."""
    n = len(x) + int(seconds * SR)
    src = zeros(n)
    src[:len(x)] = x
    acc = zeros(n)
    for delay, fb in ((1557, 0.84), (1617, 0.83), (1491, 0.85), (1422, 0.84)):
        buf = zeros(delay)
        k = 0
        lp = 0.0
        for i in range(n):
            y = buf[k]
            lp = y * 0.55 + lp * 0.45
            buf[k] = src[i] + lp * fb
            k = (k + 1) % delay
            acc[i] += y * 0.25
    for delay in (556, 441):
        buf = zeros(delay)
        k = 0
        out = zeros(n)
        for i in range(n):
            b = buf[k]
            y = -acc[i] + b
            buf[k] = acc[i] + b * 0.5
            k = (k + 1) % delay
            out[i] = y
        acc = out
    return array("f", (src[i] * (1 - wet) + acc[i] * wet for i in range(n)))


def treat_far(speech, loud):
    """A man shouting from a boat far out on the water, the shore throwing it back."""
    x = biquad(speech, "hp", 320)
    x = soft_clip(x, 2.6 if loud else 1.8)
    x = biquad(x, "peak", 1500, 0.8, 4.0)
    x = biquad(x, "lp", 2100 if loud else 1700)
    echoes = [(x, 0.0, 1.0)]
    far = x
    for delay, gain, cut in ((0.43, 0.34, 1400), (0.97, 0.2, 1100), (1.7, 0.1, 850)):
        far = biquad(far, "lp", cut)
        echoes.append((far, delay, gain))
    return reverb(mix(*echoes), 0.34)


# --- Placeholder speech --------------------------------------------------------------

def placeholder(line, v, lang, da_voice, tmp):
    """Speak one variant with `say`, before any treatment."""
    eske = line["kind"] == "speech"
    if lang == "en":
        text = v.get("tts", v["text"])
        if eske:
            return stretch(trim(speak(text, ESKE_VOICE, ESKE_RATE, tmp)), ESKE_STRETCH)
        return stretch(trim(speak(text, v.get("voice", "Reed (English (UK))"), CREW_RATE, tmp)), 1.04)
    text = v.get("da_tts", v["da"])
    pitch = SARA_ESKE_PITCH if eske else v.get("da_pitch", 40)
    if da_voice == "Sara":
        return stretch(trim(speak(f"[[pbas {pitch}]] {text}", da_voice, DA_RATE if eske else CREW_RATE, tmp)),
                       SARA_STRETCH if eske else 1.04)
    # Magnus is a man already: Eske as Daniel is, the men told apart by how far they are slowed.
    if eske:
        return stretch(trim(speak(text, da_voice, ESKE_RATE, tmp)), ESKE_STRETCH)
    return stretch(trim(speak(text, da_voice, CREW_RATE, tmp)), 1.04 * 2 ** ((39 - pitch) / 24))


# --- The script for real recordings ------------------------------------------------

SCRIPT_HEAD = """# Qivittoq: voice-over script, Night 1

Every spoken line in Night 1, in Danish and in English. Eske and the men speak either language,
chosen in the settings (Esc); Danish is the default. The subtitles show the English line in both.

The game plays whatever WAV file sits under the name in the **File** column: in `vo/da/` for
Danish and in `vo/` for English. A real recording replaces a placeholder just by being saved over
it. Subtitles take their timing from the length of each file.

This file is written by `python3 tools/make_vo.py --script` from `data/lines.json`. Change lines
there, not here.

## Recording notes

- **Eske** is a Danish sailor in his thirties: tired, hoarse, cold, with his breath audible. He
  speaks quietly to himself, never to an audience. Never theatrical. Leave a breath before and after
  each line, and trim no closer than about 0.2 s.
- **The Danish lines** are plain modern Danish, translated from the English. Have a native speaker
  check them before recording; an actor may want them older or rougher (it is 1424), as long as
  each line still means what its English subtitle says.
- **Format:** WAV, mono, 44.1 kHz, 16-bit. Record dry and close; the game adds the open-air reverb
  outside and keeps the voice dry in the tent.
- **The cold:** the game muffles Eske as he freezes, and crossfades to a second take in
  `vo/da/cold/` (or `vo/cold/`) with the same file name if there is one. Record that take breathier,
  with teeth close to chattering, or make it from the normal take with
  `python3 tools/make_vo.py --recordings DIR --lang da`.
- **The men in the dream** shout from a boat far out on the water. Record them close and loud;
  `make_vo.py --recordings` pushes them out over the water.
- **Variants:** lines with several takes (need_firewood_1, _2, _3) are chosen in turn so the same
  words never come twice in a row.

"""


def write_script(table):
    out = [SCRIPT_HEAD]
    eske = [l for l in table if l["kind"] == "speech"]
    crew = [l for l in table if l["kind"] == "voice"]
    for title, lines in (("Eske", eske), ("The men in the dream", crew)):
        out.append(f"## {title}\n\n")
        out.append("| Id | File | Danish | English (the subtitle) | When it plays | Delivery |\n"
                   "| --- | --- | --- | --- | --- | --- |\n")
        for line in lines:
            for v in line["variants"]:
                who = f" ({line['speaker']})" if line.get("speaker") else ""
                out.append(f"| `{line['id']}` | `{v['file']}` | “{v['da']}” | “{v['text']}”{who} | "
                           f"{line.get('when', '')} | {line.get('note', '')} |\n")
        out.append("\n")
    carved = [l for l in table if l["kind"] == "carved"]
    if carved:
        out.append("## Not spoken\n\n")
        for line in carved:
            v = line["variants"][0]
            out.append(f"- `{line['id']}`: “{v['text']}” (“{v.get('da', '')}”) {line.get('when', '')}\n")
        out.append("\n")
    (ROOT / "VO_SCRIPT.md").write_text("".join(out), encoding="utf-8")
    print("wrote VO_SCRIPT.md")


# --- Main -------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="only make these line ids")
    ap.add_argument("--script", action="store_true", help="only rewrite VO_SCRIPT.md")
    ap.add_argument("--lang", choices=("both", "da", "en"), default="both", help="which language to make")
    ap.add_argument("--recordings", metavar="DIR", help="treat real takes named like the files in vo/")
    args = ap.parse_args()
    if args.recordings and args.lang == "both":
        ap.error("say which language the recordings are in: --lang da or --lang en")

    table = json.loads(LINES.read_text(encoding="utf-8"))["lines"]
    if args.script:
        write_script(table)
        return
    voiced = [l for l in table if l["kind"] in ("speech", "voice")]
    if args.ids:
        voiced = [l for l in voiced if l["id"] in args.ids]
    langs = ("da", "en") if args.lang == "both" else (args.lang,)
    da_voice = danish_voice()
    if "da" in langs and not args.recordings:
        print(f"Danish voice: {da_voice}")
    with tempfile.TemporaryDirectory() as tmp:
        for lang in langs:
            out = OUT[lang]
            for line in voiced:
                for k, v in enumerate(line["variants"]):
                    rng = random.Random(f"{line['id']}-{k}")
                    if args.recordings:
                        src = Path(args.recordings) / v["file"]
                        if not src.exists():
                            print(f"  skip {v['file']} (no recording)")
                            continue
                        speech = trim(read_wav(src))
                    else:
                        speech = placeholder(line, v, lang, da_voice, tmp)
                    if line["kind"] == "speech":
                        # A real take goes in as it is; only the placeholder needs roughening.
                        warm = speech if args.recordings else treat_eske(speech, rng, False)
                        write_wav(out / v["file"], warm, -3.0)
                        write_wav(out / "cold" / v["file"],
                                  treat_eske(speech, random.Random(f"{line['id']}-{k}-cold"), True), -4.5)
                    else:
                        loud = v["text"].isupper() or "!" in v["text"]
                        write_wav(out / v["file"], treat_far(speech, loud), -2.0 if loud else -6.0)
                    print(f"  {out.relative_to(ROOT)}/{v['file']}")
    if not args.ids:
        write_script(table)


if __name__ == "__main__":
    main()
