#!/usr/bin/env python3
"""Static, conservative check of art referenced by dialogue data.

This is not a reachability proof: exact deferred references are reviewed contracts
whose assumptions are checked again when the surrounding code/data changes.
"""
from __future__ import annotations

import ast
import fnmatch
import json
from pathlib import Path
import re

MANIFEST = "tools/deferred_dialogue_assets.json"


def _const_string(text, name):
    match = re.search(rf'^const {re.escape(name)}\s*:=\s*"([^"\n]+)"\s*$', text, re.M)
    if not match:
        raise ValueError(f"ScreenArt.{name}: ожидалась строковая константа")
    return match.group(1)


def _const_dict(text, name):
    match = re.search(rf'^const {re.escape(name)}\s*:=\s*(\{{.*?\}})', text, re.M | re.S)
    if not match:
        raise ValueError(f"ScreenArt.{name}: словарь не найден")
    try:
        value = ast.literal_eval(match.group(1))
    except (SyntaxError, ValueError) as exc:
        raise ValueError(f"ScreenArt.{name}: неподдерживаемый формат словаря") from exc
    if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
        raise ValueError(f"ScreenArt.{name}: ожидались только строковые ключи и значения")
    return value


def _relative_dir(value):
    if not value.startswith("res://") or not value.endswith("/"):
        raise ValueError(f"ожидалась папка res://: {value}")
    path = value[len("res://"):]
    if ".." in Path(path).parts or path.startswith("/"):
        raise ValueError(f"небезопасная папка: {value}")
    return path


def _active_worlds(root):
    """Current explicit map plus the runtime fallback; unknown forms fail closed."""
    manager = (root / "run/run_manager.gd").read_text(encoding="utf-8")
    match = re.search(r'^const MAP_PATH\s*:=\s*"res://([^"\n]+)"\s*$', manager, re.M)
    if not match:
        raise ValueError("Run.MAP_PATH: ожидался явный путь; миры требуют пересмотра")
    path = match.group(1)
    if ".." in Path(path).parts or path.startswith("/"):
        raise ValueError(f"Run.MAP_PATH: небезопасный путь {path}")
    world = re.search(r'^world_id\s*=\s*"([^"\n]+)"\s*$', (root / path).read_text(encoding="utf-8"), re.M)
    if not world:
        raise ValueError(f"Run.MAP_PATH: мир не указан в {path}")
    # A mutable map selected by other code needs an explicit new review.
    assignments = re.findall(r'^\s*map\s*=\s*(.+)$', manager, re.M)
    if assignments != ['load(MAP_PATH) as RunMap if ResourceLoader.exists(MAP_PATH) else null']:
        raise ValueError("Run.map: изменился способ выбора мира; требуется пересмотр")
    return {"midgard", world.group(1)}


def _walk_images(node, prefix=()):
    if isinstance(node, dict):
        for key, value in node.items():
            here = prefix + (str(key),)
            if key == "image":
                if not isinstance(value, str):
                    raise ValueError(f"{ '/'.join(here) }: image должен быть строкой")
                yield "/".join(here), value
            else:
                yield from _walk_images(value, here)
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from _walk_images(value, prefix + (str(i),))


def _function_at(text, offset):
    matches = list(re.finditer(r'^(?:static\s+)?func\s+(\w+)\s*\(', text[:offset], re.M))
    return matches[-1].group(1) if matches else ""


def _function_body(text, name):
    match = re.search(rf'^(?:static\s+)?func\s+{re.escape(name)}\s*\(', text, re.M)
    if not match:
        return ""
    next_func = re.search(r'^(?:static\s+)?func\s+\w+\s*\(', text[match.end():], re.M)
    return text[match.start():match.end() + next_func.start()] if next_func else text[match.start():]


def _call_arguments(text, open_paren):
    """Split arguments, preserving nested calls and quoted strings; fail on unsupported syntax."""
    depth, quote, escaped, start = 1, "", False, open_paren + 1
    arguments = []
    for i in range(start, len(text)):
        char = text[i]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                final = text[start:i].strip()
                if final or arguments:
                    arguments.append(final)
                return arguments
        elif char == "," and depth == 1:
            arguments.append(text[start:i].strip())
            start = i + 1
    raise ValueError("не удалось разобрать аргументы вызова")


