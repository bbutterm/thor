#!/usr/bin/env bash
# Full suite with isolated data and capped logs. Keep intentional error diagnostics
# visible, but fail on unexpected execution errors as well as test failures.
set -uo pipefail
project=${1:?project directory required}
out=${2:?new output directory required}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 2
project=$(cd "$project" && pwd -P) || exit 2
if [[ -e "$out" ]]; then
    printf 'Output directory already exists: %s\n' "$out" >&2
    exit 2
fi
mkdir -p "$out/import-data" || exit 2
out=$(cd "$out" && pwd -P) || exit 2
XDG_DATA_HOME="$out/import-data" godot --headless --path "$project" --import 2>&1 | head -c 50000000 > "$out/import.log"
pipe_status=("${PIPESTATUS[@]}")
if (( pipe_status[0] != 0 || pipe_status[1] != 0 )) || grep -En 'ERROR:|SCRIPT ERROR|Parse Error' "$out/import.log" > "$out/import-errors.log"; then
    printf 'Import failed; see %s/import.log\n' "$out" >&2
    exit 1
fi
total=0
failed=0
for scene in "$project"/tests/*_test.tscn; do
    name=$(basename "$scene" .tscn)
    total=$((total + 1))
    mkdir -p "$out/user/$name"
    timeout --signal=TERM --kill-after=10s 300s env XDG_DATA_HOME="$out/user/$name" \
        godot --headless --path "$project" --fixed-fps 60 --audio-driver Dummy "res://tests/$name.tscn" \
        2>&1 | head -c 50000000 > "$out/$name.log"
    pipe_status=("${PIPESTATUS[@]}")
    grep -En 'SCRIPT ERROR|Parse Error|\[FAIL\]|^[[:space:]]*FAIL:|HITCH FAIL|(^|[^0-9])[1-9][0-9]*[[:space:]]+FAIL([[:space:]=]|$)' "$out/$name.log" > "$out/$name.failures" || true
    # Godot reports resources retained until exit as ERROR. Preserve these in a
    # separate file; expected corruption/refusal cases are also recorded there.
    parser_status=0
    python3 "$script_dir/godot_log_check.py" suite "$out/$name.log" "$name" \
        "$out/$name.expected-errors" "$out/$name.godot-errors" || parser_status=$?
    if (( pipe_status[0] != 0 || pipe_status[1] != 0 || parser_status != 0 )) || [[ -s "$out/$name.failures" || -s "$out/$name.godot-errors" ]]; then
        printf 'FAIL %-30s exit=%s cap=%s\n' "$name" "${pipe_status[0]}" "${pipe_status[1]}" | tee -a "$out/summary.txt"
        failed=$((failed + 1))
    else
        printf 'PASS %s\n' "$name" | tee -a "$out/summary.txt"
    fi
    if [[ -s "$out/$name.expected-errors" ]]; then
        printf 'NOTE %s: intentional or shutdown diagnostics saved in %s.expected-errors\n' "$name" "$name" | tee -a "$out/summary.txt"
    fi
done
printf 'TOTAL %d, FAILED %d\n' "$total" "$failed" | tee -a "$out/summary.txt"
(( failed == 0 ))
