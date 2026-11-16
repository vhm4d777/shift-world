#!/usr/bin/env python3
"""Generates every sound effect and music track used by SHIFT WORLDS.

All audio is synthesised from scratch with numpy (no samples), so the output is
original and released under CC0 together with the game's assets.

Usage:  python3 tools/generate_audio.py   (writes into ./audio)
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(2026)


# ---------------------------------------------------------------- primitives

def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def phase_from_freq(freq):
    return 2 * np.pi * np.cumsum(freq) / SR


def osc(kind, freq, dur=None, duty=0.5):
    if np.isscalar(freq):
        freq = np.full(int(SR * dur), float(freq))
    ph = phase_from_freq(freq)
    cyc = (ph / (2 * np.pi)) % 1.0
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.where(cyc < duty, 1.0, -1.0)
    if kind == "saw":
        return 2.0 * cyc - 1.0
    if kind == "tri":
        return 2.0 * np.abs(2.0 * cyc - 1.0) - 1.0
    raise ValueError(kind)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def env(n, a=0.005, d=0.1, s=0.0, r=0.05, sus_time=None):
    """ADSR envelope of n samples."""
    a_n = max(1, int(a * SR))
    d_n = max(1, int(d * SR))
    r_n = max(1, int(r * SR))
    total = n
    s_n = max(0, total - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    if len(e) < total:
        e = np.pad(e, (0, total - len(e)))
    return e[:total]


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be scalar or array."""
    if np.isscalar(cutoff):
        cutoff = np.full(len(x), float(cutoff))
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sweep(f0, f1, dur, curve="exp"):
    n = int(SR * dur)
    if curve == "exp":
        return f0 * (f1 / f0) ** np.linspace(0, 1, n)
    return np.linspace(f0, f1, n)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, start, total):
    out = np.zeros(total)
    s = int(start * SR)
    e = min(total, s + len(x))
    if s < total:
        out[s:e] += x[: e - s]
    return out


def note_hz(n):
    """MIDI note number to Hz."""
    return 440.0 * 2 ** ((n - 69) / 12.0)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def write(name, x, peak=0.85):
    os.makedirs(OUT, exist_ok=True)
    x = normalize(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name:22s} {len(x) / SR:5.2f}s")


# ---------------------------------------------------------------- sound effects

