#!/usr/bin/env python3
"""Classify Godot diagnostics even when stdout and stderr share a line."""

import argparse
import re
from pathlib import Path


ERROR_MARKER = re.compile(r"SCRIPT ERROR|ERROR:|Parse Error")
RESOURCE_ERROR = re.compile(r"^ERROR: (\d+) resources still in use at exit(?=$|[.\s])")
RESULT_MARKER = "RENDER PREFETCH RESULT:"


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


def render_classify(text):
    """Separate errors before the result marker and expected cleanup messages."""
    runtime, cleanup_expected, cleanup_unexpected = [], [], []
    runtime_count = cleanup_count = cleanup_unexpected_count = 0
    result_seen = False
    for line in text.splitlines():
        result_pos = line.find(RESULT_MARKER) if not result_seen else -1
        has_runtime = has_expected = has_unexpected = False
        for pos, message in _markers(line):
            cleanup = result_seen or (result_pos >= 0 and pos > result_pos)
            if not cleanup:
                has_runtime = True
            else:
                if _expected(message, ""):
                    has_expected = True
                else:
                    has_unexpected = True
        if has_runtime:
            runtime_count += 1
            runtime.append(line)
        if has_expected:
            cleanup_expected.append(line)
        if has_unexpected:
            cleanup_unexpected.append(line)
            cleanup_unexpected_count += 1
        if has_expected or has_unexpected:
            cleanup_count += 1
        if result_pos >= 0:
            result_seen = True
    return (runtime, cleanup_expected, cleanup_unexpected,
            runtime_count, cleanup_count, cleanup_unexpected_count)


def hitch_errors(text):
    return [line for line in text.splitlines()
            if ERROR_MARKER.search(line) or "HITCH FAIL" in line]


def write_lines(path, lines):
    Path(path).write_text("".join(line + "\n" for line in lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_subparsers(dest="mode", required=True)
    suite = modes.add_parser("suite")
    suite.add_argument("log")
    suite.add_argument("scene")
    suite.add_argument("expected")
    suite.add_argument("unexpected")
    render = modes.add_parser("render")
    render.add_argument("log")
    render.add_argument("output_dir")
    hitch = modes.add_parser("hitch")
    hitch.add_argument("log")
    hitch.add_argument("errors")
    args = parser.parse_args()
    text = Path(args.log).read_text(encoding="utf-8", errors="replace")
    if args.mode == "suite":
        expected, unexpected, _ = classify(text, args.scene)
        write_lines(args.expected, expected)
        write_lines(args.unexpected, unexpected)
    elif args.mode == "render":
        runtime, expected, unexpected, n_runtime, n_cleanup, n_unexpected = render_classify(text)
        out = Path(args.output_dir)
        write_lines(out / "runtime-errors.log", runtime)
        write_lines(out / "cleanup-expected-errors.log", expected)
        write_lines(out / "cleanup-unexpected-errors.log", unexpected)
        print(n_runtime, n_cleanup, n_unexpected)
    else:
        errors = hitch_errors(text)
        write_lines(args.errors, errors)
        return 1 if errors else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
