#!/usr/bin/env python3
"""Classify Godot diagnostics even when stdout and stderr share a line."""

import argparse
import re
from pathlib import Path


ERROR_MARKER = re.compile(r"SCRIPT ERROR|ERROR:|Parse Error")
RESOURCE_ERROR = re.compile(r"^ERROR: (\d+) resources still in use at exit(?=$|[.\s])")


def _markers(line):
    markers = list(ERROR_MARKER.finditer(line))
    for index, marker in enumerate(markers):
        end = markers[index + 1].start() if index + 1 < len(markers) else len(line)
        yield marker.start(), line[marker.start():end]


def _expected(message, scene):
    if RESOURCE_ERROR.match(message):
        return True
    if scene == "save_test" and message.startswith("ERROR: Parse JSON failed."):
        return True
    if scene == "generator_test" and re.match(r"^ERROR: build_scenes: .*ручная сцена", message):
        return True
    return False


def classify(text, scene=""):
    """Return full expected/unexpected lines and each resource diagnostic count.

    A mixed line can belong to both lists. Do not let an expected diagnostic
    mask another ERROR: or SCRIPT ERROR on that same line.
    """
    expected, unexpected, resources = [], [], []
    for line in text.splitlines():
        has_expected = has_unexpected = False
        for _, message in _markers(line):
            if _expected(message, scene):
                has_expected = True
                match = RESOURCE_ERROR.match(message)
                if match:
                    resources.append(int(match.group(1)))
            else:
                has_unexpected = True
        if has_expected:
            expected.append(line)
        if has_unexpected:
            unexpected.append(line)
    return expected, unexpected, resources


def write_lines(path, lines):
    Path(path).write_text("".join(line + "\n" for line in lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["suite"])
    parser.add_argument("log")
    parser.add_argument("scene")
    parser.add_argument("expected")
    parser.add_argument("unexpected")
    args = parser.parse_args()
    text = Path(args.log).read_text(encoding="utf-8", errors="replace")
    expected, unexpected, _ = classify(text, args.scene)
    write_lines(args.expected, expected)
    write_lines(args.unexpected, unexpected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
