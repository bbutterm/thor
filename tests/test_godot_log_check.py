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


class LogChecks(unittest.TestCase):
    def test_inline_expected_and_unexpected_preserve_full_line(self):
        line = "Leaked instance: audio - RERROR: 20 resources still in use at exit.\n"
        expected, unexpected, counts = check.classify(line)
        self.assertEqual(expected, [line.rstrip()])
        self.assertEqual(unexpected, [])
        self.assertEqual(counts, [20])
        mixed = line.rstrip() + " other output ERROR: a real failure"
        expected, unexpected, counts = check.classify(mixed)
        self.assertEqual(expected, [mixed])
        self.assertEqual(unexpected, [mixed])
        self.assertEqual(counts, [20])

    def test_scene_whitelist_does_not_mask_another_error(self):
        line = "prefix ERROR: Parse JSON failed. xyz ERROR: unrelated failure"
        expected, unexpected, _ = check.classify(line, "save_test")
        self.assertEqual(expected, [line])
        self.assertEqual(unexpected, [line])
        line = "x ERROR: build_scenes: ручная сцена rejected SCRIPT ERROR: broken"
        expected, unexpected, _ = check.classify(line, "generator_test")
        self.assertEqual(expected, [line])
        self.assertEqual(unexpected, [line])
        self.assertEqual(check.classify("SCRIPT ERROR: 13 resources still in use at exit.")[0], [])
        self.assertEqual(len(check.classify("SCRIPT ERROR: 13 resources still in use at exit.")[1]), 1)

    def test_full_suite_with_fake_engine_and_inline_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = root / "project"
            (project / "tests").mkdir(parents=True)
            (project / "tests/example_test.tscn").write_text("")
            binary = root / "bin"
            binary.mkdir()
            fake = binary / "godot"
            fake.write_text('#!/bin/bash\nif [[ " $* " == *" --import "* ]]; then\n'
                            '  printf "%s\\n" "${FAKE_IMPORT:-imported}"\nelse\n'
                            '  printf "%s\\n" "$FAKE_TEST_LOG"\nfi\n')
            fake.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(binary) + os.pathsep + env.get("PATH", "")
            expected = "prefix ERROR: 20 resources still in use at exit."
            env["FAKE_TEST_LOG"] = expected
            suite = ["bash", str(ROOT / "tools/run_test_suite.sh"), str(project)]
            out = root / "expected"
            result = subprocess.run(suite + [str(out)], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((out / "example_test.expected-errors").read_text(), expected + "\n")
            mixed = expected + " merged ERROR: unexpected"
            env["FAKE_TEST_LOG"] = mixed
            out = root / "unexpected"
            result = subprocess.run(suite + [str(out)], env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((out / "example_test.expected-errors").read_text(), mixed + "\n")
            self.assertEqual((out / "example_test.godot-errors").read_text(), mixed + "\n")
            env["FAKE_IMPORT"] = "import progress ERROR: inline import failure"
            out = root / "bad-import"
            result = subprocess.run(suite + [str(out)], env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(env["FAKE_IMPORT"], (out / "import-errors.log").read_text())



if __name__ == "__main__":
    unittest.main()
