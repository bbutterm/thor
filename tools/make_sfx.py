#!/usr/bin/env python3
"""Синтез звуков прототипа (свои, CC0). Запуск: python3 tools/make_sfx.py [префикс ...]
Пишет WAV в sounds/sfx/. Всё процедурно: шум + фильтры + огибающие.
С префиксами пишет только звуки, чьи имена с них начинаются (например: python3 tools/make_sfx.py gun_ crossbow_)."""
import os
import sys
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)
ONLY = sys.argv[1:]


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
    if ONLY and not any(name.startswith(p) for p in ONLY):
        return
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
# ---------------- Оружие (этап 1) ----------------
# Отдельный генератор шума, чтобы новые звуки не сдвигали старые
rng = np.random.default_rng(101)


def gunshot(dur, body_f0, body_f1, crack_lo, crack_hi, tail=0.6, crack=1.0):
    """Выстрел: щелчок-трескотня + «тело» + хвост реверберации."""
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    snap = bp(noise, crack_lo, crack_hi) * env(n, 0.0005, 7.0) * crack
    body = thump(dur, body_f0, body_f1) * 1.2
    tl = lp(rng.standard_normal(n), 1800) * env(n, 0.002, 2.2) * tail
    return mix(snap, body, tl)


save("gun_pistol", gunshot(0.32, 220, 70, 1500, 7000, 0.5), 0.8)
save("gun_smg", gunshot(0.16, 260, 110, 2000, 8000, 0.25, 0.9), 0.7)
save("gun_rifle", gunshot(0.28, 180, 60, 1200, 6500, 0.55, 1.1), 0.85)
save("gun_shotgun", gunshot(0.6, 120, 35, 600, 5000, 1.0, 1.3), 1.0)

# Пустой магазин — сухой щелчок
tt = t(0.06)
save("gun_empty", np.sin(2 * np.pi * 2400 * tt) * np.exp(-tt * 120) + bp(rng.standard_normal(len(tt)), 3000, 9000) * np.exp(-tt * 90) * 0.5, 0.45)

# Перезарядка: щелчок магазина + лязг затвора
n = int(SR * 0.5)
clk = np.zeros(n)
for pos, f in [(0.02, 1800), (0.30, 1300), (0.38, 2200)]:
    p0 = int(SR * pos)
    seg = t(0.06)
    clk[p0:p0 + len(seg)] += (np.sin(2 * np.pi * f * seg) + bp(rng.standard_normal(len(seg)), 2000, 8000) * 0.6) * np.exp(-seg * 70)
save("gun_reload", clk, 0.55)

# Арбалет: хлёсткий «твонк» тетивы + свист болта
tt = t(0.35)
twang = np.sin(2 * np.pi * (180 + 80 * np.exp(-tt * 20)) * tt) * np.exp(-tt * 10)
save("crossbow_fire", mix(twang, whoosh(0.25, 1200, 3000) * 0.6, thump(0.08, 300, 120) * 0.5), 0.75)
# Взвод арбалета: скрип + щелчок
n = int(SR * 0.6)
creak = bp(rng.standard_normal(n), 300, 1200) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t(0.6))) * np.linspace(0.2, 1.0, n) * 0.5
seg = t(0.05)
click = np.zeros(n)
click[n - len(seg):] = np.sin(2 * np.pi * 1600 * seg) * np.exp(-seg * 80)
save("crossbow_reload", creak + click, 0.55)

# Свитч оружия: короткий «вжух» + стук
save("weapon_switch", mix(whoosh(0.12, 700, 2200) * 0.6, thump(0.08, 260, 140) * 0.4), 0.45)
# Подбор оружия: металлический «клинк»
save("weapon_pickup", mix(metal(0.4, 640) * 0.8, thump(0.1, 220, 120) * 0.4), 0.6)
# Подбор патронов: два коротких щелчка
n = int(SR * 0.22)
cl2 = np.zeros(n)
for pos in [0.0, 0.09]:
    p0 = int(SR * pos)
    seg = t(0.05)
    cl2[p0:p0 + len(seg)] += np.sin(2 * np.pi * 1900 * seg) * np.exp(-seg * 90)
