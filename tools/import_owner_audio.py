#!/usr/bin/env python3
"""Звук владельца (ElevenLabs, блок Б6) → файлы игры. Запуск из корня проекта:
    python3 tools/import_owner_audio.py <папка архива владельца> [--only music sfx voice]
В папке — music/*.mp3 (петли 30 с), sfx/*.mp3, voice/*.mp3 и manifest.json (промпты и тексты).

Пишет OGG Vorbis 44.1 кГц туда, куда синтез (tools/make_sfx.py) не пишет, — его повторный запуск их не трогает:
  sounds/owner/music/<трек>/base|drums|full.ogg — слои из одной петли: full = оригинал, drums и base —
      НЧ-фильтр (срез LAYERS) нулевой фазы по кругу: слои в фазе с оригиналом (перекрёстная смена без
      провала), стык петли без щелчка, длина та же; full ≈ MUSIC_LUFS, слои тише на LAYERS[..][2];
  sounds/owner/sfx/<имя>.ogg — моно, тишина в начале и длинные хвосты срезаны, пик ≤ SFX_PEAK_DB
      и не громче синтеза, который заменяет (потолок громкости самых громких 300 мс — SFX);
  sounds/voice/<имя>.ogg — моно, тишина срезана, ≈ VOICE_LUFS.
Что чем играется в игре — data/owner_audio.json (правится руками).
Импорт Godot: петлям музыки — loop=true в .import (Music и так включает петлю при загрузке)."""
import json
import os
import re
import subprocess
import sys

import numpy as np
from scipy.signal import butter, resample_poly, sosfiltfilt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SR = 44100

# Файл архива → трек игры
MUSIC = {
    "music_midgard_test": "midgard",
    "music_jarl": "jarl",
    "music_shop": "shop",
    "music_jotunheim": "jotunheim",  # будущие миры: в экспорт не идут (export_presets.cfg)
    "music_helheim": "helheim",
}
# Петли владельца ≈ −14 LUFS (шина Music ещё −6 дБ): ниже голоса (−16 LUFS на шине 0 дБ), чтобы реплики
# было слышно в бою. Синтез-заглушки были громче (фон ≈ −9 LUFS) — громкость музыки правится Music.volume_db.
MUSIC_LUFS = -14.0
MUSIC_PEAK_DB = -1.0
# Сколько дБ пиков можно срезать лимитером (по кругу — стык петли не страдает), чтобы дотянуть до MUSIC_LUFS
MUSIC_MAX_LIMIT_DB = 3.0
# Слои: (срез НЧ-фильтра Гц или None, порядок Баттерворта, громкость относительно full дБ, качество Vorbis)
LAYERS = {
    "base": (1000.0, 2, -2.5, 3),
    "drums": (3800.0, 2, -1.0, 3),
    "full": (None, 0, 0.0, 4),
}

SFX_PEAK_DB = -1.0
# Сколько дБ пиков можно срезать лимитером, чтобы дотянуть тихий звук до потолка громкости
SFX_MAX_LIMIT_DB = 4.0
# Потолок громкости по самым громким 300 мс (дБFS), если у звука не задан свой
SFX_MAX_RMS_DB = -14.0
SFX_QUALITY = 4
# Особые случаи: max_ms — обрезать до (с плавным хвостом); rms — потолок громкости самых громких 300 мс (дБFS),
# подобран по синтезу, который звук заменяет (в скобках — его уровень), чтобы ничего не стало вдвое громче
SFX = {
    "axe_swing": {"max_ms": 450, "rms": -17.0},        # axe_swing_1..3 (−18…−19)
    "axe_hit_flesh": {"max_ms": 600, "rms": -14.0},    # axe_hit_1..3 (−14.3…−15.1), axe_finisher (−13.9)
    "hammer_throw": {"rms": -14.0},                    # hammer_throw (−14.6)
    "hammer_catch": {"max_ms": 900, "rms": -16.0},     # hammer_catch (−17.1)
    "hammer_impact": {"max_ms": 1200, "rms": -14.0},   # hammer_hit (−15.4)
    "ground_slam": {"rms": -9.0},                      # slam (−8.0)
    "dash": {"max_ms": 600, "rms": -18.0},             # dash (−18.9)
    "double_jump": {"max_ms": 650, "rms": -21.0},      # новый: двойной прыжок (был jump_b/jump_c −25)
    "zombie_groan": {"rms": -19.0},                    # новый: замах нежити (был enemy_growl −18.7)
    "zombie_death": {"rms": -12.0},                    # новый: смерть нежити (был enemy_destroy.ogg −7.2)
    "bloater_explode": {"rms": -10.0},                 # новый: взрывы Blast (был boss_slam −6.4)
    "crossbow_fire": {"rms": -15.0},                   # crossbow_fire (−15.3)
    "chain_lightning": {"max_ms": 1000, "rms": -20.0}, # lightning (−24.1, редкий треск)
    "coin_pickup": {"max_ms": 600, "rms": -23.0},      # coin_pickup (−25.3)
    "rune_pickup": {"rms": -17.0},                     # rune_pick (−18.4)
    "stone_door_open": {"rms": -13.0},                 # door_open (−11.4)
    "coach_whistle": {"rms": -18.0},                   # новый: свисток Одина в репликах
    "barrel_smash": {"max_ms": 900, "rms": -16.0},     # barrel_break (−19.0)
    "helmet_bonk": {"rms": -16.0},                     # новый: прыжок по головам (jump_b −25), броня элиты (hammer_bounce −20.6)
    "critical_hit": {"max_ms": 900, "rms": -15.0},     # новый: крит поверх звука удара
}

