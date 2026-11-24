#!/usr/bin/env python3
"""Unit tests for the local 2D retro sprite-to-3D PBR normalization pipeline."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

PIPELINE_DIR = Path(__file__).resolve().parent / "asset_pipeline"
if str(PIPELINE_DIR) not in sys.path:
    sys.path.insert(0, str(PIPELINE_DIR))

from extract_spritesheet import extract_all_inspiration_sprites, extract_knight_lore_characters
from generate_3d import generate_3d
from preprocess_sprite import preprocess_sprite
from validate_glb import validate_single_glb


class AssetPipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parent.parent
        self.manifest = json.loads((self.root / "assets" / "asset_manifest.json").read_text(encoding="utf-8"))

    def test_manifest_glbs_pass_validation(self) -> None:
        for entry in self.manifest.get("assets", []):
            glb_path = self.root / entry["output_glb"]
            errs, stats = validate_single_glb(
                glb_path,
                entry.get("mode", "static"),
                float(entry.get("target_height", 1.0)),
                int(entry.get("max_tris", 6000)),
                int(entry.get("max_size_kb", 4096)),
            )
            self.assertEqual(errs, [], f"GLB validation failed for {entry['id']}: {errs}")
            self.assertGreater(stats.get("tris", 0), 0)

    def test_preprocess_sprite_outputs_1024_square(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = self.root / "assets" / "source_sprites" / "hero_knight.png"
            out = Path(tmp) / "hero_conditioned.png"
            meta = preprocess_sprite(src, out, target_size=1024, padding=0.15)
            self.assertTrue(out.exists())
            self.assertEqual(meta["output_size"], [1024, 1024])
            self.assertGreaterEqual(len(meta["dominant_palette_rgb"]), 1)

    def test_generic_custom_retro_sprite_end_to_end(self) -> None:
        blender_bin = shutil.which("blender")
        self.assertIsNotNone(blender_bin, "Blender must be installed for Stage 6 asset pipeline")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            sprite_path = tmp_dir / "custom_shield.png"
            img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            for y in range(2, 14):
                for x in range(3, 13):
                    img.putpixel((x, y), (70, 120, 210, 255))
            img.save(sprite_path)

            conditioned = tmp_dir / "shield_1024.png"
            raw_glb = tmp_dir / "shield_raw.glb"
            norm_glb = tmp_dir / "shield_norm.glb"

            preprocess_sprite(sprite_path, conditioned, target_size=1024, padding=0.15)
            generate_3d(conditioned, raw_glb, "local_blender_sculpt", "sprite_sculpt", 0.8)

            norm_script = PIPELINE_DIR / "normalize_glb.py"
            subprocess.run(
                [
                    str(blender_bin),
                    "-b",
                    "-P",
                    str(norm_script),
                    "--",
                    "--in",
                    str(raw_glb),
                    "--out",
                    str(norm_glb),
                    "--mode",
                    "static",
                    "--target-height",
                    "0.8",
                    "--max-tris",
                    "8000",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )

            errs, stats = validate_single_glb(norm_glb, "static", 0.8, 8000, 1024)
            self.assertEqual(errs, [], f"Custom retro sprite E2E validation failed: {errs}")
            self.assertAlmostEqual(stats["height"], 0.8, delta=0.03)
            self.assertAlmostEqual(stats["min_y"], 0.0, delta=0.025)

    def test_knight_lore_spritesheet_extraction(self) -> None:
        sheet = self.root / "concept-art" / "knight-lore-sprites.jpg"
        self.assertTrue(sheet.exists(), "Missing concept-art/knight-lore-sprites.jpg")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            out_dir = tmp_dir / "extracted"
            src_dir = tmp_dir / "source_sprites"
            summary = extract_knight_lore_characters(sheet, out_dir, src_dir)
            self.assertEqual(summary["extracted_frames_count"], 28)
            self.assertTrue((out_dir / "knight_lore_character_sheet.png").exists())
            self.assertTrue((out_dir / "character_proportions.json").exists())
            self.assertTrue((src_dir / "hero_explorer.png").exists())
            self.assertTrue((src_dir / "hero_werewolf.png").exists())
            for fname in [
                "explorer_nw_walk_01.png",
                "explorer_se_walk_01.png",
                "explorer_se_look_left.png",
                "explorer_se_look_right.png",
                "werewolf_nw_walk_01.png",
                "werewolf_se_walk_01.png",
            ]:
                p = out_dir / fname
                self.assertTrue(p.exists(), f"Missing extracted frame: {fname}")
                im = Image.open(p)
                self.assertEqual(im.mode, "RGBA")
                self.assertIsNotNone(im.getbbox())

    def test_extract_all_knight_lore_sprites(self) -> None:
        sheet = self.root / "concept-art" / "knight-lore-sprites.jpg"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            all_dir = tmp_dir / "all"
            contact_path = tmp_dir / "all_sheet.png"
            catalog_path = tmp_dir / "all_catalog.json"
            catalog = extract_all_inspiration_sprites(sheet, all_dir, contact_path, catalog_path)
            self.assertEqual(catalog["total_rows"], 12)
            self.assertGreaterEqual(catalog["total_sprites"], 180)
            self.assertTrue(contact_path.exists())
            self.assertTrue(catalog_path.exists())
            sample = Image.open(all_dir / "r01_c01.png")
            self.assertEqual(sample.mode, "RGBA")
            self.assertIsNotNone(sample.getbbox())


if __name__ == "__main__":
    unittest.main()
