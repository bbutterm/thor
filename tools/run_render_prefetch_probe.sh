#!/usr/bin/env bash
set -uo pipefail
project=${1:-}
out=${2:-}
if [[ -z "$project" || -z "$out" || $# != 2 || -e "$out" ]]; then echo 'Usage: run-gl-probe.sh <project> <new-output-dir>' >&2; exit 2; fi
project=$(cd "$project" && pwd -P)
mkdir -p "$out" || exit 2
out=$(cd "$out" && pwd -P)
mkdir "$out/data" "$out/cache" "$out/config"
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
n=
for ((i=180; i<=199; i++)); do
  if [[ ! -e "/tmp/.X11-unix/X$i" && ! -e "/tmp/.X$i-lock" ]]; then n=$i; break; fi
done
if [[ -z "$n" ]]; then echo 'No free X display' >&2; exit 2; fi
ulimit -c 0
/usr/lib/xorg/Xorg ":$n" -config "$out/xorg.conf" -logfile "$out/xorg.log" -noreset -nolisten tcp > "$out/server.log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT
export DISPLAY=":$n"
ready=0
for ((i=0; i<50; i++)); do
  if xdpyinfo >/dev/null 2>&1; then ready=1; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 0.2
done
if (( ready != 1 )); then echo 'X server failed' >&2; exit 2; fi
export XDG_DATA_HOME="$out/data" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/config"
timeout --signal=TERM --kill-after=15s 600 stdbuf -oL -eL godot --path "$project" --fixed-fps 60 --audio-driver Dummy --rendering-method gl_compatibility --resolution 320x180 res://tests/render_prefetch_probe.tscn 2>&1 | stdbuf -i0 -o0 head -c 50000000 > "$out/godot.log"
rc=$?
runtime=$(sed '/^RENDER PREFETCH RESULT:/,$d' "$out/godot.log" | grep -cE '^(ERROR:|SCRIPT ERROR:)' || true)
cleanup_errors=$(sed -n '/^RENDER PREFETCH RESULT:/,$p' "$out/godot.log" | grep -cE '^ERROR:' || true)
printf 'commit=%s\nasset_cache_load=threaded\nexit_code=%d\nruntime_errors=%d\ncleanup_errors=%d\n' \
  "$(git -C "$project" rev-parse HEAD)" "$rc" "$runtime" "$cleanup_errors" | tee "$out/metadata.txt"
grep -E '^RENDER PREFETCH:|^REQUESTS:|^BODY:|^PORTRAIT:|^RENDER PREFETCH RESULT:' "$out/godot.log" || true
if (( rc != 0 || runtime != 0 )) || ! grep -q '^RENDER PREFETCH RESULT: PASS$' "$out/godot.log" || grep -qE 'SCRIPT ERROR|Parse Error' "$out/godot.log"; then exit 1; fi
