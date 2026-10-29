#!/usr/bin/env python3
"""Самотест tools/apply_balance.py: таблица на образце (--check) и запись (--write) во временную копию репозитория."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "tools/testdata/balance_sample.json"
fails = []


def check(cond, what):
    print(("  [OK] " if cond else "  [FAIL] ") + what)
    if not cond:
        fails.append(what)


out = subprocess.run([sys.executable, str(ROOT / "tools/apply_balance.py"), str(SAMPLE), "--check"], capture_output=True, text=True)
text = out.stdout
check(out.returncode == 1, "--check: неизвестный ключ — код выхода 1")
check("mjolnir.perfect_window" in text and "0.15" in text and "0.22" in text and "weapons/mjolnir_hand.gd:" in text, "окно хвата: было 0.15 → 0.22, файл:строка")
check("player.move_speed" in text and "player/player.gd:" in text, "скорость бега — player.gd")
check("room.spawn_batch" in text and "rooms/room.gd:" in text, "волны — room.gd")
check(any(l.startswith("style.rank_points[2]") and " 35 " in l and "player/style_tuning" in l for l in text.splitlines()), "ранги стиля: было 35 — style_tuning")
check("economy.chest_silver" in text and "run/economy" in text, "экономика — economy")
check("enemy_mult.hp" in text and "владелец" in text, "глобальный множитель — решает владелец")
check("nonsense.field" in text and "неизвестный" in text, "неизвестный ключ назван")

with tempfile.TemporaryDirectory() as tmp:
    t = Path(tmp)
    for rel in ["tools/apply_balance.py", "weapons/mjolnir_hand.gd", "player/player.gd", "player/camera_fx.gd", "rooms/room.gd",
                "player/style_tuning.tres", "player/style_tuning.gd", "run/economy.tres", "run/economy.gd", "TUNING.md"]:
        (t / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / rel, t / rel)
    out = subprocess.run([sys.executable, str(t / "tools/apply_balance.py"), str(SAMPLE), "--write"], capture_output=True, text=True)
    hand = (t / "weapons/mjolnir_hand.gd").read_text(encoding="utf-8")
    check("@export var perfect_window: float = 0.22" in hand and "@export var catch_cooldown: float = 1.0" in hand, "--write: значения по умолчанию в mjolnir_hand.gd")
    check("@export var spawn_batch: int = 4" in (t / "rooms/room.gd").read_text(encoding="utf-8"), "--write: room.gd")
    style = (t / "player/style_tuning.tres").read_text(encoding="utf-8") + (t / "player/style_tuning.gd").read_text(encoding="utf-8")
    tres = (t / "player/style_tuning.tres").read_text(encoding="utf-8")
    check("rank_points = PackedFloat32Array(0, 15, 30.0, 60, 100)" in tres, "--write: третий порог ранга стал 30, остальные целы")
    check("Записано" in out.stdout, "--write: итог напечатан")

print("=== ИТОГ APPLY BALANCE: %s ===" % ("0 FAIL" if not fails else "%d FAIL" % len(fails)))
sys.exit(1 if fails else 0)