def _producer_issues(scripts, guard):
    """Reject known producers or unknown calls that could invalidate a deferral.

    Dynamic code and modified save files are not exhaustively analyzable here.
    """
    issues = []
    kind, name = guard.get("kind"), guard.get("name")
    if kind not in {"event", "boss"} or not isinstance(name, str) or not name:
        return ["неизвестный guard отложенной ссылки"]
    for source, text in scripts:
        if kind == "event" and re.search(rf'(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])', text):
            issues.append(f"{source}: возможно появился источник события {name}")
        # External direct calls can bypass the conditions used by pick_scene.
        if source != "scripts/dialogue_manager.gd" and re.search(r'\.(?:play_scene|pick_scene)\s*\(', text):
            issues.append(f"{source}: прямой вызов сцены требует пересмотра отложенных ссылок")
        if kind == "event":
            for assignment in re.finditer(r'(?m)^\s*(?:Save\.)?data\.events\s*\[[^\]\n]+\]\s*=', text):
                func = _function_at(text, assignment.start())
                save_writer = source == "scripts/save_game.gd" and func == "bump_event"
                choice_writer = source == "scripts/dialogue_manager.gd" and func == "_on_choice_made"
                if choice_writer and (name.startswith("choice_") or 'var key := "choice_" + choice_id' not in _function_body(text, func)):
                    choice_writer = False
                if not save_writer and not choice_writer:
                    issues.append(f"{source}: прямая запись data.events требует пересмотра")
            if re.search(r'(?:Save\.)?data\s*\[\s*["\']events["\']\s*\]', text):
                issues.append(f"{source}: динамический доступ к data[events] требует пересмотра")
            for call in re.finditer(r'\bSave\.bump_event\s*\(', text):
                args = _call_arguments(text, call.end() - 1)
                arg = args[0] if len(args) == 1 else "<неизвестные аргументы>"
                if re.fullmatch(r'"[^"\n]*"', arg):
                    continue
                # A literal prefix + one variable cannot produce an event outside
                # that prefix (e.g. tutorial_step_* cannot unlock odin_finale_*).
                # Only this exact expression is recognised; function calls,
                # conditionals and a prefix overlapping the guard still fail closed.
                prefixed = re.fullmatch(r'"([A-Za-z0-9_]+)"\s*\+\s*[A-Za-z_][A-Za-z0-9_]*', arg)
                if prefixed and not name.startswith(prefixed.group(1)):
                    continue
                func = _function_at(text, call.start())
                known = source == "scripts/dialogue_manager.gd" and arg == "trigger" and func in {"run_trigger", "after_run"}
                if not known:
                    issues.append(f"{source}: динамический Save.bump_event({arg}) требует пересмотра")
                if known and func == "after_run" and 'var trigger := "victory" if won else "death"' not in _function_body(text, "after_run"):
                    issues.append(f"{source}: изменился источник события after_run")
            for call in re.finditer(r'\.run_trigger\s*\(', text):
                args = _call_arguments(text, call.end() - 1)
                arg = args[0] if args else "<нет аргумента>"
                if not re.fullmatch(r'"[^"\n]*"', arg):
                    issues.append(f"{source}: динамический run_trigger({arg}) требует пересмотра")
                elif arg.strip('"') in {name, guard.get("trigger")}:
                    issues.append(f"{source}: вызов {arg} требует пересмотра события {name}")
        else:
            for call in re.finditer(r'\.on_boss_intro\s*\(', text):
                args = _call_arguments(text, call.end() - 1)
                arg = args[0] if len(args) == 1 else ("" if not args else "<неизвестные аргументы>")
                if not arg:
                    manager = next((t for s, t in scripts if s == "scripts/dialogue_manager.gd"), "")
                    default = re.search(r'func on_boss_intro\(boss_id:\s*String\s*=\s*"([^"\n]+)"\)', manager)
                    if not default:
                        issues.append("Dialogue.on_boss_intro: неизвестный босс по умолчанию")
                    elif default.group(1) == name:
                        issues.append(f"{source}: по умолчанию доступен босс {name}")
                elif not re.fullmatch(r'"[^"\n]*"', arg):
                    issues.append(f"{source}: динамический on_boss_intro({arg}) требует пересмотра")
                elif arg.strip('"') == name:
                    issues.append(f"{source}: доступен босс {name}")
    return issues


