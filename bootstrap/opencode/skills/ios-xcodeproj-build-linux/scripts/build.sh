#!/usr/bin/env bash
# Run one Debug device build in a clean environment and print only a summary.
# Usage: bash build.sh <GATE> <attempt number>   (reads <GATE>/gate.env)
# Full log: <GATE>/logs/build-<n>.log; load samples: <GATE>/logs/load-<n>.log.
set -uo pipefail
GATE=${1:?usage: build.sh <GATE> <n>}
N=${2:?usage: build.sh <GATE> <n>}
# shellcheck disable=SC1091
. "$GATE/gate.env"
SDK="$GATE/home/.config/xtool/darwin.xtoolsdk"
LOG="$GATE/logs/build-$N.log" LOAD="$GATE/logs/load-$N.log"
: > "$LOAD"; : > "$GATE/logs/stub-tools-$N.log"
cd "$GATE/src" || exit 1
start=$(date +%s)
env -i HOME="$GATE/home" CFFIXED_USER_HOME="$GATE/home" XDG_CACHE_HOME="$GATE/cache" TMPDIR="$GATE/tmp" \
    LANG=C.UTF-8 USER="$RUN_USER" LOGNAME="$RUN_USER" STUB_TOOL_LOG="$GATE/logs/stub-tools-$N.log" \
    PATH="$GATE/stub-bin:$SWIFT_BIN:$SDK/toolset/bin:$GATE/deps/root/usr/bin:/usr/bin:/bin" \
    LD_LIBRARY_PATH="$TC/deps/lib/x86_64-linux-gnu:$TC/deps/usr/lib/x86_64-linux-gnu:$GATE/deps/root/usr/lib/x86_64-linux-gnu" \
    "$XTOOL" dev build -c "$CONFIG" --scheme "$SCHEME" --verbose > "$LOG" 2>&1 &
pid=$!
# Stop a hung build: no new log output for STALL_SECONDS (default 300). A hang seen on
# 2026-11-18: the container's process limit (pids.max) was reached, a spawn failed, and
# swift-package waited for ever.
STALL_SECONDS=${STALL_SECONDS:-300}
PIDS=/sys/fs/cgroup/pids.current
last_size=-1 last_change=$(date +%s) max_pids=0 stalled=0
descendants() { # pid -> the pid and all its descendants
    local p=$1 c
    echo "$p"
    for c in $(grep -l "^PPid:[[:space:]]*$p$" /proc/[0-9]*/status 2>/dev/null | cut -d/ -f3); do descendants "$c"; done
}
while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s) size=$(stat -c %s "$LOG")
    [ -r "$PIDS" ] && { p=$(cat "$PIDS"); [ "$p" -gt "$max_pids" ] && max_pids=$p; }
    [ "$size" != "$last_size" ] && { last_size=$size; last_change=$now; }
    echo "$(( now - start ))s $(cut -d' ' -f1-3 /proc/loadavg) tasks=$(grep -c taskComplete "$LOG") pids=${p:-?}" >> "$LOAD"
    if [ $(( now - last_change )) -ge "$STALL_SECONDS" ]; then
        stalled=1
        kill $(descendants "$pid" | sort -rn) 2>/dev/null; sleep 3
        kill -9 $(descendants "$pid" | sort -rn) 2>/dev/null
        break
    fi
    sleep 20
done
wait "$pid"; rc=$?
[ "$stalled" -eq 1 ] && echo "STALLED: no log output for ${STALL_SECONDS}s; build stopped."
echo "BUILD EXIT CODE: $rc elapsed=$(( $(date +%s) - start ))s"
[ -r "$PIDS" ] && echo "process count: peak during build $max_pids of $(cat /sys/fs/cgroup/pids.max) (cgroup peak $(cat /sys/fs/cgroup/pids.peak 2>/dev/null || echo ?))"
grep -m1 -o 'posix_spawn failed: Resource temporarily unavailable' "$LOG" >/dev/null && echo "CAUSE: process limit reached (posix_spawn EAGAIN); raise pids.max or stop other processes."
echo "peak load (1 min avg): $(sort -k2 -n -r "$LOAD" | head -1 | cut -d' ' -f2) of $(nproc) cores"
echo "tasks: $(grep -c taskComplete "$LOG") completed, $(grep -c 'TaskCompleteInfo.Result.failed' "$LOG") failed"
echo "stand-in calls: $(wc -l < "$GATE/logs/stub-tools-$N.log")"
errors=$(grep -E 'DiagnosticInfo.Kind.error' "$LOG")
if [ -n "$errors" ]; then
    echo "errors (count, message):"
    printf '%s\n' "$errors" | grep -oE 'message: "[^"]{0,200}' | sort | uniq -c | sort -rn | head -20
    echo "error locations:"
    printf '%s\n' "$errors" | grep -oE 'Location.path\("[^"]*"' | sed -E "s#$GATE/src/##; s#Location.path\(##" | sort | uniq -c | sort -rn | head -20
fi
if [ "$rc" -eq 0 ]; then
    app=$(find "$GATE/src" -path '*/Products/*-iphoneos/*.app' -maxdepth 8 -type d 2>/dev/null | head -1)
    echo "app: ${app:-not found}"
fi
exit "$rc"
