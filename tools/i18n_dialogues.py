#!/usr/bin/env python3
"""Шаблоны перевода диалогов: data/dialogues/<id>.json -> data/dialogues/<язык>/<id>.json.

Запуск из корня проекта:  python3 tools/i18n_dialogues.py [язык=en] [--check]

Файл перевода: {"speakers": {"odin": {"ru": "Один", "<язык>": "Odin"}},
                "lines": {"<id реплики>": {"ru": "оригинал", "<язык>": "перевод"}, ...}}
Ответ Тора в выборе — ключ "<id реплики>/<id выбора>". Подписи выборов («Огрызнуться») — в data/i18n/en.po.
Существующие переводы сохраняются; «ru» обновляется по оригиналу — если оригинал поменялся,
перевод помечается ("stale": true) и печатается в отчёте. Пустой перевод = в игре русский.
--check печатает покрытие по файлам и пулам и ничего не пишет.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "dialogues")


def collect(d):
    """[(id, текст)] всех реплик файла в порядке появления + пул/сцена, где встретилась."""
    out = []

    def walk(lines, where):
        for l in lines:
            if not isinstance(l, dict) or "pool" in l:
                continue
            lid = str(l.get("id", ""))
            if lid and "text" in l:
                out.append((lid, l["text"], where))
            for ch in l.get("choices", []):
                out.append(("%s/%s" % (lid, ch.get("id", "")), ch.get("text", ""), where))
                walk(ch.get("lines", []), where)

    for sc in d.get("scenes", []):
        walk(sc.get("lines", []), "scene:" + str(sc.get("id", "")))
    for k, items in d.get("pools", {}).items():
        for it in items:
            if isinstance(it, dict) and "lines" in it:
                walk(it["lines"], "pool:" + k)
            elif isinstance(it, dict):
                walk([it], "pool:" + k)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lang = args[0] if args else "en"
    check = "--check" in sys.argv
    out_dir = os.path.join(DIR, lang)
    total = done = 0
    for fn in sorted(os.listdir(DIR)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(DIR, fn), encoding="utf-8") as f:
            d = json.load(f)
        fid = d.get("id", fn[:-5])
        path = os.path.join(out_dir, fn)
        old = {"speakers": {}, "lines": {}}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                old = json.load(f)
        res = {"_comment": "Перевод %s на «%s» (tools/i18n_dialogues.py). Пустое поле — в игре русский." % (fn, lang),
               "speakers": {}, "lines": {}}
        for sp, sd in d.get("speakers", {}).items():
            o = old.get("speakers", {}).get(sp, {})
            res["speakers"][sp] = {"ru": sd.get("name", sp), lang: o.get(lang, "") if isinstance(o, dict) else str(o)}
        f_total = f_done = 0
        by_where = {}
        stale = []
        for lid, text, where in collect(d):
            o = old.get("lines", {}).get(lid, {})
            tr = o.get(lang, "") if isinstance(o, dict) else str(o)
            e = {"ru": text, lang: tr}
            if isinstance(o, dict) and tr and (o.get("ru", text) != text or o.get("stale")):
                e["stale"] = True
                stale.append(lid)
            res["lines"][lid] = e
            f_total += 1
            w = by_where.setdefault(where, [0, 0])
            w[0] += 1
            if tr.strip():
                f_done += 1
                w[1] += 1
        total += f_total
        done += f_done
        print("%-16s %4d / %4d" % (fid, f_done, f_total))
        if check:
            for w, (a, b) in by_where.items():
                if b < a:
                    print("    %-40s %d / %d" % (w, b, a))
        for lid in stale:
            print("    устарел перевод:", lid)
        if not check:
            os.makedirs(out_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(res, f, ensure_ascii=False, indent="\t")
                f.write("\n")
    print("всего: %d / %d (%.0f %%)" % (done, total, 100.0 * done / max(total, 1)))


if __name__ == "__main__":
    main()
