#!/bin/sh
set -eu

case "${TARGETARCH:-}" in
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
    ;;
  *) printf 'Unsupported tool architecture: %s\n' "${TARGETARCH:-unset}" >&2; exit 1 ;;
esac

# Each variable accepts an exact version without a leading v. The default
# selects the latest release.
uv_version=${UV_VERSION:-latest}
rtk_version=${RTK_VERSION:-latest}
fff_version=${FFF_VERSION:-latest}
gh_version=${GH_VERSION:-latest}
gitleaks_version=${GITLEAKS_VERSION:-latest}
claude_version=${CLAUDE_VERSION:-latest}
actionlint_version=${ACTIONLINT_VERSION:-latest}
sops_version=${SOPS_VERSION:-latest}
cosign_version=${COSIGN_VERSION:-latest}
maestro_version=${MAESTRO_VERSION:-latest}

# A destination argument permits isolated tests without writes to /usr/local.
destination=${1:-/usr/local/bin}
maestro_root=${MAESTRO_ROOT:-/opt/maestro}
license_root="$(dirname "$destination")/share/licenses"
versions_file=${IMAGE_VERSIONS_FILE:-$(dirname "$destination")/share/image-versions.txt}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

# The latest-release redirect has no rate limit, unlike the GitHub API.
latest_tag() {
  redirect=$(curl --fail --silent --show-error --output /dev/null \
    --write-out '%{redirect_url}' "https://github.com/$1/releases/latest") || {
    printf 'Cannot resolve the latest release of %s\n' "$1" >&2
    exit 1
  }
  case "$redirect" in
    "https://github.com/$1/releases/tag/"*) tag=${redirect#"https://github.com/$1/releases/tag/"} ;;
    *) printf 'Unexpected latest-release redirect for %s: %s\n' "$1" "$redirect" >&2; exit 1 ;;
  esac
  case "$tag" in
    ''|*/*|*' '*) printf 'Unexpected latest-release tag for %s: %s\n' "$1" "$tag" >&2; exit 1 ;;
  esac
  printf '%s\n' "$tag"
}

resolve_tag() { # repository, tag prefix, requested version
  if [ "$3" = latest ]; then
    latest_tag "$1"
  else
    printf '%s\n' "$2$3"
  fi
}

uv_tag=$(resolve_tag astral-sh/uv '' "$uv_version")
rtk_tag=$(resolve_tag rtk-ai/rtk v "$rtk_version")
fff_tag=$(resolve_tag dmtrKovalenko/fff v "$fff_version")
gh_tag=$(resolve_tag cli/cli v "$gh_version")
gitleaks_tag=$(resolve_tag gitleaks/gitleaks v "$gitleaks_version")
actionlint_tag=$(resolve_tag rhysd/actionlint v "$actionlint_version")
sops_tag=$(resolve_tag getsops/sops v "$sops_version")
cosign_tag=$(resolve_tag sigstore/cosign v "$cosign_version")
maestro_tag=$(resolve_tag mobile-dev-inc/Maestro cli- "$maestro_version")

download() {
  curl --fail --location --retry 3 --retry-max-time 600 \
    --connect-timeout 15 --max-time 900 --output "$scratch/$1" "$2"
}

# The Claude Code download host publishes the latest version as plain text and
# the per-platform checksum in the release manifest of that version.
resolve_claude_version() {
  if [ "$claude_version" != latest ]; then
    printf '%s\n' "$claude_version"
    return
  fi
  download claude-latest.txt https://downloads.claude.ai/claude-code-releases/latest
  version=$(cat "$scratch/claude-latest.txt")
  case "$version" in
    ''|*[!0-9.]*) printf 'Unexpected Claude Code version: %s\n' "$version" >&2; exit 1 ;;
  esac
  printf '%s\n' "$version"
}

validate_sha256() { # hash, asset
  case "$1" in
    *[!0-9a-fA-F]*) printf 'Invalid SHA256 for %s: %s\n' "$2" "$1" >&2; exit 1 ;;
  esac
  [ "${#1}" -eq 64 ] || {
    printf 'Invalid SHA256 for %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

verify_sha256() { # downloaded file, expected hash
  printf '%s  %s\n' "$2" "$1" | sha256sum --check --status
}

# Select the checksum line for one exact asset name. A published file that
# holds only a hash is accepted too.
select_checksum() { # checksum file, asset name, tool name
  checksum_file=$1 asset=$2 tool=$3
  report=$scratch/checksum-report
  : > "$report"
  if ! hash=$(awk -v asset="$asset" -v report="$report" '
    NF == 0 { next }
    {
      lines++
      if (NF >= 2) {
        name = $2
        sub(/^\*/, "", name)
        if (name == asset) { matches++; found = $1 }
      } else {
        single = $1
      }
    }
    END {
      if (matches > 1) { print "more than one line for " asset > report; exit 3 }
      if (matches == 1) { print found; exit 0 }
      if (lines == 1 && single != "") { print single; exit 0 }
      print "no line for " asset > report
      exit 4
    }
  ' "$checksum_file"); then
    printf 'Invalid checksum asset for %s: %s\n' "$tool" "$(cat "$report")" >&2
    exit 1
  fi
  validate_sha256 "$hash" "$asset"
  printf '%s\n' "$hash"
}

