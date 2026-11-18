#!/usr/bin/env bash
# Check every known wall of the KMP Linux iOS build before a build or signing step,
# and list all problems at once. Read-only. It never reads a password, a private key
# or the .p12 contents: it checks only paths, modes, owners and the profile's public
# metadata.
# Usage: bash preflight.sh <GATE>     (reads <GATE>/gate.env, see references/build.md)
# Exit 0 when no check fails; warnings do not fail.
set -uo pipefail
GATE=${1:?usage: preflight.sh <GATE>}
fails=0 warns=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }
skip() { printf 'SKIP  %s\n' "$1"; }

[ -r "$GATE/gate.env" ] || { echo "FAIL  $GATE/gate.env is missing"; exit 1; }
# shellcheck disable=SC1091
. "$GATE/gate.env"
for v in PROJECT SWIFT_BIN XTOOL XTOOL_HOME; do
    [ -n "${!v:-}" ] || fail "gate.env: $v is not set"
done
[ "$fails" -eq 0 ] || { echo "RESULT: $fails failed, $warns warnings"; exit 1; }
RUN=(env -i HOME="$XTOOL_HOME" CFFIXED_USER_HOME="$XTOOL_HOME" LANG=C.UTF-8 PATH="$SWIFT_BIN:/usr/bin:/bin"
    LD_LIBRARY_PATH="${TOOL_LD_LIBRARY_PATH:-}" ${XTOOL_XDG_CONFIG_HOME:+XDG_CONFIG_HOME=$XTOOL_XDG_CONFIG_HOME})

# Project and Gradle
[ -d "$PROJECT" ] && pass "project: $PROJECT" || fail "project folder missing: $PROJECT"
[ -x "$PROJECT/gradlew" ] && pass "gradlew present" || fail "no executable gradlew in $PROJECT"
if [ -n "${JAVA_HOME_FOR_BUILD:-}" ]; then
    v=$("$JAVA_HOME_FOR_BUILD/bin/java" -version 2>&1 | head -1) && pass "java: $v" || fail "java does not run: $JAVA_HOME_FOR_BUILD"
else warn "gate.env: JAVA_HOME_FOR_BUILD not set; the build uses the default java"; fi
procs=$(for p in /proc/[0-9]*; do tr '\0' ' ' < "$p/cmdline" 2>/dev/null; echo; done | grep -v grep)
busy=$(printf '%s\n' "$procs" | grep -c -E 'gradlew|GradleWrapperMain')
idle=$(printf '%s\n' "$procs" | grep -c 'GradleDaemon')
[ "$busy" -eq 0 ] && pass "no Gradle command running" || fail "$busy Gradle command(s) running: wait, one Gradle command at a time"
[ "$idle" -eq 0 ] || warn "$idle Gradle daemon(s) alive (idle daemons share memory with the build)"
if [ -n "${PORT_EVIDENCE:-}" ]; then
    [ -r "$PORT_EVIDENCE" ] && pass "port qualification evidence: $PORT_EVIDENCE" || fail "port qualification evidence missing: $PORT_EVIDENCE"
else fail "gate.env: PORT_EVIDENCE not set (setup's qualified Kotlin/Native port record)"; fi

# Swift, xtool, SDK
v=$("${RUN[@]}" swift --version 2>&1 | head -1) && pass "swift: $v" || fail "swift does not run: $v"
v=$("${RUN[@]}" "$XTOOL" --version 2>&1 | tail -1) && pass "xtool: $v" || fail "xtool does not run: $v"
s=$("${RUN[@]}" "$XTOOL" sdk status 2>&1)
case "$s" in
*"out of date"*) fail "Darwin SDK is out of date for this xtool: run 'xtool sdk install <Xcode.xip> --slim' with HOME=$XTOOL_HOME" ;;
*"Darwin SDK is installed"*) pass "Darwin SDK: $(printf '%s' "$s" | grep -m1 Version | sed 's/^ *//')" ;;
*) fail "no Darwin SDK under $XTOOL_HOME" ;;
esac
for t in unzip openssl python3; do
    p=$(command -v "$t") && pass "$t: $p" || fail "$t not found"
done
p=${ZIP:-$(command -v zip)}
[ -n "$p" ] && [ -x "$p" ] && pass "zip: $p" || fail "zip not found (set ZIP to the setup-verified binary)"
[ -n "${OBJDUMP:-}" ] && [ -x "$OBJDUMP" ] && pass "Mach-O inspector: $OBJDUMP" || fail "gate.env: OBJDUMP (llvm-objdump path) missing or not executable"

# Signer and signing inputs (paths, modes and owners only)
if [ -n "${ZSIGN:-}" ]; then
    v=$("$ZSIGN" -v 2>&1 | head -1); case "$v" in *1.1.3*) pass "zsign: $v" ;; *) warn "zsign is not the verified v1.1.3: $v" ;; esac
