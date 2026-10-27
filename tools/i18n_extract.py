#!/usr/bin/env python3
"""Собирает строки для перевода в data/i18n/en.po (ключ = русская строка, msgstr = английский).

Запуск из корня проекта:  python3 tools/i18n_extract.py [--prune] [--check]

Что собирается:
  * код (*.gd в ui/ run/ scenes/ weapons/ enemies/ rooms/ player/ scripts/):
      - литералы в tr("…"), I18n.t("…"), TranslationServer.translate("…");
      - русские литералы в объявлениях const (подписи вкладок, действий и т. п. — tr при показе);
      - русские значения по умолчанию у @export var (поля данных: «Берсерк», «Топор»…);
  * данные (*.tres в run/ weapons/ enemies/, room_title в rooms/*.tscn): все русские строки
    свойств и PackedStringArray (названия, описания, уровни рун…), кроме glyph;
  * подписи выборов ("label") в data/dialogues/*.json (сами реплики — tools/i18n_dialogues.py).
Существующие переводы сохраняются; новые ключи добавляются с пустым msgstr (их надо вписать).
--prune убирает ключи, которых больше нет нигде; --check — только отчёт (код возврата 1, если есть
пустые переводы или новые ключи).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO_PATH = os.path.join(ROOT, "data", "i18n", "en.po")
CODE_DIRS = ["ui", "run", "scenes", "weapons", "enemies", "rooms", "player", "scripts"]
DATA_DIRS = ["run", "weapons", "enemies"]
CYR = re.compile(r"[А-Яа-яЁё]")
STR = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r'(?:\btr|I18n\.t|TranslationServer\.translate)\(\s*' + STR)
LIT = re.compile(STR)
SKIP_PROPS = {"glyph", "id", "script"}

HEADER = '''msgid ""
msgstr ""
"Project-Id-Version: Thor Dostoynaya Smert\\n"
"Language: en\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"
'''


def unescape_gd(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(n, "\\" + n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def po_unescape(s):
    return unescape_gd(s)


def strip_comment(line):
    """Строка кода без комментария (# вне строковых литералов)."""
    in_str, esc = False, False
    for i, c in enumerate(line):
        if esc:
            esc = False
            continue
        if c == "\\":
            esc = True
            continue
        if c == '"':
            in_str = not in_str
        elif c == "#" and not in_str:
            return line[:i]
    return line


def scan_code(found):
    for d in CODE_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for fn in sorted(files):
                if not fn.endswith(".gd"):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                depth = 0  # скобки многострочного const
                with open(path, encoding="utf-8") as f:
                    for no, raw in enumerate(f, 1):
                        line = strip_comment(raw.rstrip("\n"))
                        stripped = line.strip()
                        in_const = depth > 0 or stripped.startswith("const ") or stripped.startswith("static const ")
                        for m in CALL.finditer(line):
                            add(found, unescape_gd(m.group(1)), "%s:%d" % (rel, no))
                        if in_const or (stripped.startswith("@export var") or stripped.startswith("@export_multiline var")):
                            for m in LIT.finditer(line):
                                s = unescape_gd(m.group(1))
                                if CYR.search(s):
                                    add(found, s, "%s:%d" % (rel, no))
                        if in_const:
                            depth += line.count("[") + line.count("{") + line.count("(")
                            depth -= line.count("]") + line.count("}") + line.count(")")
                            depth = max(depth, 0)


def tres_strings(text):
    """(имя свойства, строка) из .tres/.tscn: prop = "…" (может быть многострочной) и PackedStringArray(…)."""
    i, n = 0, len(text)
    prop = ""
    line_start = True
    while i < n:
        c = text[i]
        if line_start:
            m = re.match(r"([A-Za-z_][A-Za-z0-9_/]*)\s*=", text[i:])
            if m:
                prop = m.group(1)
        line_start = c == "\n"
        if c == '"':
            j, buf = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            yield prop, unescape_gd("".join(buf))
            i = j + 1
            continue
        i += 1


def scan_data(found):
    for d in DATA_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for fn in sorted(files):
                if not fn.endswith(".tres"):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                with open(path, encoding="utf-8") as f:
                    text = f.read()
                for prop, s in tres_strings(text):
                    if prop in SKIP_PROPS or not CYR.search(s):
                        continue
                    add(found, s, "%s (%s)" % (rel, prop))
    # подписи выборов в диалогах («Огрызнуться» / «Согласиться») — тексты реплик переводятся в data/dialogues/en/
    ddir = os.path.join(ROOT, "data", "dialogues")
    for fn in sorted(os.listdir(ddir)):
        if fn.endswith(".json"):
            with open(os.path.join(ddir, fn), encoding="utf-8") as f:
                text = f.read()
            for m in re.finditer(r'"label"\s*:\s*' + STR, text):
                add(found, unescape_gd(m.group(1)), "data/dialogues/%s (label)" % fn)
    rooms = os.path.join(ROOT, "rooms")
    for fn in sorted(os.listdir(rooms)):
        if fn.endswith(".tscn"):
            with open(os.path.join(rooms, fn), encoding="utf-8") as f:
                for prop, s in tres_strings(f.read()):
                    if prop == "room_title" and CYR.search(s):
                        add(found, s, "rooms/%s (room_title)" % fn)


def add(found, s, where):
    if s.strip() == "":
        return
    found.setdefault(s, [])
    if where not in found[s]:
        found[s].append(where)


def read_po(path):
    """{msgid: msgstr} в порядке файла."""
    entries = {}
    if not os.path.exists(path):
        return entries
    cur, key, msgid, msgstr = None, None, [], []

    def flush():
        if msgid is not None:
            k = "".join(msgid)
            if k != "":
                entries[k] = "".join(msgstr)

    msgid, msgstr = None, []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("#") or line == "":
                continue
            if line.startswith("msgid "):
                flush()
                msgid, msgstr, cur = [po_unescape(line[7:-1])], [], "id"
            elif line.startswith("msgstr "):
                msgstr, cur = [po_unescape(line[8:-1])], "str"
            elif line.startswith('"'):
                (msgid if cur == "id" else msgstr).append(po_unescape(line[1:-1]))
    flush()
    return entries


def write_po(path, found, old, prune):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = [HEADER]
    for s in sorted(found, key=lambda k: (found[k][0], k)):
        out.append("")
        for w in found[s][:4]:
            out.append("#: " + w)
        out.append('msgid "%s"' % po_escape(s))
        out.append('msgstr "%s"' % po_escape(old.get(s, "")))
    stale = [k for k in old if k not in found]
    if stale and not prune:
        out.append("")
        out.append("# --- Ключи, которых не нашёл сборщик (динамические строки или устаревшие; --prune удалит) ---")
        for s in stale:
            out.append("")
            out.append('msgid "%s"' % po_escape(s))
            out.append('msgstr "%s"' % po_escape(old[s]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return stale


def main():
    prune = "--prune" in sys.argv
    check = "--check" in sys.argv
    found = {}
    scan_code(found)
    scan_data(found)
    old = read_po(PO_PATH)
    new = [k for k in found if k not in old]
    empty = [k for k in found if old.get(k, "") == ""]
    stale = [k for k in old if k not in found]
    print("ключей: %d, новых: %d, без перевода: %d, не найдено в коде/данных: %d" % (len(found), len(new), len(empty), len(stale)))
    for k in empty[:40]:
        print("  без перевода:", k.replace("\n", "\\n"), "<-", found[k][0])
    if check:
        sys.exit(1 if empty else 0)
    write_po(PO_PATH, found, old, prune)
    print("записан", os.path.relpath(PO_PATH, ROOT))


if __name__ == "__main__":
    main()
