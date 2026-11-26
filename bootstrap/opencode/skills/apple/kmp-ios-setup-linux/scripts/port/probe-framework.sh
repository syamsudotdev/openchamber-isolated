#!/usr/bin/env bash
# Minimal iOS ARM64 framework probe for the qualified Linux port (SKILL.md step 5).
# It compiles one exported public Kotlin class with konanc, never Gradle and never
# the application, and checks the static framework with the port's own tools.
#
#   bash probe-framework.sh [--root <root>]
#
# Needs: the machine record, KONAN_HOME (C01 with the C02 iOS members), the agent
# jars (build-agent.sh) and the adapters (install-port.sh). No network.
# Output: <root>/cache/framework-probe/Probe.framework and a PASS/FAIL line per check.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib.sh
. "$HERE/../lib.sh"

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT=${2:?--root needs a path}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ROOT" ] || ROOT=$(default_root)
cli_record "$ROOT"
check_root_writable "$ROOT"
for need in KONAN_HOME KMP_IOS_AGENT_JAR KMP_IOS_BOOTSTRAP_JAR KMP_IOS_LIBTOOL KMP_IOS_ARCHIVE_INSPECTOR; do
    value=${!need:-}
    [ -n "$value" ] && [ -e "$value" ] || { printf 'BLOCK %s is not installed (%s); fix: SKILL.md steps 3 and 5\n' "$need" "${value:-empty}" >&2; exit 1; }
done
command -v node >/dev/null 2>&1 || { echo 'BLOCK node is required by the archive inspector (C26)' >&2; exit 1; }

WORK=$ROOT/cache/framework-probe
rm -rf -- "$WORK"
# The agent points the Xcode override at a deliberately empty sysroot inside the root.
mkdir -p "$WORK/src" "$ROOT/empty-sysroot" "$ROOT/tmp/home" "$ROOT/logs"
cat > "$WORK/src/Probe.kt" <<'EOF'
package probe

class ProbeApi {
    fun answer(input: Int): Int = input * 6 + 0
}

fun probeGreeting(name: String): String = "probe:" + name
EOF

LOG=$ROOT/logs/framework-probe.log
: > "$ROOT/logs/archiver-invocations.log"
export KMP_IOS_ARCHIVER_LOG=$ROOT/logs/archiver-invocations.log
export JAVA_TOOL_OPTIONS="-XX:-UsePerfData -Djava.io.tmpdir=$ROOT/tmp -Duser.home=$ROOT/tmp/home -Dprobe.root=$ROOT -Dprobe.toolchain=$ROOT/linux-toolchain -Dprobe.sysroot=$ROOT/empty-sysroot -javaagent:$KMP_IOS_AGENT_JAR=$KMP_IOS_BOOTSTRAP_JAR"
start=$(date +%s)
set +e
# enableDebugTransparentStepping=false: the Linux compiler's LLVM stubs assert
# (DebugInfoC.cpp, `assert(false)` outside __APPLE__) when an Apple target asks
# for the transparent-stepping flag, which is on by default; -opt does not avoid it.
"$KONAN_HOME/bin/konanc" -target ios_arm64 -produce framework -Xstatic-framework \
    -Xbinary=enableDebugTransparentStepping=false \
    "-Xoverride-konan-properties=targetToolchain.linux_x64-ios_arm64=$ROOT/linux-toolchain;additionalToolsDir.linux_x64=$ROOT/linux-toolchain" \
    -o "$WORK/Probe" "$WORK/src/Probe.kt" > "$LOG" 2>&1
rc=$?
set -e
printf 'konanc exit %s after %ss; log %s\n' "$rc" "$(( $(date +%s) - start ))" "$LOG"
grep -E '^PROBE3:' "$LOG" | sort -u || true
[ "$rc" -eq 0 ] || { tail -n 40 "$LOG" >&2; echo 'FAIL konanc did not produce the framework' >&2; exit 1; }

FW=$WORK/Probe.framework
fail=0
check() { # label command...
    local label=$1; shift
    if "$@" >/dev/null 2>&1; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fail=1; fi
}
check 'framework binary is a regular ar archive' sh -c "head -c 8 '$FW/Probe' | grep -q '^!<arch>'"
check 'libtool adapter ran (archiver log has one llvm-ar line)' grep -q 'llvm-ar --format=darwin rcsD' "$ROOT/logs/archiver-invocations.log"
check 'header exports ProbeApi.answer' grep -q 'answerInput' "$FW/Headers/Probe.h"
check 'header exports probeGreeting' grep -q 'probeGreetingName' "$FW/Headers/Probe.h"
check 'module map names the framework module' grep -qE '^framework module "?Probe"? ' "$FW/Modules/module.modulemap"
grep -E 'answerInput|probeGreetingName' "$FW/Headers/Probe.h" || true
check 'Info.plist targets iPhoneOS' grep -q 'iPhoneOS' "$FW/Info.plist"
if node "$KMP_IOS_ARCHIVE_INSPECTOR" "$FW/Probe" > "$WORK/archive-check.json" 2>&1; then
    tail -n 1 "$WORK/archive-check.json"
    node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");const j=JSON.parse(t.slice(0,t.lastIndexOf("}")+1));console.log("archive bytes",j.archiveBytes,"objects",j.objects.length,"indexed symbols",j.symbolTableEntries)' "$WORK/archive-check.json"
else
    tail -n 5 "$WORK/archive-check.json"; echo 'FAIL archive inspector rejected the framework binary'; fail=1
fi
[ "$fail" -eq 0 ] || { echo 'FRAMEWORK PROBE FAIL'; exit 1; }
printf 'FRAMEWORK PROBE PASS %s\n' "$FW"
