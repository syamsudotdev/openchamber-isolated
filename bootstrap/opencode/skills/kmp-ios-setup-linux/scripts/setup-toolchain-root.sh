#!/usr/bin/env bash
# Choose the machine-wide KMP-iOS toolchain root and the PATH shim directory,
# create the layout, and write the machine record (<root>/env.sh).
#
#   bash scripts/setup-toolchain-root.sh [--root <dir>] [--min-free-gib <n>] [--quiet]
#
# Fallback order for the root, first acceptable candidate wins:
#   1. --root, when given
#   2. $KMP_IOS_TOOLCHAIN_ROOT, when set
#   3. ${XDG_DATA_HOME:-$HOME/.local/share}/kmp-ios-toolchain
#   4. $HOME/.kmp-ios-toolchain
# A candidate is rejected when it is on tmpfs or under /tmp, cannot be created
# or written, or has less free space than --min-free-gib (default 20).
# Every rejection is printed as a BLOCK line with its fix, and the next
# candidate is tried. The script never writes outside the chosen root, the shim
# directory, and (only when no PATH directory is writable) ~/.profile and
# ~/.bashrc.
#
# Re-run it after each install: it refreshes the shims for the recorded tools.
# Safe to source: then it also exports the shim directory in the current shell.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"
SOURCED=0
if [ "${BASH_SOURCE[0]}" != "$0" ]; then SOURCED=1; fi

EXPLICIT=""; MIN_FREE_GIB=${KMP_IOS_MIN_FREE_GIB:-20}; QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --root) EXPLICIT=${2:?--root needs a path}; shift 2 ;;
        --min-free-gib) MIN_FREE_GIB=${2:?--min-free-gib needs a number}; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
block() { printf 'BLOCK %s\n' "$*"; }

# Filesystem type of a path, resolving to the nearest existing ancestor.
fstype_of() {
    local p=$1
    while [ ! -e "$p" ] && [ "$p" != / ]; do p=$(dirname "$p"); done
    findmnt -n -o FSTYPE -T "$p" 2>/dev/null || true
}
free_gib_of() {
    local p=$1
    while [ ! -e "$p" ] && [ "$p" != / ]; do p=$(dirname "$p"); done
    df -Pk "$p" 2>/dev/null | awk 'NR==2 { print int($4/1048576) }'
}

