#!/usr/bin/env bash
# Write one component row to the machine manifest after a successful install, so
# no later project installs it again.
#
#   bash scripts/record-component.sh <component> <version> <path> [sha256|compute] [--env NAME]...
#
# The root comes from --root, from $KMP_IOS_TOOLCHAIN_ROOT, or from the default
# record. `compute` hashes <path> now and marks the value "computed locally",
# which tells a later reader that no publisher digest was compared.
# Omit the hash only when the publisher supplies none and the file is not a
# single file; the row then says "unverified".
# --env NAME also exports NAME=<path> in the record, so a later project finds
# the tool without searching for it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

ROOT=""; envs=()
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT=${2:?--root needs a path}; shift 2 ;;
        --env) envs+=("${2:?--env needs a variable name}"); shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
[ "${#args[@]}" -ge 3 ] || { echo "usage: record-component.sh [--root <dir>] <component> <version> <path> [sha256|compute]" >&2; exit 2; }
[ -n "$ROOT" ] || ROOT=$(default_root)
cli_record "$ROOT"
check_root_writable "$ROOT"

component=${args[0]} version=${args[1]} path=${args[2]} sha=${args[3]:-unverified}
case "$sha" in
    compute)
        [ -f "$path" ] || { echo "FAIL cannot hash a missing file: $path" >&2; exit 1; }
        sha="computed locally:$(sha256sum "$path" | cut -d' ' -f1)" ;;
esac
record_row "$ROOT" "$component" "$version" "$path" "$sha"
for name in "${envs[@]}"; do
    set_env_var "$ROOT/env.sh" "$name" "$path"
    printf 'RECORDED-ENV %s=%s\n' "$name" "$path"
done
