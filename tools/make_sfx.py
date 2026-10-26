#!/usr/bin/env python3
"""Синтез звуков прототипа (свои, CC0). Запуск: python3 tools/make_sfx.py
Пишет WAV в sounds/sfx/. Всё процедурно: шум + фильтры + огибающие."""
import os
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def env(n, attack=0.005, decay_pow=2.0):
    x = np.linspace(0, 1, n)
    a = max(1, int(SR * attack))
    e = (1 - x) ** decay_pow
    e[:a] *= np.linspace(0, 1, a)
    return e


def bp(sig, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, sig)


def lp(sig, f, order=2):
    sos = butter(order, f, btype="low", fs=SR, output="sos")
    return sosfilt(sos, sig)


def hp(sig, f, order=2):
    sos = butter(order, f, btype="high", fs=SR, output="sos")
    return sosfilt(sos, sig)


def sweep_noise(dur, f0, f1, width=0.6):
    """Шум, полоса которого едет от f0 к f1 — «вжух»."""
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    blocks = 24
    for i in range(blocks):
        s, e = i * n // blocks, (i + 1) * n // blocks
        f = f0 + (f1 - f0) * (i / blocks)
        seg = bp(noise, f * (1 - width / 2), f * (1 + width / 2))[s:e]
        out[s:e] = seg
    return out


