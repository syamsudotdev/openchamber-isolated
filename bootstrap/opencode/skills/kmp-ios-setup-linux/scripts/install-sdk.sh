#!/usr/bin/env bash
# Install the one shared Darwin Swift SDK for this machine, from an authorized
# Xcode .xip, with the recorded xtool. Run once per machine; later gates reuse it.
#
#   bash scripts/install-sdk.sh <Xcode.xip> [--xtool <AppRun|xtool>] [--root <dir>]
#
# The SDK lands under the record's XTOOL_XDG_CONFIG_HOME and is recorded as
# KMP_IOS_SDK, so no project builds its own copy. An xtool-1.x SDK is rejected
# by xtool 2.x ("Darwin SDK is out of date"): reinstall with the 2.x xtool in
# that case, and never try to update a slim SDK in place.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

XIP=""; XTOOL_ARG=""; ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --xtool) XTOOL_ARG=${2:?--xtool needs a path}; shift 2 ;;
        --root) ROOT=${2:?--root needs a path}; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) XIP=$1; shift ;;
    esac
done
[ -n "$XIP" ] || { echo "usage: install-sdk.sh <Xcode.xip> [--xtool <path>] [--root <dir>]" >&2; exit 2; }
[ -r "$XIP" ] || { echo "BLOCK SDK input is missing or unreadable: $XIP; fix: download Xcode from https://developer.apple.com/download/all/ under your Apple account and pass its path" >&2; exit 1; }
[ -n "$ROOT" ] || ROOT=$(default_root)
cli_record "$ROOT"
check_root_writable "$ROOT"
# shellcheck disable=SC1091
. "$ROOT/env.sh"
XTOOL_BIN=${XTOOL_ARG:-${XTOOL:-}}
[ -n "$XTOOL_BIN" ] && [ -x "$XTOOL_BIN" ] || { printf 'BLOCK no runnable xtool: install xtool 1.22.2 first (references/toolchain-manifest.md, C15) or pass --xtool\n' >&2; exit 1; }
V=$("$XTOOL_BIN" --version 2>&1 | tail -1)
printf 'xtool: %s\n' "$V"
SDK_HOME=${XTOOL_HOME:-$ROOT/xtool-home}
SDK_XDG=${XTOOL_XDG_CONFIG_HOME:-$ROOT/xdg/config}
mkdir -p "$SDK_HOME" "$SDK_XDG"
if [ "$(findmnt -n -o FSTYPE -T "$ROOT" 2>/dev/null)" = tmpfs ]; then
    echo "BLOCK toolchain root is on tmpfs; fix: use a disk-backed root (setup-toolchain-root.sh reports this)" >&2
    exit 1
fi

SHA=$(sha256sum "$XIP" | cut -d' ' -f1)
printf 'xip sha256: %s (identity hash; it does not authenticate Apple)\n' "$SHA"
record_row "$ROOT" "XcodeXIP" "Xcode27" "$XIP" "$SHA"

# TMPDIR keeps the XIP unpack off /tmp, which can be a small tmpfs.
mkdir -p "$ROOT/tmp"
env -i HOME="$SDK_HOME" CFFIXED_USER_HOME="$SDK_HOME" LANG=C.UTF-8 TMPDIR="$ROOT/tmp" \
    XDG_CONFIG_HOME="$SDK_XDG" \
    PATH="${SWIFT_BIN:+$SWIFT_BIN:}$(dirname "$XTOOL_BIN"):/usr/bin:/bin" \
    LD_LIBRARY_PATH="${KMP_IOS_LD_LIBRARY_PATH:-}" \
    "$XTOOL_BIN" sdk install "$XIP" --slim
STATUS=$(env -i HOME="$SDK_HOME" CFFIXED_USER_HOME="$SDK_HOME" LANG=C.UTF-8 TMPDIR="$ROOT/tmp" XDG_CONFIG_HOME="$SDK_XDG" \
    PATH="${SWIFT_BIN:+$SWIFT_BIN:}$(dirname "$XTOOL_BIN"):/usr/bin:/bin" \
    LD_LIBRARY_PATH="${KMP_IOS_LD_LIBRARY_PATH:-}" "$XTOOL_BIN" sdk status 2>&1)
printf '%s\n' "$STATUS"
BUNDLE=$(printf '%s\n' "$STATUS" | awk -F': *' '/^ *Path:/ { print $2; exit }')
[ -n "$BUNDLE" ] || BUNDLE=$SDK_XDG/swiftpm/swift-sdks/darwin.artifactbundle
[ -d "$BUNDLE" ] || { printf 'BLOCK sdk install reported no bundle at %s; keep the xtool output and reinstall\n' "$BUNDLE" >&2; exit 1; }
set_env_var "$ROOT/env.sh" KMP_IOS_SDK "$BUNDLE"
set_env_var "$ROOT/env.sh" XTOOL_HOME "$SDK_HOME"
set_env_var "$ROOT/env.sh" XTOOL_XDG_CONFIG_HOME "$SDK_XDG"
SDK_VERSION=$(printf '%s\n' "$STATUS" | awk -F': *' '/Version:/ { print $2; exit }')
record_row "$ROOT" "DarwinSDK" "${SDK_VERSION:-Unknown}" "$BUNDLE" "built locally from xip sha256:$SHA"
printf 'SDK READY %s\n' "$BUNDLE"
