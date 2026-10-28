#!/usr/bin/env python3
"""Проверка стандартного ZIP, который создаёт необязательный libdeflate."""
from pathlib import Path
import tempfile
import unittest
import zipfile

import package_playtest


class PackageTest(unittest.TestCase):
    def test_libdeflate_zip_is_standard_and_lossless(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d)
            exe = folder / "ThorDostoynayaSmert.exe"
            payload = (bytes(range(256)) * 64) + b"test-godot-pck" * 200
            exe.write_bytes(payload)
            archive = folder / "Thor.zip"
            if not package_playtest.pack_libdeflate(exe, archive):
                self.skipTest("libdeflate не установлен; упаковщик использует zlib")
            with zipfile.ZipFile(archive) as z:
                self.assertEqual(z.namelist(), [exe.name])
                self.assertEqual(z.getinfo(exe.name).compress_type, zipfile.ZIP_DEFLATED)
                self.assertIsNone(z.testzip())
                self.assertEqual(z.read(exe.name), payload)


if __name__ == "__main__":
    unittest.main()
