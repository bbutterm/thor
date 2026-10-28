#!/usr/bin/env bash
set -uo pipefail
out=/workspace/thor-artifacts/body-trait-text/gl-captures
project=/workspace/thor-body-trait-gl-shots
attempt=${1:?specify attempt number}
if [[ ! $attempt =~ ^[0-9][0-9]$ || -e "$out/gl_$attempt.log" || -e "$out/shots_$attempt" ]]; then
    printf 'Invalid or already used attempt: %s\n' "$attempt" >&2
    exit 2
fi
mkdir -p "$out/shots_$attempt"
ulimit -c 0
ulimit -f 48000
display_num=
for n in $(seq 150 199); do
    if [[ ! -e "/tmp/.X11-unix/X$n" && ! -e "/tmp/.X$n-lock" ]]; then
        display_num=$n
        break
    fi
done
if [[ -z $display_num ]]; then
    printf 'No unused X display\n' >&2
    exit 2
fi
/usr/lib/xorg/Xorg ":$display_num" -config "$out/xorg.conf" -logfile "$out/xorg_$attempt.log" \
    -noreset -nolisten tcp > "$out/server_$attempt.log" 2>&1 &
xorg_pid=$!
cleanup() {
    kill "$xorg_pid" 2>/dev/null || true
    wait "$xorg_pid" 2>/dev/null || true
}
trap cleanup EXIT
export DISPLAY=":$display_num"
ready=0
for ((i=0; i<50; i++)); do
    if xdpyinfo >/dev/null 2>&1; then ready=1; break; fi
    if ! kill -0 "$xorg_pid" 2>/dev/null; then break; fi
    sleep 0.2
done
if [[ $ready != 1 ]]; then printf 'Xorg failed to start\n' >&2; exit 2; fi
export XDG_DATA_HOME=/tmp/thor-trait-text-shot-data
export XDG_CACHE_HOME=/tmp/thor-trait-text-shot-cache
export XDG_CONFIG_HOME=/tmp/thor-trait-text-shot-config
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS=4
if timeout --signal=TERM --kill-after=10s 300 godot --path "$project" --fixed-fps 60 \
    --audio-driver Dummy --rendering-method gl_compatibility --resolution 1280x720 \
    res://tests/body_trait_text_shots.tscn -- "$out/shots_$attempt" > "$out/gl_$attempt.log" 2>&1; then
    rc=0
else
    rc=$?
fi
printf '%s\n' "$rc" > "$out/gl_$attempt.exit"
exit "$rc"
