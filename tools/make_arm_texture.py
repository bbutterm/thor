#!/usr/bin/env python3
"""Текстура рук Тора из CC0-текстуры Drillimpact (assets/arms/drillimpact_psx/arms_01.png).

- Тон кожи выравнивается к нейтральному светлому: цвет задаёт тело (BodyDef.hand_color → albedo_color).
- Татуировки-кольца (плетёнка в духе портрета Тора) на предплечье и плече.
UV руки: нижняя половина листа — полоса вдоль руки (u: 0 — плечо, ~0.95 — запястье, v — по кругу);
верхняя половина — кисти.

python3 tools/make_arm_texture.py
"""
import math
import os

from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "arms", "drillimpact_psx")
SRC = os.path.join(ROOT, "arms_01.png")
DST = os.path.join(ROOT, "thor_arm.png")

# Полоса руки в пикселях листа 512×512 (по arms_uv.png)
STRIP_Y0, STRIP_Y1 = 287, 502
# Кольца татуировок: (u0, u1) — доли ширины листа
BANDS = [(0.575, 0.645), (0.20, 0.285)]
INK = (40, 50, 68)


def neutralize(img: Image.Image) -> Image.Image:
    px = img.load()
    w, h = img.size
    # Средний цвет кожи по полосе руки
    sr = sg = sb = n = 0
    for y in range(STRIP_Y0, STRIP_Y1, 3):
        for x in range(20, 490, 3):
            r, g, b = px[x, y][:3]
            sr += r; sg += g; sb += b; n += 1
    mr, mg, mb = sr / n, sg / n, sb / n
    target = 188.0  # светлый нейтральный тон: albedo_color тела задаёт оттенок
    out = Image.new("RGB", (w, h))
    po = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            # Яркостная вариация сохраняется, оттенок уходит к нейтральному (немного тепла остаётся)
            nr, ng, nb = r / mr * target, g / mg * target, b / mb * target
            lum = (nr + ng + nb) / 3.0
            k = 0.6
            po[x, y] = tuple(int(max(0, min(255, lum * k + c * (1 - k)))) for c in (nr, ng, nb))
    return out


def band_mask(w: int, h: int, u0: float, u1: float) -> Image.Image:
    """Маска кольца: две каймы по краям и две переплетённые волны между ними."""
    m = Image.new("L", (w, h), 0)
    pm = m.load()
    x0, x1 = int(u0 * w), int(u1 * w)
    bw = x1 - x0
    period = (STRIP_Y1 - STRIP_Y0) / 6.0  # 6 узлов по кругу руки
    for y in range(STRIP_Y0, STRIP_Y1):
        t = (y - STRIP_Y0) / period * 2 * math.pi
        for x in range(x0, x1):
            f = (x - x0) / bw  # 0..1 поперёк кольца
            a = 0.0
            # Каймы
            if f < 0.1 or f > 0.9:
                a = 1.0
            else:
                g = (f - 0.1) / 0.8
                w1 = 0.5 + 0.38 * math.sin(t)
                w2 = 0.5 - 0.38 * math.sin(t)
                d1 = abs(g - w1)
                d2 = abs(g - w2)
                th = 0.085
                # «Переплетение»: в точках пересечения одна волна прерывается
                over = math.cos(t) > 0
                if d1 < th and (over or d2 > th * 1.8):
                    a = 1.0
                if d2 < th and (not over or d1 > th * 1.8):
                    a = 1.0
            if a > 0:
                pm[x, y] = int(255 * a)
    return m.filter(ImageFilter.GaussianBlur(0.8))


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    img = neutralize(src)
    w, h = img.size
    ink = Image.new("RGB", (w, h), INK)
    for u0, u1 in BANDS:
        mask = band_mask(w, h, u0, u1).point(lambda v: int(v * 0.88))
        img = Image.composite(ink, img, mask)
    img.save(DST)
    print("saved", DST)


if __name__ == "__main__":
    main()
