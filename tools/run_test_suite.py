#!/usr/bin/env python3
"""Run every headless test in isolated profiles; THOR_TEST_JOBS=1..8.

The results and summary retain scene order even when subprocesses run in
parallel. Every child has its own process group for timeout/signal cleanup.
"""
from __future__ import annotations

import concurrent.futures
import locale
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_log_check import classify  # noqa: E402

MAX_LOG_BYTES = 50_000_000
IMPORT_TIMEOUT = 1200.0
TEST_TIMEOUT = 300.0
TERMINATE_GRACE = 10.0
FAILURE = r"SCRIPT ERROR|Parse Error|\[FAIL\]|^[[:space:]]*FAIL:|HITCH FAIL|(^|[^0-9])[1-9][0-9]*[[:space:]]+FAIL([[:space:]=]|$)"
IMPORT_ERROR = r"ERROR:|SCRIPT ERROR|Parse Error"


def _kill_group(process: subprocess.Popen[bytes], sig: int) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def run_logged(command: list[str], *, cwd: Path, env: dict[str, str], log: Path,
               seconds: float, stop: threading.Event,
               max_bytes: int | None = MAX_LOG_BYTES) -> tuple[int, bool, bool]:
    """Return (exit code, overflow, interrupted); kill the process group on abort.

    Child output is retained up to max_bytes, even if it ignores SIGTERM.
    A None cap is reserved for the original grep failure listing.
    A new session keeps timeout/cancellation away from the parent shell.
    """
    if stop.is_set():
        return 130, False, True
    supervisor = Path(__file__).resolve().with_name("run_test_process.py")
    wrapped = [sys.executable, str(supervisor), str(os.getpid()), *command]
    process = subprocess.Popen(wrapped, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    assert process.stdout is not None
    selector = None
    start = time.monotonic()
    terminating = None
    forced = False
    overflow = timed_out = interrupted = False
    written = 0
    try:
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        with log.open("wb") as sink:
            while True:
                now = time.monotonic()
                if stop.is_set():
                    interrupted = True
                if now - start >= seconds:
                    timed_out = True
                if (interrupted or timed_out or overflow) and terminating is None:
                    terminating = now
                    _kill_group(process, signal.SIGTERM)
                if terminating is not None and not forced and now - terminating >= TERMINATE_GRACE:
                    _kill_group(process, signal.SIGKILL)
                    forced = True
                if not selector.get_map() and process.poll() is not None:
                    break
                if selector.get_map():
                    for key, _ in selector.select(0.1):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        keep = chunk if max_bytes is None else chunk[:max(0, max_bytes - written)]
                        if keep:
                            sink.write(keep)
                            written += len(keep)
                        if len(chunk) > len(keep):
                            overflow = True
                else:
                    time.sleep(0.05)
        code = process.wait()
    except BaseException:
        _kill_group(process, signal.SIGKILL)
        process.wait()
        raise
    finally:
        if selector is not None:
            selector.close()
        process.stdout.close()
    if timed_out:
        code = 124
    elif code < 0:
        code = 128 - code
    return code, overflow, interrupted


def _write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")


def _profile_environment(out: Path, name: str, shim: Path) -> dict[str, str]:
    root = out / "import-data" if name == "import" else out / "user" / name
    for child in ("cache", "config", "Desktop"):
        (root / child).mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "XDG_DATA_HOME": str(root),
        "XDG_CACHE_HOME": str(root / "cache"),
        "XDG_CONFIG_HOME": str(root / "config"),
        "THOR_SUITE_DESKTOP": str(root / "Desktop"),
        "THOR_SUITE_ORIGINAL_PATH": os.environ.get("PATH", ""),
        # Godot on Linux invokes xdg-user-dir through execvp. The shim makes
        # F5/report_test use a unique temporary desktop regardless of host setup.
        "PATH": str(shim) + os.pathsep + os.environ.get("PATH", ""),
    })
    return env


def _grep_log(pattern: str, log: Path, result: Path, env: dict[str, str],
              stop: threading.Event) -> bool:
    """Use the original grep expression/locale, including binary-log behavior."""
    code, _, interrupted = run_logged(
        ["grep", "-En", pattern, str(log)], cwd=Path.cwd(), env=env,
        log=result, seconds=TEST_TIMEOUT, stop=stop, max_bytes=None)
    if code not in (0, 1) or interrupted:
        raise RuntimeError(f"grep could not classify {log.name} (exit={code})")
    return code == 0


def run_scene(project: Path, out: Path, shim: Path, scene: Path,
              stop: threading.Event) -> tuple[str, bool, bool]:
    name = scene.stem
    env = _profile_environment(out, name, shim)
    log = out / (name + ".log")
    command = ["godot", "--headless", "--path", str(project), "--fixed-fps", "60",
               "--audio-driver", "Dummy", "res://tests/" + scene.name]
    code, overflow, interrupted = run_logged(command, cwd=Path.cwd(), env=env,
                                             log=log, seconds=TEST_TIMEOUT, stop=stop)
    contents = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    failures = _grep_log(FAILURE, log, out / (name + ".failures"), env, stop)
    expected, unexpected, _ = classify(contents, name)
    _write_lines(out / (name + ".expected-errors"), expected)
    _write_lines(out / (name + ".godot-errors"), unexpected)
    failed = code != 0 or overflow or interrupted or failures or bool(unexpected)
    line = (f"FAIL {name:<30} exit={code} cap={int(overflow)}" if failed else f"PASS {name}")
    return line, failed, bool(expected)


