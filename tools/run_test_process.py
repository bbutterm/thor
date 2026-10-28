#!/usr/bin/env python3
"""Supervise a test process group, including on unexpected runner death (Linux)."""
from __future__ import annotations

import ctypes
import os
import signal
import subprocess
import sys
import time

PR_SET_PDEATHSIG = 1
SHUTDOWN_GRACE = 1.0


def main() -> int:
    if len(sys.argv) < 3:
        return 2
    parent = int(sys.argv[1])
    stopping = [False]

    def stop(_signum: int, _frame: object) -> None:
        stopping[0] = True

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, stop)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0) != 0:
        print(f"Unable to set parent-death signal: errno {ctypes.get_errno()}", file=sys.stderr)
        return 126
    # Parent can die in the interval before prctl; never start an orphan test.
    if os.getppid() != parent or stopping[0]:
        return 143
    try:
        child = subprocess.Popen(sys.argv[2:])
    except OSError as error:
        print(f"Unable to start test: {error}", file=sys.stderr)
        return 126
    while True:
        if stopping[0]:
            # The parent started us in a new process group. First give all
            # members a chance to stop; then kill the entire group, including
            # this supervisor, even if Godot left descendants behind.
            for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                signal.signal(sig, signal.SIG_IGN)
            os.killpg(os.getpgrp(), signal.SIGTERM)
            time.sleep(SHUTDOWN_GRACE)
            os.killpg(os.getpgrp(), signal.SIGKILL)
            return 137  # Unreachable unless delivery failed.
        try:
            code = child.wait(timeout=0.1)
            if not stopping[0]:
                return 128 - code if code < 0 else code
        except subprocess.TimeoutExpired:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
