#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
installer=${TOOLS_INSTALLER:-$root/install-tools.sh}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$temporary/bin" "$temporary/fixtures"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat > "$temporary/bin/curl" <<'SH'
#!/bin/sh
set -eu
# The latest-release query prints a fixed redirect and writes no file.
if [ "${4:-}" = --output ] && [ "${5:-}" = /dev/null ] && [ "${6:-}" = --write-out ]; then
  [ "$1" = --fail ] && [ "$2" = --silent ] && [ "$3" = --show-error ] || exit 1
  [ "${7}" = '%{redirect_url}' ] || exit 1
  url=${8}
  case "$url" in
    https://github.com/*/releases/latest) ;;
    *) printf 'Unexpected latest-release URL: %s\n' "$url" >&2; exit 1 ;;
  esac
  repo=${url#https://github.com/}
  repo=${repo%/releases/latest}
  printf 'redirect %s\n' "$repo" >> "$EVENTS"
  if [ "${BAD_REDIRECT:-}" = "$repo" ]; then
    printf '%s\n' 'https://example.com/releases/tag/9.9.9'
    exit 0
  fi
  line=$(grep -F "$repo " "$EXPECTED_TAGS") || { printf 'No fixture tag for %s\n' "$repo" >&2; exit 1; }
  printf 'https://github.com/%s/releases/tag/%s\n' "$repo" "${line#* }"
  exit 0
fi
[ "$1" = --fail ] && [ "$2" = --location ] && [ "$3" = --retry ] && [ "$4" = 3 ] || exit 1
[ "$5" = --retry-max-time ] && [ "$6" = 600 ] || exit 1
[ "$7" = --connect-timeout ] && [ "$8" = 15 ] || exit 1
[ "$9" = --max-time ] && [ "${10}" = 900 ] && [ "${11}" = --output ] || exit 1
file=${12}; url=${13}
name=${file##*/}
grep -Fx "$name $url" "$EXPECTED_URLS" >/dev/null || { printf 'Unexpected release URL: %s\n' "$url" >&2; exit 1; }
printf 'curl %s\n' "$name" >> "$EVENTS"
[ "${FAIL_DOWNLOAD:-}" != "$name" ] || exit 22
case "$name" in
  claude-latest.txt)
    printf '%s\n' "$CLAUDE_FIXTURE_VERSION" > "$file"
    ;;
  claude-manifest.json)
    cp "$FIXTURES/claude-manifest.json" "$file"
    ;;
  *.sha256|*checksums.txt)
    source=$FIXTURES/$name
    asset=$(awk -v n="$name" '$1 == n { print $2 }' "$FIXTURES/assets")
    if [ "${MISSING_CHECKSUM:-}" = "$name" ]; then
      grep -v -F "  $asset" "$source" > "$file" || :
    elif [ "${DUPLICATE_CHECKSUM:-}" = "$name" ]; then
      cat "$source" "$source" > "$file"
    elif [ "${BAD_HASH:-}" = "$name" ]; then
      printf 'deadbeef  %s\n' "$asset" > "$file"
    elif [ "$name" = uv.sha256 ] && [ "${BARE_SHA256:-}" = 1 ]; then
      cut -d' ' -f1 "$source" > "$file"
    else
      cp "$source" "$file"
    fi
    ;;
  *)
    printf 'stub download: %s\n' "$name" > "$file"
    ;;
esac
SH

