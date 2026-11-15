#!/bin/sh
set -eu

case "${TARGETARCH:-}" in
  amd64)
    uv_target=x86_64-unknown-linux-gnu
    rtk_target=x86_64-unknown-linux-musl
    fff_target=x86_64-unknown-linux-musl
    gh_target=linux_amd64
    gitleaks_target=linux_x64
    ;;
  arm64)
    uv_target=aarch64-unknown-linux-gnu
    rtk_target=aarch64-unknown-linux-gnu
    fff_target=aarch64-unknown-linux-musl
    gh_target=linux_arm64
    gitleaks_target=linux_arm64
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

# A destination argument permits isolated tests without writes to /usr/local.
destination=${1:-/usr/local/bin}
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

download() {
  curl --fail --location --retry 3 --retry-max-time 600 \
    --connect-timeout 15 --max-time 180 --output "$scratch/$1" "$2"
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
  case "$hash" in
    *[!0-9a-fA-F]*) printf 'Invalid SHA256 for %s: %s\n' "$asset" "$hash" >&2; exit 1 ;;
  esac
  [ "${#hash}" -eq 64 ] || {
    printf 'Invalid SHA256 for %s: %s\n' "$asset" "$hash" >&2
    exit 1
  }
  printf '%s\n' "$hash"
}

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

# Verify every download before extracting or installing any executable.
mkdir "$scratch/uv" "$scratch/rtk" "$scratch/gh" "$scratch/gitleaks"
tar -xzf "$scratch/$uv_asset" -C "$scratch/uv" "uv-$uv_target/uv" "uv-$uv_target/uvx"
tar -xzf "$scratch/$rtk_asset" -C "$scratch/rtk" rtk LICENSE
tar -xzf "$scratch/$gh_asset" -C "$scratch/gh" "gh_${gh_number}_$gh_target/bin/gh" "gh_${gh_number}_$gh_target/LICENSE"
tar -xzf "$scratch/$gitleaks_asset" -C "$scratch/gitleaks" gitleaks LICENSE
mkdir -p "$destination" "$license_root/rtk" "$license_root/gh" "$license_root/gitleaks" "$(dirname "$versions_file")"
install -m 0755 "$scratch/uv/uv-$uv_target/uv" "$destination/uv"
install -m 0755 "$scratch/uv/uv-$uv_target/uvx" "$destination/uvx"
install -m 0755 "$scratch/rtk/rtk" "$destination/rtk"
install -m 0755 "$scratch/$fff_asset" "$destination/fff-mcp"
install -m 0755 "$scratch/gh/gh_${gh_number}_$gh_target/bin/gh" "$destination/gh"
install -m 0755 "$scratch/gitleaks/gitleaks" "$destination/gitleaks"
install -m 0644 "$scratch/rtk/LICENSE" "$license_root/rtk/LICENSE"
install -m 0644 "$scratch/gh/gh_${gh_number}_$gh_target/LICENSE" "$license_root/gh/LICENSE"
install -m 0644 "$scratch/gitleaks/LICENSE" "$license_root/gitleaks/LICENSE"

{
  printf 'uv %s\n' "${uv_tag#v}"
  printf 'rtk %s\n' "${rtk_tag#v}"
  printf 'fff-mcp %s\n' "${fff_tag#v}"
  printf 'gh %s\n' "$gh_number"
  printf 'gitleaks %s\n' "$gitleaks_number"
} >> "$versions_file"
