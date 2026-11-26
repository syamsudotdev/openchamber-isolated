#!/usr/bin/env bash
# Shared helpers for the kmp-ios-setup-linux scripts. Source this file; do not
# run it. All functions are read-only except set_env_var and record_row, which
# only touch files inside the machine toolchain root.

# Default toolchain root, in fixed fallback order. It is a function so a script
# can print the preferred value before it exists.
default_root() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/kmp-ios-toolchain"
}

# Fill ROOT and the record path from the environment or the default record.
# Usage: cli_record <root>
# Sets RECORD. On a missing record it prints a fix line and returns 1.
cli_record() {
    local root=$1
    RECORD=${KMP_IOS_RECORD:-$root/env.sh}
    if [ -r "$RECORD" ]; then
        # shellcheck disable=SC1090,SC1091
        . "$RECORD"
        printf 'RECORD %s\n' "$RECORD"
        return 0
    fi
    printf 'BLOCK no machine record at %s; run scripts/setup-toolchain-root.sh first\n' "$RECORD" >&2
    return 1
}

# Fail with a fix line when the root cannot hold a multigigabyte toolchain.
check_root_writable() {
    local root=$1 probe
    if ! mkdir -p "$root" 2>/dev/null; then
        printf 'BLOCK root is not creatable: %s; fix: pass --root to a writable disk-backed path\n' "$root" >&2
        return 1
    fi
    probe=$root/.write-probe.$$
    if ! ( : > "$probe" ) 2>/dev/null; then
        printf 'BLOCK root is not writable: %s; fix: chown/chmod it or pass --root\n' "$root" >&2
        return 1
    fi
    rm -f -- "$probe"
    return 0
}

# Replace one "export NAME=value" line in a record, or append it. Values are
# single-quoted, so a path with spaces survives a later source.
set_env_var() {
    local file=$1 name=$2 value=$3 tmp
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || { printf '# kmp-ios-toolchain machine record. Source it; do not hand-edit.\n' > "$file"; }
    tmp=$file.tmp.$$
    awk -v name="$name" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^export " name "=" { print "export " name "=\047" value "\047"; done = 1; next }
        { print }
        END { if (!done) print "export " name "=\047" value "\047" }
    ' "$file" > "$tmp"
    mv -- "$tmp" "$file"
}

# Replace one record line verbatim, matched by its "export NAME=" prefix. Use it
# for a value that must stay expandable, such as PATH.
set_env_raw() {
    local file=$1 name=$2 line=$3 tmp
    mkdir -p "$(dirname "$file")"
    tmp=$file.tmp.$$
    awk -v prefix="export $name=" -v line="$line" '
        BEGIN { done = 0 }
        index($0, prefix) == 1 { print line; done = 1; next }
        { print }
        END { if (!done) print line }
    ' "$file" > "$tmp"
    mv -- "$tmp" "$file"
}

# Upsert one row of the machine manifest: component, version, path, sha256.
# Usage: record_row <root> <component> <version> <path> <sha256>
record_row() {
    local root=$1 component=$2 version=$3 path=$4 sha=$5
    local manifest=$root/manifest.tsv tmp
    mkdir -p "$root"
    [ -f "$manifest" ] || printf 'component\tversion\tpath\tsha256\n' > "$manifest"
    tmp=$manifest.tmp.$$
    awk -F '\t' -v OFS='\t' -v c="$component" -v v="$version" -v p="$path" -v s="$sha" '
        NR == 1 { print; next }
        $1 == c { print c, v, p, s; done = 1; next }
        { print }
        END { if (!done) print c, v, p, s }
    ' "$manifest" > "$tmp"
    mv -- "$tmp" "$manifest"
    printf 'RECORDED %s\t%s\t%s\t%s\n' "$component" "$version" "$path" "$sha"
}

# Read one export value from a record. Empty when absent.
env_value() {
    local file=$1 name=$2
    [ -r "$file" ] || return 0
    awk -v prefix="export $name=" -F "'" 'index($0, prefix) == 1 { print $2; exit }' "$file"
}

# Read one column of a component row from the manifest. Empty when absent.
manifest_field() {
    local root=$1 component=$2 column=$3
    [ -r "$root/manifest.tsv" ] || return 0
    awk -F '\t' -v c="$component" -v n="$column" '$1 == c { print $n; exit }' "$root/manifest.tsv"
}
