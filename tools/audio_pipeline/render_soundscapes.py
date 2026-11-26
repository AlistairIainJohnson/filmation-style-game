#!/usr/bin/env python3
"""Render natural offline-synthesized woodland/dungeon ambience loops (.ogg) and
clean acoustic + FluidSynth orchestral sound effects (.wav) for Knight Lore 3D."""

from __future__ import annotations

import pathlib
import subprocess
import sys
import wave

import mido
import numpy as np
from scipy import signal

from ensure_soundfont import ensure_soundfont

ROOT = pathlib.Path(__file__).resolve().parents[2]
AMB_DIR = ROOT / "assets" / "audio" / "ambience"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MIDI_DIR = ROOT / "tools" / "audio_pipeline" / ".midi"
SAMPLE_RATE = 44100


def pink_noise(n_samples: int, rng: np.random.Generator) -> np.ndarray:
    """Generate Voss-McCartney / spectral 1/f pink noise normalized to unit std."""
    white = rng.standard_normal(n_samples)
    # 1/f spectral shaping via FFT
    freqs = np.fft.rfftfreq(n_samples, d=1.0 / SAMPLE_RATE)
    spec = np.fft.rfft(white)
    scale = np.zeros_like(freqs)
    mask = freqs > 5.0
    scale[mask] = 1.0 / np.sqrt(freqs[mask])
    pink = np.fft.irfft(spec * scale, n=n_samples)
    std = np.std(pink)
    return (pink / std).astype(np.float32) if std > 1e-9 else np.zeros(n_samples, dtype=np.float32)