save("ammo_pickup", cl2, 0.5)
# Сундук появился: звон
tt = t(0.9)
save("chest_appear", sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (3 + i)) for i, f in enumerate([880, 1320, 1760])), 0.45)
# Сундук открыт: скрип петель + аккорд
n = int(SR * 0.8)
hinge = bp(rng.standard_normal(n), 500, 1600) * np.sin(np.pi * np.linspace(0, 1, n)) * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t(0.8)))
tt = t(0.8)
chord = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (2.5 + i)) * np.clip((tt - 0.25) * 20, 0, 1) for i, f in enumerate([392.0, 493.9, 587.3]))
save("chest_open", hinge * 0.5 + chord, 0.6)

# ---------------- Музыка-заглушки (блок Р, GDD 21) ----------------
# Петли 8 тактов на 120 BPM (16 с), слои одного трека одной длины: base (бас + пэд), drums (барабаны),
# full (лид + «горловой» гул). Пишет OGG в sounds/music/<трек>/<слой>.ogg (нужен ffmpeg).
# Настоящие треки — положить файлы с теми же именами, код не меняется.
import subprocess
MUSIC_OUT = os.path.join(os.path.dirname(__file__), "..", "sounds", "music")
mrng = np.random.default_rng(2101)
MSR = 32000
BPM = 120.0
BEAT = 60.0 / BPM
BARS = 8
LOOP = BEAT * 4 * BARS


def mt(dur):
    return np.linspace(0, dur, int(MSR * dur), endpoint=False)


def mlp(sig, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=MSR, output="sos"), sig)


def mhp(sig, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=MSR, output="sos"), sig)


def note_hz(n):
    """MIDI-номер → Гц."""
    return 440.0 * 2 ** ((n - 69) / 12.0)


def place(buf, sig, at):
    i = int(at * MSR) % len(buf)
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[:end - i]
    if i + len(sig) > len(buf):  # перенос хвоста в начало — петля бесшовная
        rest = i + len(sig) - len(buf)
        buf[:rest] += sig[end - i:end - i + rest]


def saw(f, dur, detune=0.0):
    tt = mt(dur)
    out = 2 * ((tt * f) % 1.0) - 1
    if detune:
        out = 0.5 * out + 0.5 * (2 * ((tt * f * (1 + detune)) % 1.0) - 1)
    return out


def adsr(n, a=0.01, r=0.1):
    e = np.ones(n)
    ai, ri = max(1, int(MSR * a)), max(1, int(MSR * r))
    e[:ai] = np.linspace(0, 1, ai)
    e[-ri:] *= np.linspace(1, 0, ri)
    return e


def kick():
    tt = mt(0.35)
    ph = 2 * np.pi * np.cumsum(np.linspace(120, 42, len(tt))) / MSR
    return np.sin(ph) * np.exp(-tt * 9) * 1.2


def snare():
    tt = mt(0.25)
    return mhp(mrng.standard_normal(len(tt)), 1500) * np.exp(-tt * 16) * 0.6 + np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 25) * 0.5


def hat():
    tt = mt(0.06)
    return mhp(mrng.standard_normal(len(tt)), 7000) * np.exp(-tt * 70) * 0.25


def tom(f):
    tt = mt(0.4)
    ph = 2 * np.pi * np.cumsum(np.linspace(f, f * 0.6, len(tt))) / MSR
    return np.sin(ph) * np.exp(-tt * 7) * 0.8


def bass_line(roots, dist=2.5, cutoff=900):
    """Восьмые ноты баса по корням тактов (MIDI), перегруз — как в darksynth."""
    buf = np.zeros(int(MSR * LOOP))
    for bar, root in enumerate(roots):
        for k in range(8):
            n = root + (12 if k in (3, 7) else 0)
            sig = saw(note_hz(n), BEAT / 2 * 0.95, 0.006) * adsr(int(MSR * BEAT / 2 * 0.95), 0.003, 0.03)
            place(buf, sig, (bar * 4 + k / 2) * BEAT)
    return np.tanh(mlp(buf, cutoff) * dist)


def pad(roots, third=3, cutoff=1400):
    buf = np.zeros(int(MSR * LOOP))
    for bar, root in enumerate(roots):
        dur = BEAT * 4
        n = int(MSR * dur)
        chord = sum(saw(note_hz(root + 12 + iv), dur, 0.01) for iv in (0, third, 7))
        place(buf, chord * adsr(n, 0.3, 0.4) * 0.25, bar * 4 * BEAT)
    return mlp(buf, cutoff)


