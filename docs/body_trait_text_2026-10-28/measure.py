#!/usr/bin/env python3
"""Conservative static text estimate; run from Thor project root, needs Pillow.

The engine's actual layout still requires tests/trait_test.tscn.
"""
import re
import sys
from pathlib import Path

from PIL import ImageFont

sys.path.insert(0, str(Path.cwd()))
from tools.i18n_extract import read_po

PO = read_po("data/i18n/en.po")
FONT = "fonts/RussoOne-Regular.ttf"
WIDTH = 200 * 340 / 390
HEIGHT = 222 * 340 / 390


def font(size):
    return ImageFont.truetype(FONT, size)


def wrap(text, size, width):
    f = font(size)
    result, current = [], ""
    for word in text.split():
        if f.getlength(word) > width:
            raise ValueError(f"word exceeds estimated width {width}: {word!r}")
        trial = (current + " " + word).strip()
        if current and f.getlength(trial) > width:
            result.append(current)
            current = word
        else:
            current = trial
    if current:
        result.append(current)
    return result


def trait_estimate(title, category, description, status):
    for step in range(12):
        total = 6
        for text, preferred, floor, outline in zip(
            [title, category, description, status], [19, 13, 13, 15],
            [14, 10, 9, 10], [5, 3, 3, 4]
        ):
            size = max(min(floor, preferred), preferred - step)
            ascent, descent = font(size).getmetrics()
            total += len(wrap(text, size, WIDTH)) * (ascent + descent) + 2 * outline
        if total <= HEIGHT - 8:
            return total, step
    raise ValueError(f"estimated overflow: {title}")


for name in ["hammer_dive", "hammer_step"]:
    text = Path(f"weapons/mjolnir_traits/{name}.tres").read_text(encoding="utf-8")
    vals = dict(re.findall(r'^(title|description|description_lvl2) = "(.*)"$', text, re.M))
    for language in ["ru", "en"]:
        for level, field in [(1, "description"), (2, "description_lvl2")]:
            title, description = vals["title"], vals[field]
            category, status = "ПРИЁМ", "НОВЫЙ" if level == 1 else "УРОВЕНЬ 2"
            if language == "en":
                title, description = PO[title], PO[description]
                category = PO["ПРИЁМ"]
                status = PO["НОВЫЙ"] if level == 1 else PO["УРОВЕНЬ %d"] % 2
            total, step = trait_estimate(title, category, description, status)
            print(f"{name} {language} level {level}: estimated {total:.0f}/{HEIGHT - 8:.1f}px, fit step {step}")

for path in ["run/passives/berserker_flaw.tres", "run/passives/smith_level.tres"]:
    data = Path(path).read_text(encoding="utf-8")
    ru = re.search(r'^description = "(.*)"$', data, re.M).group(1)
    for language, text in [("ru", ru), ("en", PO[ru])]:
        wrapped = wrap(text, 16, 340 - 6)
        maximum = max(font(16).getlength(line) for line in wrapped)
        print(f"{path} {language}: {len(wrapped)} lines; estimated width {maximum:.1f}/334px")
