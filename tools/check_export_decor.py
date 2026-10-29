#!/usr/bin/env python3
"""Защита неиспользуемых заготовок, исключённых из демо-экспорта.

Проверяет прямые ссылки, UID и строковые ключи динамического WorldArt/WallDecor.
Это консервативный статический поиск: произвольно собранные строки он не доказывает.
"""
import fnmatch
from pathlib import Path
import re

# Исходники сохраняются в репозитории; исключаются только импортированные копии в демо.
GUARDED_ART = (
    "assets/decor/banner_emblems.webp",
    "assets/decor/shield_paints.webp",
)


def _import_uid(root, resource):
    path = root / (resource + ".import")
    if not path.is_file():
        raise ValueError(f"нет файла импорта {path.relative_to(root)}")
    match = re.search(r'^uid="(uid://[^"\n]+)"\s*$', path.read_text(encoding="utf-8"), re.M)
    if not match:
        raise ValueError(f"в файле импорта нет UID: {path.relative_to(root)}")
    return match.group(1)


def check_world_art_exclusions(root, patterns, sources):
    """Вернуть ошибки для исключённых заготовок, которые начали использоваться.

    sources — пары (относительный путь, содержимое) для исполняемых данных демо;
    glTF в assets проверяются дополнительно, поскольку они могут ссылаться на текстуры.
    """
    guarded = [p for p in GUARDED_ART if any(fnmatch.fnmatchcase(p, pattern) for pattern in patterns)]
    if not guarded:
        return []
    issues = []
    all_sources = list(sources)
    for file in (root / "assets").rglob("*.gltf"):
        try:
            all_sources.append((file.relative_to(root).as_posix(), file.read_text(encoding="utf-8")))
        except (OSError, UnicodeError) as exc:
            issues.append(f"не удалось проверить ссылку в {file.relative_to(root)}: {exc}")
    for resource in guarded:
        if not (root / resource).is_file():
            issues.append(f"исходник исключённой заготовки отсутствует: {resource}")
            continue
        try:
            uid = _import_uid(root, resource)
        except (OSError, UnicodeError, ValueError) as exc:
            issues.append(str(exc))
            continue
        # Например, art="banner_emblems" или BANNERS=["banner_emblems"].
        # Совпадения в строках данных и комментариях считаются поводом для пересмотра.
        key = Path(resource).stem
        key_re = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(key) + r'(?![A-Za-z0-9_])')
        for source, text in all_sources:
            if resource in text or uid in text or key_re.search(text):
                issues.append(f"{source}: использует исключённую заготовку {resource} (путь, UID или ключ {key})")
    return sorted(set(issues))
