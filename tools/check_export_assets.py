#!/usr/bin/env python3
"""Проверяет исключения экспорта демо при добавлении залов и реплик.

Запуск перед сборкой: python3 tools/check_export_assets.py
Неизвестное выражение портрета, которого нет в исходниках, по-прежнему использует neutral.
"""
import configparser
import fnmatch
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ("rooms", "scenes", "scripts", "enemies", "player", "run", "weapons", "props", "ui", "data")
def load_aliases():
    # Таблица из UI — единый источник истины; не допускаем отставания от неё.
    text = (ROOT / "ui/portrait.gd").read_text(encoding="utf-8")
    match = re.search(r"^const ALIASES := (\{[^\n]+\})", text, re.M)
    if not match:
        raise ValueError("Не найдена таблица Portrait.ALIASES")
    return json.loads(match.group(1))


ALIASES = load_aliases()
# ChoicePick получает имя и эмоцию из call sites (run/reward_flow.gd).
UI_PAIRS = {("odin", "neutral"), ("loki", "smug")}
MODEL_PREFIXES = ("assets/quaternius/village/", "assets/quaternius/pirate/", "assets/quaternius/characters/outfits/")


def refs_from_json(value):
    if isinstance(value, dict):
        if isinstance(value.get("speaker"), str):
            yield value["speaker"], str(value.get("emotion", "neutral"))
        elif "text" in value:
            # DialogueBox по умолчанию показывает такие реплики как Одина.
            yield "odin", str(value.get("emotion", "neutral"))
        for choice in value.get("choices", []):
            if isinstance(choice, dict):
                # DialogueBox.choose подставляет выбранный ответ как реплику Тора.
                fallback = "angry" if choice.get("id") == "snap" else "embarrassed"
                yield "thor", str(choice.get("emotion", fallback))
        for child in value.values():
            yield from refs_from_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from refs_from_json(child)


def is_excluded(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def main():
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT / "export_presets.cfg", encoding="utf-8")
    issues = []
    portrait_pairs = set(UI_PAIRS)
    resource_refs = []
    script_text = []
    for top in RUNTIME:
        for f in (ROOT / top).rglob("*"):
            if not f.is_file() or f.suffix not in {".gd", ".tscn", ".tres", ".json"}:
                continue
            relative = str(f.relative_to(ROOT))
            text = f.read_text(encoding="utf-8")
            if f.suffix in {".tscn", ".tres"}:
                for path in re.findall(r'\[ext_resource[^\]]*\bpath="res://([^"\n]+)"', text):
                    resource_refs.append((relative, path))
            if f.suffix == ".gd":
                script_text.append((relative, text))
                # Прямые UI-вызовы set_speaker("имя", "эмоция", ...).
                portrait_pairs.update(re.findall(r'\.set_speaker\(\s*"([^"\n]+)"\s*,\s*"([^"\n]+)"', text))
            if f.suffix == ".json" and f.parent == ROOT / "data/dialogues":
                portrait_pairs.update(refs_from_json(json.loads(text)))
    for section in cfg.sections():
        if not re.fullmatch(r"preset\.\d+", section):
            continue
        patterns = [part.strip() for part in cfg[section].get("exclude_filter", "").strip('"').split(",") if part.strip()]
        for source, path in resource_refs:
            if is_excluded(path, patterns):
                issues.append(f"{section}: {source} ссылается на исключённый {path}")
        for sp, emotion in sorted(portrait_pairs):
            sp = ALIASES.get(sp, sp)
            # Как Portrait.texture_path: сначала нужная эмоция, затем neutral;
            # внутри каждой эмоции PNG имеет приоритет перед WebP. Исключать
            # neutral при отсутствии конкретной эмоции тоже нельзя.
            chosen = None
            for candidate in (emotion, "neutral"):
                for extension in ("png", "webp"):
                    path = f"sprites/portraits/{sp}_{candidate}.{extension}"
                    if (ROOT / path).exists():
                        chosen = path
                        break
                if chosen is not None:
                    break
            if chosen is not None and is_excluded(chosen, patterns):
                issues.append(f"{section}: портрет {sp}/{emotion} исключён: {chosen}")
        # Имена моделей в GDScript часто присоединяются к константной папке.
        for pattern in patterns:
            if not pattern.startswith(MODEL_PREFIXES):
                continue
            for file in ROOT.glob(pattern):
                for source, text in script_text:
                    if file.name in text:
                        issues.append(f"{section}: {source} упоминает исключённую модель {file.relative_to(ROOT)}")
    if issues:
        for issue in sorted(set(issues)):
            print("FAIL:", issue)
        return 1
    print(f"OK: {len(resource_refs)} статических ссылок, {len(portrait_pairs)} пар персонаж/эмоция; исключённых нужных ресурсов нет")
    return 0


if __name__ == "__main__":
    sys.exit(main())