def sfx():
    print("Sound effects:")
    d = 0.14
    f = sweep(300, 720, d)
    x = osc("square", f, duty=0.25) * env(len(f), 0.002, 0.13, 0, 0.01)
    write("jump.wav", lowpass(x, 4000), 0.55)

    n = noise(0.08)
    write("land.wav", lowpass(n, 900) * exp_decay(len(n), 0.02), 0.5)

    # Shift into the Dark World: falling whoosh + sub boom
    d = 0.5
    f = sweep(1400, 90, d)
    whoosh = lowpass(noise(d), sweep(5000, 300, d)) * env(int(SR * d), 0.01, 0.45, 0, 0.04)
    tone = osc("saw", f) * exp_decay(len(f), 0.15) * 0.5
    boom = osc("sine", sweep(110, 40, d)) * exp_decay(int(SR * d), 0.12)
    write("shift_dark.wav", lowpass(mix(whoosh, tone, boom), 3500), 0.8)

    # Shift into the Light World: rising whoosh + sparkle
    whoosh = lowpass(noise(d), sweep(400, 7000, d)) * env(int(SR * d), 0.02, 0.45, 0, 0.03) * 0.8
    tone = osc("sine", sweep(250, 1300, d)) * exp_decay(int(SR * d), 0.18) * 0.5
    sparkle = np.zeros(int(SR * d))
    for i, nn in enumerate([84, 88, 91, 96]):
        s = osc("sine", note_hz(nn), 0.18) * exp_decay(int(SR * 0.18), 0.05) * 0.35
        sparkle += at(s, 0.04 + i * 0.05, len(sparkle))
    write("shift_light.wav", mix(whoosh, tone, sparkle), 0.8)

    d = 0.18
    x = osc("square", 98, d, 0.5) * env(int(SR * d), 0.002, 0.05, 0.6, 0.05)
    x2 = at(osc("square", 92, 0.12, 0.5) * env(int(SR * 0.12), 0.002, 0.05, 0.5, 0.04), 0.1, int(SR * 0.3))
    write("blocked.wav", lowpass(mix(x, x2), 1800), 0.55)

    d = 0.7
    n = lowpass(noise(d), sweep(6000, 200, d)) * exp_decay(int(SR * d), 0.18)
    s = osc("square", sweep(700, 60, d), duty=0.3) * exp_decay(int(SR * d), 0.2) * 0.6
    write("die.wav", mix(n, s), 0.8)

    total = int(SR * 0.9)
    x = np.zeros(total)
    for i, nn in enumerate([84, 88, 91, 96, 100]):
        tone = (osc("sine", note_hz(nn), 0.5) + 0.3 * osc("sine", note_hz(nn) * 2.01, 0.5))
        x += at(tone * exp_decay(int(SR * 0.5), 0.12) * 0.5, i * 0.06, total)
    write("shard.wav", x, 0.75)

    total = int(SR * 0.9)
    x = np.zeros(total)
    for i, nn in enumerate([76, 83]):
        tone = osc("tri", note_hz(nn), 0.7) * exp_decay(int(SR * 0.7), 0.2)
        x += at(tone, i * 0.12, total)
    write("checkpoint.wav", x, 0.65)

    click = lowpass(noise(0.03), 3000) * exp_decay(int(SR * 0.03), 0.006)
    blip = osc("square", 520, 0.07, 0.25) * env(int(SR * 0.07), 0.001, 0.06, 0, 0.01)
    rumble = lowpass(noise(0.45), 260) * env(int(SR * 0.45), 0.05, 0.3, 0.2, 0.1)
    write("lever.wav", mix(click, at(blip, 0.02, int(SR * 0.1)), at(rumble, 0.05, int(SR * 0.5)) * 1.5), 0.7)

    n = highpass(noise(0.05), 1500) * exp_decay(int(SR * 0.05), 0.01)
    write("crack.wav", n, 0.4)

    n = lowpass(noise(0.4), 700) * env(int(SR * 0.4), 0.005, 0.35, 0, 0.04)
    write("crumble.wav", n, 0.65)

    total = int(SR * 1.8)
    x = np.zeros(total)
    for i, nn in enumerate([72, 76, 79, 84, 88, 91, 96]):
        tone = osc("sine", note_hz(nn), 0.9) + 0.25 * osc("square", note_hz(nn), 0.9, 0.5)
        x += at(lowpass(tone, 5000) * exp_decay(int(SR * 0.9), 0.25) * 0.4, i * 0.08, total)
    shimmer = lowpass(noise(1.8), 9000) * env(total, 0.4, 1.3, 0, 0.1) * 0.08
    write("win.wav", mix(x, shimmer), 0.8)

    d = 0.16
    x = osc("square", sweep(1500, 280, d), duty=0.5) * exp_decay(int(SR * d), 0.05)
    write("bolt.wav", lowpass(x, 3500), 0.4)

    n = highpass(noise(0.1), 2500) * exp_decay(int(SR * 0.1), 0.02)
    write("fizzle.wav", n, 0.3)

    x = osc("square", 880, 0.045, 0.25) * env(int(SR * 0.045), 0.001, 0.04, 0, 0.004)
    write("menu_move.wav", lowpass(x, 5000), 0.35)

    a = osc("square", 660, 0.06, 0.25) * env(int(SR * 0.06), 0.001, 0.05, 0, 0.005)
    b = osc("square", 990, 0.1, 0.25) * env(int(SR * 0.1), 0.001, 0.09, 0, 0.01)
    write("menu_select.wav", lowpass(mix(a, at(b, 0.06, int(SR * 0.17))), 5000), 0.4)

    a = osc("square", 660, 0.06, 0.25) * env(int(SR * 0.06), 0.001, 0.05, 0, 0.005)
    b = osc("square", 440, 0.1, 0.25) * env(int(SR * 0.1), 0.001, 0.09, 0, 0.01)
    write("menu_back.wav", lowpass(mix(a, at(b, 0.06, int(SR * 0.17))), 4000), 0.4)

    d = 0.45
    x = osc("sine", sweep(300, 1100, d)) * env(int(SR * d), 0.05, 0.38, 0, 0.02) * 0.6
    sh = lowpass(noise(d), 6000) * env(int(SR * d), 0.1, 0.33, 0, 0.02) * 0.2
    write("respawn.wav", mix(x, sh), 0.55)