cat > "$temporary/bin/sha256sum" <<'SH'
#!/bin/sh
set -eu
[ "$1" = --check ] && [ "$2" = --status ]
read -r hash file
name=${file##*/}
grep -Fx "$name $hash" "$EXPECTED_HASHES" >/dev/null || { printf 'Unexpected checksum for %s: %s\n' "$name" "$hash" >&2; exit 1; }
[ -f "$file" ]
printf 'sha %s\n' "$name" >> "$EVENTS"
[ "${FAIL_CHECKSUM:-}" != "$name" ] || exit 1
SH

cat > "$temporary/bin/tar" <<'SH'
#!/bin/sh
set -eu
[ "$(grep -c '^sha ' "$EVENTS")" = 10 ]
[ "$1" = -xzf ] && [ "$3" = -C ]
archive=${2##*/}
directory=$4
shift 4
for member do
  # These members are fixed test fixtures, independent of installer variables.
  case "$TARGETARCH:$member" in
    amd64:uv-x86_64-unknown-linux-gnu/uv|amd64:uv-x86_64-unknown-linux-gnu/uvx|amd64:rtk|amd64:LICENSE|amd64:actionlint) ;;
    amd64:gh_2.104.0_linux_amd64/bin/gh|amd64:gh_2.104.0_linux_amd64/LICENSE|amd64:gitleaks|amd64:LICENSE.txt) ;;
    arm64:uv-aarch64-unknown-linux-gnu/uv|arm64:uv-aarch64-unknown-linux-gnu/uvx|arm64:rtk|arm64:LICENSE|arm64:actionlint) ;;
    arm64:gh_2.104.0_linux_arm64/bin/gh|arm64:gh_2.104.0_linux_arm64/LICENSE|arm64:gitleaks|arm64:LICENSE.txt) ;;
    *) printf 'Unexpected archive member for %s: %s\n' "$TARGETARCH" "$member" >&2; exit 1 ;;
  esac
  mkdir -p "$directory/$(dirname "$member")"
  case "$member" in
    */LICENSE) printf '%s\n' 'MIT License' > "$directory/$member" ;;
    *LICENSE.txt) printf '%s\n' 'MIT License' 'actionlint' > "$directory/$member" ;;
    LICENSE)
      if [ "${archive#gitleaks}" != "$archive" ]; then
        printf '%s\n' 'MIT License' 'gitleaks' > "$directory/$member"
      else
        printf '%s\n' 'Apache License' 'Version 2.0, January 2004' > "$directory/$member"
      fi
      ;;
    *) printf 'stub executable: %s\n' "${member##*/}" > "$directory/$member" ;;
  esac
  printf 'extract %s\n' "$member" >> "$EVENTS"
done
printf '%s\n' tar >> "$EVENTS"
SH

