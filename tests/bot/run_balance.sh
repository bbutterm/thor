#!/usr/bin/env bash
# Все тела × RUNS забегов, PROFILE, не более JOBS независимых процессов.
# tests/bot/run_balance.sh <папка> [RUNS=5] [PROFILE=skilled] [SEED=11] [JOBS=3]
# Необязательный THOR_BOT_TRACE=1 добавляет ограниченную событийную телеметрию в JSONL.
# Необязательный THOR_BOT_MINIBOSS=<id> (fat_sven, hovding, volva, berserker) — мини-босс забега.
set -euo pipefail
OUT=$(realpath -m "${1:?папка для результатов}")
RUNS=${2:-5}
PROFILE=${3:-skilled}
SEED=${4:-11}
JOBS=${5:-3}
TRACE=${THOR_BOT_TRACE:-0}
if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ && "$JOBS" =~ ^[1-9][0-9]*$ && "$SEED" =~ ^[0-9]+$ && "$PROFILE" =~ ^(skilled|average|novice)$ && "$TRACE" =~ ^[01]$ ]]; then
    printf 'Неверные аргументы: runs и jobs > 0, seed >= 0, профиль skilled/average/novice, THOR_BOT_TRACE 0 или 1\n' >&2
    exit 2
fi
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
mapfile -t BODIES < <(find run/bodies -maxdepth 1 -name '*.tres' -printf '%f\n' | sed 's/\.tres$//' | sort)
(( ${#BODIES[@]} > 0 )) || { echo 'Не найдены тела' >&2; exit 2; }
if (( JOBS > ${#BODIES[@]} )); then JOBS=${#BODIES[@]}; fi
declare -a groups=() pids=() files=()
for ((i=0; i<${#BODIES[@]}; i++)); do
    g=$((i % JOBS))
    groups[$g]="${groups[$g]:+${groups[$g]},}${BODIES[$i]}"
done
for ((g=0; g<JOBS; g++)); do
    file="$OUT/${PROFILE}_$g.jsonl"
    log="$OUT/${PROFILE}_$g.log"
    if [[ -e "$file" || -e "$log" ]]; then
        printf 'Результат уже существует: %s или %s. Укажите новую папку.\n' "$file" "$log" >&2
        exit 2
    fi
    files+=("$file")
done
for ((g=0; g<JOBS; g++)); do
    (
        set -o pipefail
        XDG_DATA_HOME="$OUT/user_$g" timeout "${THOR_BOT_TIMEOUT:-3600}" godot --headless --path . --fixed-fps 60 res://tests/balance_run.tscn -- \
            bodies="${groups[$g]}" runs="$RUNS" seed="$SEED" profile="$PROFILE" trace="$TRACE" miniboss="${THOR_BOT_MINIBOSS:-}" out="${files[$g]}" \
            2>&1 | head -c 50000000 > "$OUT/${PROFILE}_$g.log"
    ) &
    pids+=("$!")
done
failed=0
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then failed=1; fi
done
if (( failed )); then
    echo 'Один или несколько процессов бота завершились с ошибкой; отчёт не создан.' >&2
    exit 1
fi
if rg -n 'SCRIPT ERROR|Parse Error' "$OUT"/"${PROFILE}"_*.log; then
    echo 'В журнале найдены ошибки скриптов; отчёт не создан.' >&2
    exit 1
fi
python3 - "$RUNS" "${#BODIES[@]}" "${files[@]}" <<'PY'
import json, sys
expected = int(sys.argv[1]) * int(sys.argv[2])
rows = []
for path in sys.argv[3:]:
    with open(path, encoding='utf-8') as f:
        rows.extend(json.loads(line) for line in f if line.strip())
if len(rows) != expected or any(row.get('outcome') == 'error' for row in rows):
    raise SystemExit(f'Неполный прогон: {len(rows)}/{expected}, ошибки: {sum(row.get("outcome") == "error" for row in rows)}')
PY
python3 tests/bot/balance_report.py "${files[@]}" > "$OUT/$PROFILE.md"
rg --no-filename 'ИТОГ BALANCE' "$OUT"/"${PROFILE}"_*.log
echo "Отчёт: $OUT/$PROFILE.md"
