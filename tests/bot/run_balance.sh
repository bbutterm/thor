#!/bin/bash
# Бот-плейтест баланса (блок Б5): все тела × RUNS забегов, профиль навыка PROFILE, в JOBS процессов параллельно.
#   tests/bot/run_balance.sh <папка> [RUNS=5] [PROFILE=skilled] [SEED=11] [JOBS=3]
# Итог: <папка>/<profile>_<n>.jsonl (строка на забег), <папка>/<profile>.md — отчёт balance_report.py.
# Машина общая — JOBS не больше числа свободных ядер; 9 тел × 5 забегов ≈ 15–20 мин на 3 процессах.
set -u
OUT=$(realpath -m "${1:?папка для результатов}")
RUNS=${2:-5}
PROFILE=${3:-skilled}
SEED=${4:-11}
JOBS=${5:-3}
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
BODIES=$(ls run/bodies/*.tres | xargs -n1 basename | sed 's/\.tres$//' | sort)
i=0
declare -a GROUPS_
for b in $BODIES; do
	g=$((i % JOBS))
	GROUPS_[$g]="${GROUPS_[$g]:+${GROUPS_[$g]},}$b"
	i=$((i + 1))
done
for g in "${!GROUPS_[@]}"; do
	f="$OUT/${PROFILE}_$g.jsonl"
	rm -f "$f"
	godot --headless --path . --fixed-fps 60 res://tests/balance_run.tscn -- \
		bodies="${GROUPS_[$g]}" runs="$RUNS" seed="$SEED" profile="$PROFILE" out="$OUT/${PROFILE}_$g.jsonl" \
		2>&1 | head -c 20000000 > "$OUT/${PROFILE}_$g.log" &
done
wait
python3 tests/bot/balance_report.py "$OUT"/"${PROFILE}"_*.jsonl > "$OUT/$PROFILE.md"
grep -h "ИТОГ BALANCE" "$OUT"/"${PROFILE}"_*.log
echo "Отчёт: $OUT/$PROFILE.md"