claude_number=$(resolve_claude_version)

uv_asset="uv-$uv_target.tar.gz"
download "$uv_asset" "https://github.com/astral-sh/uv/releases/download/$uv_tag/$uv_asset"
download uv.sha256 "https://github.com/astral-sh/uv/releases/download/$uv_tag/$uv_asset.sha256"
uv_hash=$(select_checksum "$scratch/uv.sha256" "$uv_asset" uv)
verify_sha256 "$scratch/$uv_asset" "$uv_hash"

rtk_asset="rtk-oss-$rtk_target.tar.gz"
download "$rtk_asset" "https://github.com/rtk-ai/rtk/releases/download/$rtk_tag/$rtk_asset"
download rtk-checksums.txt "https://github.com/rtk-ai/rtk/releases/download/$rtk_tag/checksums.txt"
rtk_hash=$(select_checksum "$scratch/rtk-checksums.txt" "$rtk_asset" rtk)
verify_sha256 "$scratch/$rtk_asset" "$rtk_hash"

fff_asset="fff-mcp-$fff_target"
download "$fff_asset" "https://github.com/dmtrKovalenko/fff/releases/download/$fff_tag/$fff_asset"
download fff.sha256 "https://github.com/dmtrKovalenko/fff/releases/download/$fff_tag/$fff_asset.sha256"
fff_hash=$(select_checksum "$scratch/fff.sha256" "$fff_asset" fff)
verify_sha256 "$scratch/$fff_asset" "$fff_hash"

