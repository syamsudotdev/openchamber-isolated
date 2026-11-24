#!/usr/bin/env bash
# Build the HostManager Java agent (probe-agent.jar) and its bootstrap jar from
# the sources beside this script. No network, no Gradle. The ASM classes come
# from the Kotlin/Native compiler jar, never from a separate download.
#
#   bash build-agent.sh --konan <kotlin-native-prebuilt dir> --out <dir> [--jdk <JDK root>]
#
# --konan holds konan/lib/kotlin-native-compiler-embeddable.jar.
# --jdk supplies javac and jar. Default: the JDK on PATH.
# Output: <out>/probe-agent.jar and <out>/probe-bootstrap.jar. Prints sizes and
# member counts, and fails when a required member is absent.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
KONAN=""; OUT=""; JDK=""
while [ $# -gt 0 ]; do
    case "$1" in
        --konan) KONAN=${2:?--konan needs a directory}; shift 2 ;;
        --out)   OUT=${2:?--out needs a directory}; shift 2 ;;
        --jdk)   JDK=${2:?--jdk needs a directory}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$KONAN" ] && [ -n "$OUT" ] || { echo "usage: build-agent.sh --konan <dir> --out <dir> [--jdk <dir>]" >&2; exit 2; }
COMPILER=$KONAN/konan/lib/kotlin-native-compiler-embeddable.jar
[ -r "$COMPILER" ] || { echo "FAIL  compiler jar missing: $COMPILER" >&2; exit 1; }
if [ -n "$JDK" ]; then
    JAVAC=$JDK/bin/javac; JAR=$JDK/bin/jar
else
    JAVAC=$(command -v javac || true); JAR=$(command -v jar || true)
fi
[ -x "$JAVAC" ] || { echo "FAIL  javac not found (--jdk or PATH)" >&2; exit 1; }
[ -x "$JAR" ] || { echo "FAIL  jar not found (--jdk or PATH)" >&2; exit 1; }

mkdir -p "$OUT/tmp" "$OUT/home" "$OUT/work"
WORK=$OUT/work
rm -rf "$WORK/bridge-classes" "$WORK/agent-classes" "$WORK/asm-extract" "$WORK/releases"
mkdir -p "$WORK/bridge-classes" "$WORK/agent-classes" "$WORK/asm-extract" \
         "$WORK/releases/probe-bootstrap" "$WORK/releases/probe-agent"
# javac writes temp files; keep them off a tmpfs and out of an unrelated home.
export TMPDIR=$OUT/tmp
export JAVA_TOOL_OPTIONS="-XX:-UsePerfData -Djava.io.tmpdir=$TMPDIR -Duser.home=$OUT/home"

# Two jars on purpose: premain and the bootstrap bridge never link Kotlin types.
"$JAVAC" --release 17 -d "$WORK/bridge-classes" "$HERE/ProbeBridge.java"
(cd "$WORK/releases/probe-bootstrap" && "$JAR" cf "$OUT/probe-bootstrap.jar" -C "$WORK/bridge-classes" .)
"$JAVAC" --release 17 -cp "$COMPILER" -d "$WORK/agent-classes" "$HERE/ProbeAgent.java"
(cd "$WORK/asm-extract" && "$JAR" xf "$COMPILER" org/jetbrains/org/objectweb/asm)
cp -a "$WORK/asm-extract/org" "$WORK/agent-classes/"
cp "$HERE/manifest.mf" "$WORK/manifest.mf"
(cd "$WORK/releases/probe-agent" && "$JAR" cfm "$OUT/probe-agent.jar" "$WORK/manifest.mf" -C "$WORK/agent-classes" .)

# The build is not complete until each jar carries its required members.
"$JAR" tf "$OUT/probe-bootstrap.jar" > "$OUT/bootstrap-members.txt"
"$JAR" tf "$OUT/probe-agent.jar" > "$OUT/agent-members.txt"
grep -qx ProbeBridge.class "$OUT/bootstrap-members.txt" || { echo "FAIL  probe-bootstrap.jar lacks ProbeBridge.class" >&2; exit 1; }
for member in ProbeAgent.class META-INF/MANIFEST.MF org/jetbrains/org/objectweb/asm/ClassReader.class; do
    grep -qx "$member" "$OUT/agent-members.txt" || { echo "FAIL  probe-agent.jar lacks $member" >&2; exit 1; }
done

printf 'probe-agent.jar %s bytes, %s members\n' "$(wc -c < "$OUT/probe-agent.jar")" "$(wc -l < "$OUT/agent-members.txt")"
printf 'probe-bootstrap.jar %s bytes, %s members\n' "$(wc -c < "$OUT/probe-bootstrap.jar")" "$(wc -l < "$OUT/bootstrap-members.txt")"
