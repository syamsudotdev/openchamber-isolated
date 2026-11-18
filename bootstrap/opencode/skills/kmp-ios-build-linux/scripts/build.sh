#!/usr/bin/env bash
# Run the KMP framework build and the unsigned xtool Release packaging in a clean
# environment, and print only a summary. Run preflight.sh first.
# Usage: bash build.sh <GATE> <attempt number>   (reads <GATE>/gate.env)
# Logs: <GATE>/logs/framework-<n>.log and <GATE>/logs/package-<n>.log.
set -uo pipefail
GATE=${1:?usage: build.sh <GATE> <n>}
N=${2:?usage: build.sh <GATE> <n>}
# shellcheck disable=SC1091
. "$GATE/gate.env"
mkdir -p "$GATE/logs"
summary() { # log
    echo "  errors: $(grep -c -E '(^e: |error:|FAILURE:)' "$1")"
    grep -E '(^e: |error:|FAILURE:|What went wrong)' "$1" | sed -E "s#$PROJECT/##g" | sort | uniq -c | sort -rn | cut -c1-220 | head -15
}

# 1. Framework. FRAMEWORK_BUILD_CMD is a reviewed gate script (for example one that
# passes the qualified port's agent and init script); otherwise run FRAMEWORK_TASK.
busy=$(for p in /proc/[0-9]*; do tr '\0' ' ' < "$p/cmdline" 2>/dev/null; echo; done | grep -v grep | grep -c -E 'gradlew|GradleWrapperMain')
[ "$busy" -eq 0 ] || { echo "Another Gradle command is running; wait for it."; exit 3; }
start=$(date +%s)
if [ -n "${FRAMEWORK_BUILD_CMD:-}" ]; then
    bash "$FRAMEWORK_BUILD_CMD" > "$GATE/logs/framework-$N.log" 2>&1; rc=$?
else
    (cd "$PROJECT" && env -i HOME="${BUILD_HOME:-$GATE/home}" LANG=C.UTF-8 USER="${RUN_USER:-$(id -un)}" \
        JAVA_HOME="${JAVA_HOME_FOR_BUILD:-}" PATH="${JAVA_HOME_FOR_BUILD:+$JAVA_HOME_FOR_BUILD/bin:}/usr/bin:/bin" \
        ./gradlew "${FRAMEWORK_TASK:?gate.env: FRAMEWORK_TASK}" --console=plain ${GRADLE_ARGS:-}) \
        > "$GATE/logs/framework-$N.log" 2>&1; rc=$?
fi
echo "FRAMEWORK EXIT CODE: $rc elapsed=$(( $(date +%s) - start ))s"
grep -E 'SKIPPED|UP-TO-DATE|NO-SOURCE' "$GATE/logs/framework-$N.log" | grep -iE 'link.*Framework.*Ios' | head -3
[ "$rc" -eq 0 ] || { summary "$GATE/logs/framework-$N.log"; exit "$rc"; }

# 2. Unsigned Release IPA from the existing host.
start=$(date +%s)
(cd "${HOST_DIR:?gate.env: HOST_DIR}" && env -i HOME="$XTOOL_HOME" CFFIXED_USER_HOME="$XTOOL_HOME" \
    TMPDIR="$GATE/tmp" LANG=C.UTF-8 USER="${RUN_USER:-$(id -un)}" LOGNAME="${RUN_USER:-$(id -un)}" \
    PATH="$SWIFT_BIN:${SDK_TOOLSET_BIN:-}:/usr/bin:/bin" LD_LIBRARY_PATH="${TOOL_LD_LIBRARY_PATH:-}" \
    ${XTOOL_XDG_CONFIG_HOME:+XDG_CONFIG_HOME=$XTOOL_XDG_CONFIG_HOME} \
    "$XTOOL" dev build --configuration release --ipa) > "$GATE/logs/package-$N.log" 2>&1; rc=$?
echo "PACKAGE EXIT CODE: $rc elapsed=$(( $(date +%s) - start ))s"
[ "$rc" -eq 0 ] || { summary "$GATE/logs/package-$N.log"; exit "$rc"; }
ipa=$(find "$HOST_DIR" -maxdepth 3 -name '*.ipa' -newer "$GATE/logs/framework-$N.log" | head -1)
echo "ipa: ${ipa:-not found}"
[ -n "$ipa" ] && { wc -c < "$ipa"; sha256sum "$ipa"; }
