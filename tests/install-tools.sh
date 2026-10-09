#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
installer=${TOOLS_INSTALLER:-$root/install-tools.sh}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$temporary/bin"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat > "$temporary/bin/curl" <<'SH'
#!/bin/sh
set -eu
[ "$1" = --fail ] && [ "$2" = --location ] && [ "$3" = --retry ] && [ "$4" = 3 ]
[ "$5" = --retry-max-time ] && [ "$6" = 600 ]
[ "$7" = --connect-timeout ] && [ "$8" = 15 ]
[ "$9" = --max-time ] && [ "${10}" = 180 ] && [ "${11}" = --output ]
file=${12}; url=${13}
name=${file##*/}
grep -Fx "$name $url" "$EXPECTED_URLS" >/dev/null
printf 'curl %s\n' "$name" >> "$EVENTS"
printf '%s\n' "stub download: $name" > "$file"
[ "${FAIL_DOWNLOAD:-}" != "$name" ] || exit 22
SH

cat > "$temporary/bin/sha256sum" <<'SH'
#!/bin/sh
set -eu
[ "$1" = --check ] && [ "$2" = --status ]
read -r hash file
name=${file##*/}
grep -Fx "$name $hash" "$EXPECTED_HASHES" >/dev/null
[ -f "$file" ]
printf 'sha %s\n' "$name" >> "$EVENTS"
[ "${FAIL_CHECKSUM:-}" != "$name" ] || exit 1
SH

cat > "$temporary/bin/tar" <<'SH'
#!/bin/sh
set -eu
[ "$(grep -c '^sha ' "$EVENTS")" = 3 ]
[ "$1" = -xzf ] && [ "$3" = -C ]
directory=$4
shift 4
for member do
  # These members are fixed test fixtures, independent of installer variables.
  case "$TARGETARCH:$member" in
    amd64:uv-x86_64-unknown-linux-gnu/uv|amd64:uv-x86_64-unknown-linux-gnu/uvx|amd64:rtk) ;;
    arm64:uv-aarch64-unknown-linux-gnu/uv|arm64:uv-aarch64-unknown-linux-gnu/uvx|arm64:rtk) ;;
    *) printf 'Unexpected archive member for %s: %s\n' "$TARGETARCH" "$member" >&2; exit 1 ;;
  esac
  mkdir -p "$directory/$(dirname "$member")"
  printf 'stub executable: %s\n' "${member##*/}" > "$directory/$member"
done
printf '%s\n' tar >> "$EVENTS"
SH

cat > "$temporary/bin/install" <<'SH'
#!/bin/sh
set -eu
[ "$1" = -m ] && [ "$2" = 0755 ]
[ "$(grep -c '^sha ' "$EVENTS")" = 3 ]
[ "$(grep -c '^tar$' "$EVENTS")" = 2 ]
case "$4" in "$DESTINATION"/*) ;; *) exit 1 ;; esac
cp "$3" "$4"
chmod 0755 "$4"
printf 'install %s\n' "${4##*/}" >> "$EVENTS"
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
export EVENTS="$temporary/events"
export EXPECTED_URLS="$temporary/urls"
export EXPECTED_HASHES="$temporary/hashes"
export TMPDIR="$temporary/scratch"
export DESTINATION="$temporary/destination"

# Fixed release examples come from the approved release evidence, not the installer.
examples() {
  case "$1" in
    amd64)
      cat > "$EXPECTED_URLS" <<'EOF'
uv.tar.gz https://github.com/astral-sh/uv/releases/download/0.12.19/uv-x86_64-unknown-linux-gnu.tar.gz
rtk.tar.gz https://github.com/rtk-ai/rtk/releases/download/v0.23.0/rtk-x86_64-unknown-linux-musl.tar.gz
fff-mcp https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-x86_64-unknown-linux-musl
EOF
      cat > "$EXPECTED_HASHES" <<'EOF'
uv.tar.gz 23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8
rtk.tar.gz d19762b5e4aec8f13d5da25631f03bc6ac672d5fec8d67dff704e8c92182e2c9
fff-mcp d1e8671f40c89c445aaa1728a21ec04b74be2e5f99091485caeabcc97f99aceb
EOF
      ;;
    arm64)
      cat > "$EXPECTED_URLS" <<'EOF'
uv.tar.gz https://github.com/astral-sh/uv/releases/download/0.12.19/uv-aarch64-unknown-linux-gnu.tar.gz
rtk.tar.gz https://github.com/rtk-ai/rtk/releases/download/v0.23.0/rtk-aarch64-unknown-linux-gnu.tar.gz
fff-mcp https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-aarch64-unknown-linux-musl
EOF
      cat > "$EXPECTED_HASHES" <<'EOF'
uv.tar.gz 0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436
rtk.tar.gz 49beb391151f696e0b30c60593cf571afed9ba4e868656633200a8b10bd3c482
fff-mcp 35f8e05d6c865266bf451d13bfa5e1b0d98438fda7dc1c9bdbc1c6a83484577d
EOF
      ;;
  esac
}

reset_case() {
  rm -rf "$TMPDIR" "$DESTINATION"
  mkdir "$TMPDIR"
  : > "$EVENTS"
  unset FAIL_CHECKSUM FAIL_DOWNLOAD
}

check_cleanup() {
  [ "$(ls -A "$TMPDIR")" = '' ] || fail 'scratch files remain'
}

for TARGETARCH in amd64 arm64; do
  export TARGETARCH
  examples "$TARGETARCH"
  reset_case
  sh "$installer" "$DESTINATION"
  for name in uv uvx rtk fff-mcp; do
    [ -x "$DESTINATION/$name" ] || fail "missing executable: $name"
  done
  for name in uv uvx rtk; do
    [ "$(cat "$DESTINATION/$name")" = "stub executable: $name" ] || fail "wrong installed contents: $name"
  done
  [ "$(cat "$DESTINATION/fff-mcp")" = 'stub download: fff-mcp' ] || fail 'wrong installed contents: fff-mcp'
  [ "$(grep -c '^curl ' "$EVENTS")" = 3 ] || fail 'wrong download count'
  [ "$(grep -c '^install ' "$EVENTS")" = 4 ] || fail 'wrong install count'
  check_cleanup

  for asset in uv.tar.gz rtk.tar.gz fff-mcp; do
    reset_case
    export FAIL_CHECKSUM="$asset"
    if sh "$installer" "$DESTINATION"; then fail "checksum rejection ignored: $asset"; fi
    [ ! -e "$DESTINATION" ] || fail 'installed before all checksums passed'
    if grep -E '^(tar|install)' "$EVENTS" >/dev/null; then fail 'extracted before verification'; fi
    check_cleanup
  done

  reset_case
  export FAIL_DOWNLOAD=rtk.tar.gz
  if sh "$installer" "$DESTINATION"; then fail 'download failure ignored'; fi
  [ ! -e "$DESTINATION" ] || fail 'installed after download failure'
  check_cleanup
done

reset_case
export TARGETARCH=unsupported
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'unsupported architecture accepted'; fi
[ ! -s "$EVENTS" ] || fail 'unsupported architecture reached network'
grep -F 'Unsupported tool architecture: unsupported' "$temporary/error" >/dev/null || fail 'missing architecture error'
[ ! -e "$DESTINATION" ] || fail 'unsupported architecture installed tools'
check_cleanup

printf '%s\n' 'PASS: installer tests'
