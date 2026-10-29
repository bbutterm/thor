#!/bin/bash
# Перезапуск генератора и откат шума unique_id в сценах без изменений по сути (кроме перечисленных аргументами).
cd "$(dirname "$0")/.."
timeout 900 godot --headless --path . res://tools/build_scenes.tscn > /tmp/regen.log 2>&1
for f in $(git diff --name-only | grep "\.tscn$"); do
	n=$(git diff -U0 "$f" | grep "^[-+]" | grep -v "^+++\|^---" | grep -v "unique_id=" | wc -l)
	if [ "$n" = "0" ]; then git checkout -- "$f"; fi
done
git status --short