cat > "$temporary/bin/install" <<'SH'
#!/bin/sh
set -eu
[ "$1" = -m ]
[ "$(grep -c '^sha ' "$EVENTS")" = 10 ]
[ "$(grep -c '^tar$' "$EVENTS")" = 5 ]
case "$4" in
  "$LICENSE_ROOT/rtk/LICENSE"|"$LICENSE_ROOT/gh/LICENSE"|"$LICENSE_ROOT/gitleaks/LICENSE"|"$LICENSE_ROOT/actionlint/LICENSE.txt") [ "$2" = 0644 ] ;;
  "$MAESTRO_ROOT/bin/maestro") [ "$2" = 0755 ] ;;
  "$DESTINATION"/*) [ "$2" = 0755 ] ;;
  *) exit 1 ;;
esac
target=$4
case "$4" in
  */) target=$4${3##*/} ;;
esac
cp "$3" "$target"
chmod "$2" "$target"
printf 'install %s\n' "${target##*/}" >> "$EVENTS"
SH
cat > "$temporary/bin/unzip" <<'SH'
#!/bin/sh
set -eu
[ "$1" = -q ] && [ "$3" = -d ] || exit 1
[ "$(grep -c '^sha ' "$EVENTS")" = 10 ] || exit 1
archive=${2##*/}
[ "$archive" = maestro.zip ] || exit 1
directory=$4
mkdir -p "$directory/maestro/bin" "$directory/maestro/lib"
printf '%s\n' 'stub maestro launcher' > "$directory/maestro/bin/maestro"
printf '%s\n' 'stub maestro launcher for Windows' > "$directory/maestro/bin/maestro.bat"
printf '%s\n' 'stub maestro jar' > "$directory/maestro/lib/maestro.jar"
printf '%s\n' 'stub maestro pom' > "$directory/maestro/lib/js-community-24.2.0.pom"
printf 'unzip %s\n' "$archive" >> "$EVENTS"
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
export EVENTS="$temporary/events"
export EXPECTED_TAGS="$temporary/tags"
export EXPECTED_URLS="$temporary/urls"
export EXPECTED_HASHES="$temporary/hashes"
export FIXTURES="$temporary/fixtures"
export TMPDIR="$temporary/scratch"
export DESTINATION="$temporary/prefix/bin"
export LICENSE_ROOT="$temporary/prefix/share/licenses"
export MAESTRO_ROOT="$temporary/prefix/opt/maestro"
export DEFAULT_VERSIONS="$temporary/prefix/share/image-versions.txt"

# Fixed release examples come from the published release assets, not the
# installer. Each architecture has its own names and hashes.
examples() {
  case "$1" in
    amd64)
      uv_target=x86_64-unknown-linux-gnu
      rtk_target=x86_64-unknown-linux-musl
      fff_target=x86_64-unknown-linux-musl
      gh_target=linux_amd64
      gitleaks_target=linux_x64
      claude_target=linux-x64
      actionlint_target=linux_amd64
      sops_target=amd64
      cosign_target=amd64
      uv_hash=5acfd9177cfecf0bf87578f059728215ccc884388988f55f7a65041b57387d91
      rtk_hash=a28407dc13038bdc9c2a1f5a047b0c636e0c1d495b15523576e2adb992a06a17
      fff_hash=d1e8671f40c89c445aaa1728a21ec04b74be2e5f99091485caeabcc97f99aceb
      gh_hash=98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e
      gitleaks_hash=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
      claude_hash=86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada
      actionlint_hash=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
      sops_hash=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
      cosign_hash=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa
      maestro_hash=5384593cb4e7a106489e75a821d157dd43f4e438df6bc308b72e82c685e1283a
      decoy_rtk=rtk-oss-aarch64-unknown-linux-musl.tar.gz
      decoy_gh=gh_2.104.0_linux_arm64.tar.gz
      decoy_gitleaks=gitleaks_8.30.1_linux_arm64.tar.gz
      decoy_actionlint=actionlint_1.7.12_linux_arm64.tar.gz
      decoy_sops=sops-v3.13.3.linux.arm64
      decoy_cosign=cosign-linux-arm64
      ;;
    arm64)
      uv_target=aarch64-unknown-linux-gnu
      rtk_target=aarch64-unknown-linux-gnu
      fff_target=aarch64-unknown-linux-musl
      gh_target=linux_arm64
      gitleaks_target=linux_arm64
      claude_target=linux-arm64
      actionlint_target=linux_arm64
      sops_target=arm64
      cosign_target=arm64
      uv_hash=74f2f5c6024d397481db228db8fc25eed420db192243f88438c118e7e013e585
      rtk_hash=9786c61dbbea704e1468ee7060930d3b45b67f79ba2babfb73463e85340628d9
      fff_hash=35f8e05d6c865266bf451d13bfa5e1b0d98438fda7dc1c9bdbc1c6a83484577d
      gh_hash=cb34cefc6f4e77b90731374a2b737516bb8f3033c6ca46aa949e5344f68069e3
      gitleaks_hash=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
      claude_hash=2e2496c9a8065df93acb0fca2d341f59a6b8777649b2e025ab8c9bcd5eef61f3
      actionlint_hash=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
      sops_hash=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77
      cosign_hash=ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2
      maestro_hash=5384593cb4e7a106489e75a821d157dd43f4e438df6bc308b72e82c685e1283a
      decoy_rtk=rtk-oss-x86_64-unknown-linux-musl.tar.gz
      decoy_gh=gh_2.104.0_linux_amd64.tar.gz
      decoy_gitleaks=gitleaks_8.30.1_linux_x64.tar.gz
      decoy_actionlint=actionlint_1.7.12_linux_amd64.tar.gz
      decoy_sops=sops-v3.13.3.linux.amd64
      decoy_cosign=cosign-linux-amd64
      ;;
  esac
  uv_asset=uv-$uv_target.tar.gz
  rtk_asset=rtk-oss-$rtk_target.tar.gz
  fff_asset=fff-mcp-$fff_target
  gh_asset=gh_2.104.0_$gh_target.tar.gz
  gitleaks_asset=gitleaks_8.30.1_$gitleaks_target.tar.gz
  claude_asset=claude
  actionlint_asset=actionlint_1.7.12_$actionlint_target.tar.gz
  sops_asset=sops-v3.13.3.linux.$sops_target
  cosign_asset=cosign-linux-$cosign_target
  maestro_asset=maestro.zip
  CLAUDE_FIXTURE_VERSION=2.1.311
  export CLAUDE_FIXTURE_VERSION

  cat > "$EXPECTED_TAGS" <<'EOF'
astral-sh/uv 0.13.8
rtk-ai/rtk v1.2.0
dmtrKovalenko/fff v0.11.0
cli/cli v2.104.0
gitleaks/gitleaks v8.30.1
rhysd/actionlint v1.7.12
getsops/sops v3.13.3
sigstore/cosign v3.1.4
mobile-dev-inc/Maestro cli-2.11.0
EOF
  cat > "$EXPECTED_URLS" <<EOF
$uv_asset https://github.com/astral-sh/uv/releases/download/0.13.8/uv-$uv_target.tar.gz
uv.sha256 https://github.com/astral-sh/uv/releases/download/0.13.8/uv-$uv_target.tar.gz.sha256
$rtk_asset https://github.com/rtk-ai/rtk/releases/download/v1.2.0/rtk-oss-$rtk_target.tar.gz
rtk-checksums.txt https://github.com/rtk-ai/rtk/releases/download/v1.2.0/checksums.txt
$fff_asset https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-$fff_target
fff.sha256 https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-$fff_target.sha256
$gh_asset https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_$gh_target.tar.gz
gh-checksums.txt https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_checksums.txt
$gitleaks_asset https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_$gitleaks_target.tar.gz
gitleaks-checksums.txt https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt
claude-latest.txt https://downloads.claude.ai/claude-code-releases/latest
claude https://downloads.claude.ai/claude-code-releases/2.1.311/$claude_target/claude
claude-manifest.json https://downloads.claude.ai/claude-code-releases/2.1.311/manifest.json
$actionlint_asset https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_$actionlint_target.tar.gz
actionlint-checksums.txt https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_checksums.txt
$sops_asset https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.$sops_target
sops-checksums.txt https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.checksums.txt
$cosign_asset https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign-linux-$cosign_target
cosign-checksums.txt https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign_checksums.txt
$maestro_asset https://github.com/mobile-dev-inc/Maestro/releases/download/cli-2.11.0/maestro.zip
maestro-checksums.txt https://github.com/mobile-dev-inc/Maestro/releases/download/cli-2.11.0/checksums_sha256.txt
EOF
  cat > "$EXPECTED_HASHES" <<EOF
$uv_asset $uv_hash
$rtk_asset $rtk_hash
$fff_asset $fff_hash
$gh_asset $gh_hash
$gitleaks_asset $gitleaks_hash
$claude_asset $claude_hash
$actionlint_asset $actionlint_hash
$sops_asset $sops_hash
$cosign_asset $cosign_hash
$maestro_asset $maestro_hash
EOF
  cat > "$FIXTURES/assets" <<EOF
uv.sha256 $uv_asset
rtk-checksums.txt $rtk_asset
fff.sha256 $fff_asset
gh-checksums.txt $gh_asset
gitleaks-checksums.txt $gitleaks_asset
actionlint-checksums.txt $actionlint_asset
sops-checksums.txt $sops_asset
cosign-checksums.txt $cosign_asset
maestro-checksums.txt $maestro_asset
EOF
  printf '%s  %s\n' "$uv_hash" "$uv_asset" > "$FIXTURES/uv.sha256"
  cat > "$FIXTURES/rtk-checksums.txt" <<EOF
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  $decoy_rtk
$rtk_hash  $rtk_asset
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  rtk-oss_amd64.deb
EOF
  printf '%s  %s\n' "$fff_hash" "$fff_asset" > "$FIXTURES/fff.sha256"
  cat > "$FIXTURES/gh-checksums.txt" <<EOF
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  $decoy_gh
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd  gh_2.104.0_linux_amd64.deb
$gh_hash  $gh_asset
EOF
  cat > "$FIXTURES/gitleaks-checksums.txt" <<EOF
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee  $decoy_gitleaks
ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  gitleaks_8.30.1_windows_x64.zip
$gitleaks_hash  $gitleaks_asset
EOF
  cat > "$FIXTURES/actionlint-checksums.txt" <<EOF
1111111111111111111111111111111111111111111111111111111111111111  $decoy_actionlint
$actionlint_hash  $actionlint_asset
EOF
  cat > "$FIXTURES/sops-checksums.txt" <<EOF
2222222222222222222222222222222222222222222222222222222222222222  $decoy_sops
$sops_hash  $sops_asset
EOF
  cat > "$FIXTURES/cosign-checksums.txt" <<EOF
3333333333333333333333333333333333333333333333333333333333333333  $decoy_cosign
4444444444444444444444444444444444444444444444444444444444444444  cosign-linux-amd64_3.1.4_linux_amd64.sbom.json
$cosign_hash  $cosign_asset
EOF
  printf '%s  %s\n' "$maestro_hash" "$maestro_asset" > "$FIXTURES/maestro-checksums.txt"
  printf '{"version":"2.1.311","platforms":{"%s":{"binary":"claude","checksum":"%s"}}}\n' \
    "$claude_target" "$claude_hash" > "$FIXTURES/claude-manifest.json"
}