gh_number=${gh_tag#v}
gh_asset="gh_${gh_number}_$gh_target.tar.gz"
gh_checksums="gh_${gh_number}_checksums.txt"
download "$gh_asset" "https://github.com/cli/cli/releases/download/$gh_tag/$gh_asset"
download gh-checksums.txt "https://github.com/cli/cli/releases/download/$gh_tag/$gh_checksums"
gh_hash=$(select_checksum "$scratch/gh-checksums.txt" "$gh_asset" gh)
verify_sha256 "$scratch/$gh_asset" "$gh_hash"

gitleaks_number=${gitleaks_tag#v}
gitleaks_asset="gitleaks_${gitleaks_number}_$gitleaks_target.tar.gz"
gitleaks_checksums="gitleaks_${gitleaks_number}_checksums.txt"
download "$gitleaks_asset" "https://github.com/gitleaks/gitleaks/releases/download/$gitleaks_tag/$gitleaks_asset"
download gitleaks-checksums.txt "https://github.com/gitleaks/gitleaks/releases/download/$gitleaks_tag/$gitleaks_checksums"
gitleaks_hash=$(select_checksum "$scratch/gitleaks-checksums.txt" "$gitleaks_asset" gitleaks)
verify_sha256 "$scratch/$gitleaks_asset" "$gitleaks_hash"

claude_asset=claude
download "$claude_asset" "https://downloads.claude.ai/claude-code-releases/$claude_number/$claude_target/claude"
download claude-manifest.json "https://downloads.claude.ai/claude-code-releases/$claude_number/manifest.json"
claude_hash=$(jq -r --arg platform "$claude_target" '.platforms[$platform].checksum // ""' "$scratch/claude-manifest.json")
validate_sha256 "$claude_hash" "$claude_asset"
verify_sha256 "$scratch/$claude_asset" "$claude_hash"

actionlint_number=${actionlint_tag#v}
actionlint_asset="actionlint_${actionlint_number}_$actionlint_target.tar.gz"
actionlint_checksums="actionlint_${actionlint_number}_checksums.txt"
download "$actionlint_asset" "https://github.com/rhysd/actionlint/releases/download/$actionlint_tag/$actionlint_asset"
download actionlint-checksums.txt "https://github.com/rhysd/actionlint/releases/download/$actionlint_tag/$actionlint_checksums"
actionlint_hash=$(select_checksum "$scratch/actionlint-checksums.txt" "$actionlint_asset" actionlint)
verify_sha256 "$scratch/$actionlint_asset" "$actionlint_hash"

sops_number=${sops_tag#v}
sops_asset="sops-v$sops_number.linux.$sops_target"
sops_checksums="sops-v$sops_number.checksums.txt"
download "$sops_asset" "https://github.com/getsops/sops/releases/download/$sops_tag/$sops_asset"
download sops-checksums.txt "https://github.com/getsops/sops/releases/download/$sops_tag/$sops_checksums"
sops_hash=$(select_checksum "$scratch/sops-checksums.txt" "$sops_asset" sops)
verify_sha256 "$scratch/$sops_asset" "$sops_hash"

cosign_number=${cosign_tag#v}
cosign_asset="cosign-linux-$cosign_target"
download "$cosign_asset" "https://github.com/sigstore/cosign/releases/download/$cosign_tag/$cosign_asset"
download cosign-checksums.txt "https://github.com/sigstore/cosign/releases/download/$cosign_tag/cosign_checksums.txt"
cosign_hash=$(select_checksum "$scratch/cosign-checksums.txt" "$cosign_asset" cosign)
verify_sha256 "$scratch/$cosign_asset" "$cosign_hash"

maestro_number=${maestro_tag#cli-}
maestro_asset=maestro.zip
download "$maestro_asset" "https://github.com/mobile-dev-inc/Maestro/releases/download/$maestro_tag/$maestro_asset"
download maestro-checksums.txt "https://github.com/mobile-dev-inc/Maestro/releases/download/$maestro_tag/checksums_sha256.txt"
maestro_hash=$(select_checksum "$scratch/maestro-checksums.txt" "$maestro_asset" maestro)
verify_sha256 "$scratch/$maestro_asset" "$maestro_hash"

# Verify every download before extracting or installing any executable.
mkdir "$scratch/uv" "$scratch/rtk" "$scratch/gh" "$scratch/gitleaks" \
  "$scratch/actionlint" "$scratch/maestro"
tar -xzf "$scratch/$uv_asset" -C "$scratch/uv" "uv-$uv_target/uv" "uv-$uv_target/uvx"
tar -xzf "$scratch/$rtk_asset" -C "$scratch/rtk" rtk LICENSE
tar -xzf "$scratch/$gh_asset" -C "$scratch/gh" "gh_${gh_number}_$gh_target/bin/gh" "gh_${gh_number}_$gh_target/LICENSE"
tar -xzf "$scratch/$gitleaks_asset" -C "$scratch/gitleaks" gitleaks LICENSE
tar -xzf "$scratch/$actionlint_asset" -C "$scratch/actionlint" actionlint LICENSE.txt
unzip -q "$scratch/$maestro_asset" -d "$scratch/maestro"
mkdir -p "$destination" "$license_root/rtk" "$license_root/gh" "$license_root/gitleaks" \
  "$license_root/actionlint" "$maestro_root/bin" "$maestro_root/lib" "$(dirname "$versions_file")"
install -m 0755 "$scratch/uv/uv-$uv_target/uv" "$destination/uv"
install -m 0755 "$scratch/uv/uv-$uv_target/uvx" "$destination/uvx"
install -m 0755 "$scratch/rtk/rtk" "$destination/rtk"
install -m 0755 "$scratch/$fff_asset" "$destination/fff-mcp"
install -m 0755 "$scratch/gh/gh_${gh_number}_$gh_target/bin/gh" "$destination/gh"
install -m 0755 "$scratch/gitleaks/gitleaks" "$destination/gitleaks"
install -m 0755 "$scratch/$claude_asset" "$destination/claude"
install -m 0755 "$scratch/actionlint/actionlint" "$destination/actionlint"
install -m 0755 "$scratch/$sops_asset" "$destination/sops"
install -m 0755 "$scratch/$cosign_asset" "$destination/cosign"
cp -R "$scratch/maestro/maestro/bin/." "$maestro_root/bin/"
cp -R "$scratch/maestro/maestro/lib/." "$maestro_root/lib/"
install -m 0755 "$scratch/maestro/maestro/bin/maestro" "$maestro_root/bin/maestro"
ln -sfn "$maestro_root/bin/maestro" "$destination/maestro"
install -m 0644 "$scratch/rtk/LICENSE" "$license_root/rtk/LICENSE"
install -m 0644 "$scratch/gh/gh_${gh_number}_$gh_target/LICENSE" "$license_root/gh/LICENSE"
install -m 0644 "$scratch/gitleaks/LICENSE" "$license_root/gitleaks/LICENSE"
install -m 0644 "$scratch/actionlint/LICENSE.txt" "$license_root/actionlint/LICENSE.txt"

{
  printf 'uv %s\n' "${uv_tag#v}"
  printf 'rtk %s\n' "${rtk_tag#v}"
  printf 'fff-mcp %s\n' "${fff_tag#v}"
  printf 'gh %s\n' "$gh_number"
  printf 'gitleaks %s\n' "$gitleaks_number"
  printf 'claude %s\n' "$claude_number"
  printf 'actionlint %s\n' "$actionlint_number"
  printf 'sops %s\n' "$sops_number"
  printf 'cosign %s\n' "$cosign_number"
  printf 'maestro %s\n' "$maestro_number"
} >> "$versions_file"
