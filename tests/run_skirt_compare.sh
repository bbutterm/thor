#!/usr/bin/env bash
# Изолированный тест рендера; сначала импорт проекта, потом отдельный Xorg и llvmpipe.
set -u -o pipefail
umask 077
project=${THOR_SKIRT_PROJECT:-/workspace/thor-skirt}
artifacts=${THOR_SKIRT_ARTIFACTS:-/workspace/thor-artifacts/room-skirt}
mkdir -p "$artifacts"
run=$(mktemp -d "$artifacts/run-XXXXXXXX") || exit 2
mkdir "$run/data" "$run/cache" "$run/config" "$run/shots"
if [[ -n "${THOR_SKIRT_CACHE_FROM:-}" && -d "${THOR_SKIRT_CACHE_FROM}/ThorDostoynayaSmert/shader_cache" ]]; then
    mkdir -p "$run/data/ThorDostoynayaSmert"
    cp -a "${THOR_SKIRT_CACHE_FROM}/ThorDostoynayaSmert/shader_cache" "$run/data/ThorDostoynayaSmert/"
fi
export XDG_DATA_HOME="$run/data"
export XDG_CACHE_HOME="$run/cache"
export XDG_CONFIG_HOME="$run/config"
printf 'run=%s\nproject=%s\nlp_num_threads=%s\nstarted=%s\n' "$run" "$project" "${LP_NUM_THREADS:-default}" "$(date -u +%FT%TZ)" | tee "$run/metadata.txt"
timeout --signal=TERM --kill-after=30s 900 godot --headless --path "$project" --import 2>&1 | head -c 50000000 > "$run/import.log"
if [[ $? != 0 ]]; then
    printf 'import failed: %s/import.log\n' "$run" >&2
    exit 1
fi
cat > "$run/xorg.conf" <<'XCONF'
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
for n in $(seq 140 199); do
    if [[ ! -e "/tmp/.X11-unix/X$n" && ! -e "/tmp/.X$n-lock" ]]; then
        display_num=$n
        break
    fi
done
if [[ -z "$display_num" ]]; then
    printf 'no available X display\n' >&2
    exit 2
fi
ulimit -c 0
/usr/lib/xorg/Xorg ":$display_num" -noreset -nolisten tcp -config "$run/xorg.conf" -logfile "$run/xorg.log" > "$run/xorg-stdout.log" 2>&1 &
xorg_pid=$!
cleanup() {
    kill "$xorg_pid" 2>/dev/null || true
    wait "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT
export DISPLAY=":$display_num"
ready=0
for ((i=0; i<50; i++)); do
    if xdpyinfo >/dev/null 2>&1; then
        ready=1
        break
    fi
    if ! kill -0 "$xorg_pid" 2>/dev/null; then
        break
    fi
    sleep 0.2
done
if [[ "$ready" != 1 ]]; then
    printf 'Xorg failed to start; see %s\n' "$run" >&2
    exit 2
fi
export LIBGL_ALWAYS_SOFTWARE=1
printf 'display=%s\n' "$DISPLAY" | tee -a "$run/metadata.txt"
timeout --signal=TERM --kill-after=30s 1200 stdbuf -oL -eL godot --path "$project" --fixed-fps 60 --audio-driver Dummy --rendering-method gl_compatibility --resolution 320x180 res://tests/room_skirt_compare.tscn -- "$run/shots" 2>&1 | head -c 50000000 > "$run/godot.log"
rc=$?
printf 'finished=%s\nexit_code=%d\n' "$(date -u +%FT%TZ)" "$rc" | tee -a "$run/metadata.txt"
printf 'Godot log: %s/godot.log\n' "$run"
exit "$rc"
