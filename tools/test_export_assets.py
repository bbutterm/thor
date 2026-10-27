#!/usr/bin/env python3
"""Проверки аудита исключений перед упаковкой плейтеста."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import check_export_assets as audit


class ExportAuditTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.old_root = audit.ROOT
        audit.ROOT = self.root
        for top in audit.RUNTIME:
            (self.root / top).mkdir(parents=True)
        (self.root / "data/dialogues").mkdir()
        (self.root / "sprites/portraits").mkdir(parents=True)
        (self.root / "assets/quaternius/village").mkdir(parents=True)
        (self.root / "sprites/portraits/hugin_shocked.webp").touch()
        (self.root / "sprites/portraits/freya_angry.webp").touch()
        (self.root / "assets/quaternius/village/Stairs_Stone.gltf").touch()
        (self.root / "export_presets.cfg").write_text(
            '[preset.0]\nexclude_filter="sprites/portraits/hugin_shocked.webp, '
            'sprites/portraits/freya_angry.webp, assets/quaternius/village/Stair*.gltf"\n',
            encoding="utf-8",
        )

    def tearDown(self):
        audit.ROOT = self.old_root
        self.tmp.cleanup()

    def check(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return audit.main()

    def test_unused_resources_are_allowed(self):
        self.assertEqual(self.check(), 0)

    def test_new_dialogue_uses_alias(self):
        line = {"speaker": "munin", "emotion": "shocked", "text": "Кар!"}
        (self.root / "data/dialogues/new.json").write_text(json.dumps({"lines": [line]}), encoding="utf-8")
        self.assertEqual(self.check(), 1)

    def test_direct_ui_call(self):
        (self.root / "ui/example.gd").write_text('p.set_speaker("freya", "angry", {})', encoding="utf-8")
        self.assertEqual(self.check(), 1)

    def test_scene_dependency(self):
        (self.root / "rooms/new.tscn").write_text(
            '[ext_resource type="PackedScene" path="res://assets/quaternius/village/Stairs_Stone.gltf" id="1"]',
            encoding="utf-8",
        )
        self.assertEqual(self.check(), 1)

    def test_script_uses_model_by_basename(self):
        (self.root / "rooms/new.gd").write_text('load(QV + "Stairs_Stone.gltf")', encoding="utf-8")
        self.assertEqual(self.check(), 1)


if __name__ == "__main__":
    unittest.main()
