#!/usr/bin/env python3
"""Проверки аудита исключений перед упаковкой плейтеста."""
import contextlib
import configparser
import fnmatch
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
        (self.root / "sprites/backgrounds").mkdir(parents=True)
        (self.root / "sprites/story").mkdir(parents=True)
        (self.root / "run/maps").mkdir(parents=True)
        (self.root / "tools").mkdir()
        (self.root / "assets/quaternius/village").mkdir(parents=True)
        (self.root / "sprites/portraits/hugin_shocked.webp").touch()
        (self.root / "sprites/portraits/freya_angry.webp").touch()
        (self.root / "sprites/portraits/draugr_neutral.webp").touch()
        (self.root / "assets/quaternius/village/Stairs_Stone.gltf").touch()
        (self.root / "sprites/backgrounds/midgard_village.webp").touch()
        (self.root / "ui/screen_art.gd").write_text(
            'const BACKGROUNDS := "res://sprites/backgrounds/"\n'
            'const STORY := "res://sprites/story/"\n'
            'const BACKDROPS := {"shop": "dwarf_shop", "yggdrasil": "yggdrasil_top", '
            '"helheim": "hel_throne", "couch": "couch_room"}\n'
            'const WORLD_BACKDROPS := {"midgard": "midgard_village", "asgard": "yggdrasil_top"}\n',
            encoding="utf-8",
        )
        (self.root / "run/run_manager.gd").write_text(
            'const MAP_PATH := "res://run/maps/midgard.tres"\n'
            'func start():\n'
            '\tmap = load(MAP_PATH) as RunMap if ResourceLoader.exists(MAP_PATH) else null\n',
            encoding="utf-8",
        )
        (self.root / "run/maps/midgard.tres").write_text('world_id = "midgard"\n', encoding="utf-8")
        (self.root / "scripts/dialogue_manager.gd").write_text(
            'func on_boss_intro(boss_id: String = "jarl") -> bool:\n\treturn true\n', encoding="utf-8"
        )
        self.set_deferred([])
        (self.root / "export_presets.cfg").write_text(
            '[preset.0]\nexport_filter="all_resources"\ninclude_filter="data/dialogues/*.json"\n'
            'exclude_filter="sprites/portraits/hugin_shocked.webp, '
            'sprites/portraits/freya_angry.webp, sprites/portraits/draugr_*.webp, assets/quaternius/village/Stair*.gltf"\n',
            encoding="utf-8",
        )

    def tearDown(self):
        audit.ROOT = self.old_root
        self.tmp.cleanup()

    def check(self):
        return self.check_with_output()[0]

    def check_with_output(self):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            code = audit.main()
        return code, stream.getvalue()

    def set_deferred(self, records):
        (self.root / "tools/deferred_dialogue_assets.json").write_text(
            json.dumps({"version": 1, "deferred": records}), encoding="utf-8"
        )

    def put_dialogue(self, filename, scenes):
        (self.root / "data/dialogues" / filename).write_text(
            json.dumps({"draft": True, "scenes": scenes}), encoding="utf-8"
        )

    def exclude(self, path):
        cfg = self.root / "export_presets.cfg"
        text = cfg.read_text(encoding="utf-8")
        cfg.write_text(text.replace('exclude_filter="', 'exclude_filter="' + path + ', ', 1), encoding="utf-8")

    def deferred_finale(self):
        scene = {"id": "finale_a", "trigger": "meet", "conditions": ["event:odin_finale_unlocked"], "backdrop": "yggdrasil"}
        entry = {
            "source": "data/dialogues/finale.json", "scene": "finale_a", "field": "backdrop",
            "value": "yggdrasil", "path": "sprites/backgrounds/yggdrasil_top.webp", "trigger": "meet",
            "conditions": ["event:odin_finale_unlocked"],
            "guard": {"kind": "event", "name": "odin_finale_unlocked", "trigger": "meet"},
            "reason": "future finale",
        }
        self.put_dialogue("finale.json", [scene])
        self.set_deferred([entry])
        (self.root / entry["path"]).touch()
        self.exclude(entry["path"])
        return scene, entry

    def deferred_finale_image(self):
        scene, backdrop = self.deferred_finale()
        scene["image"] = "finale"
        self.put_dialogue("finale.json", [scene])
        image = {
            "source": "data/dialogues/finale.json", "scene": "finale_a", "field": "image",
            "value": "finale", "path": "sprites/story/finale.webp", "trigger": "meet",
            "conditions": ["event:odin_finale_unlocked"],
            "guard": {"kind": "event", "name": "odin_finale_unlocked", "trigger": "meet"},
            "reason": "future finale image",
        }
        self.set_deferred([backdrop, image])
        (self.root / image["path"]).touch()
        self.exclude(image["path"])
        return scene, image

    def test_unused_resources_are_allowed(self):
        self.assertEqual(self.check(), 0)

    def test_new_dialogue_uses_alias(self):
        line = {"speaker": "munin", "emotion": "shocked", "text": "Кар!"}
        (self.root / "data/dialogues/new.json").write_text(json.dumps({"lines": [line]}), encoding="utf-8")
        self.assertEqual(self.check(), 1)

    def test_direct_ui_call(self):
        (self.root / "ui/example.gd").write_text('p.set_speaker("freya", "angry", {})', encoding="utf-8")
        self.assertEqual(self.check(), 1)

    def test_new_dialogue_needs_excluded_neutral_fallback(self):
        line = {"speaker": "draugr", "emotion": "embarrassed", "text": "..."}
        (self.root / "data/dialogues/new.json").write_text(json.dumps({"lines": [line]}), encoding="utf-8")
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

    def test_excluded_active_backdrop_uses_screenart_alias_even_in_draft_file(self):
        path = "sprites/backgrounds/dwarf_shop.webp"
        (self.root / path).touch()
        self.exclude(path)
        self.put_dialogue("shop.json", [{"id": "active", "backdrop": "shop"}])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("active", output)
        self.assertIn(path, output)
        self.assertIn("активная ссылка исключена", output)

    def test_missing_active_backdrop_does_not_silently_fallback(self):
        self.put_dialogue("shop.json", [{"id": "active", "backdrop": "shop"}])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("файл отсутствует: sprites/backgrounds/dwarf_shop.webp", output)

    def test_nested_choice_story_image_is_checked(self):
        path = "sprites/story/first_death.webp"
        (self.root / path).touch()
        self.exclude(path)
        self.put_dialogue("choice.json", [{"id": "active", "lines": [{
            "choices": [{"id": "yes", "lines": [{"image": "first_death"}]}]
        }]}])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("lines/0/choices/0/lines/0/image", output)
        self.assertIn(path, output)

    def test_none_image_and_backdrop_do_not_require_file(self):
        self.put_dialogue("none.json", [{"id": "active", "backdrop": "none", "lines": [{"image": "none"}]}])
        self.assertEqual(self.check(), 0)

    def test_run_backdrop_checks_current_world_and_not_future_world_aliases(self):
        self.put_dialogue("run.json", [{"id": "active", "backdrop": "run"}])
        self.exclude("sprites/backgrounds/yggdrasil_top.webp")
        self.assertEqual(self.check(), 0)  # asgard is in the map but is not the selected RunMap
        self.exclude("sprites/backgrounds/midgard_village.webp")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("midgard_village.webp", output)

    def test_current_world_selection_must_be_explicit(self):
        (self.root / "run/run_manager.gd").write_text('const MAP_PATH := choose_world()\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("MAP_PATH", output)

    def test_static_code_backdrop_uses_same_alias_rules(self):
        path = "sprites/backgrounds/couch_room.webp"
        (self.root / path).touch()
        self.exclude(path)
        (self.root / "ui/other.gd").write_text('var art = ScreenArt.backdrop("couch")\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("ui/other.gd#code/backdrop", output)
        self.assertIn(path, output)

    def test_unknown_dynamic_screenart_call_requires_review(self):
        (self.root / "ui/other.gd").write_text('ScreenArt.backdrop(str(next_background))\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("динамический ScreenArt.backdrop", output)

    def test_deferred_reference_is_explicit_not_reported_as_active(self):
        self.deferred_finale()
        code, output = self.check_with_output()
        self.assertEqual(code, 0)
        self.assertIn("DEFERRED:", output)
        self.assertIn("finale_a/backdrop", output)
        self.assertIn("исключён из экспорта", output)

    def test_finale_image_is_separately_deferred_by_same_event(self):
        self.deferred_finale_image()
        code, output = self.check_with_output()
        self.assertEqual(code, 0)
        self.assertIn("DEFERRED:", output)
        self.assertIn("finale_a/image", output)
        self.assertIn("sprites/story/finale.webp", output)
        self.assertIn("finale_a/backdrop", output)

    def test_active_scene_cannot_reuse_deferred_finale_image(self):
        scene, image = self.deferred_finale_image()
        active = {"id": "active", "lines": [{"image": "finale"}]}
        self.put_dialogue("finale.json", [scene, active])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("#active/lines/0/image", output)
        self.assertIn(image["path"], output)
        self.assertIn("активная ссылка исключена", output)

    def test_active_pool_cannot_reuse_deferred_finale_image(self):
        scene, image = self.deferred_finale_image()
        data = {"scenes": [scene], "pools": {"active": [{"lines": [{"image": "finale"}]}]}}
        (self.root / "data/dialogues/finale.json").write_text(json.dumps(data), encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("pool:active", output)
        self.assertIn(image["path"], output)

    def test_changed_finale_guard_invalidates_deferred_image(self):
        scene, image = self.deferred_finale_image()
        scene["conditions"] = []
        self.put_dialogue("finale.json", [scene])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("условия/событие изменились", output)
        self.assertIn(image["path"], output)
        self.assertIn("активная ссылка исключена", output)

    def test_added_finale_event_source_invalidates_deferred_image(self):
        _, image = self.deferred_finale_image()
        (self.root / "scripts/new.gd").write_text('Save.bump_event("odin_finale_unlocked")\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("источник события", output)
        self.assertIn(image["path"], output)

    def test_changed_finale_image_cannot_reuse_old_deferral(self):
        scene, _ = self.deferred_finale_image()
        scene["image"] = "other"
        (self.root / "sprites/story/other.webp").touch()
        self.put_dialogue("finale.json", [scene])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("отложенная ссылка отсутствует или изменилась", output)

    def test_candidate_export_excludes_only_exact_finale_image(self):
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(Path(__file__).resolve().parent.parent / "export_presets.cfg", encoding="utf-8")
        for section in ("preset.0", "preset.1"):
            patterns = [x.strip() for x in cfg[section]["exclude_filter"].strip('"').split(",")]
            with self.subTest(section=section):
                self.assertTrue(any(fnmatch.fnmatchcase("sprites/story/finale.webp", p) for p in patterns))
                self.assertFalse(any(fnmatch.fnmatchcase("sprites/story/first_death.webp", p) for p in patterns))

    def test_changed_guard_or_trigger_rejects_stale_deferral(self):
        scene, _ = self.deferred_finale()
        scene["conditions"] = []
        self.put_dialogue("finale.json", [scene])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("условия/событие изменились", output)
        self.assertIn("активная ссылка исключена", output)

    def test_deferred_source_file_must_still_exist(self):
        _, entry = self.deferred_finale()
        (self.root / entry["path"]).unlink()
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("файл отсутствует", output)
        self.assertIn(entry["path"], output)

    def test_changed_alias_cannot_reuse_old_deferred_record(self):
        self.deferred_finale()
        screen = self.root / "ui/screen_art.gd"
        screen.write_text(screen.read_text(encoding="utf-8").replace('"yggdrasil": "yggdrasil_top"',
                                                                      '"yggdrasil": "new_top"'), encoding="utf-8")
        (self.root / "sprites/backgrounds/new_top.webp").touch()
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("отложенная ссылка отсутствует или изменилась", output)

    def test_deferred_reference_does_not_hide_active_use_of_same_file(self):
        scene, _ = self.deferred_finale()
        self.put_dialogue("finale.json", [scene, {"id": "active", "backdrop": "yggdrasil"}])
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("#active/backdrop", output)
        self.assertIn("активная ссылка исключена", output)

    def test_new_event_producer_requires_review(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.bump_event("odin_finale_unlocked")\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("возможно появился источник события", output)

    def test_nested_dynamic_event_producer_requires_review(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.bump_event(str(next_event))\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("динамический Save.bump_event", output)

    def test_disjoint_literal_event_prefix_cannot_unlock_deferred_scene(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.bump_event("tutorial_step_" + id)\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 0, output)

    def test_matching_literal_event_prefix_still_requires_review(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.bump_event("odin_" + id)\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("динамический Save.bump_event", output)

    def test_conditional_prefixed_event_still_requires_review(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.bump_event("tutorial_step_" + id if ok else other)\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("динамический Save.bump_event", output)

    def test_direct_write_to_event_dictionary_requires_review(self):
        self.deferred_finale()
        (self.root / "scripts/new.gd").write_text('Save.data.events[computed_event] = 1\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("прямая запись data.events", output)

    def test_new_or_unknown_meet_trigger_requires_review(self):
        self.deferred_finale()
        script = self.root / "scripts/new.gd"
        script.write_text('Dialogue.run_trigger("meet")\n', encoding="utf-8")
        self.assertEqual(self.check(), 1)
        script.write_text('Dialogue.run_trigger(next_trigger)\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("динамический run_trigger", output)

    def test_new_deferred_boss_producer_requires_review(self):
        scene = {"id": "hel_intro", "trigger": "boss_intro", "conditions": ["boss == hel", "first_time"], "backdrop": "helheim"}
        entry = {"source": "data/dialogues/hel.json", "scene": "hel_intro", "field": "backdrop", "value": "helheim",
                 "path": "sprites/backgrounds/hel_throne.webp", "trigger": "boss_intro", "conditions": scene["conditions"],
                 "guard": {"kind": "boss", "name": "hel", "trigger": "boss_intro"}, "reason": "future boss"}
        self.put_dialogue("hel.json", [scene])
        self.set_deferred([entry])
        (self.root / entry["path"]).touch()
        self.exclude(entry["path"])
        self.assertEqual(self.check(), 0)
        (self.root / "scenes/new.gd").write_text('Dialogue.on_boss_intro("hel")\n', encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("доступен босс hel", output)

    def test_excluded_dialogue_json_is_not_hidden_by_deferred_art(self):
        self.deferred_finale()
        self.exclude("data/dialogues/finale.json")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("файл диалогов исключён", output)

    def test_dialogue_json_must_be_included_explicitly(self):
        self.put_dialogue("active.json", [{"id": "active", "backdrop": "none"}])
        cfg = self.root / "export_presets.cfg"
        cfg.write_text(cfg.read_text(encoding="utf-8").replace('include_filter="data/dialogues/*.json"',
                                                              'include_filter=""'), encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("JSON диалогов не включён явно", output)

    def test_unsupported_export_filter_fails_closed(self):
        cfg = self.root / "export_presets.cfg"
        cfg.write_text(cfg.read_text(encoding="utf-8").replace('export_filter="all_resources"',
                                                              'export_filter="selected_resources"'), encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("не поддерживается", output)

    def test_missing_export_preset_cannot_report_ok(self):
        (self.root / "export_presets.cfg").write_text("", encoding="utf-8")
        code, output = self.check_with_output()
        self.assertEqual(code, 1)
        self.assertIn("не найдено ни одного preset", output)


if __name__ == "__main__":
    unittest.main()