def butter_bandpass(x: np.ndarray, low_hz: float, high_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SAMPLE_RATE
    lo = max(10.0, low_hz) / nyq
    hi = min(nyq * 0.92, high_hz) / nyq
    sos = signal.butter(order, [lo, hi], btype="bandpass", output="sos")
    return signal.sosfilt(sos, x).astype(np.float32)


def butter_lowpass(x: np.ndarray, cutoff_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SAMPLE_RATE
    hi = min(nyq * 0.92, cutoff_hz) / nyq
    sos = signal.butter(order, hi, btype="lowpass", output="sos")
    return signal.sosfilt(sos, x).astype(np.float32)


def butter_highpass(x: np.ndarray, cutoff_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SAMPLE_RATE
    lo = max(10.0, cutoff_hz) / nyq
    sos = signal.butter(order, lo, btype="highpass", output="sos")
    return signal.sosfilt(sos, x).astype(np.float32)


def simple_stereo_reverb(stereo: np.ndarray, rt60_s: float = 1.2, wet: float = 0.35) -> np.ndarray:
    """Warm stereo multitap + comb tail so distant woodland birds/owls/drips sit naturally in space."""
    n = len(stereo)
    out = stereo.copy()
    taps_l = [(0.029, 0.45), (0.047, 0.36), (0.071, 0.28), (0.109, 0.22), (0.163, 0.15), (0.241, 0.10)]
    taps_r = [(0.033, 0.45), (0.053, 0.36), (0.079, 0.28), (0.119, 0.22), (0.173, 0.15), (0.257, 0.10)]
    scale = max(0.3, min(2.0, rt60_s))
    wet_buf = np.zeros_like(stereo)
    for delay_s, g in taps_l:
        d = int(round(delay_s * scale * SAMPLE_RATE))
        if d < n:
            wet_buf[d:, 0] += stereo[: n - d, 0] * g
    for delay_s, g in taps_r:
        d = int(round(delay_s * scale * SAMPLE_RATE))
        if d < n:
            wet_buf[d:, 1] += stereo[: n - d, 1] * g
    wet_buf[:, 0] = butter_lowpass(wet_buf[:, 0], 4200.0, order=1)
    wet_buf[:, 1] = butter_lowpass(wet_buf[:, 1], 4200.0, order=1)
    return (out * (1.0 - wet * 0.4) + wet_buf * wet).astype(np.float32)


def wrap_seamless_loop(stereo_with_tail: np.ndarray, loop_samples: int) -> np.ndarray:
    body = stereo_with_tail[:loop_samples].copy()
    if len(stereo_with_tail) > loop_samples:
        tail = stereo_with_tail[loop_samples:]
        add_len = min(len(tail), len(body))
        fade = np.linspace(1.0, 0.0, add_len, dtype=np.float32)[:, None]
        body[:add_len] += tail[:add_len] * fade
    # Short 200ms crossfade at the seam itself to guarantee zero click
    xf = min(int(0.20 * SAMPLE_RATE), loop_samples // 4)
    w_in = np.linspace(0.0, 1.0, xf, dtype=np.float32)[:, None]
    w_out = 1.0 - w_in
    seam = body[:xf].copy() * w_in + body[-xf:].copy() * w_out
    body[:xf] = seam
    return body


def write_wav(path: pathlib.Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if audio.ndim == 1:
        audio = np.stack([audio, audio], axis=1)
    pcm = np.clip(audio * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(audio.shape[1])
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


def encode_ogg(stereo: np.ndarray, out_ogg: pathlib.Path, target_lufs: float = -24.0) -> None:
    tmp_wav = MIDI_DIR / (out_ogg.stem + ".tmp.wav")
    norm_wav = MIDI_DIR / (out_ogg.stem + ".norm.wav")
    write_wav(tmp_wav, stereo)
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    cmd_ff = [
        "ffmpeg", "-y",
        "-i", str(tmp_wav),
        "-af", f"loudnorm=I={target_lufs}:TP=-2.0:LRA=8",
        str(norm_wav),
    ]
    subprocess.run(cmd_ff, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cmd_ogg = ["oggenc", "-Q", "-q", "5", "-o", str(out_ogg), str(norm_wav)]
    subprocess.run(cmd_ogg, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tmp_wav.unlink(missing_ok=True)
    norm_wav.unlink(missing_ok=True)
    print(f"[OK] Rendered {out_ogg.relative_to(ROOT)} ({len(stereo)/SAMPLE_RATE:.1f}s)")


def render_ambience_dungeon() -> None:
    """Warm, quiet subterranean dungeon air + sparse distant cavernous water drops."""
    rng = np.random.default_rng(101)
    loop_s = 30.0
    total_s = 33.0
    n_loop = int(loop_s * SAMPLE_RATE)
    n_tot = int(total_s * SAMPLE_RATE)

    # Decorrelated low-passed cavernous air bed (50-220 Hz, slow breathing LFO)
    l_air = butter_bandpass(pink_noise(n_tot, rng), 55.0, 220.0, order=2)
    r_air = butter_bandpass(pink_noise(n_tot, rng), 55.0, 220.0, order=2)
    t = np.arange(n_tot, dtype=np.float32) / SAMPLE_RATE
    lfo = 0.72 + 0.28 * np.sin(2.0 * np.pi * (2.0 / loop_s) * t)
    bed = np.stack([l_air, r_air], axis=1) * lfo[:, None] * 0.06

    # Sparse distant water droplets
    drops_buf = np.zeros((n_tot, 2), dtype=np.float32)
    drop_times = [2.4, 7.8, 12.1, 18.6, 23.9, 27.5]
    for dt_s in drop_times:
        idx0 = int(dt_s * SAMPLE_RATE)
        dur_s = 0.045
        dn = int(dur_s * SAMPLE_RATE)
        if idx0 + dn >= n_tot:
            continue
        td = np.arange(dn, dtype=np.float32) / SAMPLE_RATE
        f0 = rng.uniform(950.0, 1450.0)
        f1 = f0 * 1.45
        phase = 2.0 * np.pi * (f0 * td + 0.5 * ((f1 - f0) / dur_s) * td * td)
        env = np.sin(np.pi * np.minimum(1.0, td / 0.005)) * np.exp(-td / 0.011)
        drop = np.sin(phase) * env * rng.uniform(0.18, 0.30)
        pan = rng.uniform(0.25, 0.75)
        drops_buf[idx0 : idx0 + dn, 0] += drop * np.cos(pan * np.pi * 0.5)
        drops_buf[idx0 : idx0 + dn, 1] += drop * np.sin(pan * np.pi * 0.5)

    drops_rev = simple_stereo_reverb(drops_buf, rt60_s=1.8, wet=0.65)
    mix = wrap_seamless_loop(bed + drops_rev, n_loop)
    encode_ogg(mix, AMB_DIR / "ambience_dungeon.ogg", target_lufs=-27.0)


def _synth_bird_phrase(rng: np.random.Generator) -> np.ndarray:
    """Synthesize a soft, natural multi-syllable woodland bird call using curved pitch contours."""
    n_notes = int(rng.integers(3, 6))
    parts: list[np.ndarray] = []
    species = int(rng.integers(0, 3))
    for i in range(n_notes):
        dur = float(rng.uniform(0.055, 0.13))
        n = int(dur * SAMPLE_RATE)
        t = np.arange(n, dtype=np.float32) / SAMPLE_RATE
        if species == 0:  # Robin / flute-like rising whistle
            f0 = rng.uniform(2100.0, 2700.0)
            f1 = f0 * rng.uniform(1.18, 1.42)
            freq_curve = f0 + (f1 - f0) * np.sin(0.5 * np.pi * t / dur)
        elif species == 1:  # Blackbird mellow descending call
            f0 = rng.uniform(2400.0, 3100.0)
            f1 = f0 * rng.uniform(0.74, 0.88)
            freq_curve = f0 + (f1 - f0) * (t / dur) ** 1.3
        else:  # Warbler gentle trilled chirp
            f_center = rng.uniform(2700.0, 3600.0)
            freq_curve = f_center + 280.0 * np.sin(2.0 * np.pi * 34.0 * t)
        phase = np.cumsum(2.0 * np.pi * freq_curve / SAMPLE_RATE)
        # Smooth bell envelope (zero click) + subtle soft 2nd harmonic
        env = np.sin(np.pi * t / dur) ** 1.4
        sig = (0.85 * np.sin(phase) + 0.15 * np.sin(2.0 * phase)) * env
        parts.append(sig.astype(np.float32))
        gap_s = float(rng.uniform(0.04, 0.11))
        parts.append(np.zeros(int(gap_s * SAMPLE_RATE), dtype=np.float32))
    return np.concatenate(parts)


def render_ambience_woodland_day() -> None:
    """Gentle wind through leaves, foliage rustles, and spacious distant woodland birdsong."""
    rng = np.random.default_rng(202)
    loop_s = 30.0
    total_s = 33.0
    n_loop = int(loop_s * SAMPLE_RATE)
    n_tot = int(total_s * SAMPLE_RATE)
    t = np.arange(n_tot, dtype=np.float32) / SAMPLE_RATE

    # Soft dual-band wind breeze (low warmth + mid canopy air)
    w_l = butter_bandpass(pink_noise(n_tot, rng), 180.0, 620.0, order=2)
    w_r = butter_bandpass(pink_noise(n_tot, rng), 180.0, 620.0, order=2)
    swirl_l = 0.65 + 0.35 * np.sin(2.0 * np.pi * (2.0 / loop_s) * t + 0.2)
    swirl_r = 0.65 + 0.35 * np.sin(2.0 * np.pi * (2.0 / loop_s) * t + 1.6)
    wind = np.stack([w_l * swirl_l, w_r * swirl_r], axis=1) * 0.085

    # Soft periodic leaf rustles
    for gust_t in [4.2, 11.5, 19.0, 25.4]:
        g0 = int(gust_t * SAMPLE_RATE)
        gn = int(rng.uniform(1.1, 1.9) * SAMPLE_RATE)
        if g0 + gn < n_tot:
            tg = np.arange(gn, dtype=np.float32) / gn
            env = (0.5 - 0.5 * np.cos(2.0 * np.pi * tg)) ** 1.5
            gl = butter_bandpass(pink_noise(gn, rng), 1600.0, 4600.0, order=2) * env * 0.032
            gr = butter_bandpass(pink_noise(gn, rng), 1600.0, 4600.0, order=2) * env * 0.032
            wind[g0 : g0 + gn, 0] += gl
            wind[g0 : g0 + gn, 1] += gr

    # Distant woodland birds
    birds = np.zeros((n_tot, 2), dtype=np.float32)
    for bt in [1.8, 5.9, 10.4, 15.2, 20.6, 24.8, 28.0]:
        phrase = _synth_bird_phrase(rng)
        i0 = int(bt * SAMPLE_RATE)
        if i0 + len(phrase) < n_tot:
            pan = rng.uniform(0.15, 0.85)
            amp = rng.uniform(0.055, 0.095)
            birds[i0 : i0 + len(phrase), 0] += phrase * amp * np.cos(pan * np.pi * 0.5)
            birds[i0 : i0 + len(phrase), 1] += phrase * amp * np.sin(pan * np.pi * 0.5)

    birds_rev = simple_stereo_reverb(birds, rt60_s=1.1, wet=0.55)
    mix = wrap_seamless_loop(wind + birds_rev, n_loop)
    encode_ogg(mix, AMB_DIR / "ambience_woodland_day.ogg", target_lufs=-24.5)


def render_ambience_woodland_night() -> None:
    """Cool nocturnal forest breeze, soft natural chirping crickets, and distant warm owl hoots."""
    rng = np.random.default_rng(303)
    loop_s = 30.0
    total_s = 33.0
    n_loop = int(loop_s * SAMPLE_RATE)
    n_tot = int(total_s * SAMPLE_RATE)
    t = np.arange(n_tot, dtype=np.float32) / SAMPLE_RATE

    # Cool quiet night air
    w_l = butter_bandpass(pink_noise(n_tot, rng), 140.0, 450.0, order=2)
    w_r = butter_bandpass(pink_noise(n_tot, rng), 140.0, 450.0, order=2)
    swirl = 0.7 + 0.3 * np.sin(2.0 * np.pi * (1.0 / loop_s) * t)
    bed = np.stack([w_l, w_r], axis=1) * swirl[:, None] * 0.06

    # Realistic sparse cricket chirps (3 soft sine-pulse syllables per burst, spaced naturally)
    crickets = np.zeros((n_tot, 2), dtype=np.float32)
    for c_pan, c_freq, period_s, offset_s in [(0.22, 3950.0, 1.85, 0.4), (0.78, 4220.0, 2.35, 1.2)]:
        ct = offset_s
        while ct < loop_s - 0.8:
            # One 3-syllable chirp burst (~220ms)
            for syl in range(3):
                s0 = int((ct + syl * 0.055) * SAMPLE_RATE)
                sn = int(0.032 * SAMPLE_RATE)
                if s0 + sn < n_tot:
                    ts = np.arange(sn, dtype=np.float32) / SAMPLE_RATE
                    env = np.sin(np.pi * np.arange(sn, dtype=np.float32) / sn) ** 1.5
                    # Smooth harmonic chirp (pure sine + faint 2nd harmonic, no harsh square!)
                    sig = np.sin(2.0 * np.pi * c_freq * ts) * env * 0.022
                    crickets[s0 : s0 + sn, 0] += sig * np.cos(c_pan * np.pi * 0.5)
                    crickets[s0 : s0 + sn, 1] += sig * np.sin(c_pan * np.pi * 0.5)
            ct += period_s + rng.uniform(-0.12, 0.18)

    # 2 Distant warm Owl hoots ("hoo... hoo-hoooo")
    owls = np.zeros((n_tot, 2), dtype=np.float32)
    for owl_t, pan in [(6.5, 0.30), (21.5, 0.72)]:
        for offset, dur, f_start, f_end in [(0.0, 0.36, 365.0, 345.0), (0.62, 0.22, 355.0, 355.0), (0.95, 0.78, 355.0, 310.0)]:
            i0 = int((owl_t + offset) * SAMPLE_RATE)
            dn = int(dur * SAMPLE_RATE)
            if i0 + dn < n_tot:
                to = np.arange(dn, dtype=np.float32) / SAMPLE_RATE
                freq_c = f_start + (f_end - f_start) * (to / dur) ** 1.4
                ph = np.cumsum(2.0 * np.pi * freq_c / SAMPLE_RATE)
                # Breathy soft vowel-like hoot
                breath = butter_bandpass(pink_noise(dn, rng), 260.0, 620.0, order=2) * 0.12
                env = (np.sin(np.pi * to / dur) ** 1.3) * np.exp(-to * 0.8)
                hoot = (0.88 * np.sin(ph) + 0.12 * np.sin(2.0 * ph) + breath) * env * 0.11
                owls[i0 : i0 + dn, 0] += hoot * np.cos(pan * np.pi * 0.5)
                owls[i0 : i0 + dn, 1] += hoot * np.sin(pan * np.pi * 0.5)

    nature_rev = simple_stereo_reverb(crickets + owls, rt60_s=1.2, wet=0.50)
    mix = wrap_seamless_loop(bed + nature_rev, n_loop)
    encode_ogg(mix, AMB_DIR / "ambience_woodland_night.ogg", target_lufs=-25.5)


def norm_and_save_sfx(name: str, mono_or_stereo: np.ndarray, peak_target: float = 0.65) -> None:
    pk = float(np.max(np.abs(mono_or_stereo)))
    out = mono_or_stereo.copy()
    if pk > 1e-6:
        out *= peak_target / pk
    write_wav(SFX_DIR / f"{name}.wav", out)
    print(f"[OK] Rendered SFX {name}.wav ({len(out)/SAMPLE_RATE*1000:.0f} ms)")


def render_acoustic_sfx(sf2_path: pathlib.Path) -> None:
    """Render natural footsteps, slams, scrapes, plus FluidSynth orchestral/harp chimes."""
    rng = np.random.default_rng(777)

    # 1. Crisp Stone Flagstone Footsteps (4 variants) -> built to sound crisp through dungeon RoomFX!
    for i in range(4):
        n = int(0.085 * SAMPLE_RATE)
        t = np.arange(n, dtype=np.float32) / SAMPLE_RATE
        click_noise = butter_bandpass(pink_noise(n, rng), 900.0 + i * 120.0, 3400.0, order=2)
        click_env = np.exp(-t / 0.008)
        body_f = rng.uniform(115.0, 145.0)
        body = np.sin(2.0 * np.pi * body_f * np.exp(-t * 14.0) * t) * np.exp(-t / 0.022)
        step = click_noise * click_env * 0.75 + body * 0.65
        norm_and_save_sfx(f"step_stone_{i}", step, peak_target=0.62)

    # 2. Soft Woodland Turf/Leaf Footsteps (4 variants)
    for i in range(4):
        n = int(0.11 * SAMPLE_RATE)
        t = np.arange(n, dtype=np.float32) / SAMPLE_RATE
        rustle = butter_bandpass(pink_noise(n, rng), 550.0, 2200.0, order=2) * np.sin(np.pi * np.minimum(1.0, t / 0.08)) * np.exp(-t / 0.032)
        thump = np.sin(2.0 * np.pi * rng.uniform(75.0, 95.0) * t) * np.exp(-t / 0.028)
        norm_and_save_sfx(f"step_woodland_{i}", rustle * 0.65 + thump * 0.55, peak_target=0.48)

    # 3. Heavy Guard / Melkhior Footsteps (2 variants)
    for i in range(2):
        n = int(0.14 * SAMPLE_RATE)
        t = np.arange(n, dtype=np.float32) / SAMPLE_RATE
        clink = butter_bandpass(pink_noise(n, rng), 1100.0, 2800.0, order=2) * np.exp(-t / 0.015)
        thud = np.sin(2.0 * np.pi * (82.0 + i * 8.0) * np.exp(-t * 10.0) * t) * np.exp(-t / 0.045)
        norm_and_save_sfx(f"step_guard_{i}", thud * 0.85 + clink * 0.40, peak_target=0.68)

    # 4. Jump & Landings & Physics Push / Slam / Bounce
    # Jump (light cloth whoosh + soft upward air)
    n_j = int(0.16 * SAMPLE_RATE)
    tj = np.arange(n_j, dtype=np.float32) / SAMPLE_RATE
    whoosh = butter_bandpass(pink_noise(n_j, rng), 320.0, 1400.0, order=2) * np.sin(np.pi * tj / 0.16)
    norm_and_save_sfx("jump", whoosh, peak_target=0.45)

    # Land Stone & Land Woodland
    n_l = int(0.18 * SAMPLE_RATE)
    tl = np.arange(n_l, dtype=np.float32) / SAMPLE_RATE
    thud_l = np.sin(2.0 * np.pi * 88.0 * np.exp(-tl * 8.0) * tl) * np.exp(-tl / 0.055)
    grit_l = butter_bandpass(pink_noise(n_l, rng), 450.0, 2200.0, order=2) * np.exp(-tl / 0.025)
    norm_and_save_sfx("land_stone", thud_l * 0.8 + grit_l * 0.5, peak_target=0.68)
    norm_and_save_sfx("land_woodland", butter_lowpass(thud_l * 0.7 + grit_l * 0.3, 600.0), peak_target=0.55)

    # Push Stone Scrape
    n_p = int(0.22 * SAMPLE_RATE)
    tp = np.arange(n_p, dtype=np.float32) / SAMPLE_RATE
    scrape = butter_bandpass(pink_noise(n_p, rng), 110.0, 750.0, order=2) * np.sin(np.pi * tp / 0.22)
    norm_and_save_sfx("push_stone", scrape, peak_target=0.48)

    # Bounce Thud
    n_b = int(0.14 * SAMPLE_RATE)
    tb = np.arange(n_b, dtype=np.float32) / SAMPLE_RATE
    norm_and_save_sfx("bounce_thud", np.sin(2.0 * np.pi * 125.0 * np.exp(-tb * 12.0) * tb) * np.exp(-tb / 0.038), peak_target=0.58)

    # Heavy Iron Portcullis Slam
    n_s = int(0.45 * SAMPLE_RATE)
    ts = np.arange(n_s, dtype=np.float32) / SAMPLE_RATE
    clang = (np.sin(2.0 * np.pi * 240.0 * ts) * 0.4 + np.sin(2.0 * np.pi * 387.0 * ts) * 0.3 +
             butter_bandpass(pink_noise(n_s, rng), 400.0, 3200.0) * 0.6) * np.exp(-ts / 0.11)
    boom = np.sin(2.0 * np.pi * 68.0 * np.exp(-ts * 6.0) * ts) * np.exp(-ts / 0.14)
    norm_and_save_sfx("portcullis_slam", clang * 0.55 + boom * 0.85, peak_target=0.78)

    # 5. FluidSynth-rendered Orchestral / Magical SFX
    def render_fs_sfx(name: str, notes: list[tuple[int, int, float, float, int]], tail_s: float = 0.8, peak: float = 0.60) -> None:
        mid = mido.MidiFile(ticks_per_beat=480)
        trk = mido.MidiTrack()
        mid.tracks.append(trk)
        trk.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(120.0), time=0))
        seen_ch: set[int] = set()
        msgs: list[tuple[int, mido.Message]] = []
        for ch, prog, start_s, dur_s, pitch in notes:
            if ch not in seen_ch:
                seen_ch.add(ch)
                msgs.append((0, mido.Message("program_change", channel=ch, program=prog, time=0)))
                msgs.append((0, mido.Message("control_change", channel=ch, control=91, value=78, time=0)))
            t0 = int(round(start_s * 960.0))
            t1 = int(round((start_s + dur_s) * 960.0))
            msgs.append((t0, mido.Message("note_on", channel=ch, note=pitch, velocity=96, time=0)))
            msgs.append((t1, mido.Message("note_off", channel=ch, note=pitch, velocity=0, time=0)))
        msgs.sort(key=lambda x: (x[0], 0 if x[1].type == "note_off" else 1))
        prev = 0
        for tk, m in msgs:
            trk.append(m.copy(time=max(0, tk - prev)))
            prev = tk
        mid_path = MIDI_DIR / f"sfx_{name}.mid"
        raw_wav = MIDI_DIR / f"sfx_{name}.raw.wav"
        mid.save(mid_path)
        subprocess.run(
            ["fluidsynth", "-ni", "-g", "0.9", "-r", str(SAMPLE_RATE),
             "-o", "synth.reverb.active=yes", "-o", "synth.reverb.room-size=0.72",
             "-o", "synth.reverb.level=0.65", "-F", str(raw_wav), str(sf2_path), str(mid_path)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with wave.open(str(raw_wav), "rb") as wf:
            nch = wf.getnchannels()
            arr = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        arr = arr.reshape(-1, nch)
        abs_m = np.max(np.abs(arr), axis=1)
        nz = np.where(abs_m > 0.0015)[0]
        if len(nz) > 0:
            end_i = min(len(arr), int(nz[-1]) + int(0.15 * SAMPLE_RATE))
            arr = arr[:end_i]
        raw_wav.unlink(missing_ok=True)
        norm_and_save_sfx(name, arr, peak_target=peak)

    render_fs_sfx("menu_select", [(0, 8, 0.0, 0.18, 82)], peak=0.52)          # Celesta Bb5
    render_fs_sfx("pause_toggle", [(0, 8, 0.0, 0.14, 77), (0, 8, 0.08, 0.25, 82)], peak=0.52)
    render_fs_sfx("pickup_chime", [(0, 46, 0.0, 0.35, 70), (0, 46, 0.06, 0.35, 77), (0, 8, 0.12, 0.45, 82)], peak=0.56)
    render_fs_sfx("appear_sparkles", [(0, 46, 0.0, 0.4, 70), (0, 46, 0.06, 0.4, 73), (0, 46, 0.12, 0.4, 77), (0, 8, 0.18, 0.55, 82)], peak=0.58)
    render_fs_sfx("cauldron_accept", [(0, 46, 0.0, 0.4, 70), (0, 46, 0.07, 0.4, 74), (0, 46, 0.14, 0.5, 77), (1, 14, 0.14, 0.9, 82)], peak=0.64)
    render_fs_sfx("cauldron_reject", [(0, 47, 0.0, 0.45, 42), (1, 60, 0.0, 0.45, 53), (1, 60, 0.0, 0.45, 54)], peak=0.62)
    render_fs_sfx("transform_swell", [(0, 48, 0.0, 1.1, 46), (0, 48, 0.1, 1.0, 54), (1, 60, 0.2, 0.9, 58), (2, 47, 0.0, 0.6, 46), (3, 52, 0.25, 1.0, 65)], peak=0.66)
    render_fs_sfx("death_sting", [(0, 48, 0.0, 0.6, 66), (0, 48, 0.15, 0.7, 61), (0, 48, 0.30, 0.9, 58), (1, 47, 0.0, 0.7, 46)], peak=0.65)


def main() -> int:
    MIDI_DIR.mkdir(parents=True, exist_ok=True)
    sf2_path = ensure_soundfont()
    render_ambience_dungeon()
    render_ambience_woodland_day()
    render_ambience_woodland_night()
    render_acoustic_sfx(sf2_path)
    print("==> All natural soundscapes & acoustic SFX rendered successfully!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