def drums(pattern="drive", war=True):
    buf = np.zeros(int(MSR * LOOP))
    for bar in range(BARS):
        for b in range(4):
            at = (bar * 4 + b) * BEAT
            place(buf, kick(), at)
            if pattern == "drive" and b in (1, 3):
                place(buf, snare(), at)
            for h in range(2):
                place(buf, hat(), at + h * BEAT / 2)
        if war and bar % 2 == 1:  # боевые барабаны — дробь томов в конце каждого второго такта
            for k, f in enumerate([140, 120, 100, 90]):
                place(buf, tom(f), (bar * 4 + 3 + k / 4) * BEAT)
    return buf


def lead(roots, scale=(0, 3, 5, 7, 10), cutoff=3500):
    """Арпеджио-лид шестнадцатыми + горловой гул (низкий пэд с формантой)."""
    buf = np.zeros(int(MSR * LOOP))
    step = BEAT / 4
    for bar, root in enumerate(roots):
        for k in range(16):
            n = root + 24 + scale[(k * 2 + bar) % len(scale)] + (12 if k % 8 == 7 else 0)
            dur = step * 0.9
            place(buf, saw(note_hz(n), dur, 0.004) * adsr(int(MSR * dur), 0.002, 0.04) * 0.35, (bar * 4 + k / 4) * BEAT)
    drone = np.zeros(int(MSR * LOOP))
    tt = mt(LOOP)
    root = roots[0]
    drone += saw(note_hz(root - 12), LOOP, 0.003) * (0.6 + 0.4 * np.sin(2 * np.pi * tt / (BEAT * 8)))
    drone = sosfilt(butter(2, [250, 700], btype="band", fs=MSR, output="sos"), drone) * 1.2
    return mlp(buf, cutoff) + drone


def save_music(track, layer, sig, gain=0.8):
    if ONLY and not any(("music_" + track).startswith(p) or p == "music" for p in ONLY):
        return
    d = os.path.join(MUSIC_OUT, track)
    os.makedirs(d, exist_ok=True)
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * gain
    tmp = os.path.join(d, layer + ".tmp.wav")
    wavfile.write(tmp, MSR, (sig * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3", os.path.join(d, layer + ".ogg")], check=True)
    os.remove(tmp)
    print("   music", track, layer)


if not ONLY or any(p.startswith("music") for p in ONLY):
    print("Музыка…")
    # Мидгард: пульсирующий darksynth, ля минор, боевые барабаны (GDD 21)
    mid = [45, 45, 41, 43, 45, 45, 48, 43]
    save_music("midgard", "base", bass_line(mid) + pad(mid) * 0.6, 0.75)
    save_music("midgard", "drums", drums("drive", True), 0.7)
    save_music("midgard", "full", lead(mid), 0.55)
    # Ярл Бьорн: тяжелее, ре минор, более злой бас
    jarl = [38, 38, 41, 36, 38, 38, 34, 36]
    save_music("boss", "base", bass_line(jarl, 4.0, 700) + pad(jarl) * 0.5, 0.8)
    save_music("boss", "drums", drums("drive", True), 0.75)
    save_music("boss", "full", lead(jarl, (0, 1, 5, 7, 8), 4000), 0.55)
    # Ярл Бьорн (блок О): своя тема-заглушка — тяжёлый марш в до-диез миноре, «королевский» лид с хроматикой
    jt = [37, 37, 40, 35, 37, 42, 40, 35]
    save_music("jarl", "base", bass_line(jt, 4.5, 650) + pad(jt, 3, 1100) * 0.55, 0.8)
    save_music("jarl", "drums", drums("drive", True), 0.78)
    save_music("jarl", "full", lead(jt, (0, 1, 4, 7, 8), 3800), 0.55)
    # Мини-босс: короткая агрессивная петля
    mb = [40, 40, 43, 38, 40, 40, 43, 45]
    save_music("miniboss", "base", bass_line(mb, 3.5, 800), 0.8)
    save_music("miniboss", "drums", drums("drive", True), 0.75)
    # Меню: медленный ретровейв — только пэд и гул
    menu = [45, 41, 48, 43, 45, 41, 48, 43]
    save_music("menu", "base", pad(menu, 3, 900) + lead(menu, (0, 7, 12, 7, 3), 1200) * 0.25, 0.6)
    # «План тренировок»: расслабленный лоу-фай — мягкий пэд в мажоре и тихие барабаны
    plan = [48, 45, 41, 43, 48, 45, 41, 43]
    save_music("plan", "base", pad(plan, 4, 1100) + mlp(drums("soft", False), 2500) * 0.35, 0.6)
    # Ларёк: смешная «лифтовая» мелодия
    shop = [48, 53, 55, 48, 48, 53, 55, 55]
    save_music("shop", "base", pad(shop, 4, 2000) * 0.7 + lead(shop, (0, 4, 7, 12, 9), 2600) * 0.6, 0.6)
    # Стингер удара-приземления: бас-удар + тарелка
    tt = mt(1.6)
    st = np.tanh(np.sin(2 * np.pi * np.cumsum(np.linspace(90, 35, len(tt))) / MSR) * np.exp(-tt * 3) * 3) + mhp(mrng.standard_normal(len(tt)), 5000) * np.exp(-tt * 2.5) * 0.3
    save_music("stingers", "slam", st, 0.9)
# --- Блок К: серебро и ларёк ---
# Монета: короткий высокий «динь»
tt = t(0.25)
save("coin_pickup", sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (18 + i * 6)) for i, f in enumerate([2637.0, 3520.0, 5274.0])), 0.4)
# Покупка: звон монет + колокольчик кассы
n = int(SR * 0.7)
jingle = np.zeros(n)
for pos in [0.0, 0.05, 0.11, 0.16]:
    p0 = int(SR * pos)
    seg = t(0.18)
    jingle[p0:p0 + len(seg)] += sum(np.sin(2 * np.pi * f * seg) * np.exp(-seg * 30) for f in [2400 + pos * 3000, 3300 + pos * 2000]) * 0.5
