#!/usr/bin/env python3
"""Собрать один ZIP Windows-плейтеста с проверкой размера и содержимого.

python3 tools/package_playtest.py [--godot godot] [--skip-export]
Шаблон Godot 4.6.3 Windows должен быть установлен в пользовательский каталог движка.
"""
import argparse
import ctypes
import ctypes.util
import datetime
import os
from pathlib import Path
import struct
import subprocess
import sys
import zipfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "export/windows/ThorDostoynayaSmert.exe"
ZIP = ROOT / "export/windows/ThorDostoynayaSmert-windows.zip"
MAX_ZIP_BYTES = 95_000_000
MAX_LOG_BYTES = 50_000_000


def godot_command(command, log_path):
    """Обрезаем сохранённый лог, но дочитываем поток, чтобы не остановить Godot SIGPIPE."""
    written = 0
    with log_path.open("wb") as log:
        p = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert p.stdout is not None
        for chunk in iter(lambda: p.stdout.read(65536), b""):
            remaining = max(MAX_LOG_BYTES - written, 0)
            if remaining:
                data = chunk[:remaining]
                log.write(data)
                written += len(data)
        status = p.wait()
    if status != 0:
        raise RuntimeError(f"Godot завершился с кодом {status}; лог: {log_path}")


def pack_libdeflate(exe, output):
    """Стандартный ZIP/DEFLATE. Возвращает False, если системной библиотеки нет."""
    lib_path = ctypes.util.find_library("deflate")
    if not lib_path:
        return False
    try:
        lib = ctypes.CDLL(lib_path)
        lib.libdeflate_alloc_compressor.argtypes = [ctypes.c_int]
        lib.libdeflate_alloc_compressor.restype = ctypes.c_void_p
        lib.libdeflate_deflate_compress_bound.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.libdeflate_deflate_compress_bound.restype = ctypes.c_size_t
        lib.libdeflate_deflate_compress.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        lib.libdeflate_deflate_compress.restype = ctypes.c_size_t
        lib.libdeflate_free_compressor.argtypes = [ctypes.c_void_p]
    except (OSError, AttributeError):
        return False
    source = exe.read_bytes()
    if len(source) >= 0xffffffff:
        raise RuntimeError("Файл слишком велик для ZIP без ZIP64")
    compressor = lib.libdeflate_alloc_compressor(12)
    if not compressor:
        raise RuntimeError("Не удалось создать libdeflate compressor")
    try:
        bound = lib.libdeflate_deflate_compress_bound(compressor, len(source))
        compressed = ctypes.create_string_buffer(bound)
        count = lib.libdeflate_deflate_compress(compressor, source, len(source), compressed, bound)
    finally:
        lib.libdeflate_free_compressor(compressor)
    if not count:
        raise RuntimeError("Ошибка libdeflate")
    name = exe.name.encode("ascii")
    crc = zlib.crc32(source) & 0xffffffff
    now = datetime.datetime.now()
    dos_time = (now.hour << 11) | (now.minute << 5) | (now.second // 2)
    dos_date = ((now.year - 1980) << 9) | (now.month << 5) | now.day
    local = struct.pack("<IHHHHHIIIHH", 0x04034b50, 20, 0, 8, dos_time, dos_date, crc, count, len(source), len(name), 0) + name
    central = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014b50, 20, 20, 0, 8, dos_time, dos_date, crc, count, len(source), len(name), 0, 0, 0, 0, 0, 0) + name
    end = struct.pack("<IHHHHIIH", 0x06054b50, 0, 0, 1, 1, len(central), len(local) + count, 0)
    with output.open("wb") as f:
        f.write(local)
        f.write(memoryview(compressed)[:count])
        f.write(central)
        f.write(end)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="путь к Godot 4.6.3")
    parser.add_argument("--skip-export", action="store_true", help="упаковать существующий exe")
    parser.add_argument("--zlib", action="store_true", help="использовать zlib вместо необязательного libdeflate")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tools/check_export_assets.py")], cwd=ROOT, check=True)
    EXE.parent.mkdir(parents=True, exist_ok=True)
    if not args.skip_export:
        version = subprocess.run([args.godot, "--version"], text=True, capture_output=True, check=True).stdout.strip()
        if not version.startswith("4.6.3.stable"):
            raise RuntimeError(f"Для экспорта нужен Godot 4.6.3 stable, установлен {version}")
        godot_command([args.godot, "--headless", "--path", str(ROOT), "--import"], EXE.parent / "import.log")
        godot_command([args.godot, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop", str(EXE)], EXE.parent / "export.log")
    if not EXE.is_file() or EXE.stat().st_size == 0:
        raise FileNotFoundError(f"Нет собранного файла {EXE}")
    tmp = ZIP.with_suffix(".zip.tmp")
    try:
        packed = False if args.zlib else pack_libdeflate(EXE, tmp)
        if not packed:
            with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
                z.write(EXE, arcname=EXE.name)
        size = tmp.stat().st_size
        with zipfile.ZipFile(tmp) as z:
            if z.namelist() != [EXE.name] or z.testzip() is not None:
                raise RuntimeError("ZIP не прошёл проверку содержимого и CRC")
        if size > MAX_ZIP_BYTES:
            raise RuntimeError(f"ZIP {size:,} байт превышает предел {MAX_ZIP_BYTES:,} байт")
        os.replace(tmp, ZIP)
        print(f"Готово: {ZIP} ({size:,} байт; внутри {EXE.name})")
    finally:
        tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        print(f"ОШИБКА: {exc}", file=sys.stderr)
        sys.exit(1)
