#!/usr/bin/env python3
"""Small synthetic checks for mixed Godot stdout/stderr; no engine required."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import godot_log_check as check


class PreviewLogChecks(unittest.TestCase):
    def test_render_phase_and_full_mixed_context(self):
        line = ("frame ERROR: bad renderer RENDER PREFETCH RESULT: PASS "
                "ERROR: 2 resources still in use at exit. ERROR: bad cleanup")
        runtime, expected, unexpected, nr, nc, nu = check.render_classify(line)
        self.assertEqual((nr, nc, nu), (1, 1, 1))
        self.assertEqual((runtime, expected, unexpected), ([line], [line], [line]))
        line = "prefix RENDER PREFETCH RESULT: PASS tail ERROR: 2 resources still in use at exit."
        runtime, expected, unexpected, nr, nc, nu = check.render_classify(line)
        self.assertEqual((nr, nc, nu), (0, 1, 0))
        self.assertEqual((runtime, expected, unexpected), ([], [line], []))

    def test_hitch_inline_error_and_clean_line(self):
        line = "frame output ERROR: missed error"
        self.assertEqual(check.hitch_errors(line), [line])
        self.assertEqual(check.hitch_errors("0 errors, frame complete"), [])

    def test_fixed_runner_embedded_validation(self):
        script = (ROOT / "tests/bot/fixed_exit_ab.sh").read_text()
        start = script.index("\n", script.index("<<'PY'")) + 1
        end = script.index("\nPY\n", start)
        validator = script[start:end]
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            row = {"valid": True, "body": "thrall", "seed": 11,
                   "trace_enabled": False, "picks": [], "outcome": "death",
                   "spawned": [], "planned": []}
            (case / "result.jsonl").write_text(json.dumps(row) + "\n")
            command = [sys.executable, "-B", "-", str(case), "0", "0", str(ROOT / "tools")]
            expected = "prefix ERROR: 20 resources still in use at exit."
            (case / "combined.log").write_text(expected + "\n")
            result = subprocess.run(command, input=validator, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("exit_resources=20", result.stdout)
            self.assertEqual((case / "expected-errors.log").read_text(), expected + "\n")
            mixed = expected + " mixed ERROR: unexpected"
            (case / "combined.log").write_text(mixed + "\n")
            result = subprocess.run(command, input=validator, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((case / "expected-errors.log").read_text(), mixed + "\n")
            self.assertEqual((case / "unexpected-errors.log").read_text(), mixed + "\n")

    def test_render_and_hitch_command_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            line = ("prefix RENDER PREFETCH RESULT: PASS "
                    "ERROR: 2 resources still in use at exit. ERROR: unexpected")
            log = root / "godot.log"
            log.write_text(line + "\n")
            command = [sys.executable, str(ROOT / "tools/godot_log_check.py")]
            result = subprocess.run(command + ["render", str(log), str(root)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "0 1 1")
            self.assertEqual((root / "cleanup-expected-errors.log").read_text(), line + "\n")
            self.assertEqual((root / "cleanup-unexpected-errors.log").read_text(), line + "\n")
            result = subprocess.run(command + ["hitch", str(log), str(root / "errors.log")], text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual((root / "errors.log").read_text(), line + "\n")

    def test_hitch_wrapper_with_fake_engine_and_display(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = root / "project"
            (project / "tools").mkdir(parents=True)
            (project / ".godot/imported").mkdir(parents=True)
            for name in ("run_hitch_render.sh", "godot_log_check.py"):
                shutil.copy(ROOT / "tools" / name, project / "tools" / name)
            binary = root / "bin"
            binary.mkdir()
            (binary / "godot").write_text(
                '#!/bin/bash\nprintf "%s\\n" "медиане, gl_compatibility)" '
                '"Пройдено залов: 1 из 1" "Удары-приземления с реальным приземлением: 1" '
                '"=== ИТОГ HITCH: OK" "$FAKE_TEST_LOG"\n')
            (binary / "xdpyinfo").write_text('#!/bin/bash\nexit 0\n')
            (binary / "Xvfb").write_text('#!/bin/bash\nexec /bin/sleep 10\n')
            for item in binary.iterdir():
                item.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(binary) + os.pathsep + env.get("PATH", "")
            env["FAKE_TEST_LOG"] = "frame text ERROR: unexpected renderer problem"
            out = root / "out"
            result = subprocess.run(["bash", str(project / "tools/run_hitch_render.sh"),
                                     "gl_compatibility", str(out)], env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((out / "godot-errors.log").read_text(), env["FAKE_TEST_LOG"] + "\n")


if __name__ == "__main__":
    unittest.main()