def main(argv: list[str], selected: tuple[str, ...] | None = None) -> int:
    if len(argv) < 2:
        print("Usage: run_test_suite.sh <project> <new-output-directory>", file=sys.stderr)
        return 2
    if sys.platform != "linux":
        print("Isolated test desktop is supported only on Linux.", file=sys.stderr)
        return 2
    raw_jobs = os.environ.get("THOR_TEST_JOBS", "1")
    if not re.fullmatch(r"[1-8]", raw_jobs):
        print("THOR_TEST_JOBS must be an integer from 1 to 8.", file=sys.stderr)
        return 2
    jobs = int(raw_jobs)
    try:
        project = Path(argv[0]).resolve(strict=True)
        out = Path(argv[1])
        try:
            locale.setlocale(locale.LC_COLLATE, "")
        except locale.Error:
            pass  # Bash likewise falls back to the C locale when unavailable.
        scenes = sorted((project / "tests").glob("*_test.tscn"),
                        key=lambda p: (locale.strxfrm(p.name), os.fsencode(p.name)))
        if selected is not None:
            if not selected or len(set(selected)) != len(selected):
                raise ValueError("Selected scene names must be nonempty and unique")
            selected_names = set(selected)
            missing = selected_names - {scene.stem for scene in scenes}
            if missing:
                raise ValueError("Selected test scenes are missing: " + ", ".join(sorted(missing)))
            scenes = [scene for scene in scenes if scene.stem in selected_names]
        if not scenes:
            raise ValueError("No *_test.tscn scenes found")
        # Do not resolve the final path first: a dangling output symlink must
        # never cause the suite to create or populate its absent target.
        if out.is_symlink():
            raise ValueError(f"Output path is a symlink: {out}")
        out.mkdir(parents=True, exist_ok=False)
        out = out.resolve(strict=True)
        shim = out / "bin"
        shim.mkdir()
        xdg = shim / "xdg-user-dir"
        xdg.write_text('#!/bin/sh\n'
                       'if [ "${1:-}" = DESKTOP ]; then\n'
                       '  printf "%s\\n" "$THOR_SUITE_DESKTOP"\n'
                       'else\n'
                       '  PATH=$THOR_SUITE_ORIGINAL_PATH\n'
                       '  export PATH\n'
                       '  exec xdg-user-dir "$@"\n'
                       'fi\n', encoding="utf-8")
        xdg.chmod(0o700)
    except (OSError, ValueError) as error:
        print(f"Cannot prepare test suite: {error}", file=sys.stderr)
        return 2

    stop = threading.Event()
    received_signal = [0]

    def stop_handler(signum: int, _frame: object) -> None:
        received_signal[0] = signum
        stop.set()

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop_handler)

    env = _profile_environment(out, "import", shim)
    import_log = out / "import.log"
    try:
        code, overflow, interrupted = run_logged(["godot", "--headless", "--path", str(project), "--import"],
                                                  cwd=Path.cwd(), env=env, log=import_log,
                                                  seconds=IMPORT_TIMEOUT, stop=stop)
        import_errors = _grep_log(IMPORT_ERROR, import_log, out / "import-errors.log", env, stop)
        if code != 0 or overflow or interrupted or import_errors:
            print(f"Import failed; see {import_log}", file=sys.stderr)
            return 128 + received_signal[0] if received_signal[0] else 1
        summary = out / "summary.txt"
        failed = 0
        next_index = 0
        completed: dict[int, tuple[str, bool, bool]] = {}
        with summary.open("w", encoding="utf-8") as sink, concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = {pool.submit(run_scene, project, out, shim, scene, stop): index
                       for index, scene in enumerate(scenes)}
            for future in concurrent.futures.as_completed(futures):
                index = futures[future]
                name = scenes[index].stem
                try:
                    completed[index] = future.result()
                except Exception as error:
                    completed[index] = (f"FAIL {name:<30} worker={type(error).__name__}: {error}", True, False)
                while next_index in completed:
                    line, bad, expected = completed.pop(next_index)
                    print(line, flush=True)
                    print(line, file=sink, flush=True)
                    failed += int(bad)
                    if expected:
                        n = scenes[next_index].stem
                        note = f"NOTE {n}: intentional or shutdown diagnostics saved in {n}.expected-errors"
                        print(note, flush=True)
                        print(note, file=sink, flush=True)
                    next_index += 1
            total = f"TOTAL {len(scenes)}, FAILED {failed}"
            print(total, flush=True)
            print(total, file=sink, flush=True)
        if received_signal[0]:
            return 128 + received_signal[0]
        return 1 if failed else 0
    except (OSError, RuntimeError) as error:
        print(f"Test suite error: {error}", file=sys.stderr)
        return 128 + received_signal[0] if received_signal[0] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
