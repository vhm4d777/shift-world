#!/usr/bin/env python3
"""Generates the audio added in SHIFT WORLDS 2.0: boss-fight and shop sound
effects, the boss music and a second level theme. Uses the same synthesis
primitives as generate_audio.py (no samples; everything is original, CC0).

Usage:  python3 tools/generate_audio_v2.py   (writes into ./audio)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_audio import (SR, at, circular_delay as _cd, env, exp_decay, highpass, lowpass, mix,  # noqa: E402
                            noise, normalize, note_hz, osc, pad_note, soft_clip, sweep, t_axis, write)

rng = np.random.default_rng(2027)


def sfx():
    print("Sound effects (v2):")
    # token pickup: two bright coin pings
    total = int(SR * 0.35)
    x = np.zeros(total)
    for i, nn in enumerate([88, 95]):
        tone = osc("square", note_hz(nn), 0.25, 0.25) * 0.4 + osc("sine", note_hz(nn), 0.25)
        x += at(tone * exp_decay(int(SR * 0.25), 0.07), i * 0.06, total)
    write("token.wav", lowpass(x, 7000), 0.5)

    # player shot: short laser pew
    d = 0.12
    x = osc("square", sweep(1800, 500, d), duty=0.3) * exp_decay(int(SR * d), 0.03)
    write("fire.wav", lowpass(x, 5000), 0.35)

    # boss takes a hit: crunchy tick
    d = 0.09
    n = highpass(noise(d), 1200) * exp_decay(int(SR * d), 0.015)
    t = osc("square", sweep(500, 180, d), duty=0.5) * exp_decay(int(SR * d), 0.025) * 0.6
    write("boss_hit.wav", mix(n, t), 0.45)

    # player hurt
    d = 0.35
    t = osc("saw", sweep(600, 120, d)) * exp_decay(int(SR * d), 0.08)
    n = lowpass(noise(d), 2500) * exp_decay(int(SR * d), 0.05)
    write("hurt.wav", soft_clip(mix(t, n * 0.7), 1.5), 0.7)

    # boss roar: detuned low growl with noise
    d = 1.4
    f = sweep(70, 45, d)
    growl = osc("saw", f) + osc("saw", f * 1.03) + osc("square", f * 0.5, None, 0.4) * 0.6
    growl *= 1 + 0.4 * np.sin(2 * np.pi * 9 * t_axis(d))
    roar = lowpass(growl, 900) * env(int(SR * d), 0.08, 1.0, 0.5, 0.3)
    breath = lowpass(noise(d), sweep(2500, 600, d)) * env(int(SR * d), 0.1, 1.1, 0.3, 0.2) * 0.5
    write("boss_roar.wav", soft_clip(mix(roar, breath), 2.0), 0.85)

    # explosion
    d = 0.9
    n = lowpass(noise(d), sweep(5000, 120, d)) * exp_decay(int(SR * d), 0.22)
    boom = osc("sine", sweep(120, 35, d)) * exp_decay(int(SR * d), 0.25)
    write("explosion.wav", soft_clip(mix(n, boom * 1.2), 1.4), 0.85)

    # boss death: long falling boom with a shimmer tail
    d = 2.6
    boom = osc("sine", sweep(90, 25, d)) * exp_decay(int(SR * d), 0.6)
    rumble = lowpass(noise(d), sweep(4000, 80, d)) * exp_decay(int(SR * d), 0.7)
    sh = np.zeros(int(SR * d))
    for i, nn in enumerate([84, 88, 91, 96, 100, 103]):
        s = osc("sine", note_hz(nn), 1.2) * exp_decay(int(SR * 1.2), 0.3) * 0.25
        sh += at(s, 0.9 + i * 0.1, len(sh))
    write("boss_die.wav", mix(boom * 1.3, rumble, sh), 0.9)

    # buy: cash-register style arpeggio
    total = int(SR * 0.5)
    x = np.zeros(total)
    for i, nn in enumerate([76, 81, 85, 88]):
        tone = osc("square", note_hz(nn), 0.2, 0.25) * exp_decay(int(SR * 0.2), 0.06)
        x += at(tone, i * 0.055, total)
    write("buy.wav", lowpass(x, 6000), 0.5)

    # laser charge-up and blast
    d = 0.8
    x = osc("sine", sweep(200, 1600, d)) * env(int(SR * d), 0.05, 0.7, 0.4, 0.05) * 0.6
    x += lowpass(noise(d), sweep(500, 6000, d)) * env(int(SR * d), 0.2, 0.55, 0.3, 0.05) * 0.3
    write("laser_charge.wav", x, 0.5)
    d = 0.6
    x = osc("saw", 110 + 8 * np.sin(2 * np.pi * 30 * t_axis(d))) + osc("square", 220, d, 0.3) * 0.5
    x = lowpass(x, 2200) * env(int(SR * d), 0.005, 0.5, 0.6, 0.1)
    x += highpass(noise(d), 3000) * env(int(SR * d), 0.005, 0.5, 0.2, 0.1) * 0.3
    write("laser.wav", soft_clip(x, 1.5), 0.6)

    # slam / shockwave
    d = 0.6
    boom = osc("sine", sweep(160, 40, d)) * exp_decay(int(SR * d), 0.12)
    crack = lowpass(noise(d), 1800) * exp_decay(int(SR * d), 0.08)
    write("slam.wav", soft_clip(mix(boom * 1.4, crack), 1.6), 0.85)

    # boss enters phase two: rising alarm
    d = 1.0
    x = osc("square", sweep(200, 800, d), duty=0.5) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 8 * t_axis(d))))
    write("phase.wav", lowpass(x, 3000) * env(int(SR * d), 0.01, 0.9, 0.4, 0.1), 0.55)

    # orb pop
    d = 0.18
    x = osc("sine", sweep(900, 200, d)) * exp_decay(int(SR * d), 0.04)
    write("orb_pop.wav", x, 0.45)

    # boss shot volley
    d = 0.2
    x = osc("square", sweep(700, 180, d), duty=0.4) * exp_decay(int(SR * d), 0.06)
    write("boss_fire.wav", lowpass(x, 3000), 0.4)

    # keyboard tick for name entry
    x = osc("square", 1400, 0.03, 0.25) * exp_decay(int(SR * 0.03), 0.006)
    write("type.wav", x, 0.3)


# ---------------------------------------------------------------- music

def make_track(bpm, bars):
    beat = 60.0 / bpm
    bar = beat * 4
    n = int(SR * bar * bars)
    return beat, bar, n


def place_in(buf, sig, t):
    n = len(buf)
    s = int(t * SR) % n
    e = s + len(sig)
    if e <= n:
        buf[s:e] += sig
    else:
        k = n - s
        buf[s:] += sig[:k]
        buf[: e - n] += sig[k:]


def cdelay(x, delay_s, feedback, mix_amt, repeats=5):
    out = x.copy()
    shift = int(delay_s * SR)
    g = mix_amt
    for i in range(1, repeats + 1):
        out += np.roll(x, shift * i) * g
        g *= feedback
    return out


def kick():
    return osc("sine", sweep(160, 40, 0.3)) * exp_decay(int(SR * 0.3), 0.08)


def snare():
    s = lowpass(noise(0.2), 4000) * exp_decay(int(SR * 0.2), 0.05)
    return s + osc("tri", 190, 0.2) * exp_decay(int(SR * 0.2), 0.03) * 0.5


def hat():
    return highpass(noise(0.04), 6000) * exp_decay(int(SR * 0.04), 0.01)


def boss_music():
    """Two synchronised layers at 150 BPM in D minor, like the level music."""
    beat, bar, n = make_track(150, 16)
    prog = [[50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 49, 52]]   # Dm Bb C A
    riff = [0, 0, 12, 0, 10, 0, 7, 8]
    lead = [(0, 74, 1.5), (1.5, 77, 0.5), (2, 76, 1), (3, 74, 1), (4, 72, 2), (6, 69, 2),
            (8, 74, 1.5), (9.5, 77, 0.5), (10, 81, 1), (11, 79, 1), (12, 77, 2), (14, 76, 2)]
    light = np.zeros(n)
    dark = np.zeros(n)
    for blk in range(8):
        ch = prog[blk % 4]
        t0 = blk * 2 * bar
        # light: driving arps + pads + clean drums
        pad = pad_note([note_hz(m + 12) for m in ch], 2 * bar, "tri") * env(int(SR * 2 * bar), 0.3, 0.5, 0.8, 0.5)
        place_in(light, lowpass(pad, 3000) * 0.22, t0)
        for i in range(32):
            nn = ch[i % 3] + 24 + (12 if i % 8 == 7 else 0)
            d = beat / 4 * 0.85
            tone = osc("square", note_hz(nn), d, 0.25) * env(int(SR * d), 0.002, 0.1, 0.0, 0.01)
            place_in(light, lowpass(tone, 4500) * 0.09, t0 + i * beat / 4)
        for b in range(8):
            place_in(light, kick() * 0.5, t0 + b * beat)
            if b % 2 == 1:
                place_in(light, snare() * 0.25, t0 + b * beat)
            place_in(light, hat() * 0.08, t0 + b * beat + beat / 2)
        # dark: distorted riff bass + heavy drums
        for i in range(16):
            d = beat / 2 * 0.9
            f = note_hz(ch[0] - 12 + riff[i % 8])
            tone = osc("saw", f, d) + osc("saw", f * 1.01, d) + osc("square", f / 2, d, 0.5) * 0.5
            cut = 500 + 2500 * exp_decay(int(SR * d), 0.04)
            place_in(dark, soft_clip(lowpass(tone, cut), 2.5) * env(int(SR * d), 0.002, 0.2, 0.5, 0.03) * 0.2, t0 + i * beat / 2)
        for b in range(8):
            place_in(dark, kick() * 0.7, t0 + b * beat)
            place_in(dark, kick() * 0.4, t0 + b * beat + beat * 0.75)
            if b % 2 == 1:
                place_in(dark, soft_clip(snare(), 2.0) * 0.32, t0 + b * beat)
            for k in range(2):
                place_in(dark, hat() * 0.06, t0 + b * beat + k * beat / 2)
    # lead melody: bells in light, screaming saw in dark (second half)
    for rep in range(2):
        for b, nn, ln in lead:
            d = ln * beat
            t0 = 8 * bar + rep * 4 * bar + b * beat
            tone = osc("sine", note_hz(nn), d) + 0.35 * osc("sine", note_hz(nn) * 2, d)
            place_in(light, tone * exp_decay(int(SR * d), 0.4) * env(int(SR * d), 0.004, 0.1, 1.0, 0.05) * 0.14, t0)
            vib = 1 + 0.01 * np.sin(2 * np.pi * 6 * t_axis(d))
            st = osc("saw", note_hz(nn - 12) * vib) + osc("square", note_hz(nn - 12) * 1.004 * vib, None, 0.5) * 0.6
            place_in(dark, soft_clip(lowpass(st, 2200), 2.2) * env(int(SR * d), 0.01, 0.2, 0.7, 0.08) * 0.11, t0)
    light = cdelay(light, beat * 0.75, 0.4, 0.25)
    dark = cdelay(dark, beat * 0.5, 0.3, 0.18)
    write("boss_light.wav", soft_clip(normalize(light, 0.95), 1.1), 0.8)
    write("boss_dark.wav", soft_clip(normalize(dark, 0.95), 1.3), 0.8)


def theme2_music():
    """Second level theme (used in even-numbered worlds): 112 BPM, E minor / G major."""
    beat, bar, n = make_track(112, 16)
    light_prog = [[52, 55, 59, 62], [48, 52, 55, 59], [55, 59, 62, 66], [50, 54, 57, 61]]  # Em7 Cmaj7 Gmaj7 D
    dark_prog = [[52, 55, 59, 64], [48, 51, 55, 60], [47, 50, 54, 59], [47, 51, 54, 57]]   # Em Cm Bm B7
    melody = [(0, 79, 1), (1, 81, 1), (2, 83, 2), (4, 81, 1), (5, 79, 1), (6, 76, 2),
              (8, 78, 1), (9, 79, 1), (10, 81, 3), (13, 79, 1), (14, 78, 2),
              (16, 76, 2), (18, 79, 1), (19, 83, 1), (20, 86, 2), (22, 83, 2),
              (24, 81, 2), (26, 79, 1), (27, 78, 1), (28, 76, 4)]
    light = np.zeros(n)
    dark = np.zeros(n)
    for blk in range(8):
        lc = light_prog[blk % 4]
        dc = dark_prog[blk % 4]
        t0 = blk * 2 * bar
        pad = pad_note([note_hz(m + 12) for m in lc], 2 * bar, "sine", 0.003) * env(int(SR * 2 * bar), 0.8, 0.5, 0.8, 0.8)
        place_in(light, pad * 0.28, t0)
        place_in(light, osc("tri", note_hz(lc[0] - 12), 2 * bar) * env(int(SR * 2 * bar), 0.05, 1.0, 0.5, 0.4) * 0.3, t0)
        # plucked 8th-note pattern
        pat = [0, 2, 1, 3, 2, 1, 3, 2]
        for i in range(16):
            nn = lc[pat[i % 8]] + 12
            d = beat / 2
            tone = osc("tri", note_hz(nn), d) * exp_decay(int(SR * d), 0.09)
            place_in(light, tone * 0.13, t0 + i * beat / 2)
        for b in range(8):
            if blk >= 2 and b % 2 == 0:
                place_in(light, kick() * 0.25, t0 + b * beat)
            place_in(light, hat() * 0.05, t0 + b * beat + beat / 2)
        drone = pad_note([note_hz(dc[0] - 12), note_hz(dc[2] - 12)], 2 * bar, "saw", 0.007)
        place_in(dark, lowpass(drone, 600) * env(int(SR * 2 * bar), 0.5, 0.5, 0.9, 0.5) * 0.3, t0)
        for i in range(16):
            d = beat / 2 * 0.8
            f = note_hz(dc[0] - 12 + (7 if i % 4 == 2 else 0))
            tone = osc("square", f, d, 0.3) + osc("saw", f * 1.005, d)
            place_in(dark, soft_clip(lowpass(tone, 900), 1.6) * env(int(SR * d), 0.003, 0.15, 0.3, 0.03) * 0.2, t0 + i * beat / 2)
        if blk >= 1:
            for b in range(8):
                place_in(dark, kick() * 0.55, t0 + b * beat)
                if b % 2 == 1:
                    place_in(dark, snare() * 0.22, t0 + b * beat)
                place_in(dark, hat() * 0.05, t0 + b * beat + beat / 2)
    for b, nn, ln in melody:
        d = ln * beat
        t0 = 8 * bar + b * beat
        tone = osc("sine", note_hz(nn), d) + 0.3 * osc("tri", note_hz(nn) * 2, d)
        place_in(light, tone * exp_decay(int(SR * d), 0.5) * env(int(SR * d), 0.01, 0.1, 1.0, 0.08) * 0.14, t0)
        vib = 1 + 0.008 * np.sin(2 * np.pi * 5 * t_axis(d))
        st = osc("saw", note_hz(nn - 12) * vib) + osc("square", note_hz(nn - 12) * 1.003 * vib, None, 0.4) * 0.5
        place_in(dark, soft_clip(lowpass(st, 1500), 1.8) * env(int(SR * d), 0.02, 0.2, 0.6, 0.12) * 0.1, t0)
    light = cdelay(light, beat * 0.75, 0.45, 0.3)
    dark = cdelay(dark, beat * 0.5, 0.35, 0.22)
    write("music2_light.wav", soft_clip(normalize(light, 0.95), 1.1), 0.8)
    write("music2_dark.wav", soft_clip(normalize(dark, 0.95), 1.2), 0.8)


if __name__ == "__main__":
    sfx()
    boss_music()
    theme2_music()
