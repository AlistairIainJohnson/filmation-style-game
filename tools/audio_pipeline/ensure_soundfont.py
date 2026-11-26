#!/usr/bin/env python3
"""Ensure an MIT/permissively licensed orchestral SoundFont exists in the local gitignored cache."""

from __future__ import annotations

import pathlib
import sys
import zipfile
import io

import httpx

ROOT = pathlib.Path(__file__).resolve().parents[2]
SF2_DIR = ROOT / "tools" / "audio_pipeline" / ".soundfonts"
TARGET_SF2 = SF2_DIR / "orchestra.sf2"
MIN_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB

# Ordered list of official/reputable free orchestral SoundFont sources
SOURCES: list[dict[str, str]] = [
    {
        "name": "MuseScore_General (MIT)",
        "url": "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf2",
        "kind": "sf2",
    },
    {
        "name": "MuseScore_General_HQ (MIT)",
        "url": "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General_HQ.sf2",
        "kind": "sf2",
    },
    {
        "name": "FluidR3_GM (MIT)",
        "url": "https://keymusician01.s3.amazonaws.com/FluidR3_GM.zip",
        "kind": "zip",
    },
    {
        "name": "GeneralUser_GS (Permissive)",
        "url": "https://www.dropbox.com/s/4x27l49kxcwamp5/GeneralUser_GS_1.471.zip?dl=1",
        "kind": "zip",
    },
]


def ensure_soundfont(force: bool = False) -> pathlib.Path:
    SF2_DIR.mkdir(parents=True, exist_ok=True)
    if not force and TARGET_SF2.exists() and TARGET_SF2.stat().st_size >= MIN_SIZE_BYTES:
        print(f"[OK] Cached orchestral SoundFont ready: {TARGET_SF2} ({TARGET_SF2.stat().st_size / (1024*1024):.1f} MB)")
        return TARGET_SF2

    tmp_path = SF2_DIR / "orchestra.sf2.tmp"
    for src in SOURCES:
        print(f"Downloading {src['name']} from {src['url']} ...")
        try:
            with httpx.Client(follow_redirects=True, timeout=180.0) as client:
                if src["kind"] == "sf2":
                    with client.stream("GET", src["url"]) as resp:
                        resp.raise_for_status()
                        with open(tmp_path, "wb") as f:
                            total = 0
                            for chunk in resp.iter_bytes(chunk_size=1024 * 512):
                                f.write(chunk)
                                total += len(chunk)
                        if total >= MIN_SIZE_BYTES:
                            tmp_path.replace(TARGET_SF2)
                            print(f"[OK] Downloaded {src['name']} ({total / (1024*1024):.1f} MB) -> {TARGET_SF2}")
                            return TARGET_SF2
                else:
                    resp = client.get(src["url"])
                    resp.raise_for_status()
                    with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
                        sf2_members = [m for m in zf.namelist() if m.lower().endswith(".sf2")]
                        if not sf2_members:
                            raise RuntimeError("No .sf2 file inside archive")
                        member = sf2_members[0]
                        data = zf.read(member)
                        if len(data) < MIN_SIZE_BYTES:
                            raise RuntimeError(f"Extracted .sf2 too small: {len(data)} bytes")
                        tmp_path.write_bytes(data)
                        tmp_path.replace(TARGET_SF2)
                        print(f"[OK] Extracted {member} ({len(data) / (1024*1024):.1f} MB) -> {TARGET_SF2}")
                        return TARGET_SF2
        except Exception as exc:
            print(f"[WARN] Failed {src['name']}: {exc}", file=sys.stderr)
            if tmp_path.exists():
                tmp_path.unlink()

    raise RuntimeError("All orchestral SoundFont download sources failed.")


if __name__ == "__main__":
    ensure_soundfont(force="--force" in sys.argv)
