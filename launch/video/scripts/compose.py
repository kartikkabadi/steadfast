"""Original soundtrack + sound effects for the Steadfast launch film.

Everything here is synthesised from scratch with numpy, so the audio is
royalty-free and reproducible. Structure mirrors a classic launch-film arc:
quiet cold open -> riser -> silence -> drop -> breakdown -> build -> drop -> sting.

    python compose.py <public-dir>
"""
import sys, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, fftconvolve

SR = 44100
BPM = 120
BEAT = 60 / BPM          # 0.5 s
BAR = BEAT * 4           # 2 s
LENGTH = 55.0
rng = np.random.default_rng(7)

OUT = sys.argv[1] if len(sys.argv) > 1 else "public"


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, f, order=2):
    return sosfilt(butter(order, min(f, SR / 2 - 100), "low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def lp_sweep(x, cutoff, block=256):
    """Lowpass whose cutoff follows an array, filtered block-wise with carried state."""
    from scipy.signal import sosfilt_zi
    y = np.empty_like(x)
    zi = None
    for i in range(0, len(x), block):
        c = float(np.clip(cutoff[min(i, len(cutoff) - 1)], 40, SR / 2 - 200))
        sos = butter(2, c, "low", fs=SR, output="sos")
        if zi is None:
            zi = sosfilt_zi(sos) * x[0]
        y[i:i + block], zi = sosfilt(sos, x[i:i + block], zi=zi)
    return y


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def saw(freq, t, phase=0.0):
    ph = (freq * t + phase) % 1.0
    return 2 * ph - 1


def supersaw(freq, t, voices=7, detune=0.18):
    out = np.zeros_like(t)
    for i in range(voices):
        d = (i - (voices - 1) / 2) / ((voices - 1) / 2) * detune / 12
        out += saw(freq * 2 ** d, t, rng.random())
    return out / voices


def adsr(n, a, d, s, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    if a + d + r > n:
        scale = n / (a + d + r)
        a, d = int(a * scale), int(d * scale)
        r = n - a - d
    sustain_len = max(0, n - a - d - r)
    env = np.concatenate([
        np.linspace(0, 1, max(a, 1)),
        np.linspace(1, s, max(d, 1)),
        np.full(int(sustain_len), s),
        np.linspace(s, 0, max(r, 1)),
    ])
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def reverb_ir(seconds=2.2, damp=6000, seed=1):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.9 / seconds)
    left = lp(r.standard_normal(n), damp) * env
    right = lp(r.standard_normal(n), damp) * env
    left[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    right[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    return left / np.abs(left).sum() * 40, right / np.abs(right).sum() * 40


IR = reverb_ir()
IR_LONG = reverb_ir(4.5, 5000, 3)


def verb(mono, ir=IR, mix=0.3):
    l = fftconvolve(mono, ir[0])
    r = fftconvolve(mono, ir[1])
    dry = np.pad(mono, (0, len(l) - len(mono)))
    return np.stack([dry * (1 - mix) + l * mix, dry * (1 - mix) + r * mix], 1)


def place(buf, sig, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= len(buf):
        return
    if sig.ndim == 1:
        lg, rg = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        sig = np.stack([sig * lg * 1.414, sig * rg * 1.414], 1)
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n] * gain


# ---------------------------------------------------------------- instruments

def kick(punch=1.0):
    t = t_(0.45)
    f = 44 + 120 * np.exp(-t * 32) * punch + 40 * np.exp(-t * 300)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 6.5)
    click = hp(rng.standard_normal(len(t)), 3000) * np.exp(-t * 400) * 0.25
    return np.tanh((body + click) * 1.6) * 0.9


def clap():
    t = t_(0.5)
    n = rng.standard_normal(len(t))
    env = np.zeros_like(t)
    for k, o in enumerate([0, 0.011, 0.022]):
        env += (t >= o) * np.exp(-(t - o).clip(0) * (180 if k < 2 else 22))
    s = bp(n, 900, 4200) * env
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 40) * 0.4
    return (s + body) * 0.55


def hat(open_=False):
    t = t_(0.35 if open_ else 0.06)
    n = hp(rng.standard_normal(len(t)), 7500, 4)
    return n * np.exp(-t * (11 if open_ else 70)) * (0.22 if open_ else 0.18)


def shaker():
    t = t_(0.09)
    return bp(rng.standard_normal(len(t)), 5000, 11000) * np.sin(np.pi * t / 0.09) ** 2 * 0.08


def bass_note(note, dur):
    t = t_(dur)
    f = midi(note)
    s = saw(f, t) * 0.55 + np.sin(2 * np.pi * f * t) * 0.9 + np.sin(2 * np.pi * f / 2 * t) * 0.35
    s = lp_sweep(s, 380 + 900 * np.exp(-t * 14))
    return np.tanh(s * 1.3) * adsr(len(t), 0.004, 0.08, 0.75, 0.04) * 0.55


def pad_chord(notes, dur, bright=2200):
    t = t_(dur)
    s = np.zeros_like(t)
    for n in notes:
        s += supersaw(midi(n), t, 5, 0.14)
    s = lp(s / len(notes), bright, 2)
    return s * adsr(len(t), 0.35, 0.3, 0.85, 0.6) * 0.95


def pluck(note, dur=0.22, bright=1.0):
    t = t_(dur + 0.25)
    f = midi(note)
    s = saw(f, t) * 0.6 + saw(f * 1.004, t) * 0.4
    s = s * 0.5 + np.sign(np.sin(2 * np.pi * f * t)) * 0.18
    y = lp_sweep(s, 400 + 5200 * bright * np.exp(-t * 18))
    return y * np.exp(-t * 7) * 0.45


def stab(notes, dur=0.35):
    t = t_(dur + 0.4)
    s = np.zeros_like(t)
    for n in notes:
        s += supersaw(midi(n), t, 7, 0.22)
    s = lp_sweep(s / len(notes), 3200 + 3000 * np.exp(-t * 10))
    return s * adsr(len(t), 0.003, 0.15, 0.55, 0.3) * 0.6


def riser(dur, start=300, end=7000):
    t = t_(dur)
    n = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    seg = int(0.05 * SR)
    for i in range(0, len(t), seg):
        p = i / len(t)
        c = start * (end / start) ** p
        chunk = n[i:i + seg]
        out[i:i + seg] = bp(chunk, c * 0.7, min(c * 1.4, 20000))
    tone = supersaw(midi(48), t, 5, 0.3)
    f = 130 * 2 ** (np.linspace(0, 2, len(t)))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.15
    env = np.linspace(0, 1, len(t)) ** 2.2
    return (out * 0.5 + tone) * env


def impact():
    t = t_(3.0)
    f = 30 + 70 * np.exp(-t * 5)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
    crash = hp(rng.standard_normal(len(t)), 2500) * np.exp(-t * 2.2) * 0.25
    return np.tanh(boom * 1.4) * 0.9 + crash


def reverse_swell(dur=1.0):
    t = t_(dur)
    s = np.zeros_like(t)
    for n in [65, 69, 72, 76]:
        s += supersaw(midi(n), t, 5, 0.2)
    s = lp(s / 4, 2600) * (t / dur) ** 3
    return s * 0.5


# ---------------------------------------------------------------- arrangement

# F  -  G  -  Em  -  Am   (IV V iii vi in C) — lifted, unresolved, optimistic
PROG = [
    dict(root=41, pad=[57, 60, 64, 67], arp=[65, 69, 72, 76, 77, 76, 72, 69]),  # Fmaj9-ish
    dict(root=43, pad=[59, 62, 67, 69], arp=[67, 71, 74, 79, 81, 79, 74, 71]),  # G6
    dict(root=40, pad=[59, 62, 64, 67], arp=[64, 67, 71, 74, 76, 74, 71, 67]),  # Em7
    dict(root=45, pad=[60, 64, 67, 71], arp=[69, 72, 76, 79, 81, 79, 76, 72]),  # Am(add9)
]


def chord(bar_index):
    return PROG[bar_index % 4]


def build_music():
    n = int(LENGTH * SR)
    drums = np.zeros((n, 2))
    bass = np.zeros((n, 2))
    pads = np.zeros((n, 2))
    arps = np.zeros((n, 2))
    fx = np.zeros((n, 2))
    duck = np.ones(n)

    K = kick()
    C = clap()

    def duck_at(at, depth=0.65, length=0.32):
        i = int(at * SR)
        m = int(length * SR)
        curve = 1 - depth * np.exp(-np.linspace(0, 5, m))
        seg = duck[i:i + m]
        duck[i:i + m] = np.minimum(seg, curve[: len(seg)])

    def groove(start, end, energy=1.0, arp=True, open_hats=True):
        bars = int(round((end - start) / BAR))
        for b in range(bars):
            t0 = start + b * BAR
            ch = chord(b)
            for beat in range(4):
                bt = t0 + beat * BEAT
                place(drums, K, bt, 1.0)
                duck_at(bt)
                if beat in (1, 3):
                    place(drums, C, bt, 0.8)
                place(drums, hat(), bt + BEAT / 2, 1.0, 0.25)
                if open_hats:
                    place(drums, hat(True), bt + BEAT / 2, 0.55 * energy, -0.2)
                for s in range(4):
                    place(drums, shaker(), bt + s * BEAT / 4, 0.5 if s % 2 else 0.25, 0.4)
                # offbeat house bass + 16th pickup
                place(bass, bass_note(ch["root"] + 12, BEAT * 0.42), bt + BEAT / 2, 1.0)
                if beat == 3:
                    place(bass, bass_note(ch["root"] + 24, BEAT * 0.2), bt + BEAT * 0.75, 0.6)
            place(pads, verb(pad_chord(ch["pad"], BAR), mix=0.35), t0, 0.7 * energy)
            if arp:
                for s in range(8):
                    note = ch["arp"][s] + (12 if energy > 1.05 and s % 4 == 2 else 0)
                    place(arps, pluck(note, 0.18, 0.8 + 0.3 * energy), t0 + s * BEAT / 2, 0.9, 0.35 if s % 2 else -0.35)
            if energy > 1.05:
                # chord stabs on the and-of-2 and the 4 for the second drop
                place(arps, verb(stab([n + 12 for n in ch["pad"]], 0.18), mix=0.25), t0 + BEAT * 1.5, 0.55)
                place(arps, verb(stab([n + 12 for n in ch["pad"]], 0.18), mix=0.25), t0 + BEAT * 3.0, 0.45)

    def fill(at):
        # snare/clap fill over the last beat of a section
        for k in range(4):
            place(drums, C, at + k * BEAT / 4, 0.35 + 0.15 * k)

    # 0 - 4: cold open. soft pad, no drums.
    place(pads, verb(pad_chord([57, 60, 64, 67], 4.4, 1400), IR_LONG, 0.5), 0.0, 1.6)
    # 4 - 7.5: build under the confession lines. filtered kick + riser.
    for b in range(7):
        bt = 4.0 + b * BEAT
        place(drums, lp(K, 220), bt, 0.9)
        place(drums, hat(), bt + BEAT / 2, 0.5 + b * 0.08, 0.25)
    place(pads, verb(pad_chord([59, 62, 67, 69], 3.5, 1200), IR_LONG, 0.4), 4.0, 0.5)
    place(fx, verb(riser(3.4, 250, 9000), mix=0.3), 4.1, 0.55)
    place(fx, verb(reverse_swell(0.9), mix=0.2), 6.6, 0.5)
    # 7.5 - 8.0: silence (the pause)

    # 8.0: drop one
    place(fx, impact(), 8.0, 0.9)
    place(arps, verb(stab([69, 72, 76, 77], 0.6), IR_LONG, 0.4), 8.0, 0.6)
    groove(8.0, 28.0, 1.0)
    for f_at in (19.5, 27.5):
        fill(f_at)

    # 28 - 36: breakdown. pad + arp + sub, no kick.
    for b in range(4):
        t0 = 28.0 + b * BAR
        ch = chord(b)
        place(pads, verb(pad_chord(ch["pad"], BAR, 2600), IR_LONG, 0.45), t0, 0.9)
        sub = np.sin(2 * np.pi * midi(ch["root"]) * t_(BAR)) * adsr(int(BAR * SR), 0.05, 0.2, 0.8, 0.2) * 0.12
        place(bass, sub, t0, 1.0)
        for s in range(8):
            place(arps, verb(pluck(ch["arp"][s] + 12, 0.15, 0.6), mix=0.45), t0 + s * BEAT / 2, 0.8, 0.4 if s % 2 else -0.4)
        for beat in range(4):
            place(drums, hat(), t0 + beat * BEAT + BEAT / 2, 0.35, 0.3)

    # 36 - 40: build. clap roll accelerating, riser, kick rising.
    for k in range(8):
        place(drums, C, 36.0 + k * BEAT / 2, 0.25 + k * 0.03)
    for k in range(8):
        place(drums, C, 38.0 + k * BEAT / 4, 0.35 + k * 0.03)
    for k in range(8):
        place(drums, C, 39.0 + k * BEAT / 8, 0.45 + k * 0.03)
    for b in range(6):
        place(drums, lp(K, 300 + b * 200), 36.0 + b * BEAT, 0.75)
    place(fx, verb(riser(3.5, 200, 12000), mix=0.25), 36.0, 0.7)
    place(pads, verb(pad_chord([60, 64, 67, 71], 3.5, 900), IR_LONG, 0.4), 36.0, 0.6)
    # 39.5 - 40: silence

    # 40: drop two
    place(fx, impact(), 40.0, 1.0)
    groove(40.0, 50.0, 1.15)
    fill(49.5)

    # 51: final sting — wide chord, impact, long tail
    place(fx, impact(), 51.0, 0.9)
    place(arps, verb(stab([57, 64, 69, 72, 76, 79], 1.6), IR_LONG, 0.55), 51.0, 0.9)
    place(pads, verb(pad_chord([57, 60, 64, 67, 71], 3.8, 2400), IR_LONG, 0.55), 51.0, 0.75)
    place(bass, bass_note(33, 1.2), 51.0, 0.9)
    # 50 - 51: one last bar of drums leading in
    for beat in range(2):
        place(drums, K, 50.0 + beat * BEAT, 1.0)
        duck_at(50.0 + beat * BEAT)
        place(drums, hat(), 50.0 + beat * BEAT + BEAT / 2, 1.0, 0.25)
    for k in range(4):
        place(drums, C, 50.5 + k * BEAT / 4, 0.4 + 0.1 * k)

    d = duck[:, None]
    mix = drums * 0.95 + bass * d * 0.9 + pads * (0.35 + 0.65 * d) * 0.85 + arps * (0.5 + 0.5 * d) * 0.8 + fx * 0.8
    # gentle master glue
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)
    # hard silences for the two "pause" moments
    for a, b in ((7.5, 8.0), (39.5, 40.0)):
        i, j = int(a * SR), int(b * SR)
        ramp = int(0.012 * SR)
        mix[i:i + ramp] *= np.linspace(1, 0, ramp)[:, None]
        mix[i + ramp:j] = 0
    # final fade
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    peak = np.abs(mix).max()
    return mix / peak * 0.93


# ---------------------------------------------------------------- sound effects

def sfx():
    out = {}
    # keyboard taps: 4 variants
    for k in range(4):
        t = t_(0.09)
        n = rng.standard_normal(len(t))
        tap = bp(n, 1800 + 400 * k, 6500) * np.exp(-t * 140) * 0.6
        thock = np.sin(2 * np.pi * (230 + 25 * k) * t) * np.exp(-t * 90) * 0.5
        out[f"key-{k}"] = tap + thock
    t = t_(0.16)
    out["key-enter"] = (bp(rng.standard_normal(len(t)), 1200, 5000) * np.exp(-t * 90) * 0.7
                        + np.sin(2 * np.pi * 150 * t) * np.exp(-t * 45) * 0.8)
    # error thud: the page can't load
    t = t_(0.9)
    f = 95 + 60 * np.exp(-t * 18)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6)
    out["error"] = verb(np.tanh(thud * 1.5) * 0.9 + lp(rng.standard_normal(len(t)), 900) * np.exp(-t * 30) * 0.2, mix=0.25)
    # soft UI tick for selections
    t = t_(0.12)
    out["select"] = np.sin(2 * np.pi * (1250 + 500 * np.exp(-t * 60)) * t) * np.exp(-t * 55) * 0.45
    # clock tick for the hours counter
    t = t_(0.05)
    out["tick"] = hp(rng.standard_normal(len(t)), 3500) * np.exp(-t * 200) * 0.55 + np.sin(2 * np.pi * 3100 * t) * np.exp(-t * 150) * 0.2
    # air whoosh for sheets and text
    t = t_(0.7)
    n = rng.standard_normal(len(t))
    w = np.zeros_like(t)
    seg = int(0.02 * SR)
    for i in range(0, len(t), seg):
        p = i / len(t)
        c = 500 + 3500 * np.sin(np.pi * p)
        w[i:i + seg] = bp(n[i:i + seg], c * 0.6, c * 1.6)
    out["air"] = verb(w * np.sin(np.pi * t / 0.7) ** 2 * 0.7, mix=0.3)
    # denied: two short low blips
    t = t_(0.32)
    blip = np.zeros_like(t)
    for o in (0.0, 0.13):
        tt = (t - o).clip(0)
        blip += (t >= o) * np.sin(2 * np.pi * 220 * tt) * np.exp(-tt * 28)
    out["deny"] = lp(np.sign(blip) * np.abs(blip) ** 0.7, 1800) * 0.45
    # commit: a deep latch + shimmer
    t = t_(1.4)
    latch = np.sin(2 * np.pi * np.cumsum(70 + 160 * np.exp(-t * 40)) / SR) * np.exp(-t * 9)
    shimmer = sum(np.sin(2 * np.pi * midi(n) * t) for n in (81, 88, 93)) * np.exp(-t * 3.5) * 0.08
    out["commit"] = verb(np.tanh(latch * 1.6) * 0.8 + shimmer, IR_LONG, 0.35)
    # pause mark snap (in the silence)
    t = t_(0.5)
    snap = hp(rng.standard_normal(len(t)), 2000) * np.exp(-t * 260) * 0.7 + np.sin(2 * np.pi * 520 * t) * np.exp(-t * 60) * 0.35
    out["snap"] = verb(snap, IR_LONG, 0.35)
    # text stretch "steadfaaaast" — rising tape squeal
    t = t_(1.6)
    f = 220 * 2 ** (t / 1.6 * 2.2)
    out["stretch"] = lp(saw(1, t) * 0, 100) + np.sin(2 * np.pi * np.cumsum(f) / SR) * (t / 1.6) * 0.12
    return out


def write(path, x):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    peak = np.abs(x).max()
    if peak > 0.99:
        x = x / peak * 0.99
    wavfile.write(path, SR, (x * 32767).astype(np.int16))


if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "audio"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    write(os.path.join(OUT, "audio", "soundtrack.wav"), build_music())
    for name, sig in sfx().items():
        sig = np.asarray(sig, dtype=np.float64)
        write(os.path.join(OUT, "sfx", f"{name}.wav"), sig / np.abs(sig).max() * 0.966)  # -0.3 dBFS peak
    # The rm-*.wav files come from https://remotion.media (Remotion's sfx skill) and are
    # peak-normalised to -0.3 dBFS with ffmpeg's volumedetect/volume filters, and every
    # effect has leading silence trimmed (silenceremove, -55 dB) so it lands on its frame.
    print("ok")