reset_case() {
  rm -rf "$TMPDIR" "$temporary/prefix" "$temporary/custom"
  mkdir "$TMPDIR"
  : > "$EVENTS"
  unset FAIL_CHECKSUM FAIL_DOWNLOAD MISSING_CHECKSUM DUPLICATE_CHECKSUM BAD_HASH BAD_REDIRECT BARE_SHA256
}

check_cleanup() {
  [ "$(ls -A "$TMPDIR")" = '' ] || fail 'scratch files remain'
}

cat > "$temporary/expected-versions" <<'EOF'
uv 0.13.8
rtk 1.2.0
fff-mcp 0.11.0
gh 2.104.0
gitleaks 8.30.1
claude 2.1.311
actionlint 1.7.12
sops 3.13.3
cosign 3.1.4
maestro 2.11.0
EOF

for TARGETARCH in amd64 arm64; do
  export TARGETARCH
  examples "$TARGETARCH"
  reset_case
  sh "$installer" "$DESTINATION"
  for name in uv uvx rtk fff-mcp gh gitleaks claude actionlint sops cosign maestro; do
    [ -x "$DESTINATION/$name" ] || fail "missing executable: $name"
  done
  for name in uv uvx rtk gh gitleaks actionlint; do
    [ "$(cat "$DESTINATION/$name")" = "stub executable: $name" ] || fail "wrong installed contents: $name"
  done
  [ "$(cat "$DESTINATION/fff-mcp")" = "stub download: $fff_asset" ] || fail 'wrong installed contents: fff-mcp'
  [ "$(cat "$DESTINATION/claude")" = "stub download: $claude_asset" ] || fail 'wrong installed contents: claude'
  [ "$(cat "$DESTINATION/sops")" = "stub download: $sops_asset" ] || fail 'wrong installed contents: sops'
  [ "$(cat "$DESTINATION/cosign")" = "stub download: $cosign_asset" ] || fail 'wrong installed contents: cosign'
  [ -L "$DESTINATION/maestro" ] || fail 'maestro is not a link'
  [ "$(readlink "$DESTINATION/maestro")" = "$MAESTRO_ROOT/bin/maestro" ] || fail 'wrong maestro link target'
  [ "$(cat "$MAESTRO_ROOT/bin/maestro")" = 'stub maestro launcher' ] || fail 'wrong maestro launcher contents'
  [ "$(cat "$MAESTRO_ROOT/bin/maestro.bat")" = 'stub maestro launcher for Windows' ] || fail 'missing maestro Windows launcher'
  [ "$(cat "$MAESTRO_ROOT/lib/maestro.jar")" = 'stub maestro jar' ] || fail 'wrong maestro jar contents'
  [ "$(cat "$MAESTRO_ROOT/lib/js-community-24.2.0.pom")" = 'stub maestro pom' ] || fail 'missing maestro non-jar library'
  [ "$(stat -c '%a' "$MAESTRO_ROOT/bin/maestro")" = 755 ] || fail 'wrong maestro launcher permissions'
  [ -f "$LICENSE_ROOT/rtk/LICENSE" ] || fail 'missing RTK license'
  [ "$(cat "$LICENSE_ROOT/rtk/LICENSE")" = "$(printf '%s\n' 'Apache License' 'Version 2.0, January 2004')" ] || fail 'wrong RTK license contents'
  [ "$(stat -c '%a' "$LICENSE_ROOT/rtk/LICENSE")" = 644 ] || fail 'wrong RTK license permissions'
  [ "$(cat "$LICENSE_ROOT/gh/LICENSE")" = 'MIT License' ] || fail 'wrong gh license contents'
  [ "$(stat -c '%a' "$LICENSE_ROOT/gh/LICENSE")" = 644 ] || fail 'wrong gh license permissions'
  [ "$(cat "$LICENSE_ROOT/gitleaks/LICENSE")" = "$(printf '%s\n' 'MIT License' 'gitleaks')" ] || fail 'wrong gitleaks license contents'
  [ "$(stat -c '%a' "$LICENSE_ROOT/gitleaks/LICENSE")" = 644 ] || fail 'wrong gitleaks license permissions'
  [ "$(cat "$LICENSE_ROOT/actionlint/LICENSE.txt")" = "$(printf '%s\n' 'MIT License' 'actionlint')" ] || fail 'wrong actionlint license contents'
  [ "$(stat -c '%a' "$LICENSE_ROOT/actionlint/LICENSE.txt")" = 644 ] || fail 'wrong actionlint license permissions'
  [ "$(grep -c '^extract LICENSE$' "$EVENTS")" = 2 ] || fail 'wrong license extraction count'
  [ "$(grep -c "^extract gh_2.104.0_linux_$TARGETARCH/LICENSE\$" "$EVENTS")" = 1 ] || fail 'wrong gh license extraction count'
  [ "$(grep -c '^extract LICENSE.txt$' "$EVENTS")" = 1 ] || fail 'wrong actionlint license extraction count'
  [ "$(grep -c '^redirect ' "$EVENTS")" = 9 ] || fail 'wrong latest-release resolution count'
  [ "$(grep -c '^curl ' "$EVENTS")" = 21 ] || fail 'wrong download count'
  [ "$(grep -c '^sha ' "$EVENTS")" = 10 ] || fail 'wrong checksum count'
  [ "$(grep -c '^tar$' "$EVENTS")" = 5 ] || fail 'wrong extraction count'
  [ "$(grep -c '^unzip maestro.zip$' "$EVENTS")" = 1 ] || fail 'wrong maestro extraction count'
  [ "$(grep -c '^install ' "$EVENTS")" = 15 ] || fail 'wrong install count'
  cmp "$temporary/expected-versions" "$DEFAULT_VERSIONS" || fail 'wrong versions file contents'
  check_cleanup

  for asset in "$uv_asset" "$rtk_asset" "$fff_asset" "$gh_asset" "$gitleaks_asset" \
    "$claude_asset" "$actionlint_asset" "$sops_asset" "$cosign_asset" "$maestro_asset"; do
    reset_case
    export FAIL_CHECKSUM="$asset"
    if sh "$installer" "$DESTINATION"; then fail "checksum rejection ignored: $asset"; fi
    [ ! -e "$temporary/prefix" ] || fail 'installed before all checksums passed'
    if grep -E '^(tar|install)' "$EVENTS" >/dev/null; then fail 'extracted before verification'; fi
    check_cleanup
  done

  for asset in "$rtk_asset" uv.sha256; do
    reset_case
    export FAIL_DOWNLOAD="$asset"
    if sh "$installer" "$DESTINATION"; then fail "download failure ignored: $asset"; fi
    [ ! -e "$temporary/prefix" ] || fail 'installed after download failure'
    check_cleanup
  done
