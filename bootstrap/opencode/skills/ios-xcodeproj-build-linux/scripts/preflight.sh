#!/usr/bin/env bash
# Check every known wall of the Linux Xcode-project build before a build runs, and
# list all problems at once. Read-only: it changes nothing and reads no secret.
# Usage: bash preflight.sh <GATE>     (reads <GATE>/gate.env, see references/build.md)
# Exit 0 when no check fails; warnings do not fail.
set -uo pipefail
GATE=${1:?usage: preflight.sh <GATE>}
SKILL=$(cd "$(dirname "$0")/.." && pwd)
SETUP=$(cd "$SKILL/.." && pwd)/kmp-ios-setup-linux
fails=0 warns=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }

# Machine record first: it holds the shared toolchain root and the one Darwin
# SDK, so this gate opens the SDK that setup made instead of building another
# (setup step 0). gate.env then overrides any path this build pins.
RECORD=${KMP_IOS_RECORD:-${XDG_DATA_HOME:-$HOME/.local/share}/kmp-ios-toolchain/env.sh}
record=0
if [ -r "$RECORD" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$RECORD"
    record=1
    TC=${TC:-${KMP_IOS_TOOLCHAIN_ROOT:-}}
fi

if [ ! -r "$GATE/gate.env" ]; then
    echo "FAIL  $GATE/gate.env is missing"; exit 1
fi
# shellcheck disable=SC1091
. "$GATE/gate.env"
for v in TC SWIFT_BIN XTOOL XCODEGEN SCHEME CONFIG RUN_USER APP_SOURCES; do
    [ -n "${!v:-}" ] || fail "gate.env: $v is not set and the record has no value"
done
[ "$fails" -eq 0 ] || { echo "RESULT: $fails failed, $warns warnings"; exit 1; }

[ "$record" -eq 1 ] && pass "machine record: $RECORD" || warn "no machine record at $RECORD: run kmp-ios-setup-linux scripts/setup-toolchain-root.sh (setup step 0)"
SDK=${KMP_IOS_SDK:-}
if [ -n "$SDK" ] && [ -d "$SDK" ]; then pass "shared SDK bundle: $SDK"; else
    fail "shared Darwin SDK missing (KMP_IOS_SDK unset or absent): run bash $SETUP/scripts/install-sdk.sh <Xcode.xip> (setup step 4)"
    SDK=$GATE/home/.config/xtool/darwin.xtoolsdk
fi
RUN=(env -i HOME="${XTOOL_HOME:-$GATE/home}" CFFIXED_USER_HOME="${XTOOL_HOME:-$GATE/home}" TMPDIR="$GATE/tmp" LANG=C.UTF-8
    USER="$RUN_USER" LOGNAME="$RUN_USER" PATH="$GATE/stub-bin:$SWIFT_BIN:$SDK/toolset/bin:$GATE/deps/root/usr/bin:/usr/bin:/bin"
    LD_LIBRARY_PATH="$TC/deps/lib/x86_64-linux-gnu:$TC/deps/usr/lib/x86_64-linux-gnu:$GATE/deps/root/usr/lib/x86_64-linux-gnu")

# Tools
v=$("${RUN[@]}" swift --version 2>&1 | head -1) && pass "swift: $v" || fail "swift does not run: $v"
v=$("${RUN[@]}" "$XTOOL" --version 2>&1 | tail -1)
case "$v" in "xtool 2."*) pass "xtool: $v" ;; *) fail "xtool must be 2.x for Xcode projects, got: $v" ;; esac
s=$("${RUN[@]}" "$XTOOL" sdk status 2>&1)
case "$s" in
*"out of date"*) fail "Darwin SDK is out of date for this xtool: reinstall the shared SDK with bash $SETUP/scripts/install-sdk.sh <Xcode.xip> and the xtool 2.x that this build needs" ;;
*"Darwin SDK is installed"*) pass "Darwin SDK: $(printf '%s' "$s" | grep -m1 Version | sed 's/^ *//')" ;;
*) fail "no shared Darwin SDK under ${XTOOL_HOME:-$GATE/home}: run bash $SETUP/scripts/install-sdk.sh <Xcode.xip> (setup step 4)" ;;
esac
v=$("${RUN[@]}" "$XCODEGEN" --version 2>&1 | tail -1) && pass "xcodegen: $v" || fail "xcodegen does not run: $v"
for t in dsymutil zip rsync; do
    p=$("${RUN[@]}" sh -c "command -v $t") && pass "$t: $p" || fail "$t not on the build PATH"
