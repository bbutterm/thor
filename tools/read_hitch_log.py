#!/usr/bin/env python3
"""Read, hash and summarize run_hitch_render.sh output without modifying any input."""
from __future__ import annotations
import argparse
import ast
from collections import Counter
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Any

CAP_BYTES = 50_000_000
RESULT = re.compile(r"^=== ИТОГ HITCH: (\d+) фризов > \+(\d+) мс вне загрузки ===$")
ROOMS = re.compile(r"^Пройдено залов: (\d+) из (\d+)$")
SLAMS = re.compile(r"^Удары-приземления с реальным приземлением: (\d+)$")
NOISE = re.compile(r"^Всплесков без событий > \+(\d+) мс: (\d+) \(не считаются\)$")
FRAMES = re.compile(r"^Кадров: (\d+), медиана ([\d.]+) мс; худший всплеск по событию вне загрузки залов: \+([\d.]+) мс$")
BANNER = re.compile(r"^=== HITCH TEST \(порог \+(\d+) мс к медиане, ([a-z_]+)\) ===$")
ROW = re.compile(r"^\s*(?:(>>>|~)\s+)?кадр (\d+)\s+([\d.]+) мс \(медиана ([\d.]+)\)\s+\[(.*?)\]\s+\(до: (.*?)\)$")
PSO_DETAIL = re.compile(r'^\s+кадр \d+\s')


