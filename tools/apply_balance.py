#!/usr/bin/env python3
"""Перенос баланса из debug-панели (П8, DEBUG_PANEL.md) в код.

    python3 tools/apply_balance.py balance.json           # таблица «поле — было — стало — файл:строка»
    python3 tools/apply_balance.py balance.json --check   # то же; код выхода 1, если есть неизвестные ключи
    python3 tools/apply_balance.py balance.json --write   # поменять значения @export по умолчанию и строки TUNING.md

Ключ файла — «источник.поле». Источники с файлом: player, mjolnir, camera, room (по умолчанию в rooms/room.gd —
сцены залов могут перекрывать), style (player/style_tuning.tres, поле с индексом «rank_points[2]» или «points/slam»),
economy (run/economy.tres). Глобальные множители (enemy_mult, econ_mult, waves_mult) файла не имеют — печатаются
отдельно: переносить ли их в EnemyDef/константы, решает владелец.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GD_SOURCES = {
    "player": "player/player.gd",
    "mjolnir": "weapons/mjolnir_hand.gd",
    "camera": "player/camera_fx.gd",
    "room": "rooms/room.gd",
}
TRES_SOURCES = {
    "style": ("player/style_tuning.tres", "player/style_tuning.gd"),
    "economy": ("run/economy.tres", "run/economy.gd"),
}
GLOBAL_SOURCES = {"enemy_mult", "econ_mult", "waves_mult"}


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = ("%.4f" % float(v)).rstrip("0")
    return s + "0" if s.endswith(".") else s


def gd_export(path, field):
    """(номер строки, текст значения) у `@export… var field[: T] = value` в .gd."""
    rx = re.compile(r"^(@export[^\n]*?\bvar\s+" + re.escape(field) + r"\b[^=\n]*=\s*)([^#\n]+?)(\s*(#.*)?)$")
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = rx.match(line)
        if m:
            return i, m.group(2).strip(), rx
    return None, None, None


def tres_value(path, field):
    """(номер строки, текст значения) у `field = value` в .tres; None — поле не записано (значение из скрипта)."""
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith(field + " = "):
            return i, line[len(field) + 3:].strip()
    return None, None


NUM = r"-?\d+(?:\.\d+)?"


def array_body_start(text):
    """Начало списка чисел: после «(» у PackedFloat32Array(...) или «[» у массива."""
    for ch in "([":
        i = text.find(ch)
        if i >= 0:
            return i + 1
    return 0


def index_part(text, idx):
    nums = re.findall(NUM, text[array_body_start(text):])
    return nums[idx] if idx < len(nums) else None


def plan(values):
    rows, unknown, globals_ = [], [], []
    for key, new in values.items():
        if "." not in key:
            unknown.append(key)
            continue
        src, field = key.split(".", 1)
        if src in GLOBAL_SOURCES:
            globals_.append((key, new))
            continue
        base = re.split(r"[\[/]", field)[0]
        idx = None
        m = re.search(r"\[(\d+)\]$", field)
        if m:
            idx = int(m.group(1))
        if src in GD_SOURCES:
            path = ROOT / GD_SOURCES[src]
            line, old, _ = gd_export(path, base)
            if line is None:
                unknown.append(key)
                continue
            rows.append({"key": key, "file": GD_SOURCES[src], "line": line, "old": old, "new": new, "kind": "gd", "field": base})
        elif src in TRES_SOURCES:
            tres, script = TRES_SOURCES[src]
            line, old = tres_value(ROOT / tres, base)
            target = tres
            if line is None:
                line, old, _ = gd_export(ROOT / script, base)
                target = script
            if line is None:
                unknown.append(key)
                continue
            shown = old
            if idx is not None:
                shown = index_part(old, idx)
            elif "/" in field:
                k = field.split("/", 1)[1]
                mm = re.search(r'"' + re.escape(k) + r'":\s*(-?[\d.]+)', (ROOT / target).read_text(encoding="utf-8"))
                shown = mm.group(1) if mm else "?"
            rows.append({"key": key, "file": target, "line": line, "old": shown, "new": new, "kind": "tres" if target == tres else "gd",
                         "field": base, "index": idx, "dict_key": field.split("/", 1)[1] if "/" in field else None})
        else:
            unknown.append(key)
    return rows, unknown, globals_


def write(rows):
    for r in rows:
        path = ROOT / r["file"]
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        i = r["line"] - 1
        line = lines[i]
        new = fmt(r["new"])
        if r.get("dict_key"):
            # Словарь очков стиля: значение ключа где угодно в файле
            text = path.read_text(encoding="utf-8")
            text = re.sub(r'("' + re.escape(r["dict_key"]) + r'":\s*)-?[\d.]+', lambda m: m.group(1) + new, text, count=1)
            path.write_text(text, encoding="utf-8")
            continue
        if r.get("index") is not None:
            value_part = line.split("=", 1)[1]
            body = array_body_start(value_part)
            nums = list(re.finditer(NUM, value_part[body:]))
            off = len(line.split("=", 1)[0]) + 1 + body
            m = nums[r["index"]]
            line = line[:off + m.start()] + new + line[off + m.end():]
        elif r["kind"] == "gd":
            _, _, rx = gd_export(path, r["field"])
            line = rx.sub(lambda m: m.group(1) + new + m.group(3), line.rstrip("\n")) + "\n"
        else:
            line = "%s = %s\n" % (r["field"], new)
        lines[i] = line
        path.write_text("".join(lines), encoding="utf-8")
    # TUNING.md: «`поле` старое» → «`поле` новое»
    tuning = ROOT / "TUNING.md"
    text = tuning.read_text(encoding="utf-8")
    changed = 0
    for r in rows:
        if r.get("index") is not None or r.get("dict_key") or r["old"] is None:
            continue
        old = str(r["old"]).strip()
        pat = "`%s` %s" % (r["field"], old)
        if pat in text:
            text = text.replace(pat, "`%s` %s" % (r["field"], fmt(r["new"])), 1)
            changed += 1
    tuning.write_text(text, encoding="utf-8")
    return changed


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    data = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    values = data.get("values", {})
    rows, unknown, globals_ = plan(values)
    print("Баланс: %s (сборка %s, %s)%s" % (args[0], data.get("build", "?"), data.get("saved", "?"),
                                          (" — «%s»" % data["note"]) if data.get("note") else ""))
    print("%-40s %10s %10s  %s" % ("поле", "было", "стало", "файл:строка"))
    for r in rows:
        print("%-40s %10s %10s  %s:%d" % (r["key"], r["old"], fmt(r["new"]), r["file"], r["line"]))
    for key, new in globals_:
        print("%-40s %10s %10s  глобальный множитель — решает владелец" % (key, "1", fmt(new)))
    for key in unknown:
        print("%-40s неизвестный ключ — пропущен" % key)
    if "--write" in argv:
        n = write(rows)
        print("Записано: %d значений, строк TUNING.md: %d" % (len(rows), n))
    if "--check" in argv and unknown:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
