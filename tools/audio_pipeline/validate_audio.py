#!/usr/bin/env python3
"""Validate all rendered audio files in assets/audio/ for non-silence, no clipping, and config completeness."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import wave

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIO_DIR = ROOT / "assets" / "audio"
SCORE_JSON = ROOT / "data" / "knight_lore" / "audio_score.json"
SOUNDSCAPES_JSON = ROOT / "data" / "knight_lore" / "audio_soundscapes.json"


def check_wav(path: pathlib.Path) -> tuple[float, float, float]:
    with wave.open(str(path), "rb") as wf:
        nch = wf.getnchannels()
        sr = wf.getframerate()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)
    arr = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if arr.size == 0:
        raise ValueError(f"Empty audio file: {path}")
    peak = float(np.max(np.abs(arr)))
    rms = float(np.sqrt(np.mean(arr * arr)))
    dur = nframes / float(sr)
    return dur, peak, 20.0 * np.log10(max(rms, 1e-9))


def check_ogg(path: pathlib.Path) -> tuple[float, float, float]:
    # Decode via ffmpeg to raw s16le stdout
    res = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "s16le", "-acodec", "pcm_s16le", "-ac", "2", "-ar", "44100", "-"],
        check=True,
        stdout=subprocess.PIPE,
    )
    arr = np.frombuffer(res.stdout, dtype=np.int16).astype(np.float32) / 32768.0
    if arr.size == 0:
        raise ValueError(f"Empty ogg audio: {path}")
    peak = float(np.max(np.abs(arr)))
    rms = float(np.sqrt(np.mean(arr * arr)))
    dur = (arr.size // 2) / 44100.0
    return dur, peak, 20.0 * np.log10(max(rms, 1e-9))


def main() -> int:
    errors: list[str] = []

    wavs = sorted(AUDIO_DIR.rglob("*.wav"))
    oggs = sorted(AUDIO_DIR.rglob("*.ogg"))
    if not oggs:
        errors.append("No .ogg files found in assets/audio/")
    if not wavs:
        errors.append("No .wav files found in assets/audio/")

    for p in oggs:
        dur, peak, rms_db = check_ogg(p)
        if peak > 0.99:
            errors.append(f"Clipping in {p.relative_to(ROOT)}: peak={peak:.3f}")
        if rms_db < -48.0:
            errors.append(f"Too quiet/silent {p.relative_to(ROOT)}: rms={rms_db:.1f} dBFS")
        print(f"  [OGG] {p.relative_to(ROOT)}: {dur:.2f}s peak={peak:.3f} rms={rms_db:.1f} dBFS")

    for p in wavs:
        dur, peak, rms_db = check_wav(p)
        if peak > 0.99:
            errors.append(f"Clipping in {p.relative_to(ROOT)}: peak={peak:.3f}")
        if rms_db < -50.0:
            errors.append(f"Too quiet/silent {p.relative_to(ROOT)}: rms={rms_db:.1f} dBFS")
        print(f"  [WAV] {p.relative_to(ROOT)}: {dur:.2f}s peak={peak:.3f} rms={rms_db:.1f} dBFS")

    # Verify JSON references
    if SCORE_JSON.exists():
        sc = json.loads(SCORE_JSON.read_text())
        for cname, cdata in sc.get("cues", {}).items():
            stream = cdata.get("stream", "")
            rel = stream.replace("res://", "")
            if not (ROOT / rel).exists():
                errors.append(f"Missing score cue stream for '{cname}': {stream}")

    if SOUNDSCAPES_JSON.exists():
        ss = json.loads(SOUNDSCAPES_JSON.read_text())
        for bname, bdata in ss.get("biomes", {}).items():
            ambs = bdata.get("ambience_streams", {})
            for phase in ["day", "night"]:
                sp = ambs.get(phase, "")
                if sp and not (ROOT / sp.replace("res://", "")).exists():
                    errors.append(f"Missing ambience stream for {bname}/{phase}: {sp}")
        for ename, edata in ss.get("sfx_events", {}).items():
            for sp in edata.get("streams", []):
                if not (ROOT / sp.replace("res://", "")).exists():
                    errors.append(f"Missing sfx stream for '{ename}': {sp}")
            for b, lst in edata.get("biome_streams", {}).items():
                for sp in lst:
                    if not (ROOT / sp.replace("res://", "")).exists():
                        errors.append(f"Missing biome sfx stream for '{ename}/{b}': {sp}")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    print(f"==> Audio validation PASSED ({len(oggs)} .ogg, {len(wavs)} .wav)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