def mix(*parts):
    """Складывает сигналы разной длины."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def save(name, sig, gain=0.9):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * gain
    fade = min(len(sig), int(SR * 0.004))
    sig[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (sig * 32767).astype(np.int16))
    print("  ", name)


def whoosh(dur=0.2, f0=600, f1=2400):
    s = sweep_noise(dur, f0, f1)
    x = np.linspace(0, 1, len(s))
    return s * np.sin(np.pi * x) ** 1.5


def thump(dur=0.25, f0=110, f1=45):
    tt = t(dur)
    freq = np.linspace(f0, f1, len(tt))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * env(len(tt), 0.002, 3.0)


def metal(dur=0.6, base=420):
    tt = t(dur)
    ratios = [1.0, 2.76, 5.4, 8.93, 13.34]
    sig = sum(np.sin(2 * np.pi * base * r * tt) * np.exp(-tt * (4 + r * 2)) / (1 + i) for i, r in enumerate(ratios))
    return sig


print("Синтез звуков…")
# Взмах топора — три варианта по высоте
for i, (a, b) in enumerate([(500, 2200), (650, 2600), (420, 1700)]):
    save("axe_swing_%d" % (i + 1), whoosh(0.18 + 0.03 * i, a, b), 0.55)

# Удар топора по врагу: глухой удар + хруст
for i in range(3):
    n = int(SR * 0.22)
    crunch = bp(rng.standard_normal(n), 900, 4000) * env(n, 0.001, 4.0)
    save("axe_hit_%d" % (i + 1), thump(0.22, 140 - i * 15, 50) * 1.2 + crunch * 0.6, 0.85)

# Тяжёлый финишер комбо
n = int(SR * 0.4)
save("axe_finisher", thump(0.4, 120, 35) * 1.4 + bp(rng.standard_normal(n), 300, 2500) * env(n, 0.001, 3.0) * 0.8, 0.95)

# Бросок молота: гудящий «вжух» + электрическое жужжание
tt = t(0.35)
buzz = np.sign(np.sin(2 * np.pi * 95 * tt)) * 0.15 * np.sin(np.pi * np.linspace(0, 1, len(tt)))
save("hammer_throw", whoosh(0.35, 300, 1600) + lp(buzz, 900), 0.7)

# Молот попал
n = int(SR * 0.3)
save("hammer_hit", thump(0.3, 160, 50) + metal(0.3, 380) * 0.5 + bp(rng.standard_normal(n), 2000, 7000) * env(n, 0.001, 5) * 0.3, 0.9)

# Молот вернулся в руку — металлический «клац»
save("hammer_catch", mix(metal(0.5, 520), thump(0.12, 200, 90) * 0.6), 0.75)

# Молот отскочил от стены
save("hammer_bounce", mix(metal(0.35, 300) * 0.8, thump(0.15, 180, 70)), 0.6)

# Цепная молния — треск
n = int(SR * 0.35)
crack = np.zeros(n)
for _ in range(70):
    p = rng.integers(0, n - 400)
    crack[p:p + 400] += rng.standard_normal(400) * np.exp(-np.linspace(0, 8, 400))
crack = hp(crack, 1500) * env(n, 0.001, 1.5)
save("lightning", crack, 0.7)

# Рывок — короткий воздушный «фшух»
save("dash", whoosh(0.16, 900, 3500) * 1.0 + lp(rng.standard_normal(int(SR * 0.16)), 400) * env(int(SR * 0.16), 0.001, 2) * 0.3, 0.6)

# Удар-приземление — «бум» с низами и пылью
n = int(SR * 0.9)
boom = thump(0.9, 90, 28) * 1.5 + lp(rng.standard_normal(n), 600) * env(n, 0.002, 2.5) * 0.9
save("slam", boom, 1.0)

# Супер-прыжок — взлёт с подъёмом тона
tt = t(0.4)
rise = np.sin(2 * np.pi * np.cumsum(np.linspace(200, 700, len(tt))) / SR) * np.sin(np.pi * np.linspace(0, 1, len(tt))) * 0.3
save("super_jump", whoosh(0.4, 400, 3000) + rise, 0.7)

# Отбитый снаряд — звонкий «пинг»
tt = t(0.4)
ping = (np.sin(2 * np.pi * 1320 * tt) + 0.5 * np.sin(2 * np.pi * 1980 * tt)) * np.exp(-tt * 9)
save("reflect", mix(ping, thump(0.1, 300, 150) * 0.3), 0.6)

# Снаряд метателя — бульк-проклятье
tt = t(0.45)
wob = np.sin(2 * np.pi * (180 + 60 * np.sin(2 * np.pi * 9 * tt)) * tt) * env(len(tt), 0.02, 1.5)
save("curse_throw", lp(wob + rng.standard_normal(len(tt)) * 0.1, 1200), 0.5)

# Замах врага (рык) — низкий шум
n = int(SR * 0.5)
growl = bp(rng.standard_normal(n), 90, 400) * np.sin(np.pi * np.linspace(0, 1, n))
growl *= 1 + 0.6 * np.sin(2 * np.pi * 28 * t(0.5))
save("enemy_growl", growl, 0.5)

# Враг шмякнулся об стену
n = int(SR * 0.3)
save("wall_splat", thump(0.3, 100, 40) * 1.3 + bp(rng.standard_normal(n), 200, 1500) * env(n, 0.001, 3) * 0.7, 0.9)

# Выбор руны — аккорд
tt = t(1.2)
chord = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (2.5 + i)) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]))
save("rune_pick", chord, 0.5)

# Дверь открывается — каменный скрежет
n = int(SR * 1.0)
grind = bp(rng.standard_normal(n), 60, 500) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t(1.0)))
grind *= np.sin(np.pi * np.linspace(0, 1, n)) ** 0.5
save("door_open", grind + thump(1.0, 60, 30) * 0.4, 0.7)

# Удар босса по площади
n = int(SR * 1.2)
save("boss_slam", thump(1.2, 70, 22) * 1.6 + lp(rng.standard_normal(n), 400) * env(n, 0.002, 2) * 1.0, 1.0)

# Игрок получил урон
save("player_hurt", thump(0.2, 220, 90) + bp(rng.standard_normal(int(SR * 0.2)), 500, 2000) * env(int(SR * 0.2), 0.001, 3) * 0.5, 0.7)
# Молот воткнулся в стену/пол — глухой удар с каменным хрустом
n = int(SR * 0.35)
save("hammer_stick", thump(0.35, 130, 40) * 1.3 + bp(rng.standard_normal(n), 400, 3000) * env(n, 0.001, 4.0) * 0.6 + metal(0.35, 260) * 0.25, 0.85)

# Идеальный хват — звонкое «дзынь»
tt = t(0.7)
ding = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (5 + 3 * i)) / (1 + i) for i, f in enumerate([1568.0, 2349.3, 3136.0]))
save("perfect_catch", mix(ding, metal(0.4, 900) * 0.3), 0.6)
print("Готово:", OUT)
