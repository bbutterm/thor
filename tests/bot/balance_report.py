#!/usr/bin/env python3
"""Отчёт бот-плейтеста (блок Б5) по файлам JSON Lines из tests/balance_run.tscn.

  python3 tests/bot/balance_report.py run.jsonl [run2.jsonl ...]            # таблицы по набору
  python3 tests/bot/balance_report.py --compare before.jsonl after.jsonl    # «до → после»

Печатает Markdown в stdout. Цели (GDD 15.2, 24): Слава за забег 150–250; забег опытного игрока ~15 мин
(перевод времени бота в человеческое — HUMAN_* ниже); Свен и Ярл проходимы, но опасны.
"""
import json
import statistics as st
import sys
from collections import Counter, defaultdict

GLORY_RANGE = (150, 250)
# Перевод времени бота во время человека: бой человека медленнее (ищет врагов, промахивается, лезет на ярусы) —
# ×HUMAN_FIGHT_MULT, плюс на каждый зал HUMAN_ROOM_OVERHEAD с (дойти до двери и лута, прочитать карточки,
# загрузка; бот это делает мгновенно, а паузу на выборе таймер забега не считает).
HUMAN_FIGHT_MULT = 1.8
HUMAN_ROOM_OVERHEAD = 25.0
RUN_MINUTES_TARGET = (12.0, 18.0)
RANKS = ["Скуф", "Сойдёт", "Неплохо", "Достойно", "ДОСТ.!"]
CAUSES = {
    "draugr_warrior": "воин", "draugr_thrower": "метатель", "draugr_fodder": "корм", "boss_jarl": "Ярл",
    "miniboss_sven": "Свен", "fall": "падение", "barrel": "бочка", "own_fire": "свой огонь", "shieldbearer": "щитоносец",
    "bloated": "раздутый", "shaman": "шаман", "loki_merc": "наёмник", "lava": "лава (испытание)", "unknown": "?",
    "timeout": "время вышло", "room_timeout": "застрял в зале",
}


def load(paths):
    out = []
    for p in paths:
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    out.append(_fix_falls(json.loads(line)))
    return out


def _fix_falls(r):
    """Падение в пропасть — урон 9999: в таблицах считаем его как потерю оставшегося HP."""
    for rm in r.get("rooms", []):
        src = rm.get("src", {})
        for k, v in list(src.items()):
            if v >= 9000:
                real = max(0.0, min(rm.get("hp_max", 100.0), v - 9999 + rm.get("hp_max", 100.0)))
                real = min(real, rm.get("hp_start", real))
                src["fall"] = src.get("fall", 0.0) + real
                if k != "fall":
                    del src[k]
                else:
                    src["fall"] = real
                rm["dmg"] = rm["dmg"] - v + real
    if r.get("dmg_total", 0) >= 9000:
        r["dmg_total"] = sum(rm.get("dmg", 0) for rm in r.get("rooms", []))
    return r


def mean(xs):
    xs = list(xs)
    return st.mean(xs) if xs else 0.0


def fmt(x, d=0):
    return f"{x:.{d}f}"


def human_minutes(r):
    rooms = [rm for rm in r["rooms"] if rm.get("fight_time", 0) > 0 or rm.get("reward") in ("shop", "rest")]
    fight = sum(rm.get("fight_time", 0.0) for rm in r["rooms"])
    other = max(0.0, r["time"] - fight)
    return (fight * HUMAN_FIGHT_MULT + other + HUMAN_ROOM_OVERHEAD * len(rooms)) / 60.0


def fight_rooms(r):
    """Боевые залы забега (без ларька/отдыха): записи с боем."""
    return [rm for rm in r["rooms"] if rm.get("fight_time", 0) > 0]