else fail "gate.env: ZSIGN not set"; fi
me=$(id -u)
check_secret() { # name path
    local name=$1 path=$2
    if [ -z "$path" ]; then fail "gate.env: $name not set"; return; fi
    if [ ! -e "$path" ]; then fail "$name missing: $path"; return; fi
    [ "$(stat -L -c %u "$path")" = "$me" ] || fail "$name owner is not the current user: $path"
    [ -z "$(find -L "$path" -maxdepth 0 -perm /077)" ] || fail "$name allows group or other access (needs 600 or 400): $path"
    [ -z "$(find -L "$(dirname "$path")" -maxdepth 0 -perm /022)" ] || fail "$name folder is writable by group or others: $(dirname "$path")"
    git -C "$(dirname "$path")" rev-parse --is-inside-work-tree >/dev/null 2>&1 && fail "$name is inside a Git work tree: $path"
    [ -s "$path" ] && pass "$name: $path (mode $(stat -L -c %a "$path"))" || fail "$name is empty: $path"
}
check_secret P12 "${P12:-}"
check_secret PASSWORD_FILE "${PASSWORD_FILE:-}"
[ -n "${ENTITLEMENTS:-}" ] && [ -r "$ENTITLEMENTS" ] && pass "entitlements: $ENTITLEMENTS" || fail "gate.env: ENTITLEMENTS missing or unreadable"
root=${SIGN_STAGE_ROOT:-${XDG_RUNTIME_DIR:-/dev/shm}}
[ "$(findmnt -n -o FSTYPE --target "$root" 2>/dev/null)" = tmpfs ] && pass "tmpfs staging root: $root" || fail "staging root is not tmpfs: $root"

# Profile public metadata
if [ -n "${PROFILE:-}" ] && [ -r "$PROFILE" ]; then
    d=$(mktemp -d)
    if openssl cms -verify -noverify -inform DER -in "$PROFILE" -out "$d/p.plist" >/dev/null 2>&1; then
        python3 -I - "$d/p.plist" "${BUNDLE_ID:-}" "${UDID:-}" <<'PY'
import datetime, fnmatch, plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
bundle, udid = sys.argv[2], sys.argv[3]
ents = p.get("Entitlements", {})
def out(ok, text, level="FAIL"):
    print(("PASS  " if ok else f"{level}  ") + text)
devices = p.get("ProvisionedDevices")
out(devices is not None, "profile is a development profile (lists devices)")
out(ents.get("get-task-allow") is True, "profile allows get-task-allow")
out(p["ExpirationDate"].replace(tzinfo=None) > datetime.datetime.utcnow(), f"profile not expired ({p['ExpirationDate']:%Y-%m-%d})")
app_id = ents.get("application-identifier", "")
if bundle:
    out(fnmatch.fnmatchcase(bundle, app_id.split(".", 1)[-1]), f"profile App ID {app_id} covers {bundle}")
if udid:
    out(udid in (devices or []), f"profile lists UDID {udid}")
PY
    else fail "profile is not a readable CMS file: $PROFILE"; fi
    rm -rf -- "$d"
else fail "gate.env: PROFILE missing or unreadable"; fi

# Device route
if [ -n "${USBMUXD_SOCKET:-}" ] && [ -S "$USBMUXD_SOCKET" ]; then
    # USB devices (-l) and network devices such as netmuxd Wi-Fi devices (-n).
    usb=$(env -i USBMUXD_SOCKET_ADDRESS="UNIX:$USBMUXD_SOCKET" "${DEVTOOLS:-/usr}/bin/idevice_id" -l 2>/dev/null)
    net=$(env -i USBMUXD_SOCKET_ADDRESS="UNIX:$USBMUXD_SOCKET" "${DEVTOOLS:-/usr}/bin/idevice_id" -n 2>/dev/null)
    ids=$(printf "%s\n%s\n" "$usb" "$net" | sed "/^$/d")
    nflag=; [ -n "$net" ] && printf "%s\n" "$net" | grep -qx "${UDID:-$(printf "%s" "$net" | head -1)}" && nflag=-n
    if [ -z "$ids" ]; then warn "no device visible through $USBMUXD_SOCKET (DevicePending)"
    elif [ -n "${UDID:-}" ] && ! printf '%s\n' "$ids" | grep -qx "$UDID"; then warn "UDID $UDID is not among visible devices"
    else
        pass "device visible: $(printf '%s' "$ids" | head -1)"
        dm=$(env -i USBMUXD_SOCKET_ADDRESS="UNIX:$USBMUXD_SOCKET" "${DEVTOOLS:-/usr}/bin/ideviceinfo" $nflag -u "${UDID:-$(printf "%s" "$ids" | head -1)}" -q com.apple.security.mac.amfi -k DeveloperModeStatus 2>/dev/null)
        [ "$dm" = true ] && pass "Developer Mode on" || warn "Developer Mode not confirmed: '$dm'"
    fi
else skip "device route: USBMUXD_SOCKET not set or socket missing"; fi

echo "RESULT: $fails failed, $warns warnings"
[ "$fails" -eq 0 ]
