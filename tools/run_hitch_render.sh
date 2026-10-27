#!/usr/bin/env bash
# Прогон с отдельным дисплеем и сохранением результатов: см. docs/hitch_2026-10-27.md.
set -uo pipefail

method=${1:-}
out=${2:-}
if [[ ! "$method" =~ ^(gl_compatibility|forward_plus)$ || -z "$out" || $# != 2 ]]; then
    printf 'Использование: %s gl_compatibility|forward_plus <новая папка результатов>\n' "$0" >&2
    exit 2
fi
if [[ -e "$out" ]]; then
    printf 'Папка уже существует: %s. Укажите новую папку.\n' "$out" >&2
    exit 2
fi
for dependency in godot timeout xdpyinfo; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Не найдена программа: %s\n' "$dependency" >&2
        exit 2
    fi
done
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ ! -d "$root/.godot/imported" ]]; then
    printf 'Сначала импортируйте проект в Godot: %s\n' "$root" >&2
    exit 2
fi
if command -v Xvfb >/dev/null 2>&1; then
    server=$(command -v Xvfb)
    server_kind=xvfb
elif [[ -x /usr/lib/xorg/Xorg ]]; then
    server=/usr/lib/xorg/Xorg
    server_kind=xorg
elif command -v Xorg >/dev/null 2>&1; then
    server=$(command -v Xorg)
    server_kind=xorg
else
    echo 'Нужен Xvfb или Xorg с драйвером dummy.' >&2
    exit 2
fi

umask 077
mkdir -p -- "$out" || exit 2
out=$(cd "$out" && pwd -P)
mkdir "$out/data" "$out/cache" "$out/config" || exit 2
cat > "$out/xorg.conf" <<'XCONF'
Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection
Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync 28-80
    VertRefresh 48-75
    Modeline "1280x720" 74.25 1280 1390 1430 1650 720 725 730 750
EndSection
Section "Screen"
    Identifier "DummyScreen"
    Device "DummyDevice"
    Monitor "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1280x720"
    EndSubSection
EndSection
XCONF

display_num=
for ((n=101; n<=199; n++)); do
    if [[ ! -e "/tmp/.X11-unix/X$n" && ! -e "/tmp/.X$n-lock" ]]; then
        display_num=$n
        break
    fi
done
if [[ -z "$display_num" ]]; then
    echo 'Не найден свободный дисплей X11.' >&2
    exit 2
fi
ulimit -c 0
if [[ "$server_kind" == xvfb ]]; then
    "$server" ":$display_num" -screen 0 1280x720x24 -noreset -nolisten tcp > "$out/server.log" 2>&1 &
else
    "$server" ":$display_num" -config "$out/xorg.conf" -logfile "$out/xorg.log" -noreset -nolisten tcp > "$out/server.log" 2>&1 &
fi
server_pid=$!
cleanup() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export DISPLAY=":$display_num"
ready=0
for ((i=0; i<50; i++)); do
    if xdpyinfo >/dev/null 2>&1; then
        ready=1
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        break
    fi
    sleep 0.2
done
if [[ "$ready" != 1 ]]; then
    printf 'Не удалось запустить дисплей. Лог: %s\n' "$out/server.log" >&2
    exit 2
fi

export XDG_DATA_HOME="$out/data"
export XDG_CACHE_HOME="$out/cache"
export XDG_CONFIG_HOME="$out/config"
limit=${THOR_HITCH_TIMEOUT:-7200}
threshold=${THOR_HITCH_THRESHOLD_MS:-50}
printf 'method=%s\ndisplay=%s\nproject=%s\ntimeout=%s\nthreshold_ms=%s\nstarted_utc=%s\n' \
    "$method" "$DISPLAY" "$root" "$limit" "$threshold" "$(date -u +%FT%TZ)" | tee "$out/metadata.txt"
timeout --signal=TERM --kill-after=30s "$limit" godot --path "$root" --fixed-fps 60 --audio-driver Dummy \
    --rendering-method "$method" --resolution 320x180 res://tests/hitch_test.tscn -- "$threshold" \
    2>&1 | head -c 50000000 > "$out/godot.log"
rc=$?
if (( rc == 0 )) && ! grep -Fq "медиане, $method)" "$out/godot.log"; then
    echo 'Тест не подтвердил запрошенный метод рендеринга.' >&2
    rc=1
fi
if (( rc == 0 )) && { ! grep -Fq 'Удары-приземления с реальным приземлением:' "$out/godot.log" || ! grep -Fq '=== ИТОГ HITCH:' "$out/godot.log"; }; then
    echo 'В журнале нет полного итога сценария.' >&2
    rc=1
fi
if (( rc == 0 )) && grep -Eq 'SCRIPT ERROR|Parse Error' "$out/godot.log"; then
    echo 'В журнале есть ошибка скрипта или разбора.' >&2
    rc=1
fi
printf 'finished_utc=%s\nexit_code=%d\n' "$(date -u +%FT%TZ)" "$rc" | tee -a "$out/metadata.txt"
printf 'Результат: %s/godot.log\n' "$out"
exit "$rc"
