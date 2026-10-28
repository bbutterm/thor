#!/usr/bin/env bash
# Sequential diagnostic; run only in an available headless window after import.
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  printf 'Usage: %s /absolute/new/results-directory\n' "$0" >&2
  exit 2
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
engine=${THOR_GODOT_BIN:-godot}
command -v -- "$engine" >/dev/null
# Refuse to overwrite anything, including prior result JSONL or user data.
mkdir -- "$1"
result_dir=$(cd -- "$1" && pwd -P)
case "$result_dir/" in
  "$project_dir/"*) printf 'Results must be outside the project tree.\n' >&2; exit 2 ;;
esac

git -C "$project_dir" rev-parse HEAD > "$result_dir/commit.txt"
git -C "$project_dir" status --porcelain=v1 > "$result_dir/worktree-status.txt"
sha256sum "$project_dir/tests/bot/fixed_encounter_room.tscn" \
  "$project_dir/tests/bot/fixed_encounter_runner.gd" > "$result_dir/fixture-sha256.txt"

for trace in 0 1; do
  for repeat in 1 2 3; do
    # Alternate the order to avoid always running one variant first.
    if (( repeat % 2 == 0 )); then modes=(1 0); else modes=(0 1); fi
    for teardown in "${modes[@]}"; do
      used_bytes=$(du -sb -- "$result_dir" | cut -f1)
      if (( used_bytes > 25000000 )); then
        printf 'Stopping: result directory exceeded the 25 MB reserve (%s bytes).\n' "$used_bytes" >&2
        exit 1
      fi
      case_dir="$result_dir/trace${trace}_repeat${repeat}_teardown${teardown}"
      mkdir -- "$case_dir" "$case_dir/user"
      cmd=(timeout --kill-after=5s 180s "$engine" --headless --verbose --path "$project_dir"
        --fixed-fps 60 --audio-driver Dummy res://tests/fixed_encounter_run.tscn --
        body=thrall profile=skilled seed=11 "trace=$trace" "teardown=$teardown" "out=$case_dir/result.jsonl")
      {
        printf 'ulimit -c 0; ulimit -f 512; XDG_DATA_HOME=%q ' "$case_dir/user"
        printf '%q ' "${cmd[@]}"
        printf '\n'
      } > "$case_dir/command.txt"
      printf 'Running trace=%s repeat=%s teardown=%s\n' "$trace" "$repeat" "$teardown"
      status=0
      (
        ulimit -c 0
        # Bash units are 1024 bytes. Applies to stdout and Godot's own log files.
        ulimit -f 512
        export XDG_DATA_HOME="$case_dir/user"
        "${cmd[@]}"
      ) > "$case_dir/combined.log" 2>&1 || status=$?
      printf '%s\n' "$status" > "$case_dir/exit.status"
      if (( status != 0 )); then
        printf 'Process failed or hit a limit (%s); retain %s and stop.\n' "$status" "$case_dir" >&2
        exit 1
      fi
      capped_file=$(find "$case_dir" -type f -size +524287c -print -quit)
      if [[ -n "$capped_file" ]]; then
        printf 'Potentially capped file %s; retain this run and stop.\n' "$capped_file" >&2
        exit 1
      fi
      # The resource-at-exit ERROR is the measurement, not a script failure.
      validation_status=0
      python3 - "$case_dir" "$trace" "$teardown" > "$case_dir/validation.log" 2>&1 <<'PY' || validation_status=$?
import json
import re
import sys
from pathlib import Path

case = Path(sys.argv[1])
trace, teardown = sys.argv[2:]
log = (case / "combined.log").read_text(errors="replace")
unexpected = [line for line in log.splitlines()
              if (line.startswith("SCRIPT ERROR:") or line.startswith("ERROR:"))
              and not re.match(r"^ERROR: \d+ resources still in use at exit", line)]
if unexpected:
    sys.exit("Unexpected engine/script error; retain the log and stop: " + unexpected[0])
lines = (case / "result.jsonl").read_text().splitlines()
if len(lines) != 1:
    sys.exit("Expected exactly one recorded result")
row = json.loads(lines[0])
if (not row.get("valid") or row.get("body") != "thrall" or row.get("seed") != 11
        or row.get("trace_enabled") != (trace == "1") or row.get("picks") != []):
    sys.exit("Invalid or unexpected recorded scenario")
marker = "FIXED TEARDOWN: game_freed=true room_freed=true bot_freed=true stayed_paused=true"
if (teardown == "1" and log.count(marker) != 1) or (teardown == "0" and "FIXED TEARDOWN:" in log):
    sys.exit("Missing or unexpected teardown verification")
leak = re.search(r"^ERROR: (\d+) resources still in use at exit", log, re.M)
print("  outcome=%s spawned=%d/%d exit_resources=%s" %
      (row.get("outcome"), len(row.get("spawned", [])), len(row.get("planned", [])),
       leak.group(1) if leak else "none"))
PY
      cat "$case_dir/validation.log"
      if (( validation_status != 0 )); then
        printf 'Validation failed; retain %s and stop.\n' "$case_dir" >&2
        exit 1
      fi
      used_bytes=$(du -sb -- "$result_dir" | cut -f1)
      if (( used_bytes > 25000000 )); then
        printf 'Stopping: result directory exceeded the 25 MB reserve (%s bytes).\n' "$used_bytes" >&2
        exit 1
      fi
    done
  done
done
used_bytes=$(du -sb -- "$result_dir" | cut -f1)
printf 'All runs saved in %s (%s bytes). Inspect full logs, including ObjectDB warnings.\n' "$result_dir" "$used_bytes"
