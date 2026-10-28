#!/usr/bin/env python3
"""Проверки защиты исключённых заготовок декора демо."""
import configparser
import contextlib
import fnmatch
import io
from pathlib import Path
import tempfile
import unittest

import check_export_assets as audit
from check_export_decor import GUARDED_ART, check_world_art_exclusions


class ExportDecorTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for n, resource in enumerate(GUARDED_ART):
            path = self.root / resource
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
            Path(str(path) + ".import").write_text(f'uid="uid://fixture{n}"\n', encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, patterns, *sources):
        return check_world_art_exclusions(self.root, patterns, sources)

    def test_unreferenced_existing_excluded_sources_are_allowed(self):
        self.assertEqual(self.check(GUARDED_ART, ("rooms/room.tscn", 'art = "banner_axes"')), [])

    def test_direct_path_in_scene_is_rejected_for_each_excluded_resource(self):
        for resource in GUARDED_ART:
            with self.subTest(resource=resource):
                text = f'[ext_resource type="Texture2D" path="res://{resource}" id="1"]'
                issues = self.check([resource], ("rooms/new.tscn", text))
                self.assertTrue(any(resource in issue and "rooms/new.tscn" in issue for issue in issues), issues)

    def test_wall_decor_art_key_is_rejected(self):
        text = '[node name="Picture" type="Node3D"]\nart = "shield_paints"\n'
        issues = self.check(GUARDED_ART, ("rooms/new.tscn", text))
        self.assertTrue(any("shield_paints.webp" in issue for issue in issues), issues)

    def test_worldart_list_key_is_rejected(self):
        text = 'const BANNERS := ["banner_axes", "banner_emblems"]\n'
        issues = self.check(GUARDED_ART, ("scripts/world_art.gd", text))
        self.assertTrue(any("banner_emblems.webp" in issue for issue in issues), issues)

    def test_split_path_key_in_script_is_rejected(self):
        text = 'var texture = load(MIDGARD_TEXTURES + "thatch.webp")\n'
        issues = self.check(GUARDED_ART, ("rooms/new.gd", text))
        self.assertTrue(any("thatch.webp" in issue for issue in issues), issues)

    def test_uid_reference_is_rejected(self):
        issues = self.check(GUARDED_ART, ("rooms/new.tscn", 'uid="uid://fixture0"'))
        self.assertTrue(any(GUARDED_ART[0] in issue for issue in issues), issues)

    def test_gltf_dependency_is_also_scanned(self):
        gltf = self.root / "assets/example/model.gltf"
        gltf.parent.mkdir(parents=True)
        gltf.write_text('{"images": [{"uri": "thatch.webp"}]}', encoding="utf-8")
        issues = self.check(GUARDED_ART)
        self.assertTrue(any("model.gltf" in issue and "thatch.webp" in issue for issue in issues), issues)

    def test_wildcard_exclusion_cannot_hide_use(self):
        issues = self.check(["assets/decor/*.webp"], ("rooms/new.tscn", 'art = "banner_emblems"'))
        self.assertTrue(any("banner_emblems.webp" in issue for issue in issues), issues)

    def test_resource_that_is_not_excluded_can_be_used(self):
        issues = self.check([], ("rooms/new.tscn", 'art = "banner_emblems"'))
        self.assertEqual(issues, [])

    def test_missing_original_or_uid_fails_closed(self):
        first = self.root / GUARDED_ART[0]
        first.unlink()
        issues = self.check([GUARDED_ART[0]])
        self.assertTrue(any("исходник" in issue for issue in issues), issues)
        first.touch()
        Path(str(first) + ".import").write_text("[remap]\n", encoding="utf-8")
        issues = self.check([GUARDED_ART[0]])
        self.assertTrue(any("UID" in issue for issue in issues), issues)

    def test_both_real_export_presets_exclude_exact_resources(self):
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(Path(__file__).resolve().parent.parent / "export_presets.cfg", encoding="utf-8")
        for section in ("preset.0", "preset.1"):
            patterns = [x.strip() for x in cfg[section]["exclude_filter"].strip('"').split(",")]
            for path in GUARDED_ART:
                with self.subTest(section=section, path=path):
                    self.assertTrue(any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns))

    def test_main_audit_rejects_dynamic_wall_art_key(self):
        # Минимальный изолированный проект; ресурсы и фильтры существуют, поэтому
        # именно новая динамическая ссылка должна перевести аудит в FAIL.
        for top in audit.RUNTIME:
            (self.root / top).mkdir(parents=True, exist_ok=True)
        (self.root / "data/dialogues").mkdir(exist_ok=True)
        (self.root / "rooms/new.tscn").write_text('art = "banner_emblems"\n', encoding="utf-8")
        (self.root / "export_presets.cfg").write_text(
            '[preset.0]\nexport_filter="all_resources"\ninclude_filter="data/dialogues/*.json"\n'
            'exclude_filter="' + ", ".join(GUARDED_ART) + '"\n', encoding="utf-8")
        # Дополнительная инфраструктура для возможной интеграции общего аудита диалогов.
        (self.root / "ui/screen_art.gd").write_text(
            'const BACKGROUNDS := "res://sprites/backgrounds/"\nconst STORY := "res://sprites/story/"\n'
            'const BACKDROPS := {}\nconst WORLD_BACKDROPS := {"midgard": "midgard_village"}\n', encoding="utf-8")
        (self.root / "run/maps").mkdir(exist_ok=True)
        (self.root / "run/maps/midgard.tres").write_text('world_id = "midgard"\n', encoding="utf-8")
        (self.root / "run/run_manager.gd").write_text(
            'const MAP_PATH := "res://run/maps/midgard.tres"\nfunc start():\n'
            '\tmap = load(MAP_PATH) as RunMap if ResourceLoader.exists(MAP_PATH) else null\n', encoding="utf-8")
        (self.root / "sprites/backgrounds").mkdir(parents=True, exist_ok=True)
        (self.root / "sprites/backgrounds/midgard_village.webp").touch()
        (self.root / "tools").mkdir(exist_ok=True)
        (self.root / "tools/deferred_dialogue_assets.json").write_text('{"version": 1, "deferred": []}', encoding="utf-8")
        old_root = audit.ROOT
        audit.ROOT = self.root
        stream = io.StringIO()
        try:
            with contextlib.redirect_stdout(stream):
                result = audit.main()
        finally:
            audit.ROOT = old_root
        self.assertEqual(result, 1, stream.getvalue())
        self.assertIn("rooms/new.tscn", stream.getvalue())
        self.assertIn("banner_emblems.webp", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
