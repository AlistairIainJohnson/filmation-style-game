#!/usr/bin/env python3
"""Unit tests for import_ldtk.py and validate_world.py."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from import_ldtk import compile_ldtk
from validate_world import validate_data_dir


class LevelToolsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parent.parent
        self.data_dir = self.root / "data"
        self.ldtk_path = self.root / "levels" / "filmation_world.ldtk"

    def test_real_data_dir_validates_cleanly(self) -> None:
        errors, _warnings, summary = validate_data_dir(self.data_dir, self.root)
        self.assertEqual(errors, [], f"Unexpected validation errors: {errors}")
        self.assertEqual(summary["rooms"], 4)
        self.assertEqual(summary["world_rooms"], 4)

    def test_ldtk_import_produces_valid_world(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_data = Path(tmp)
            for fname in ["materials.json", "entities.json", "lighting_presets.json"]:
                shutil.copy2(self.data_dir / fname, tmp_data / fname)

            wg_out, written = compile_ldtk(self.ldtk_path, tmp_data)
            self.assertTrue(wg_out.exists())
            self.assertEqual(len(written), 4)

            for room_path in written:
                room_data = json.loads(room_path.read_text(encoding="utf-8"))
                pillars = [b for b in room_data.get("blocks", []) if b.get("type") == "stone_pillar"]
                for pillar in pillars:
                    self.assertTrue(pillar.get("cutaway"), f"{room_path.name} stone_pillar must set cutaway=True")

            errors, _warnings, summary = validate_data_dir(tmp_data, self.root)
            self.assertEqual(errors, [], f"Compiled LDtk world failed validation: {errors}")
            self.assertEqual(summary["rooms"], 4)

    def test_validator_rejects_broken_reciprocity_and_blocked_spawn(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_data = Path(tmp)
            shutil.copytree(self.data_dir, tmp_data, dirs_exist_ok=True)

            # 1. Put a void_cell on room (8,8) north spawn (6, 1)
            r88_path = tmp_data / "rooms" / "room_08_08.json"
            r88 = json.loads(r88_path.read_text(encoding="utf-8"))
            r88["floor"]["void_cells"].append([6, 1])
            r88_path.write_text(json.dumps(r88), encoding="utf-8")

            # 2. Break exit reciprocity in world_graph.json
            wg_path = tmp_data / "world_graph.json"
            wg = json.loads(wg_path.read_text(encoding="utf-8"))
            wg["rooms"][1]["exits"].pop("west", None)
            wg_path.write_text(json.dumps(wg), encoding="utf-8")

            errors, _warnings, _summary = validate_data_dir(tmp_data, self.root)
            joined = "\n".join(errors)
            self.assertIn("void_cell", joined)
            self.assertIn("reciprocity broken", joined)


if __name__ == "__main__":
    unittest.main()
