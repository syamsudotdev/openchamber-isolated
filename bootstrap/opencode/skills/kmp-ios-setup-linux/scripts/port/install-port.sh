#!/usr/bin/env bash
# Install the custom port pieces from this skill into the machine toolchain root:
# the libtool adapter, the archive inspector and the slice driver.
#
#   bash install-port.sh [--root <root>] [--llvm-bin <dir>]
#
# --root defaults to KMP_IOS_TOOLCHAIN_ROOT, then to the record at
#   ${XDG_DATA_HOME:-$HOME/.local/share}/kmp-ios-toolchain/env.sh
# --llvm-bin records the JetBrains LLVM bin directory used by the adapter.
# The script prints the env lines the record must hold; it never downloads.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib.sh
. "$HERE/../lib.sh"

ROOT=""; LLVM_BIN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT=${2:?--root needs a path}; shift 2 ;;
        --llvm-bin) LLVM_BIN=${2:?--llvm-bin needs a path}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ROOT" ] || ROOT=$(default_root)
cli_record "$ROOT"
check_root_writable "$ROOT"

mkdir -p "$ROOT/port" "$ROOT/linux-toolchain/bin" "$ROOT/tmp" "$ROOT/logs"
install -m 0644 "$HERE/inspect-archive.cjs" "$ROOT/port/inspect-archive.cjs"
install -m 0644 "$HERE/select-slice.cjs" "$ROOT/port/select-slice.cjs"
install -m 0755 "$HERE/libtool-adapter" "$ROOT/linux-toolchain/bin/libtool"
[ -n "$LLVM_BIN" ] || LLVM_BIN=$ROOT/konan-data/dependencies/llvm-21-x86_64-linux-essentials-116/bin

set_env_var "$ROOT/env.sh" KMP_IOS_LIBTOOL "$ROOT/linux-toolchain/bin/libtool"
set_env_var "$ROOT/env.sh" KMP_IOS_ARCHIVE_INSPECTOR "$ROOT/port/inspect-archive.cjs"
set_env_var "$ROOT/env.sh" KMP_IOS_SLICER "$ROOT/port/select-slice.cjs"
set_env_var "$ROOT/env.sh" LLVM_BIN "$LLVM_BIN"
set_env_var "$ROOT/env.sh" KMP_IOS_ARCHIVER_LOG "$ROOT/logs/archiver-invocations.log"

printf 'PORT READY %s\n' "$ROOT/linux-toolchain/bin/libtool"
printf 'Pass to the compiler: -Xoverride-konan-properties=...;targetToolchain.linux_x64-ios_arm64=%s;additionalToolsDir.linux_x64=%s\n' \
    "$ROOT/linux-toolchain" "$ROOT/linux-toolchain"
printf 'llvm-ar: %s\n' "$LLVM_BIN/llvm-ar"