done

# Stand-in tools
for f in actool ibtool ld lipo asset_symbols.py; do
    src="$SKILL/scripts/stub-tools/$f"; [ "$f" = asset_symbols.py ] && src="$SKILL/scripts/$f"
    if [ ! -e "$GATE/stub-bin/$f" ]; then fail "stand-in missing: $GATE/stub-bin/$f (install from $src)"
    elif ! cmp -s "$src" "$GATE/stub-bin/$f"; then fail "stand-in out of date: $GATE/stub-bin/$f differs from $src"
    else pass "stand-in: $f"; fi
done
for f in actool ibtool ld lipo; do
    [ -x "$GATE/stub-bin/$f" ] || fail "stand-in not executable: $GATE/stub-bin/$f"
done

# Source, overlay and project
S="$GATE/src"
if [ ! -d "$S" ]; then fail "no source export at $S"; else
    if [ -r "$GATE/linux-overlay.patch" ]; then
        # The overlay is a binary-safe `git diff --no-index --binary --no-prefix` patch.
        (cd "$S" && git apply -p1 -R --check "$GATE/linux-overlay.patch" >/dev/null 2>&1) \
            && pass "overlay applied ($(sha256sum "$GATE/linux-overlay.patch" | cut -c1-12))" \
            || fail "linux-overlay.patch is not applied to $S"
    else fail "no $GATE/linux-overlay.patch"; fi
    proj=$(find "$S" -maxdepth 1 -name '*.xcodeproj' | head -1)
    if [ -z "$proj" ]; then fail "no .xcodeproj in $S: run xcodegen generate"
    elif [ "$S/project.yml" -nt "$proj/project.pbxproj" ]; then fail "project.yml is newer than $(basename "$proj"): run xcodegen generate"
    else pass "project: $(basename "$proj")"; fi
    m=$(grep -n -E '/usr/bin/codesign|xcrun |Crashlytics/run' "$S/project.yml" 2>/dev/null)
    [ -z "$m" ] && pass "no macOS-only calls in project.yml" \
        || warn "macOS-only calls left in project.yml (fine only in targets this scheme does not build): $(printf '%s' "$m" | cut -d: -f1 | tr '\n' ' ')"

    # Compiler difference: @State static in compiled sources. Dry run of the codemod
    # (ast-grep 0.51.3); sample, example and test folders are not compiled.
    rules="$SKILL/scripts/codemods/state-static.yml"
    if json=$(env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="$GATE/home" UV_CACHE_DIR="$GATE/cache/uv" \
        uvx --from ast-grep-cli==0.51.3 ast-grep scan --rule "$rules" --json=compact "$S" 2>/dev/null); then
        st=$(printf '%s' "$json" | python3 -c '
import json, re, sys
for m in json.load(sys.stdin):
    if not re.search(r"/(Examples?|Tests?|Demo|Samples?|UITests)/", m["file"]):
        print(m["file"] + ":" + str(m["range"]["start"]["line"] + 1))' | sed "s#$S/##")
        [ -z "$st" ] && pass "codemod state-static: no matches in compiled sources" \
            || fail "codemod state-static not applied ($(printf '%s\n' "$st" | wc -l) matches): $(printf '%s' "$st" | tr '\n' ' ')"
    else
        warn "ast-grep 0.51.3 did not run (uvx); fallback grep: $(grep -rln --include=*.swift -E '@State +(private +)?static' "$S" 2>/dev/null | grep -v -E '/(Examples?|Tests?|Demo|Samples?|UITests)/' | wc -l) file(s)"
    fi

    # Stale stand-in outputs.
    st=$(find "$S" -path '*Intermediates.noindex*' -name 'GeneratedAssetSymbols.swift' -size 0 2>/dev/null)
    [ -z "$st" ] && pass "no stale empty GeneratedAssetSymbols.swift" \
        || fail "stale empty symbol files (delete them): $(printf '%s' "$st" | wc -l) file(s)"

    # Asset symbol coverage: app sources and each local package with catalogs.
    tmp=$(mktemp -d "$GATE/tmp/preflight.XXXXXX")
    for dir in "$S/$APP_SOURCES" "$S"/Packages/*/; do
        [ -d "$dir" ] || continue
        mapfile -t cats < <(find "$dir" -name '*.xcassets' -type d | sort)
        [ ${#cats[@]} -gt 0 ] || continue
        python3 -I "$SKILL/scripts/asset_symbols.py" "$tmp/s.swift" "${cats[@]}" >/dev/null
        grep -oE 'static let [A-Za-z0-9_]+ = (Image|Color)Resource' "$tmp/s.swift" | awk '{print $3}' | sort -u > "$tmp/gen"
        { grep -rhoE '(UIImage|UIColor)\(resource: *\.[A-Za-z0-9_]+' --include=*.swift "$dir" | sed -E 's/.*\.//'
          grep -rhoE '\bImage\(\.[A-Za-z0-9_]+\)' --include=*.swift "$dir" | sed -E 's/Image\(\.//; s/\)//'
          grep -rhoE '(Image|Color)Resource\.[A-Za-z0-9_]+' --include=*.swift "$dir" | sed -E 's/.*\.//'; } | sort -u > "$tmp/used"
        miss=$(comm -23 "$tmp/used" "$tmp/gen" | tr '\n' ' ')
        name=${dir%/}; name=${name#"$S"/}
        [ -z "$miss" ] && pass "asset symbols: $name ($(wc -l < "$tmp/used") names used)" \
            || fail "asset symbols missing in $name: $miss"
    done
    rm -rf "$tmp"
fi

# Device route (install step only)
if [ -n "${USBMUXD_SOCKET:-}" ]; then
    if [ -S "$USBMUXD_SOCKET" ]; then
        # USB devices (-l) and network devices such as netmuxd Wi-Fi devices (-n).
        d=$( { env -i USBMUXD_SOCKET_ADDRESS="UNIX:$USBMUXD_SOCKET" "${DEVTOOLS:-/usr}/bin/idevice_id" -l
               env -i USBMUXD_SOCKET_ADDRESS="UNIX:$USBMUXD_SOCKET" "${DEVTOOLS:-/usr}/bin/idevice_id" -n | sed "s/$/ (network: use -n)/"; } 2>/dev/null)
        [ -n "$d" ] && pass "device visible: $(printf '%s' "$d" | head -1)" || warn "no iPhone visible through $USBMUXD_SOCKET (install step will be DevicePending)"
    else warn "usbmuxd socket missing: $USBMUXD_SOCKET"; fi
fi
if [ -r /sys/fs/cgroup/pids.max ] && [ "$(cat /sys/fs/cgroup/pids.max)" != max ]; then
    # A full build used at least 558 processes and threads (2026-11-18, build 10 hit
    # pids.max=1024 at that point); the true peak is not measured yet.
    pmax=$(cat /sys/fs/cgroup/pids.max) pcur=$(cat /sys/fs/cgroup/pids.current) free=$(( pmax - pcur ))
    if [ "$free" -lt "${PIDS_MIN_FREE:-560}" ]; then
        fail "process headroom: only $free free of $pmax (a build needs more than 558): raise the container's pids limit or stop other processes"
    elif [ "$free" -lt 1000 ]; then
        warn "process headroom: $free free of $pmax; the build peak is not measured yet, so it can still hit the limit"
    else pass "process headroom: $free free of $pmax"; fi
fi
free=$(df -Pk "$GATE" | awk 'NR==2 {print int($4/1048576)}')
[ "$free" -ge 20 ] && pass "disk: ${free} GiB free" || warn "disk: only ${free} GiB free"

echo "RESULT: $fails failed, $warns warnings"
[ "$fails" -eq 0 ]
