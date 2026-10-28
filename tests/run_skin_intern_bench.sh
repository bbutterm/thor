#!/usr/bin/env bash
# Эксперимент в отдельном процессе и Xorg; не запускайте параллельно с бенчмарками.
set -u -o pipefail
umask 077
mode=${1:-mixed}
if [[ "$mode" != mixed && "$mode" != all_grunts ]]; then
    printf 'usage: %s [mixed|all_grunts]\n' "$0" >&2
    exit 2
fi
project=${THOR_SKIN_PROJECT:-/workspace/thor-skins}
artifacts=${THOR_SKIN_ARTIFACTS:-/workspace/thor-artifacts/skin-intern}
method=${THOR_SKIN_RENDER_METHOD:-gl_compatibility}
mkdir -p "$artifacts"
run=$(mktemp -d "$artifacts/${mode}-XXXXXXXX") || exit 2
mkdir "$run/data" "$run/cache" "$run/config" "$run/shots"
export XDG_DATA_HOME="$run/data"
export XDG_CACHE_HOME="$run/cache"
export XDG_CONFIG_HOME="$run/config"
printf 'run=%s\nproject=%s\nmode=%s\nmethod=%s\nlp_num_threads=%s\nstarted=%s\n' "$run" "$project" "$mode" "$method" "${LP_NUM_THREADS:-default}" "$(date -u +%FT%TZ)" | tee "$run/metadata.txt"
timeout --signal=TERM --kill-after=30s 900 godot --headless --path "$project" --import 2>&1 | head -c 50000000 > "$run/import.log"
if [[ $? != 0 ]]; then
    printf 'import failed: %s/import.log\n' "$run" >&2
    exit 1
fi
timeout --signal=TERM --kill-after=30s 300 godot --headless --path "$project" --fixed-fps 60 res://tests/skin_intern_experiment.tscn 2>&1 | head -c 50000000 > "$run/functional.log"
if [[ $? != 0 ]]; then
    printf 'functional check failed: %s/functional.log\n' "$run" >&2
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
for n in $(seq 150 199); do
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
if [[ "$method" == gl_compatibility ]]; then
    export LIBGL_ALWAYS_SOFTWARE=1
fi
printf 'display=%s\n' "$DISPLAY" | tee -a "$run/metadata.txt"
args=("$run/shots")
if [[ "$mode" == all_grunts ]]; then
    args+=("all_grunts")
fi
timeout --signal=TERM --kill-after=30s 1500 stdbuf -oL -eL godot --path "$project" --fixed-fps 60 --audio-driver Dummy --rendering-method "$method" --resolution 320x180 res://tests/skin_intern_bench.tscn -- "${args[@]}" 2>&1 | head -c 50000000 > "$run/godot.log"
rc=$?
printf 'finished=%s\nexit_code=%d\n' "$(date -u +%FT%TZ)" "$rc" | tee -a "$run/metadata.txt"
printf 'Godot log: %s/godot.log\n' "$run"
exit "$rc"
