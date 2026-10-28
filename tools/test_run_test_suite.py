#!/usr/bin/env python3
"""Regression tests for the suite runner using fake Godot processes."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parent
RUNNER = ROOT / "run_test_suite.sh"
FAKE_GODOT = r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time

def event(kind, name, **extra):
    data = {"kind": kind, "name": name, "time": time.monotonic(), "pid": os.getpid(), **extra}
    fd = os.open(os.environ["THOR_FAKE_EVENTS"], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.write(fd, (json.dumps(data) + "\n").encode()); os.close(fd)

if "--import" in sys.argv:
    event("start", "import")
    if os.environ.get("THOR_FAKE_IMPORT_HANG") == "1":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        child = subprocess.Popen([sys.executable, "-c", "import os,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open(os.environ['THOR_FAKE_CHILD_READY'],'w').write('ready'); time.sleep(60)"])
        while not os.path.exists(os.environ["THOR_FAKE_CHILD_READY"]): time.sleep(0.01)
        event("child", "import", child=child.pid)
        time.sleep(60)
    time.sleep(0.08)
    if os.environ.get("THOR_FAKE_IMPORT_FAIL") == "1":
        print("ERROR: fake import failure"); sys.exit(0)
    event("end", "import"); sys.exit(0)

name = next(arg.rsplit("/", 1)[-1][:-5] for arg in sys.argv if arg.endswith(".tscn"))
desktop = (subprocess.check_output(["xdg-user-dir", "DESKTOP"], text=True).strip()
           if os.environ.get("THOR_FAKE_CHECK_DESKTOP", "1") == "1" else "not checked")
documents = subprocess.check_output(["xdg-user-dir", "DOCUMENTS"], text=True).strip()
event("start", name, data=os.environ["XDG_DATA_HOME"], desktop=desktop, documents=documents, cwd=os.getcwd())
if name == "a_slow_test": time.sleep(0.45)
elif name == "b_fast_test": time.sleep(0.08)
elif name == "c_expected_test": print("ERROR: 2 resources still in use at exit.")
elif name == "d_mixed_test": print("ERROR: 2 resources still in use at exit. ERROR: surprise")
elif name == "e_assert_test": print("[FAIL] failure with exit 0")
elif name == "f_exit_test": print("nonzero exit"); sys.exit(7)
elif name == "k_nonbreaking_space_test": print("1\u00a0FAIL")
elif name == "l_binary_test":
    sys.stdout.flush(); os.write(1, b"binary\x00[FAIL]\n")
elif name == "g_overflow_test":
    while True:
        os.write(1, b"X" * 65536)
elif name == "h_hang_test":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = subprocess.Popen([sys.executable, "-c", "import os,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open(os.environ['THOR_FAKE_CHILD_READY'],'w').write('ready'); time.sleep(60)"])
    while not os.path.exists(os.environ["THOR_FAKE_CHILD_READY"]): time.sleep(0.01)
    event("child", name, child=child.pid)
    time.sleep(60)
else:
    time.sleep(0.08)
print("=== ИТОГ: 0 FAIL ===")
event("end", name)
'''


class SuiteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="thor suite $probe ")
        self.base = Path(self.temp.name)
        self.project = self.base / "project with spaces"
        (self.project / "tests").mkdir(parents=True)
        self.bin = self.base / "fake bin"
        self.bin.mkdir()
        fake = self.bin / "godot"
        fake.write_text(FAKE_GODOT, encoding="utf-8")
        fake.chmod(0o700)
        original_xdg = self.bin / "xdg-user-dir"
        original_xdg.write_text('#!/bin/sh\nprintf "original-%s\\n" "$1"\n', encoding="utf-8")
        original_xdg.chmod(0o700)
        self.events = self.base / "events.jsonl"
        self.env = os.environ.copy()
        self.env.update({"PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", ""),
                         "THOR_FAKE_EVENTS": str(self.events),
                         "THOR_FAKE_CHILD_READY": str(self.base / "child-ready"), "THOR_TEST_JOBS": "3"})

    def tearDown(self) -> None:
        self.temp.cleanup()

    def scenes(self, *names: str) -> None:
        for name in names:
            (self.project / "tests" / (name + ".tscn")).write_text("fake scene", encoding="utf-8")

    def run_suite(self, out: Path, **extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(RUNNER), str(self.project), str(out)], env={**self.env, **extra},
                              capture_output=True, text=True, timeout=40)

    def events_read(self) -> list[dict]:
        return [json.loads(line) for line in self.events.read_text().splitlines()]

    def test_parallel_order_isolation_and_expected_errors(self) -> None:
        names = ["a_slow_test", "b_fast_test", "c_expected_test", "i_last_test", "j_last_test"]
        self.scenes(*names)
        out = self.base / 'out with spaces $[safe]'
        result = self.run_suite(out)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = (out / "summary.txt").read_text().splitlines()
        self.assertEqual([x.split()[1] for x in lines if x.startswith("PASS ")], names)
        self.assertEqual(lines[-1], "TOTAL 5, FAILED 0")
        self.assertIn("NOTE c_expected_test:", "\n".join(lines))
        events = self.events_read()
        self.assertEqual(sum(e["kind"] == "start" and e["name"] == "import" for e in events), 1)
        import_end = next(e["time"] for e in events if e["kind"] == "end" and e["name"] == "import")
        starts = [e for e in events if e["kind"] == "start" and e["name"] != "import"]
        self.assertTrue(all(e["time"] >= import_end for e in starts))
        self.assertEqual(len({e["data"] for e in starts}), len(names))
        self.assertEqual(len({e["desktop"] for e in starts}), len(names))
        self.assertTrue(all(e["desktop"] == str(out / "user" / e["name"] / "Desktop") for e in starts))
        self.assertTrue(all(e["documents"] == "original-DOCUMENTS" for e in starts))
        activity = sorted((e["time"], 1 if e["kind"] == "start" else -1)
                          for e in events if e["name"] != "import" and e["kind"] in ("start", "end"))
        active = high = 0
        for _, delta in activity:
            active += delta
            high = max(high, active)
        self.assertGreaterEqual(high, 2)
        self.assertLessEqual(high, 3)

    def test_default_is_sequential(self) -> None:
        self.scenes("a_slow_test", "b_fast_test", "i_last_test")
        env = self.env.copy()
        env.pop("THOR_TEST_JOBS")
        out = self.base / "default sequential"
        result = subprocess.run([str(RUNNER), str(self.project), str(out)], env=env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events_read()
        activity = sorted((e["time"], 1 if e["kind"] == "start" else -1)
                          for e in events if e["name"] != "import" and e["kind"] in ("start", "end"))
        active = high = 0
        for _, delta in activity:
            active += delta
            high = max(high, active)
        self.assertEqual(high, 1)

    def test_scene_order_matches_bash_locale(self) -> None:
        available = subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.splitlines()
        if "ru_RU.utf8" not in available:
            self.skipTest("ru_RU.utf8 locale unavailable")
        self.scenes("runes_test", "run_map_test")
        out = self.base / "locale order"
        env = {**self.env, "LC_ALL": "ru_RU.utf8"}
        reference = subprocess.run(["bash", "-c", 'printf "%s\\n" "$1"/tests/*_test.tscn',
                                    "bash", str(self.project)], env=env, capture_output=True, text=True)
        self.assertEqual(reference.returncode, 0)
        expected = [Path(x).stem for x in reference.stdout.splitlines()]
        result = subprocess.run([str(RUNNER), str(self.project), str(out)], env=env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual = [x.split()[1] for x in (out / "summary.txt").read_text().splitlines()
                  if x.startswith("PASS ")]
        self.assertEqual(actual, expected)

    def test_fast_subset_runs_only_selected_scenes(self) -> None:
        fast_spec = importlib.util.spec_from_file_location("ci_fast", ROOT / "run_ci_fast.py")
        assert fast_spec and fast_spec.loader
        # The wrapper imports its sibling runner, as it does in CI.
        sys.path.insert(0, str(ROOT))
        try:
            fast = importlib.util.module_from_spec(fast_spec)
            fast_spec.loader.exec_module(fast)
        finally:
            sys.path.pop(0)
        self.scenes(*fast.CI_FAST_SCENES, "z_unselected_test")
        out = self.base / "fast subset"
        result = subprocess.run([sys.executable, "-B", str(ROOT / "run_ci_fast.py"),
                                 str(self.project), str(out)], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("this is not the full suite", result.stdout)
        lines = (out / "summary.txt").read_text().splitlines()
        self.assertEqual(lines[-1], f"TOTAL {len(fast.CI_FAST_SCENES)}, FAILED 0")
        self.assertEqual({x.split()[1] for x in lines if x.startswith("PASS ")}, set(fast.CI_FAST_SCENES))
        events = self.events_read()
        self.assertEqual(sum(e["kind"] == "start" and e["name"] == "import" for e in events), 1)
        self.assertFalse(any(e["name"] == "z_unselected_test" for e in events))

    def test_fast_subset_fails_closed_if_a_scene_is_missing(self) -> None:
        self.scenes("smoke_test")
        out = self.base / "missing fast scenes"
        result = subprocess.run([sys.executable, "-B", str(ROOT / "run_ci_fast.py"),
                                 str(self.project), str(out)], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("Selected test scenes are missing", result.stderr)
        self.assertFalse(out.exists())
        self.assertFalse(self.events.exists())

    def test_failure_detection_and_log_cap(self) -> None:
        self.scenes("d_mixed_test", "e_assert_test", "f_exit_test", "g_overflow_test")
        out = self.base / "failures"
        result = self.run_suite(out)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = (out / "summary.txt").read_text()
        self.assertIn("TOTAL 4, FAILED 4", summary)
        self.assertIn("ERROR: surprise", (out / "d_mixed_test.godot-errors").read_text())
        self.assertIn("ERROR: 2 resources", (out / "d_mixed_test.expected-errors").read_text())
        self.assertIn("[FAIL]", (out / "e_assert_test.failures").read_text())
        self.assertIn("exit=7", summary)
        self.assertIn("cap=1", summary)
        self.assertEqual((out / "g_overflow_test.log").stat().st_size, 50_000_000)

    def test_import_failure_and_bad_job_count(self) -> None:
        self.scenes("a_slow_test")
        out = self.base / "bad import"
        result = self.run_suite(out, THOR_FAKE_IMPORT_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("fake import failure", (out / "import-errors.log").read_text())
        self.assertFalse((out / "summary.txt").exists())
        self.assertEqual([e["name"] for e in self.events_read()], ["import"])
        for invalid in ("0", "9", "-1", "02", "", "3.0"):
            out = self.base / ("invalid_" + (invalid or "empty"))
            result = self.run_suite(out, THOR_TEST_JOBS=invalid)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(out.exists())

    def test_existing_output_is_never_overwritten(self) -> None:
        self.scenes("a_slow_test")
        out = self.base / "existing"
        out.mkdir()
        sentinel = out / "sentinel"
        sentinel.write_text("preserved")
        result = self.run_suite(out)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(sentinel.read_text(), "preserved")

    def test_dangling_output_symlink_does_not_create_target(self) -> None:
        self.scenes("a_slow_test")
        target = self.base / "absent-target"
        out = self.base / "output-symlink"
        out.symlink_to(target, target_is_directory=True)
        result = self.run_suite(out)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(out.is_symlink())
        self.assertFalse(target.exists())
        self.assertFalse(self.events.exists())

    def test_missing_scenes_do_not_look_like_a_passing_suite(self) -> None:
        out = self.base / "no scenes"
        result = self.run_suite(out)
        self.assertEqual(result.returncode, 2)
        self.assertIn("No *_test.tscn scenes", result.stderr)
        self.assertFalse(out.exists())

    def test_grep_semantics_for_locale_and_binary_output(self) -> None:
        self.scenes("k_nonbreaking_space_test", "l_binary_test")
        out = self.base / "grep compatibility"
        result = self.run_suite(out, LC_ALL="C.UTF-8")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = (out / "summary.txt").read_text()
        self.assertIn("PASS k_nonbreaking_space_test", summary)
        self.assertIn("FAIL l_binary_test", summary)
        pattern = (r"SCRIPT ERROR|Parse Error|\[FAIL\]|^[[:space:]]*FAIL:|HITCH FAIL|"
                   r"(^|[^0-9])[1-9][0-9]*[[:space:]]+FAIL([[:space:]=]|$)")
        for name in ("k_nonbreaking_space_test", "l_binary_test"):
            reference = subprocess.run(["grep", "-En", pattern, str(out / (name + ".log"))],
                                       env={**self.env, "LC_ALL": "C.UTF-8"}, capture_output=True)
            self.assertIn(reference.returncode, (0, 1))
            # GNU grep emits its binary-file match notice on stderr. Preserve
            # the notice and fail rather than hiding a binary [FAIL] marker.
            self.assertEqual((out / (name + ".failures")).read_bytes(), reference.stdout + reference.stderr)

    def test_original_caller_cwd_and_extra_argument(self) -> None:
        self.scenes("a_slow_test")
        out = self.base / "caller cwd"
        result = subprocess.run([str(RUNNER), str(self.project), str(out), "ignored"],
                                cwd=self.base, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        start = next(e for e in self.events_read() if e["kind"] == "start" and e["name"] == "a_slow_test")
        self.assertEqual(start["cwd"], str(self.base))

    def test_other_unix_retains_original_sequential_runner(self) -> None:
        fake_uname = self.bin / "uname"
        fake_uname.write_text("#!/bin/sh\nprintf 'Darwin\\n'\n")
        fake_uname.chmod(0o700)
        self.scenes("a_slow_test", "c_expected_test", "d_mixed_test", "e_assert_test", "f_exit_test")
        env = {**self.env, "THOR_FAKE_CHECK_DESKTOP": "0"}
        env.pop("THOR_TEST_JOBS")
        out = self.base / "other unix"
        result = subprocess.run([str(RUNNER), str(self.project), str(out)], cwd=self.base, env=env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        summary = (out / "summary.txt").read_text()
        self.assertIn("PASS a_slow_test", summary)
        self.assertIn("PASS c_expected_test", summary)
        self.assertIn("NOTE c_expected_test:", summary)
        self.assertIn("FAIL d_mixed_test", summary)
        self.assertIn("FAIL e_assert_test", summary)
        self.assertIn("FAIL f_exit_test", summary)
        self.assertIn("TOTAL 5, FAILED 3", summary)
        events = self.events_read()
        starts = [e for e in events if e["kind"] == "start" and e["name"] != "import"]
        self.assertTrue(all(e["cwd"] == str(self.base) for e in starts))
        activity = sorted((e["time"], 1 if e["kind"] == "start" else -1)
                          for e in events if e["name"] != "import" and e["kind"] in ("start", "end"))
        active = high = 0
        for _, delta in activity:
            active += delta
            high = max(high, active)
        self.assertEqual(high, 1)
        unsupported = self.base / "unsupported parallel unix"
        result = subprocess.run([str(RUNNER), str(self.project), str(unsupported)],
                                env={**env, "THOR_TEST_JOBS": "3"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(unsupported.exists())
        self.assertIn("only on Linux", result.stderr)

    def test_windows_selftest_fails_closed(self) -> None:
        wine = self.bin / "wine"
        wine.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                        "print(os.environ['THOR_FAKE_WINE_TEXT'])\n"
                        "sys.exit(int(os.environ.get('THOR_FAKE_WINE_EXIT', '0')))\n")
        wine.chmod(0o700)
        exe = self.base / "fake.exe"
        exe.touch()
        good = "SELFTEST OK scene=Game room=res://rooms/test.tscn enemies=3"
        scenarios = (
            ("good", good, "0", 0),
            ("expected", good + "\nERROR: 2 resources still in use at exit.", "0", 0),
            ("mixed", good + "\nERROR: surprise", "0", 1),
            ("zero", good.replace("enemies=3", "enemies=0"), "0", 1),
            ("no_marker", "nothing printed", "0", 1),
            ("reported_fail", good + "\nSELFTEST FAIL: problem", "0", 1),
            ("bad_exit", good, "7", 1),
        )
        for name, content, code, expected in scenarios:
            with self.subTest(name=name):
                out = self.base / ("wine-" + name)
                result = subprocess.run([sys.executable, "-B", str(ROOT / "ci_windows_selftest.py"),
                                         str(exe), str(out)], capture_output=True, text=True, timeout=15,
                                        env={**self.env, "THOR_FAKE_WINE_TEXT": content, "THOR_FAKE_WINE_EXIT": code})
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                if name == "expected":
                    self.assertIn("resources still in use", (out / "selftest.expected-errors").read_text())
                if name == "mixed":
                    self.assertIn("ERROR: surprise", (out / "selftest.godot-errors").read_text())

    def test_timeout(self) -> None:
        spec = importlib.util.spec_from_file_location("suite_runner", ROOT / "run_test_suite.py")
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.TERMINATE_GRACE = 0.2
        log = self.base / "timeout.log"
        code, overflow, interrupted = module.run_logged([sys.executable, "-c", "import time; time.sleep(60)"],
                                                        cwd=self.base, env=self.env, log=log,
                                                        seconds=0.2, stop=threading.Event())
        self.assertEqual(code, 124)
        self.assertFalse(overflow or interrupted)

    def test_parent_signals_terminate_descendants(self) -> None:
        for sent in (signal.SIGTERM, signal.SIGKILL):
            with self.subTest(signal=sent):
                self.scenes("h_hang_test")
                self.events.unlink(missing_ok=True)
                (self.base / "child-ready").unlink(missing_ok=True)
                out = self.base / f"signal-{int(sent)}"
                process = subprocess.Popen([str(RUNNER), str(self.project), str(out)], env=self.env,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                deadline = time.monotonic() + 10
                child = None
                try:
                    while time.monotonic() < deadline:
                        if self.events.exists():
                            child = next((e for e in self.events_read() if e["kind"] == "child"), None)
                            if child:
                                break
                        time.sleep(0.05)
                    self.assertIsNotNone(child, "fake Godot did not start its child")
                    assert child
                    os.kill(process.pid, sent)
                    process.wait(timeout=15)
                    if sent == signal.SIGTERM:
                        self.assertEqual(process.returncode, 143)
                    end = time.monotonic() + 5
                    while time.monotonic() < end and (self._alive(child["pid"]) or self._alive(child["child"])):
                        time.sleep(0.05)
                    self.assertFalse(self._alive(child["pid"]), "fake Godot was orphaned")
                    self.assertFalse(self._alive(child["child"]), "fake Godot child was orphaned")
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    if child:
                        for pid in (child["pid"], child["child"]):
                            if self._alive(pid):
                                try:
                                    os.kill(pid, signal.SIGKILL)
                                except ProcessLookupError:
                                    pass

    def test_sigkill_during_import_terminates_descendants(self) -> None:
        self.scenes("a_slow_test")
        out = self.base / "interrupted import"
        process = subprocess.Popen([str(RUNNER), str(self.project), str(out)],
                                   env={**self.env, "THOR_FAKE_IMPORT_HANG": "1"},
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 10
        child = None
        try:
            while time.monotonic() < deadline:
                if self.events.exists():
                    child = next((e for e in self.events_read() if e["kind"] == "child"), None)
                    if child:
                        break
                time.sleep(0.05)
            self.assertIsNotNone(child)
            assert child
            os.kill(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            end = time.monotonic() + 5
            while time.monotonic() < end and (self._alive(child["pid"]) or self._alive(child["child"])):
                time.sleep(0.05)
            self.assertFalse(self._alive(child["pid"]), "import process was orphaned")
            self.assertFalse(self._alive(child["child"]), "import descendant was orphaned")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            if child:
                for pid in (child["pid"], child["child"]):
                    if self._alive(pid):
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    @staticmethod
    def _alive(pid: int) -> bool:
        try:
            # A dead child can remain as a zombie until pid 1 reaps it.
            stat = Path(f"/proc/{pid}/stat").read_text()
            return stat.rsplit(")", 1)[1].strip().split()[0] != "Z"
        except FileNotFoundError:
            return False


if __name__ == "__main__":
    unittest.main()