done

# An exact version selection must skip the redirect query.
export TARGETARCH=amd64
examples amd64
reset_case
env UV_VERSION=0.13.8 RTK_VERSION=1.2.0 FFF_VERSION=0.11.0 GH_VERSION=2.104.0 \
  GITLEAKS_VERSION=8.30.1 CLAUDE_VERSION=2.1.311 ACTIONLINT_VERSION=1.7.12 \
  SOPS_VERSION=3.13.3 COSIGN_VERSION=3.1.4 MAESTRO_VERSION=2.11.0 \
  IMAGE_VERSIONS_FILE="$temporary/custom/versions.txt" \
  sh "$installer" "$DESTINATION"
[ "$(grep -c '^redirect ' "$EVENTS")" = 0 ] || fail 'exact versions requested the latest release'
if grep -Fx 'curl claude-latest.txt' "$EVENTS" >/dev/null; then fail 'exact Claude version requested the latest version'; fi
[ -x "$DESTINATION/gh" ] || fail 'missing executable: gh'
cmp "$temporary/expected-versions" "$temporary/custom/versions.txt" || fail 'wrong version override file contents'
[ ! -e "$DEFAULT_VERSIONS" ] || fail 'wrote the default versions file when IMAGE_VERSIONS_FILE is set'
check_cleanup