def body_table(runs):
    by = defaultdict(list)
    for r in runs:
        by[r["body"]].append(r)
    lines = ["| Тело | Забегов | Побед | Время, с (бот) | ≈ мин человека | Залов (ср.) | Где умер (зал: причина) | Урон за зал | Убито | Слава ср. / мин / макс | Серебро | Ранги стиля, % времени боя | Подсадок |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for body in sorted(by):
        rs = by[body]
        wins = sum(1 for r in rs if r["outcome"] == "win")
        deaths = []
        for r in rs:
            if r["outcome"] != "win":
                deaths.append(f"{r['death_room'] + 1} {r['death_scene']}: {CAUSES.get(r['cause'], r['cause'])}")
        dmg_room = mean(mean(rm["dmg"] for rm in fight_rooms(r)) for r in rs if fight_rooms(r))
        rt = [sum(r["rank_time"][i] for r in rs) for i in range(5)]
        tot = sum(rt) or 1.0
        ranks = " / ".join(f"{100 * x / tot:.0f}" for x in rt)
        gl = [r["glory"] for r in rs]
        lines.append(f"| {body} | {len(rs)} | {wins} | {fmt(mean(r['time'] for r in rs))} | {fmt(mean(human_minutes(r) for r in rs), 1)} | "
                     f"{fmt(mean(r['rooms_reached'] for r in rs), 1)} | {'; '.join(deaths) or '—'} | {fmt(dmg_room)} | "
                     f"{fmt(mean(r['kills'] for r in rs))} | {fmt(mean(gl))} / {min(gl)} / {max(gl)} | "
                     f"{fmt(mean(r['silver'] for r in rs))} | {ranks} | {sum(r['stats'].get('assists', 0) for r in rs)} |")
    return "\n".join(lines)


def room_tables(runs):
    by_scene = defaultdict(list)
    by_index = defaultdict(list)
    deaths_scene = Counter()
    deaths_index = Counter()
    for r in runs:
        for rm in r["rooms"]:
            if rm.get("fight_time", 0) <= 0:
                continue
            by_scene[rm["scene"]].append(rm)
            by_index[rm["index"]].append(rm)
        if r["outcome"] != "win" and r["rooms"]:
            last = r["rooms"][-1]
            deaths_scene[last["scene"]] += 1
            deaths_index[last["index"]] += 1

    def row(name, rms, deaths):
        cleared = [rm for rm in rms if rm.get("cleared")]
        srcs = Counter()
        for rm in rms:
            for k, v in rm["src"].items():
                srcs[k] += v
        top = ", ".join(f"{CAUSES.get(k, k)} {v / max(1, len(rms)):.0f}" for k, v in srcs.most_common(3))
        return (f"| {name} | {len(rms)} | {fmt(mean(rm['dmg'] for rm in rms))} | {fmt(mean(100 * rm['dmg'] / max(1, rm['hp_max']) for rm in rms))} % | "
                f"{fmt(mean(rm['t_clear'] for rm in cleared))} | {fmt(mean(rm['kills'] for rm in rms))} | {deaths} | {top or '—'} |")

    head = "| {} | Боёв | Урон по Тору | % макс. HP | Зачистка, с | Убито | Смертей | Главные источники урона (ср. за бой) |\n|---|---|---|---|---|---|---|---|"
    a = [head.format("Зал")]
    for sc in sorted(by_scene):
        a.append(row(sc, by_scene[sc], deaths_scene[sc]))
    b = [head.format("№ зала")]
    for i in sorted(by_index):
        b.append(row(str(i + 1), by_index[i], deaths_index[i]))
    return "\n".join(a), "\n".join(b)


def boss_table(runs):
    lines = ["| Босс | Боёв | Побед | Смертей в бою | Время боя, с (ср. / мин / макс) | Урон по Тору (ср.) | % макс. HP | Фазы Ярла, с от начала (2 / 3) |",
             "|---|---|---|---|---|---|---|---|"]
    for bid, title in (("sven", "Толстый Свен"), ("jarl", "Ярл Бьорн")):
        fights = []
        for r in runs:
            for rm in r["rooms"]:
                b = rm.get("boss")
                if b and b.get("id") == bid:
                    fights.append((r, rm, b))
        if not fights:
            lines.append(f"| {title} | 0 | — | — | — | — | — | — |")
            continue
        kills = [f for f in fights if f[2].get("killed")]
        died = len(fights) - len(kills)
        times = [f[2]["time"] for f in kills]
        tt = f"{fmt(mean(times))} / {fmt(min(times))} / {fmt(max(times))}" if times else "—"
        ph = ""
        if bid == "jarl":
            p2 = [float(f[2]["phase_t"]["2"]) for f in fights if "2" in f[2].get("phase_t", {})]
            p3 = [float(f[2]["phase_t"]["3"]) for f in fights if "3" in f[2].get("phase_t", {})]
            ph = f"{fmt(mean(p2))} / {fmt(mean(p3))}"
        lines.append(f"| {title} | {len(fights)} | {len(kills)} | {died} | {tt} | {fmt(mean(f[2]['dmg'] for f in fights))} | "
                     f"{fmt(mean(100 * f[2]['dmg'] / max(1, f[1]['hp_max']) for f in fights))} % | {ph or '—'} |")
    return "\n".join(lines)


def glory_sources(runs):
    tot = Counter()
    for r in runs:
        for k, v in r.get("glory_src", {}).items():
            k2 = "бонус зала (испытание, элита, мини-босс…)" if k.startswith("bonus_") else k
            tot[k2] += v
    n = max(1, len(runs))
    names = {"kill": "убийства (с множителями)", "multikill": "мультикилл", "streak": "серии по 10", "boss": "босс (Ярл)",
             "room_clear": "зачистка зала"}
    return ", ".join(f"{names.get(k, k)} {v / n:.0f}" for k, v in tot.most_common())


def summary(runs):
    wins = [r for r in runs if r["outcome"] == "win"]
    gl = [r["glory"] for r in runs]
    return {
        "runs": len(runs),
        "win_rate": 100.0 * len(wins) / max(1, len(runs)),
        "time": mean(r["time"] for r in runs),
        "time_win": mean(r["time"] for r in wins),
        "human_min_win": mean(human_minutes(r) for r in wins),
        "rooms": mean(r["rooms_reached"] for r in runs),
        "glory": mean(gl),
        "glory_min": min(gl) if gl else 0,
        "glory_max": max(gl) if gl else 0,
        "glory_win": mean(r["glory"] for r in wins),
        "glory_death": mean(r["glory"] for r in runs if r["outcome"] != "win"),
        "kills": mean(r["kills"] for r in runs),
        "dmg_room": mean(mean(rm["dmg"] for rm in fight_rooms(r)) for r in runs if fight_rooms(r)),
        "silver": mean(r["silver"] for r in runs),
        "assists": mean(r["stats"].get("assists", 0) for r in runs),
    }


def boss_summary(runs, bid):
    fights = []
    for r in runs:
        for rm in r["rooms"]:
            b = rm.get("boss")
            if b and b.get("id") == bid:
                fights.append((rm, b))
    if not fights:
        return {"fights": 0}
    kills = [b for _, b in fights if b.get("killed")]
    return {"fights": len(fights), "death_rate": 100.0 * (len(fights) - len(kills)) / len(fights),
            "time": mean(b["time"] for b in kills), "dmg_pct": mean(100 * b["dmg"] / max(1, rm["hp_max"]) for rm, b in fights)}


def out_of_range(runs):
    s = summary(runs)
    notes = []
    if not GLORY_RANGE[0] <= s["glory"] <= GLORY_RANGE[1]:
        notes.append(f"Слава за забег в среднем {s['glory']:.0f} — вне цели {GLORY_RANGE[0]}–{GLORY_RANGE[1]} (GDD 15.2).")
    if s["win_rate"] > 0 and not RUN_MINUTES_TARGET[0] <= s["human_min_win"] <= RUN_MINUTES_TARGET[1]:
        notes.append(f"Победный забег ≈ {s['human_min_win']:.1f} мин человека (бот {s['time_win']:.0f} с игрового времени) — "
                     f"вне цели ~15 мин ({RUN_MINUTES_TARGET[0]:.0f}–{RUN_MINUTES_TARGET[1]:.0f}).")
    for bid, title in (("sven", "Свен"), ("jarl", "Ярл")):
        b = boss_summary(runs, bid)
        if b["fights"] == 0:
            continue
        if b["death_rate"] < 5 and b["dmg_pct"] < 30:
            notes.append(f"{title} не опасен: смертей в бою {b['death_rate']:.0f} %, урон по Тору {b['dmg_pct']:.0f} % макс. HP за бой.")
        if b["death_rate"] > 60:
            notes.append(f"{title} слишком тяжёл: смертей в бою {b['death_rate']:.0f} %.")
    return notes


def report(runs, title=""):
    out = []
    if title:
        out.append(f"### {title}\n")
    s = summary(runs)
    out.append(f"Забегов {s['runs']}, побед {s['win_rate']:.0f} %, время забега {s['time']:.0f} с (победа — {s['time_win']:.0f} с, "
               f"≈ {s['human_min_win']:.1f} мин человека), Слава {s['glory']:.0f} (мин {s['glory_min']}, макс {s['glory_max']}; "
               f"победа {s['glory_win']:.0f}, смерть {s['glory_death']:.0f}), урон за боевой зал {s['dmg_room']:.0f}, подсадок {s['assists']:.1f} за забег.\n")
    out.append("**По телам**\n")
    out.append(body_table(runs) + "\n")
    out.append("Ранги стиля — доля времени боя: " + " / ".join(RANKS) + ".\n")
    a, b = room_tables(runs)
    out.append("**По залам (сцена)**\n")
    out.append(a + "\n")
    out.append("**По номеру зала в забеге**\n")
    out.append(b + "\n")
    out.append("**Боссы**\n")
    out.append(boss_table(runs) + "\n")
    out.append("**Откуда Слава** (в среднем за забег): " + glory_sources(runs) + ".\n")
    notes = out_of_range(runs)
    out.append("**Вне целей:**\n")
    out.append("\n".join(f"- {n}" for n in notes) if notes else "- всё в пределах целей.")
    out.append("")
    return "\n".join(out)


def compare(before, after, label_b="до", label_a="после"):
    sb, sa = summary(before), summary(after)
    rows = [("Побед, %", "win_rate", 0), ("Время забега, с", "time", 0), ("Победа: время, с", "time_win", 0),
            ("Победа: ≈ мин человека", "human_min_win", 1), ("Залов пройдено", "rooms", 1), ("Слава ср.", "glory", 0),
            ("Слава мин", "glory_min", 0), ("Слава макс", "glory_max", 0), ("Слава: победа", "glory_win", 0),
            ("Слава: смерть", "glory_death", 0), ("Убито", "kills", 0), ("Урон по Тору за зал", "dmg_room", 0),
            ("Серебро", "silver", 0)]
    out = [f"| Показатель | {label_b} | {label_a} |", "|---|---|---|"]
    for name, k, d in rows:
        out.append(f"| {name} | {fmt(sb[k], d)} | {fmt(sa[k], d)} |")
    for bid, title in (("sven", "Свен"), ("jarl", "Ярл")):
        b1, b2 = boss_summary(before, bid), boss_summary(after, bid)
        if b1["fights"] and b2["fights"]:
            out.append(f"| {title}: смертей в бою, % | {fmt(b1['death_rate'])} | {fmt(b2['death_rate'])} |")
            out.append(f"| {title}: время боя, с | {fmt(b1['time'])} | {fmt(b2['time'])} |")
            out.append(f"| {title}: урон по Тору, % HP | {fmt(b1['dmg_pct'])} | {fmt(b2['dmg_pct'])} |")
    # По телам: Слава и победы
    out.append("")
    out.append(f"| Тело | Побед {label_b} | Побед {label_a} | Слава {label_b} | Слава {label_a} | Время {label_b}, с | Время {label_a}, с |")
    out.append("|---|---|---|---|---|---|---|")
    bodies = sorted({r["body"] for r in before} | {r["body"] for r in after})
    for body in bodies:
        rb = [r for r in before if r["body"] == body]
        ra = [r for r in after if r["body"] == body]
        wb = sum(1 for r in rb if r["outcome"] == "win")
        wa = sum(1 for r in ra if r["outcome"] == "win")
        out.append(f"| {body} | {wb}/{len(rb)} | {wa}/{len(ra)} | {fmt(mean(r['glory'] for r in rb))} | {fmt(mean(r['glory'] for r in ra))} | "
                   f"{fmt(mean(r['time'] for r in rb))} | {fmt(mean(r['time'] for r in ra))} |")
    return "\n".join(out)


def main(argv):
    if len(argv) >= 3 and argv[0] == "--compare":
        print(compare(load([argv[1]]), load([argv[2]])))
        return
    runs = load(argv)
    print(report(runs))


if __name__ == "__main__":
    main(sys.argv[1:])