class DialogueAssets:
    def __init__(self, root, scripts):
        self.root = root
        self.scripts = scripts
        self.issues = []
        self.edges = []
        self.sources = []
        self.scenes = {}
        self.valid_deferred = set()
        art = (root / "ui/screen_art.gd").read_text(encoding="utf-8")
        self.backdrops = _const_dict(art, "BACKDROPS")
        self.world_backdrops = _const_dict(art, "WORLD_BACKDROPS")
        self.background_dir = _relative_dir(_const_string(art, "BACKGROUNDS"))
        self.story_dir = _relative_dir(_const_string(art, "STORY"))
        self.worlds = _active_worlds(root)
        for source, text in scripts:
            if re.search(r'\bRun\.map(?:\s*=|\.world_id\s*=|\.set\s*\()', text):
                self.issues.append(f"{source}: изменяется Run.map; состав миров требует пересмотра")
        manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
        if not isinstance(manifest, dict) or manifest.get("version") != 1 or not isinstance(manifest.get("deferred"), list):
            raise ValueError(f"{MANIFEST}: неверная версия или список deferred")
        self.deferred = {}
        for entry in manifest["deferred"]:
            if not isinstance(entry, dict):
                raise ValueError(f"{MANIFEST}: запись должна быть объектом")
            key = (entry.get("source"), entry.get("scene"), entry.get("field"))
            if not all(isinstance(v, str) and v for v in key) or key in self.deferred:
                raise ValueError(f"{MANIFEST}: отсутствующий или повторный ключ {key}")
            if not isinstance(entry.get("reason"), str) or not entry["reason"].strip():
                raise ValueError(f"{MANIFEST}: для {key} требуется причина отсрочки")
            self.deferred[key] = entry
        self._gather()
        self._validate_deferrals()

    def _paths(self, kind, value):
        if value in {"", "none"}:
            return []
        if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
            raise ValueError(f"{kind}: неподдерживаемый идентификатор {value!r}")
        if kind == "image":
            return [self.story_dir + value + ".webp"]
        keys = [self.world_backdrops.get(w, "midgard_village") for w in sorted(self.worlds)] if value == "run" else [value]
        return sorted({self.background_dir + self.backdrops.get(key, key) + ".webp" for key in keys})

    def _add(self, source, scene, field, kind, value):
        if not isinstance(value, str):
            raise ValueError(f"{source}#{scene}/{field}: ожидалась строка")
        for path in self._paths(kind, value):
            self.edges.append((source, scene, field, value, path))

    def _gather(self):
        for path in sorted((self.root / "data/dialogues").glob("*.json")):
            source = path.relative_to(self.root).as_posix()
            self.sources.append(source)
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or not isinstance(data.get("scenes", []), list) or not isinstance(data.get("pools", {}), dict):
                raise ValueError(f"{source}: ожидались объект, список scenes и словарь pools")
            for scene in data.get("scenes", []):
                if not isinstance(scene, dict) or not isinstance(scene.get("id"), str) or not scene["id"]:
                    raise ValueError(f"{source}: сцена без строкового id")
                key = (source, scene["id"])
                if key in self.scenes:
                    raise ValueError(f"{source}: повторный id сцены {scene['id']}")
                self.scenes[key] = scene
                if "backdrop" in scene:
                    self._add(source, scene["id"], "backdrop", "backdrop", scene["backdrop"])
                for field, value in _walk_images(scene):
                    self._add(source, scene["id"], field, "image", value)
            for pool, lines in data.get("pools", {}).items():
                for field, value in _walk_images(lines):
                    self._add(source, "pool:" + str(pool), field, "image", value)
        # Dynamic calls inside the dialogue reader are covered by the JSON traversal above.
        known_dynamic = {
            ("ui/dialogue_box.gd", "story", "id"),
            ("ui/dialogue_box.gd", "backdrop_path", "backdrop"),
            ("scripts/dialogue_manager.gd", "story_path", "image"),
            ("scripts/dialogue_manager.gd", "story_path", "str(l.image)"),
            ("scripts/dialogue_manager.gd", "story_path", "str(sc.image)"),
            ("scripts/dialogue_manager.gd", "backdrop_path", "str(sc.backdrop)"),
        }
        for source, text in self.scripts:
            for call in re.finditer(r'\bScreenArt\.(backdrop|backdrop_path|story|story_path)\s*\(', text):
                args = _call_arguments(text, call.end() - 1)
                arg = args[0] if len(args) == 1 else "<неизвестные аргументы>"
                kind = "backdrop" if call.group(1).startswith("backdrop") else "image"
                if re.fullmatch(r'"[^"\n]*"', arg):
                    self._add(source, "code", call.group(1), kind, arg[1:-1])
                elif (source, call.group(1), arg) not in known_dynamic:
                    self.issues.append(f"{source}: динамический ScreenArt.{call.group(1)}({arg}) требует пересмотра")
        self._add("runtime", "default", "backdrop", "backdrop", "run")

    def _validate_deferrals(self):
        edge_map = {}
        for source, scene, field, value, path in self.edges:
            edge_map.setdefault((source, scene, field), []).append((value, path))
        for key, entry in self.deferred.items():
            scene = self.scenes.get((key[0], key[1]))
            edge = edge_map.get(key)
            guard = entry.get("guard")
            if not isinstance(scene, dict) or edge != [(entry.get("value"), entry.get("path"))]:
                self.issues.append(f"{key}: отложенная ссылка отсутствует или изменилась")
                continue
            if scene.get("trigger") != entry.get("trigger") or scene.get("conditions", []) != entry.get("conditions"):
                self.issues.append(f"{key}: условия/событие изменились; требуется пересмотр")
                continue
            if not isinstance(guard, dict) or guard.get("trigger") != scene.get("trigger"):
                self.issues.append(f"{key}: отсутствует проверяемый guard")
                continue
            expected = f"event:{guard.get('name')}" if guard.get("kind") == "event" else f"boss == {guard.get('name')}"
            if expected not in scene.get("conditions", []):
                self.issues.append(f"{key}: guard {expected!r} не найден среди условий")
                continue
            producer_issues = _producer_issues(self.scripts, guard)
            self.issues.extend(f"{key}: {message}" for message in producer_issues)
            if not producer_issues:
                self.valid_deferred.add(key)

    def audit_preset(self, section, patterns, include_patterns, export_filter):
        issues, deferred = [], []
        if export_filter != "all_resources":
            issues.append(f"{section}: export_filter={export_filter!r} не поддерживается аудитом диалогов")
        for source in self.sources:
            if any(fnmatch.fnmatchcase(source, p) for p in patterns):
                issues.append(f"{section}: файл диалогов исключён: {source}")
            elif not any(fnmatch.fnmatchcase(source, p) for p in include_patterns):
                issues.append(f"{section}: JSON диалогов не включён явно: {source}")
        for source, scene, field, value, path in self.edges:
            key = (source, scene, field)
            entry = self.deferred.get(key) if key in self.valid_deferred else None
            if entry and (value, path) != (entry.get("value"), entry.get("path")):
                entry = None
            if not (self.root / path).is_file():
                issues.append(f"{section}: {source}#{scene}/{field}: файл отсутствует: {path}")
                continue
            excluded = any(fnmatch.fnmatchcase(path, p) for p in patterns)
            if entry:
                status = "исключён из экспорта" if excluded else "включён в экспорт"
                deferred.append(f"{section}: {source}#{scene}/{field}: {path} — отложено ({status}); {entry.get('reason', '')}")
            elif excluded:
                issues.append(f"{section}: {source}#{scene}/{field}: активная ссылка исключена: {path}")
        return issues, deferred
