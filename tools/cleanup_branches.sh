#!/usr/bin/env bash
# П9 (NOW.md, партия 5): чистка веток на GitHub. Запускать у себя в клоне репозитория (из облачной сессии
# GitHub не даёт пушить метки и удалять ветки — 403).
#   bash tools/cleanup_branches.sh          # показать, что будет сделано
#   bash tools/cleanup_branches.sh --run    # сделать
# 16 веток с коммитами вне main → метки archive/<ветка>, затем удалить; 7 веток, уже целиком в main, — удалить.
# Остаются: main, builds, claude/plan-next.
set -euo pipefail
ARCHIVE="codex/build-work codex/deck-n10 codex/future-finale-art codex/headless-loader codex/hitch-n11 codex/mechanics-review
codex/narrative-review codex/room-color-probe-work codex/shop-art codex/skin-intern-work codex/skirt-work codex/sven-art
codex/ui-combo-overlap wip/b0-dress-rooms wip/b1-outline wip/b5-bot-balance"
MERGED="claude/regen-rooms codex/art-story codex/balance-work codex/main-candidate codex/outline-work codex/preview-work codex/rooms-work"
RUN=${1:-}
git fetch origin --prune
for b in $ARCHIVE; do
  sha=$(git rev-parse "origin/$b" 2>/dev/null || true)
  [ -z "$sha" ] && { echo "нет ветки $b — пропуск"; continue; }
  echo "метка archive/$b → $sha, удалить $b"
  if [ "$RUN" = "--run" ]; then
    git push origin "$sha:refs/tags/archive/$b"
    [ "$(git ls-remote origin "refs/tags/archive/$b" | cut -f1)" = "$sha" ] || { echo "метка archive/$b не создана — стоп"; exit 1; }
    git push origin --delete "$b"
  fi
done
for b in $MERGED; do
  git rev-parse "origin/$b" >/dev/null 2>&1 || { echo "нет ветки $b — пропуск"; continue; }
  if [ -n "$(git rev-list origin/main..origin/$b)" ]; then echo "$b не целиком в main — НЕ удаляю"; continue; fi
  echo "удалить $b (уже в main)"
  [ "$RUN" = "--run" ] && git push origin --delete "$b"
done
echo "Готово. Ветки: $(git ls-remote --heads origin | wc -l)"