VOICE_LUFS = -16.0
VOICE_PEAK_DB = -1.5
VOICE_QUALITY = 4
# Кряхтение и «Ух!» в архиве — по два дубля подряд (пауза ~300 мс): берём первый
VOICE = {
    "thor_grunt_hha": {"max_ms": 560},
    "thor_pain_uh": {"max_ms": 560},
}


def decode(path, ch):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).reshape(-1, ch).astype(np.float64)


def _pipe_args(x):
    return ["-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-"]


def loudness(x):
    """Интегральная громкость (LUFS) — ffmpeg loudnorm, первый проход."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats"] + _pipe_args(x) + ["-af", "loudnorm=print_format=json", "-f", "null", "-"],
                       input=x.astype(np.float32).tobytes(), capture_output=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr.decode("utf-8", "replace"), re.S)
    return float(json.loads(m.group(0))["input_i"])


def true_peak_db(x):
    """Пик с 4-кратной передискретизацией (≈ dBTP)."""
    up = resample_poly(x, 4, 1, axis=0)
    return 20 * np.log10(np.abs(up).max() + 1e-12)


def moving_mean(v, w):
    """Скользящее среднее окна w (через накопленную сумму — быстро на длинных петлях), длина len(v) - w + 1."""
    cs = np.concatenate([[0.0], np.cumsum(v)])
    return (cs[w:] - cs[:-w]) / w


def rms300_db(x):
    m = x.mean(axis=1)
    w = int(SR * 0.3)
    if len(m) <= w:
        return 10 * np.log10((m ** 2).mean() + 1e-12)
    return 10 * np.log10(moving_mean(m ** 2, w).max() + 1e-12)


def envelope(m, ms):
    """Огибающая (RMS окна ms), той же длины, что сигнал."""
    w = max(1, int(SR * ms / 1000))
    e = moving_mean(np.concatenate([np.zeros(w // 2), m ** 2, np.zeros(w - w // 2 - 1)]), w)
    return np.sqrt(np.maximum(e, 0.0))


def encode(x, path, quality):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-v", "error"] + _pipe_args(x) + ["-c:a", "libvorbis", "-q:a", str(quality), path],
                   input=np.clip(x, -1.0, 1.0).astype(np.float32).tobytes(), check=True)


def circular_limit(x, peak_db):
    """Лимитер по кругу для петли: [x x x] → середина, огибающая на стыке непрерывна."""
    n = len(x)
    return limit(np.concatenate([x, x, x], axis=0), peak_db)[n:2 * n]


def limit(x, peak_db):
    """Мягкий пиковый лимитер ffmpeg (alimiter, с компенсацией задержки): поднять тихое без клиппинга."""
    lim = 10 ** ((peak_db - 0.5) / 20)  # запас на межсэмпловые пики
    r = subprocess.run(["ffmpeg", "-v", "error"] + _pipe_args(x) + ["-af", "alimiter=limit=%.4f:attack=1:release=40:level=disabled:latency=1" % lim,
                        "-f", "f32le", "-"], input=x.astype(np.float32).tobytes(), capture_output=True, check=True)
    y = np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, x.shape[1]).astype(np.float64)
    out = np.zeros_like(x)
    out[:min(len(x), len(y))] = y[:len(x)]
    tp = true_peak_db(out)
    if tp > peak_db:
        out *= 10 ** ((peak_db - tp) / 20)
    return out


def trim(x, head_db=-36.0, tail_db=-50.0, pre_ms=2.0, post_ms=30.0, max_ms=None, fade_ms=30.0):
    """Тишину в начале — до первой атаки (минус pre_ms), хвост — где огибающая ниже tail_db от пика."""
    env_fast = envelope(x.mean(axis=1), 1.0)
    start = int(np.argmax(env_fast > env_fast.max() * 10 ** (head_db / 20)))
    start = max(0, start - int(SR * pre_ms / 1000))
    env = envelope(x.mean(axis=1), 10.0)
    above = np.where(env > env.max() * 10 ** (tail_db / 20))[0]
    end = min(len(x), int(above[-1]) + int(SR * post_ms / 1000)) if len(above) else len(x)
    if max_ms:
        end = min(end, start + int(SR * max_ms / 1000))
    y = x[start:end].copy()
    fi = min(len(y), int(SR * 0.002))
    y[:fi] *= np.linspace(0, 1, fi)[:, None]
    fo = min(len(y) // 3, int(SR * fade_ms / 1000))
    if fo > 0:
        y[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    return y, start, end


def circular_lowpass(x, cutoff, order):
    """НЧ-фильтр нулевой фазы по кругу: петля [x x x] → середина. Длина та же, стык бесшовный, фаза не сдвинута."""
    sos = butter(order, cutoff, btype="low", fs=SR, output="sos")
    tiled = np.concatenate([x, x, x], axis=0)
    y = sosfiltfilt(sos, tiled, axis=0)
    n = len(x)
    return y[n:2 * n]


def do_music(src):
    for name, track in MUSIC.items():
        path = os.path.join(src, "music", name + ".mp3")
        if not os.path.exists(path):
            print("  нет", path)
            continue
        x = decode(path, 2)
        out_dir = os.path.join(ROOT, "sounds", "owner", "music", track)
        print("  music %-10s %.3f с, %d сэмплов, исходник %.1f LUFS" % (track, len(x) / SR, len(x), loudness(x)), flush=True)
        for layer, (cut, order, rel_db, q) in LAYERS.items():
            y = circular_lowpass(x, cut, order) if cut else x.copy()
            # Громкость слоя: full — MUSIC_LUFS; отфильтрованные — на rel_db тише
            g = (MUSIC_LUFS + rel_db) - loudness(y)
            g = min(g, MUSIC_PEAK_DB + MUSIC_MAX_LIMIT_DB - true_peak_db(y))
            y = y * 10 ** (g / 20)
            if true_peak_db(y) > MUSIC_PEAK_DB:
                y = circular_limit(y, MUSIC_PEAK_DB)
            encode(y, os.path.join(out_dir, layer + ".ogg"), q)
            print("     %-5s %-10s %.1f LUFS, пик %.1f дБTP" % (layer, ("НЧ %d Гц" % cut) if cut else "оригинал", loudness(y), true_peak_db(y)), flush=True)


def do_sfx(src):
    for name, opt in SFX.items():
        path = os.path.join(src, "sfx", name + ".mp3")
        if not os.path.exists(path):
            print("  нет", path)
            continue
        x = decode(path, 1)
        y, s, e = trim(x, max_ms=opt.get("max_ms"))
        g_peak = SFX_PEAK_DB - true_peak_db(y)
        g_rms = opt.get("rms", SFX_MAX_RMS_DB) - rms300_db(y)
        g = min(g_peak + SFX_MAX_LIMIT_DB, g_rms)
        y = y * 10 ** (g / 20)
        if true_peak_db(y) > SFX_PEAK_DB:
            y = limit(y, SFX_PEAK_DB)
        encode(y, os.path.join(ROOT, "sounds", "owner", "sfx", name + ".ogg"), SFX_QUALITY)
        print("  sfx %-16s %4d..%4d мс (из %4d) %+5.1f дБ → пик %5.1f дБTP, 300 мс %5.1f дБ" % (
            name, s * 1000 // SR, e * 1000 // SR, len(x) * 1000 // SR, g, true_peak_db(y), rms300_db(y)), flush=True)


def do_voice(src):
    for f in sorted(os.listdir(os.path.join(src, "voice"))):
        if not f.endswith(".mp3"):
            continue
        name = f[:-4]
        x = decode(os.path.join(src, "voice", f), 1)
        y, s, e = trim(x, head_db=-40.0, tail_db=-48.0, pre_ms=8.0, post_ms=60.0, fade_ms=40.0,
                       max_ms=VOICE.get(name, {}).get("max_ms"))
        g = VOICE_LUFS - loudness(y)
        y = y * 10 ** (g / 20)
        if true_peak_db(y) > VOICE_PEAK_DB:
            y = limit(y, VOICE_PEAK_DB)
        encode(y, os.path.join(ROOT, "sounds", "voice", name + ".ogg"), VOICE_QUALITY)
        print("  voice %-26s %4d..%4d мс (из %4d) → %.1f LUFS, пик %.1f дБTP" % (
            name, s * 1000 // SR, e * 1000 // SR, len(x) * 1000 // SR, loudness(y), true_peak_db(y)), flush=True)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    only = args[args.index("--only") + 1:] if "--only" in args else ["music", "sfx", "voice"]
    if "music" in only:
        do_music(src)
    if "sfx" in only:
        do_sfx(src)
    if "voice" in only:
        do_voice(src)


if __name__ == "__main__":
    main()
