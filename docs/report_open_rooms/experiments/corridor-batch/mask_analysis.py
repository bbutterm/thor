#!/usr/bin/env python3
"""Перепроверить маски двух контрольных ракурсов сохранённого эксперимента."""
from pathlib import Path
from PIL import Image, ImageChops


def mask(a, b):
    data_a = a.get_flattened_data() if hasattr(a, "get_flattened_data") else a.getdata()
    data_b = b.get_flattened_data() if hasattr(b, "get_flattened_data") else b.getdata()
    return {i for i, (left, right) in enumerate(zip(data_a, data_b)) if left != right}


def main():
    folder = Path(__file__).resolve().parent
    images = {}
    for name in ("floor_original", "floor_rows", "floor_sides", "floor_hidden", "entrance_original", "entrance_hidden"):
        with Image.open(folder / f"{name}.png") as image:
            images[name] = image.convert("RGB")
    original, rows = images["floor_original"], images["floor_rows"]
    sides, hidden = images["floor_sides"], images["floor_hidden"]
    batch_delta = mask(original, rows)
    hide_delta = mask(sides, hidden)
    print(f"floor original → rows: {len(batch_delta)} pixels, bbox {ImageChops.difference(original, rows).getbbox()}")
    print(f"floor rows → sides: {len(mask(rows, sides))} pixels")
    print(f"floor sides → hidden: {len(hide_delta)} pixels, bbox {ImageChops.difference(sides, hidden).getbbox()}")
    print(f"intersection of candidate and hidden deltas: {len(batch_delta & hide_delta)} pixels")
    print(f"entrance original → hidden: {len(mask(images['entrance_original'], images['entrance_hidden']))} pixels")


if __name__ == "__main__":
    main()
