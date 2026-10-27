#!/usr/bin/env bash
# Стресс Dummy-рендерера и проверка полного журнала, в том числе ошибок, которые Godot не отражает в exit code.
set -uo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
rounds="${1:-5}"
if ! [[ "$rounds" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Число запусков должно быть положительным целым.\n' >&2
  exit 2
fi
out_dir="$(mktemp -d "${TMPDIR:-/tmp}/thor-rid-check.XXXXXXXX")"
godot_bin="${GODOT_BIN:-godot}"
failures=0
printf 'Полные журналы и отдельные user://: %s\n' "$out_dir"
for ((i=1; i<=rounds; i++)); do
  data_dir="$out_dir/user-$i"
  mkdir -p "$data_dir"
  log="$out_dir/run-$i.log"
  XDG_DATA_HOME="$data_dir" timeout 180 "$godot_bin" --headless --path "$project_dir" --fixed-fps 60 res://tests/dummy_rid_stress.tscn 2>&1 | head -c 50000000 > "$log"
  status=$?
  if ((status != 0)); then
    printf 'Запуск %s: код Godot/pipeline %s\n' "$i" "$status" >&2
    failures=$((failures + 1))
  elif grep -nE '^(SCRIPT ERROR:|ERROR:)' "$log"; then
    printf 'Запуск %s: ошибка в журнале (в том числе при очистке).\n' "$i" >&2
    failures=$((failures + 1))
  elif ! grep -q '^STRESS DONE$' "$log"; then
    printf 'Запуск %s: сценарий не сообщил о завершении.\n' "$i" >&2
    failures=$((failures + 1))
  else
    printf 'Запуск %s: OK\n' "$i"
  fi
done
printf 'Итого: %s запусков, %s с ошибками.\n' "$rounds" "$failures"
((failures == 0))