# ---------------------------------------------------------------- music

BPM = 100
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 16
LEN = BAR * BARS
N = int(SR * LEN)


def circular_delay(x, delay_s, feedback=0.4, mix_amt=0.35, repeats=5):
    """Echo that wraps around the loop point so the track loops seamlessly."""
    out = x.copy()
    shift = int(delay_s * SR)
    g = mix_amt
    for i in range(1, repeats + 1):
        out += np.roll(x, shift * i) * g
        g *= feedback
    return out


def place(buf, sig, t):
    s = int(t * SR) % N
    e = s + len(sig)
    if e <= N:
        buf[s:e] += sig
    else:
        k = N - s
        buf[s:] += sig[:k]
        buf[: e - N] += sig[k:]


def pad_note(freqs, dur, kind="tri", detune=0.004):
    n = int(SR * dur)
    out = np.zeros(n)
    for f in freqs:
        for dt in (-detune, detune):
            out += osc(kind, f * (1 + dt), dur)
    return out / (2 * len(freqs))


def music():
    print("Music:")
    # Chord roots per 2-bar block (MIDI). Light: F  G  Am C. Dark: Dm/F  Em/G  Am  E7
    light_chords = [[53, 57, 60, 64], [55, 59, 62, 69], [57, 60, 64, 67], [48, 52, 55, 59]]
    dark_chords = [[53, 57, 62, 65], [55, 59, 64, 67], [57, 60, 64, 69], [52, 56, 59, 62]]
    melody = [  # (beat offset within 8 bars, midi, beats) used in bars 9-16
        (0, 76, 2), (2, 79, 1), (3, 77, 1), (4, 76, 2), (6, 74, 2),
        (8, 74, 2), (10, 76, 1), (11, 79, 1), (12, 81, 3), (15, 79, 1),
        (16, 81, 2), (18, 79, 1), (19, 76, 1), (20, 77, 2), (22, 76, 2),
        (24, 72, 2), (26, 74, 1), (27, 76, 1), (28, 76, 4),
    ]

    # ---------------- Light layer
    light = np.zeros(N)
    for blk in range(8):
        ch = light_chords[blk % 4]
        t0 = blk * 2 * BAR
        pad = pad_note([note_hz(n + 12) for n in ch], 2 * BAR, "tri") * env(int(SR * 2 * BAR), 0.6, 0.5, 0.8, 0.7)
        place(light, lowpass(pad, 2500) * 0.30, t0)
        bass = osc("sine", note_hz(ch[0] - 12), 2 * BAR) * env(int(SR * 2 * BAR), 0.05, 1.0, 0.6, 0.5)
        place(light, bass * 0.32, t0)
        # 16th-note arpeggio
        arp = [ch[0] + 24, ch[1] + 24, ch[2] + 24, ch[3] + 24, ch[2] + 24, ch[1] + 24]
        for i in range(32):
            nn = arp[i % len(arp)]
            if blk >= 4 and i % 8 == 7:
                nn += 12
            tone = (osc("square", note_hz(nn), BEAT / 4 * 0.9, 0.125) * 0.5 + osc("sine", note_hz(nn), BEAT / 4 * 0.9))
            tone *= env(len(tone), 0.002, 0.12, 0.0, 0.02)
            place(light, lowpass(tone, 3200) * 0.10, t0 + i * BEAT / 4)
        # shaker on off-beats
        for b in range(8):
            sh = highpass(noise(0.05), 5000) * exp_decay(int(SR * 0.05), 0.012)
            place(light, sh * 0.06, t0 + b * BEAT + BEAT / 2)
    # bell melody in the second half
    for beat, nn, ln in melody:
        d = ln * BEAT
        tone = osc("sine", note_hz(nn), d) + 0.35 * osc("sine", note_hz(nn) * 2.0, d) + 0.12 * osc("sine", note_hz(nn) * 3.01, d)
        tone *= exp_decay(len(tone), 0.45) * env(len(tone), 0.004, 0.1, 1.0, 0.08)
        place(light, tone * 0.16, 8 * BAR + beat * BEAT)
    light = circular_delay(light, BEAT * 0.75, 0.45, 0.3)

    # ---------------- Dark layer
    dark = np.zeros(N)
    for blk in range(8):
        ch = dark_chords[blk % 4]
        t0 = blk * 2 * BAR
        drone = pad_note([note_hz(ch[0] - 12), note_hz(ch[0] - 5)], 2 * BAR, "saw", 0.006)
        place(dark, lowpass(drone, 700) * env(int(SR * 2 * BAR), 0.4, 0.5, 0.9, 0.5) * 0.34, t0)
        # pulsing 8th-note bass
        for i in range(16):
            d = BEAT / 2 * 0.85
            f = note_hz(ch[0] - 12 + (12 if i % 4 == 3 else 0))
            tone = osc("saw", f, d) + osc("saw", f * 1.007, d)
            cut = 400 + 1600 * exp_decay(int(SR * d), 0.05)
            place(dark, soft_clip(lowpass(tone, cut), 1.5) * env(int(SR * d), 0.003, 0.15, 0.3, 0.03) * 0.22, t0 + i * BEAT / 2)
        # kick on 1 & 3, snare on 2 & 4 (from bar 3 onward)
        if blk >= 1:
            for b in range(8):
                if b % 2 == 0:
                    k = osc("sine", sweep(140, 42, 0.28)) * exp_decay(int(SR * 0.28), 0.08)
                    place(dark, k * 0.55, t0 + b * BEAT)
                else:
                    s = lowpass(noise(0.18), 3000) * exp_decay(int(SR * 0.18), 0.045)
                    s += osc("tri", 180, 0.18) * exp_decay(int(SR * 0.18), 0.03) * 0.5
                    place(dark, s * 0.25, t0 + b * BEAT)
        # eerie low arpeggio
        arp = [ch[0] + 12, ch[2] + 12, ch[1] + 12, ch[3] + 12]
        for i in range(16):
            nn = arp[i % 4]
            d = BEAT / 2 * 0.8
            tone = osc("square", note_hz(nn), d, 0.3) * env(int(SR * d), 0.002, 0.2, 0.0, 0.02)
            place(dark, lowpass(tone, 1400) * 0.09, t0 + i * BEAT / 2)
    # distorted lead echoing the light melody a step lower
    for beat, nn, ln in melody:
        d = ln * BEAT
        f = note_hz(nn - 12)
        vib = 1 + 0.008 * np.sin(2 * np.pi * 5.5 * t_axis(d))
        tone = osc("saw", f * vib) + osc("square", f * 1.003 * vib, None, 0.5) * 0.6
        tone = soft_clip(lowpass(tone, 1600), 2.0) * env(int(SR * d), 0.02, 0.2, 0.6, 0.15)
        place(dark, tone * 0.10, 8 * BAR + beat * BEAT)
    dark = circular_delay(dark, BEAT * 0.5, 0.35, 0.22)

    write("music_light.wav", soft_clip(normalize(light, 0.95), 1.1), 0.8)
    write("music_dark.wav", soft_clip(normalize(dark, 0.95), 1.2), 0.8)


if __name__ == "__main__":
    sfx()
    music()
