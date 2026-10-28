#!/usr/bin/env python3
"""Run the tagged Windows build under Wine, bounded and with strict diagnostics."""
from __future__ import annotations

import os
from pathlib import Path
import re
import signal
import sys
import threading

sys.dont_write_bytecode = True
from godot_log_check import classify  # noqa: E402
from run_test_suite import FAILURE, _grep_log, run_logged  # noqa: E402

SUCCESS = re.compile(r"^SELFTEST OK\b[^\r\n]*\benemies=[1-9][0-9]*\b", re.MULTILINE)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: ci_windows_selftest.py <exe> <new-output-dir>", file=sys.stderr)
        return 2
    try:
        exe = Path(argv[0]).resolve(strict=True)
        if not exe.is_file():
            raise ValueError("Selftest executable is not a file")
        output = Path(argv[1])
        if output.is_symlink():
            raise ValueError("Output path is a symlink")
        output.mkdir(parents=True, exist_ok=False)
        output = output.resolve(strict=True)
    except (OSError, ValueError) as exc:
        print(f"Cannot prepare Wine selftest: {exc}", file=sys.stderr)
        return 2

    env = os.environ.copy()
    env.update({"WINEPREFIX": str(output / "wine-prefix"), "WINEARCH": "win64", "WINEDEBUG": "-all"})
    stop = threading.Event()
    received = [0]

    def handle(signum: int, _frame: object) -> None:
        received[0] = signum
        stop.set()

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, handle)
    log = output / "selftest.log"
    try:
        code, overflow, interrupted = run_logged(
            ["wine", str(exe), "--headless", "--", "--selftest"],
            cwd=Path.cwd(), env=env, log=log, seconds=300, stop=stop)
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
        failures = _grep_log(FAILURE + r"|SELFTEST FAIL", log, output / "selftest.failures", env, stop)
        expected, unexpected, _ = classify(text)
        (output / "selftest.expected-errors").write_text("".join(x + "\n" for x in expected), encoding="utf-8")
        (output / "selftest.godot-errors").write_text("".join(x + "\n" for x in unexpected), encoding="utf-8")
        if expected:
            print("NOTE: expected shutdown diagnostics saved in selftest.expected-errors")
        if code or overflow or interrupted or failures or unexpected or not SUCCESS.search(text):
            print(f"Wine selftest failed: exit={code}, cap={int(overflow)}, log={log}", file=sys.stderr)
            return 128 + received[0] if received[0] else 1
        print("Windows Wine selftest passed with at least one enemy.")
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"Wine selftest error: {exc}", file=sys.stderr)
        return 128 + received[0] if received[0] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