reset_case
export BAD_REDIRECT=cli/cli
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'bad redirect accepted'; fi
grep -F 'Unexpected latest-release redirect for cli/cli: https://example.com/releases/tag/9.9.9' "$temporary/error" >/dev/null \
  || fail 'missing bad redirect error'
if grep -E '^curl ' "$EVENTS" >/dev/null; then fail 'downloaded after bad redirect'; fi
[ ! -e "$temporary/prefix" ] || fail 'installed after bad redirect'
check_cleanup

reset_case
export MISSING_CHECKSUM=rtk-checksums.txt
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'missing checksum line accepted'; fi
grep -F "Invalid checksum asset for rtk: no line for $rtk_asset" "$temporary/error" >/dev/null \
  || fail 'missing checksum line error'
if grep -E '^(tar|install)' "$EVENTS" >/dev/null; then fail 'extracted after missing checksum line'; fi
[ ! -e "$temporary/prefix" ] || fail 'installed after missing checksum line'
check_cleanup

reset_case
export DUPLICATE_CHECKSUM=gh-checksums.txt
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'duplicate checksum line accepted'; fi
grep -F "Invalid checksum asset for gh: more than one line for $gh_asset" "$temporary/error" >/dev/null \
  || fail 'duplicate checksum line error'
if grep -E '^(tar|install)' "$EVENTS" >/dev/null; then fail 'extracted after duplicate checksum line'; fi
[ ! -e "$temporary/prefix" ] || fail 'installed after duplicate checksum line'
check_cleanup

reset_case
export BAD_HASH=gitleaks-checksums.txt
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'short checksum accepted'; fi
grep -F "Invalid SHA256 for $gitleaks_asset: deadbeef" "$temporary/error" >/dev/null \
  || fail 'missing short checksum error'
[ ! -e "$temporary/prefix" ] || fail 'installed after short checksum'
check_cleanup

# A published .sha256 file that holds only the hash is accepted.
reset_case
export BARE_SHA256=1
sh "$installer" "$DESTINATION"
[ -x "$DESTINATION/uv" ] || fail 'missing executable after bare checksum file'
cmp "$temporary/expected-versions" "$DEFAULT_VERSIONS" || fail 'wrong versions file contents after bare checksum file'
check_cleanup

reset_case
export TARGETARCH=unsupported
if sh "$installer" "$DESTINATION" > "$temporary/error" 2>&1; then fail 'unsupported architecture accepted'; fi
[ ! -s "$EVENTS" ] || fail 'unsupported architecture reached network'
grep -F 'Unsupported tool architecture: unsupported' "$temporary/error" >/dev/null || fail 'missing architecture error'
[ ! -e "$DESTINATION" ] || fail 'unsupported architecture installed tools'
check_cleanup

printf '%s\n' 'PASS: installer tests'