def file_info(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    digest = sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(65536), b''):
            digest.update(chunk)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def metadata(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    result = {}
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            result[key] = value
    return result


def summarize(directory: Path, short: bool = False) -> dict[str, Any]:
    directory = directory.resolve()
    log_path = directory / 'godot.log'
    if not log_path.is_file():
        raise FileNotFoundError(f'Godot log not found: {log_path}')
    meta = metadata(directory / 'metadata.txt')
    lines = log_path.read_text(encoding='utf-8', errors='replace').splitlines()
    finals = [(i, RESULT.match(line)) for i, line in enumerate(lines) if RESULT.match(line)]
    final_index = finals[0][0] if len(finals) == 1 else None
    final = finals[0][1] if len(finals) == 1 else None
    banners = [BANNER.match(x) for x in lines if BANNER.match(x)]
    room_rows = [ROOMS.match(x) for x in lines if ROOMS.match(x)]
    slam_rows = [SLAMS.match(x) for x in lines if SLAMS.match(x)]
    noise_rows = [NOISE.match(x) for x in lines if NOISE.match(x)]
    frame_rows = [FRAMES.match(x) for x in lines if FRAMES.match(x)]
    pso_rows = [(i + 1, x) for i, x in enumerate(lines) if x.startswith('Компиляции пайплайнов вне загрузки залов:')]
    method = banners[-1].group(2) if banners else meta.get('method')
    requested = meta.get('method')
    method_match = None if method is None or requested is None else method == requested
    complete = bool(final and len(room_rows) == 1 and len(slam_rows) == 1 and len(frame_rows) == 1 and len(banners) == 1)
    noise_count = int(noise_rows[0].group(2)) if len(noise_rows) == 1 else (0 if complete and not noise_rows else None)
    threshold = int(final.group(2)) if final else (int(meta['threshold_ms']) if meta.get('threshold_ms', '').isdigit() else None)
    rows = []
    for number, line in enumerate(lines, 1):
        found = ROW.match(line)
        if found:
            kind, frame, frame_ms, median, current, previous = found.groups()
            rows.append({"line": number, "kind": 'event' if kind == '>>>' else ('unmarked' if kind == '~' else 'loading'), "frame": int(frame),
                         "frame_ms": float(frame_ms), "local_median_ms": float(median),
                         "displayed_excess_ms": round(float(frame_ms) - float(median), 2),
                         "current": current, "previous": previous, "raw": line})
    error_entries = []
    for i, line in enumerate(lines):
        if 'ERROR:' not in line and 'Parse Error' not in line and 'HITCH FAIL' not in line:
            continue
        phase = 'undetermined' if final_index is None else ('execution' if i < final_index else 'after_result')
        # Godot prints stack traces as indented lines following an error.  Keep
        # the entire contiguous block, plus nearby lines for local context.
        block_end = i + 1
        while block_end < len(lines) and lines[block_end][:1].isspace() and not any(
            marker in lines[block_end] for marker in ('ERROR:', 'Parse Error', 'HITCH FAIL')
        ):
            block_end += 1
        error_entries.append({"line": i + 1, "phase": phase, "text": line,
                              "context_start_line": max(1, i - 1),
                              "context": lines[max(0, i - 2):min(len(lines), max(i + 3, block_end + 2))]})
    phases = Counter(item['phase'] for item in error_entries)
    cleanup_warnings = [{"line": i + 1, "text": line} for i, line in enumerate(lines)
                        if final_index is not None and i > final_index and 'WARNING:' in line]
    resource_warnings = [item for item in cleanup_warnings if re.search(r'objectdb|leak|resource', item['text'], re.IGNORECASE)]
    pso_line = pso_rows[0][1] if len(pso_rows) == 1 else None
    pso = {"state": 'missing', "draw_compilations": None, "all_compilations": None,
           "report_line": pso_line, "detail_lines": []}
    if len(pso_rows) == 1:
        # Only the contiguous detail rows following this summary are guaranteed
        # to be outside loading windows; earlier spike rows may include loading.
        index = pso_rows[0][0]
        while index < len(lines) and PSO_DETAIL.match(lines[index]):
            pso['detail_lines'].append({"line": index + 1, "text": lines[index]})
            index += 1
    if method in ('gl_compatibility', 'headless'):
        pso['state'] = 'unavailable_for_renderer'
    elif method in ('forward_plus', 'mobile') and pso_line is not None:
        content = pso_line.split(':', 1)[1].strip()
        try:
            counts = {} if content == 'нет' else ast.literal_eval(content)
        except (SyntaxError, ValueError):
            counts = None
        if isinstance(counts, dict) and all(isinstance(k, str) and k.startswith('pso_')
                                            and type(v) is int and v >= 0 for k, v in counts.items()):
            pso['state'] = 'available'
            pso['all_compilations'] = counts
            pso['draw_compilations'] = counts.get('pso_draw', 0)
        else:
            pso['state'] = 'unparsed_report'
    room_result = {"completed": int(room_rows[0].group(1)), "total": int(room_rows[0].group(2))} if len(room_rows) == 1 else None
    slams = int(slam_rows[0].group(1)) if len(slam_rows) == 1 else None
    event_hitches = int(final.group(1)) if final else None
    launcher_exit = int(meta['exit_code']) if re.fullmatch(r'-?\d+', meta.get('exit_code', '')) else None
    issues = []
    for label, count in [('result', len(finals)), ('banner', len(banners)), ('room_summary', len(room_rows)), ('slam_summary', len(slam_rows)), ('frame_summary', len(frame_rows)), ('pso_summary', len(pso_rows)), ('noise_summary', len(noise_rows))]:
        if count > 1:
            issues.append(f'multiple_{label}_lines:{count}')
    if log_path.stat().st_size >= CAP_BYTES:
        issues.append('log_at_or_above_50MB_cap_may_be_truncated')
    report = {
        "input": {"directory": str(directory), "godot_log": file_info(log_path), "metadata_file": file_info(directory / 'metadata.txt'),
                  "hitches_log": file_info(directory / 'data/ThorDostoynayaSmert/hitches.log'),
                  "user_godot_log": file_info(directory / 'data/ThorDostoynayaSmert/logs/godot.log'),
                  "xorg_log": file_info(directory / 'xorg.log'), "server_log": file_info(directory / 'server.log'),
                  "godot_errors_log": file_info(directory / 'godot-errors.log')},
        "metadata": meta, "method": method, "requested_method": requested, "method_matches_request": method_match,
        "adapter_lines": [line for line in lines if 'OpenGL API ' in line or 'Vulkan API ' in line or line.startswith('Renderer:')],
        "complete_summary": complete, "rooms": room_result, "actual_landings": slams,
        "frames": {"count": int(frame_rows[0].group(1)), "global_median_ms": float(frame_rows[0].group(2)),
                   "worst_event_excess_ms": float(frame_rows[0].group(3))} if len(frame_rows) == 1 else None,
        "threshold_ms": threshold, "event_hitches": event_hitches, "unmarked_spikes": noise_count,
        "spike_rows_above_half_threshold": {kind: sum(r['kind'] == kind for r in rows) for kind in ('event', 'unmarked', 'loading')},
        "spike_rows": [] if short else rows, "pso_draw_outside_loading": pso,
        "errors": {"execution_count": phases['execution'], "after_result_count": phases['after_result'],
                   "undetermined_count": phases['undetermined'], "entries": [] if short else error_entries,
                   "classification_note": 'Phase follows position relative to the unique result line; absent/duplicate result leaves phase undetermined.'},
        "warnings_after_result": cleanup_warnings, "resource_warnings_after_result": len(resource_warnings),
        "clean_shutdown": (not phases['after_result'] and not cleanup_warnings) if final_index is not None and launcher_exit is not None and log_path.stat().st_size < CAP_BYTES else None,
        "launcher_exit": launcher_exit, "integrity_issues": issues,
        "launcher_and_test_pass": bool(complete and room_result and room_result['completed'] == 10 and room_result['total'] == 10
                                       and slams and event_hitches == 0 and not error_entries and not issues and launcher_exit == 0 and method_match is not False),
        "pso_draw_requires_review": (pso['draw_compilations'] > 0) if pso['state'] == 'available' else None,
        "interpretation": 'Unmarked spikes are omitted from the test hitch total. GL/Dummy compilation counters are unavailable; pso_draw must be reviewed separately when supported.'}
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--summary', action='store_true', help='omit detailed spike/error entries; input logs remain unchanged')
    args = parser.parse_args()
    try:
        report = summarize(args.directory, short=args.summary)
    except (OSError, ValueError) as exc:
        parser.exit(2, f'{exc}\n')
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
