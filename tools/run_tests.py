#!/usr/bin/env python3
"""Запуск headless-тестов: по изменениям, выбранные или все.

  python3 tools/run_tests.py --changed            # по git diff от origin/main + незакоммиченное
  python3 tools/run_tests.py --test catch_test    # один (можно повторять --test)
  python3 tools/run_tests.py --all                # все tests/*_test.tscn
  --jobs N (1–8, по умолчанию 4), --base <ветка>, --out <новая папка>, --dry-run (только список)

Выбор по изменениям — карта tests/test_map.json (её формат описан в поле _comment).
Сам прогон — tools/run_test_suite.py: импорт, отдельная папка данных на тест,
лимит логов, классификация ошибок. Вывод — строки PASS/FAIL, TOTAL и код выхода.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
sys.path.insert(0, str(TOOLS))

MAP_PATH = PROJECT / "tests" / "test_map.json"
## Класс, который упоминают больше тестов, считается общим: его тесты берутся только из карты
AUTO_REF_LIMIT = 8


def all_tests() -> list[str]:
    return sorted(p.stem for p in (PROJECT / "tests").glob("*_test.tscn"))


def _git(*args: str) -> list[str]:
    out = subprocess.run(["git", *args], cwd=PROJECT, check=True, capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def changed_files(base: str) -> list[str]:
    merge_base = _git("merge-base", base, "HEAD")[0]
    files = set(_git("diff", "--name-only", merge_base))  # коммиты ветки + рабочая копия
    files.update(_git("ls-files", "--others", "--exclude-standard"))
    return sorted(files)


def _matches(path: str, pattern: str) -> bool:
    if any(ch in pattern for ch in "*?["):
        return fnmatch.fnmatch(path, pattern)
    return path.startswith(pattern)


def _normalize(path: str) -> str:
    # x.gd.uid, x.png.import меняются вместе с самим файлом
    for suffix in (".uid", ".import"):
        if path.endswith(suffix):
            return path[: -len(suffix)]
    return path


def _test_sources() -> dict[str, str]:
    sources = {}
    for name in all_tests():
        gd = PROJECT / "tests" / (name + ".gd")
        sources[name] = gd.read_text(encoding="utf-8", errors="replace") if gd.exists() else ""
    return sources


def _auto_refs(path: str, sources: dict[str, str]) -> tuple[list[str], str]:
    """Тесты, чей .gd упоминает res://-путь файла или его class_name (если класс не общий)."""
    hits = {n for n, src in sources.items() if "res://" + path in src}
    note = ""
    file = PROJECT / path
    if path.endswith(".gd") and file.exists():
        m = re.search(r"^class_name\s+(\w+)", file.read_text(encoding="utf-8", errors="replace"), re.M)
        if m:
            word = re.compile(r"\b" + re.escape(m.group(1)) + r"\b")
            users = {n for n, src in sources.items() if word.search(src)}
            if len(users) <= AUTO_REF_LIMIT:
                hits |= users
            else:
                note = f"класс {m.group(1)} общий ({len(users)} тестов) — только карта"
    return sorted(hits), note


def select(files: list[str], test_map: dict, verbose: bool) -> list[str]:
    known = set(all_tests())
    sources = _test_sources()
    chosen: set[str] = set()
    for raw in files:
        path = _normalize(raw)
        reason: list[str] = []
        if any(_matches(path, p) for p in test_map.get("all", [])):
            if verbose:
                print(f"  {raw}: все тесты")
            return sorted(known)
        if any(_matches(path, p) for p in test_map.get("ignore", [])):
            if verbose:
                print(f"  {raw}: пропуск")
            continue
        picked: set[str] = set()
        matched = False
        for rule in test_map["rules"]:
            if any(_matches(path, p) for p in rule["paths"]):
                matched = True
                picked.update(rule["tests"])
        stem = Path(path).name.split(".")[0]
        if path.startswith("tests/") and stem in known:
            picked.add(stem)
            matched = True
            reason.append("сам тест")
        refs, note = _auto_refs(path, sources)
        if refs:
            picked.update(refs)
            reason.append("упоминают: " + ", ".join(refs))
        if note:
            reason.append(note)
        if not matched:
            picked.update(test_map.get("default", []))
            reason.append("нет правила — default")
        chosen |= picked
        if verbose:
            extra = f" ({'; '.join(reason)})" if reason else ""
            print(f"  {raw}: {', '.join(sorted(picked)) or '—'}{extra}")
    return sorted(chosen & known)


def check_map(test_map: dict) -> list[str]:
    """Имена в карте, которых нет среди tests/*_test.tscn."""
    known = set(all_tests())
    names = set(test_map.get("default", []))
    for rule in test_map["rules"]:
        names.update(rule["tests"])
    return sorted(names - known)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--changed", action="store_true", help="тесты по изменённым файлам")
    mode.add_argument("--all", action="store_true", help="все тесты")
    mode.add_argument("--test", action="append", metavar="ИМЯ", help="один тест (можно несколько раз)")
    parser.add_argument("--jobs", type=int, default=4, help="параллельных тестов, 1–8 (по умолчанию 4)")
    parser.add_argument("--base", default="origin/main", help="с чем сравнивать для --changed")
    parser.add_argument("--out", help="новая папка результатов (по умолчанию /tmp/thor-tests-<время>)")
    parser.add_argument("--dry-run", action="store_true", help="только показать, какие тесты пойдут")
    args = parser.parse_args(argv)
    if not 1 <= args.jobs <= 8:
        print("--jobs: от 1 до 8", file=sys.stderr)
        return 2

    test_map = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    unknown = check_map(test_map)
    if unknown:
        print("В tests/test_map.json нет таких тестов: " + ", ".join(unknown), file=sys.stderr)
        return 2

    if args.all:
        tests = all_tests()
    elif args.test:
        tests = sorted({t.removesuffix(".tscn") for t in args.test})
        missing = set(tests) - set(all_tests())
        if missing:
            print("Нет тестов: " + ", ".join(sorted(missing)), file=sys.stderr)
            return 2
    else:
        files = changed_files(args.base)
        print(f"Изменено файлов: {len(files)} (от {args.base})")
        tests = select(files, test_map, verbose=True)

    print(f"Тестов: {len(tests)} — {' '.join(tests) if tests else 'нечего запускать'}", flush=True)
    if args.dry_run or not tests:
        return 0

    out = args.out or f"/tmp/thor-tests-{time.strftime('%Y%m%d-%H%M%S')}"
    os.environ["THOR_TEST_JOBS"] = str(args.jobs)
    import run_test_suite  # noqa: E402

    started = time.monotonic()
    code = run_test_suite.main([str(PROJECT), out], selected=tuple(tests))
    print(f"Время: {time.monotonic() - started:.0f} с; логи — {out}")
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
