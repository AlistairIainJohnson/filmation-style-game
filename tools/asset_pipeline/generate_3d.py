#!/usr/bin/env python3
"""Stage B: Pluggable 2D-to-3D asset generation dispatcher.
Defaults to 100% local Apple Silicon execution via headless Blender 5.3.0;
supports optional TripoSR (Apple MPS) and cloud adapters (Tripo, Meshy, hosted TRELLIS 2)."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def generate_3d(
    sprite_path: Path,
    out_glb: Path,
    provider: str,
    kind: str,
    target_height: float,
) -> None:
    out_glb.parent.mkdir(parents=True, exist_ok=True)

    if provider == "local_blender_sculpt":
        blender_bin = shutil.which("blender")
        if not blender_bin:
            raise RuntimeError("Blender CLI not found on PATH.")
        script = Path(__file__).resolve().parent / "blender_sculpt_generator.py"
        cmd = [
            blender_bin,
            "-b",
            "-P",
            str(script),
            "--",
            "--sprite",
            str(sprite_path),
            "--out",
            str(out_glb),
            "--kind",
            kind,
            "--height",
            str(target_height),
        ]
        subprocess.run(cmd, check=True)
        return

    if provider == "local_triposr":
        try:
            import torch  # noqa: F401
        except ImportError as exc:
            raise RuntimeError(
                "local_triposr requires PyTorch with Apple MPS and TripoSR installed. "
                "Use --provider local_blender_sculpt or install torch + tsr in a dedicated ML venv."
            ) from exc
        raise NotImplementedError("Hook local TripoSR MPS CLI invocation when tsr package is installed.")

    env_map = {
        "cloud_tripo": "TRIPO_API_KEY",
        "cloud_meshy": "MESHY_API_KEY",
        "cloud_trellis2": "FAL_KEY",
    }
    if provider in env_map:
        key_name = env_map[provider]
        if not os.environ.get(key_name):
            raise RuntimeError(f"Provider '{provider}' selected, but environment variable {key_name} is not set.")
        raise NotImplementedError(f"Cloud upload adapter stub for {provider}; wire HTTP POST when account is configured.")

    raise ValueError(f"Unknown 3D generator provider: {provider}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate raw 3D GLB from a conditioned 2D sprite")
    parser.add_argument("--sprite", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--provider", default="local_blender_sculpt")
    parser.add_argument("--kind", default="sprite_sculpt")
    parser.add_argument("--height", type=float, default=1.0)
    args = parser.parse_args(argv)

    generate_3d(Path(args.sprite).resolve(), Path(args.out).resolve(), args.provider, args.kind, args.height)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