# Reason a candidate is unusable, or nothing when it is usable.
root_problem() {
    local p=$1 fs free
    case "$p" in
        /tmp/*|/dev/shm/*|/run/*) printf 'that path is on a volatile filesystem; use a disk-backed path under $HOME or $XDG_DATA_HOME' ; return ;;
    esac
    fs=$(fstype_of "$p")
    case "$fs" in
        tmpfs|ramfs) printf 'filesystem is %s; a toolchain needs a disk-backed path' "$fs"; return ;;
    esac
    free=$(free_gib_of "$p")
    if [ -n "$free" ] && [ "$free" -lt "$MIN_FREE_GIB" ]; then
        printf 'only %s GiB free, need %s GiB; free space or pass --min-free-gib' "$free" "$MIN_FREE_GIB"; return
    fi
    if ! mkdir -p "$p" 2>/dev/null; then printf 'not creatable by this user; fix the parent permissions or choose another path'; return; fi
    if ! ( : > "$p/.write-probe.$$" ) 2>/dev/null; then printf 'not writable by this user (chmod 555 or another owner); fix the mode/owner or choose another path'; return; fi
    rm -f -- "$p/.write-probe.$$"
}

candidates=()
[ -n "$EXPLICIT" ] && candidates+=("$EXPLICIT")
[ -n "${KMP_IOS_TOOLCHAIN_ROOT:-}" ] && candidates+=("$KMP_IOS_TOOLCHAIN_ROOT")
candidates+=("$(default_root)")
candidates+=("$HOME/.kmp-ios-toolchain")

ROOT=""
for candidate in "${candidates[@]}"; do
    problem=$(root_problem "$candidate")
    if [ -z "$problem" ]; then ROOT=$candidate; say "ROOT $ROOT"; break; fi
    block "toolchain root $candidate: $problem"
done
[ -n "$ROOT" ] || { printf 'FAIL no usable toolchain root; pass --root to a writable disk-backed path\n' >&2; exit 1; }

for dir in downloads bin konan-data linux-toolchain/bin port agent empty-sysroot swift-distribution \
           xtool-distribution sdk xdg/config xtool-home cache tmp logs; do
    mkdir -p "$ROOT/$dir"
done

# PATH shim directory: the first writable directory already on PATH, ~/.local/bin first.
is_writable_dir() {
    local d=$1
    case "$d" in /*) ;; *) return 1 ;; esac
    [ -d "$d" ] || return 1
    ( : > "$d/.write-probe.$$" ) 2>/dev/null || return 1
    rm -f -- "$d/.write-probe.$$"
}
SHIM=""
PATH_HAS_LOCAL=0
case ":$PATH:" in *":$HOME/.local/bin:"*) PATH_HAS_LOCAL=1 ;; esac
if [ "$PATH_HAS_LOCAL" -eq 1 ]; then
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    if is_writable_dir "$HOME/.local/bin"; then SHIM=$HOME/.local/bin; fi
fi
if [ -z "$SHIM" ]; then
    old_ifs=$IFS; IFS=:
    for entry in $PATH; do
        [ -n "$entry" ] || continue
        if is_writable_dir "$entry"; then SHIM=$entry; break; fi
    done
    IFS=$old_ifs
fi

if [ -z "$SHIM" ]; then
    SHIM=$HOME/.local/bin
    mkdir -p "$SHIM"
    marker='# kmp-ios-toolchain: keep local shims on PATH'
    for rc in "$HOME/.profile" "$HOME/.bashrc"; do
        touch "$rc"
        if ! grep -qF "$marker" "$rc"; then
            printf '\n%s\ncase ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac\nexport PATH\n' "$marker" >> "$rc"
            say "PATH-ADDED $rc"
        else
            say "PATH-KEPT  $rc (entry already present)"
        fi
    done
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
    PROFILE_ADDED=1
    block "no writable directory was on PATH; created $SHIM and added it to ~/.profile and ~/.bashrc (new shells pick it up; this shell now has it)"
fi
say "SHIM $SHIM"

# Machine record: keep an existing record, otherwise write the template.
if [ -r "$ROOT/env.sh" ]; then
    say "RECORD-KEPT $ROOT/env.sh"
else
    {
        printf '# kmp-ios-toolchain machine record. Source it; do not hand-edit.\n'
        printf "# root chosen on %s; components are recorded in %s/manifest.tsv\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROOT"
        printf 'export KMP_IOS_TOOLCHAIN_ROOT=%s\n' "'$ROOT'"
    } > "$ROOT/env.sh"
    set_env_var "$ROOT/env.sh" KMP_IOS_TOOLCHAIN_BIN "$ROOT/bin"
    set_env_var "$ROOT/env.sh" KONAN_HOME ""
    set_env_var "$ROOT/env.sh" KONAN_DATA_DIR "$ROOT/konan-data"
    set_env_var "$ROOT/env.sh" KONAN_USE_INTERNAL_SERVER 0
    set_env_var "$ROOT/env.sh" SWIFT_BIN ""
    set_env_var "$ROOT/env.sh" XTOOL ""
    set_env_var "$ROOT/env.sh" XTOOL2 ""
    set_env_var "$ROOT/env.sh" XTOOL_HOME "$ROOT/xtool-home"
    set_env_var "$ROOT/env.sh" XTOOL_XDG_CONFIG_HOME "$ROOT/xdg/config"
    set_env_var "$ROOT/env.sh" KMP_IOS_SDK ""
    set_env_var "$ROOT/env.sh" ZSIGN ""
    set_env_var "$ROOT/env.sh" LLVM_BIN "$ROOT/konan-data/dependencies/llvm-21-x86_64-linux-essentials-116/bin"
    set_env_var "$ROOT/env.sh" OBJDUMP ""
    set_env_var "$ROOT/env.sh" KMP_IOS_AGENT_JAR "$ROOT/agent/probe-agent.jar"
    set_env_var "$ROOT/env.sh" KMP_IOS_BOOTSTRAP_JAR "$ROOT/agent/probe-bootstrap.jar"
    set_env_var "$ROOT/env.sh" KMP_IOS_LIBTOOL "$ROOT/linux-toolchain/bin/libtool"
    set_env_var "$ROOT/env.sh" KMP_IOS_ARCHIVE_INSPECTOR "$ROOT/port/inspect-archive.cjs"
    set_env_var "$ROOT/env.sh" KMP_IOS_SLICER "$ROOT/port/select-slice.cjs"
    set_env_var "$ROOT/env.sh" KMP_IOS_ARCHIVER_LOG "$ROOT/logs/archiver-invocations.log"
    set_env_var "$ROOT/env.sh" KMP_IOS_LD_LIBRARY_PATH "$ROOT/deps/lib/x86_64-linux-gnu:$ROOT/deps/usr/lib/x86_64-linux-gnu"
    set_env_raw "$ROOT/env.sh" PATH "export PATH=\"$ROOT/bin:\$PATH\""
    say "RECORD-WROTE $ROOT/env.sh"
fi
if [ ! -r "$ROOT/manifest.tsv" ]; then
    printf 'component\tversion\tpath\tsha256\n' > "$ROOT/manifest.tsv"
    say "RECORD-WROTE $ROOT/manifest.tsv"
fi

# Fill empty record fields from components that are already extracted under the
# root, so a later re-run needs no hand edit.
fill() { # name candidate
    local name=$1 candidate=$2
    [ -n "$candidate" ] && [ -e "$candidate" ] || return 0
    [ -z "$(env_value "$ROOT/env.sh" "$name")" ] || return 0
    set_env_var "$ROOT/env.sh" "$name" "$candidate"
    say "RECORD-FILLED $name=$candidate"
}
if [ -x "$ROOT/kotlin-native/bin/konanc" ]; then fill KONAN_HOME "$ROOT/kotlin-native"; fi
for candidate in "$ROOT"/swift-distribution/*/usr/bin/swift; do
    if [ -x "$candidate" ]; then fill SWIFT_BIN "$(dirname "$candidate")"; break; fi
done
if [ -x "$ROOT/xtool-distribution/squashfs-root/AppRun" ]; then fill XTOOL "$ROOT/xtool-distribution/squashfs-root/AppRun"; fi
if [ -x "$ROOT/xtool2-distribution/squashfs-root/AppRun" ]; then fill XTOOL2 "$ROOT/xtool2-distribution/squashfs-root/AppRun"; fi
# The JetBrains LLVM essentials set has no llvm-objdump; the Swift usr/bin has one.
for candidate in "$ROOT/konan-data/dependencies/llvm-21-x86_64-linux-essentials-116/bin/llvm-objdump" \
                 "$ROOT"/swift-distribution/*/usr/bin/llvm-objdump; do
    if [ -x "$candidate" ]; then fill OBJDUMP "$candidate"; break; fi
done

# Shims. Each one sources the record, so it stays valid when a later step fills
# a value, and names the setup step when its tool is not installed yet.
write_shim() { # name body-file
    install -m 0755 "$2" "$SHIM/$1"
    say "SHIM-WROTE $SHIM/$1"
}
shim_header() { # name variable usage
    printf '#!/bin/sh\n# kmp-ios-toolchain shim: %s. Rewritten by scripts/setup-toolchain-root.sh.\nset -eu\nROOT=%s\nif [ -r "$ROOT/env.sh" ]; then . "$ROOT/env.sh"; fi\n[ -n "${%s:-}" ] || { echo "kmp-ios-toolchain: %s is not installed (%s is empty); see %s/manifest.tsv and setup step 3" >&2; exit 127; }\n' "$1" "'$ROOT'" "$2" "$1" "$2" "$ROOT"
}
# The shared SDK lives under the record's XDG_CONFIG_HOME, so swift, swiftc and
# xtool discover it only with that value. HOME is not changed: xtool keeps its
# login token under $HOME/.config/xtool/data, never under the root.
sdk_xdg=$'if [ -n "${XTOOL_XDG_CONFIG_HOME:-}" ]; then export XDG_CONFIG_HOME="$XTOOL_XDG_CONFIG_HOME"; fi\n'
tmpd=$(mktemp -d "$ROOT/tmp/shim.XXXXXX")
trap 'rm -rf -- "$tmpd"' EXIT
{ shim_header konanc KONAN_HOME; printf 'exec "$KONAN_HOME/bin/konanc" "$@"\n'; } > "$tmpd/konanc"
write_shim konanc "$tmpd/konanc"
{ shim_header swift SWIFT_BIN; printf '%s' "$sdk_xdg"; printf 'if [ -n "${KMP_IOS_LD_LIBRARY_PATH:-}" ]; then export LD_LIBRARY_PATH="$KMP_IOS_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi\nexec "$SWIFT_BIN/swift" "$@"\n'; } > "$tmpd/swift"
write_shim swift "$tmpd/swift"
{ shim_header swiftc SWIFT_BIN; printf '%s' "$sdk_xdg"; printf 'if [ -n "${KMP_IOS_LD_LIBRARY_PATH:-}" ]; then export LD_LIBRARY_PATH="$KMP_IOS_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi\nexec "$SWIFT_BIN/swiftc" "$@"\n'; } > "$tmpd/swiftc"
write_shim swiftc "$tmpd/swiftc"
{ shim_header xtool XTOOL; printf '%s' "$sdk_xdg"; cat <<'EOF'
# `xtool devices` returns at once when no device is connected. Pass --wait explicitly.
if [ "${1-}" = devices ]; then
  case " $* " in
    *" --wait "*|*" --no-wait "*) ;;
    *) shift; set -- devices --no-wait "$@" ;;
  esac
fi
exec "$XTOOL" "$@"
EOF
} > "$tmpd/xtool"
write_shim xtool "$tmpd/xtool"
{ shim_header zsign ZSIGN; printf 'exec "$ZSIGN" "$@"\n'; } > "$tmpd/zsign"
write_shim zsign "$tmpd/zsign"

printf 'RESULT root=%s shim=%s record=%s\n' "$ROOT" "$SHIM" "$ROOT/env.sh"
if [ "$SOURCED" -eq 0 ] && [ "${PROFILE_ADDED:-0}" -eq 1 ]; then
    say "This shell does not have the change yet: export PATH=\"$SHIM:\$PATH\" (new shells read it from the profile when the fallback ran)"
fi