tt = t(0.7)
bell = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * (4 + i)) * np.clip((tt - 0.2) * 30, 0, 1) for i, f in enumerate([1318.5, 1975.5]))
save("shop_buy", jingle + bell * 0.6, 0.55)
# Нет денег: низкое «бу-бу»
tt = t(0.4)
buzz = np.sign(np.sin(2 * np.pi * 110 * tt)) * 0.3 * env(len(tt), 0.01, 1.5)
save("shop_broke", mix(lp(buzz, 900), thump(0.2, 140, 90) * 0.5), 0.45)
# Бочка разбилась: треск досок + глухой удар
n = int(SR * 0.45)
crack = bp(rng.standard_normal(n), 800, 4000) * env(n, 0.001, 4.0)
for pos in [0.03, 0.08, 0.15]:
    p0 = int(SR * pos)
    m = int(SR * 0.04)
    crack[p0:p0 + m] += bp(rng.standard_normal(m), 1500, 6000) * np.exp(-np.linspace(0, 6, m))
save("barrel_break", mix(crack, thump(0.3, 160, 60) * 0.8), 0.7)

# --- Блок Ф: испытания ---
# Старт испытания: рог (две ноты)
tt = t(0.9)
horn = sum(np.sin(2 * np.pi * f * h * tt) / (h * h) for h in range(1, 6) for f in [196.0]) * np.clip(tt * 8, 0, 1) * np.exp(-np.maximum(tt - 0.6, 0) * 8)
save("trial_start", lp(horn, 2500), 0.6)
# Испытание пройдено: восходящий аккорд
tt = t(1.1)
win = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * 2.5) * np.clip((tt - i * 0.09) * 40, 0, 1) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]))
save("trial_win", win, 0.55)
# Провал: «ва-ва-ваа» вниз
n = int(SR * 1.0)
tt = t(1.0)
freq = np.concatenate([np.full(int(SR * 0.25), 330.0), np.full(int(SR * 0.25), 311.0), np.linspace(294.0, 240.0, n - int(SR * 0.5))])
saw = 2 * ((np.cumsum(freq) / SR) % 1.0) - 1
save("trial_fail", lp(saw, 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * tt)) * env(n, 0.01, 0.8), 0.5)

print("Готово:", OUT)
