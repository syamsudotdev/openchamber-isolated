#!/bin/sh
set -eu

case "${TARGETARCH:-}" in
  amd64)
    uv_target=x86_64-unknown-linux-gnu
    uv_sha=23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8
    rtk_target=x86_64-unknown-linux-musl
    rtk_sha=9a0f4f8240a0701d9c409dcd9afc1f6f1e8625d55299d84af17fcd26d0b70600
    fff_target=x86_64-unknown-linux-musl
    fff_sha=d1e8671f40c89c445aaa1728a21ec04b74be2e5f99091485caeabcc97f99aceb
    gh_target=linux_amd64
    gh_sha=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
    gitleaks_target=linux_x64
    gitleaks_sha=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
    ;;
  arm64)
    uv_target=aarch64-unknown-linux-gnu
    uv_sha=0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436
    rtk_target=aarch64-unknown-linux-gnu
    rtk_sha=318d1b3b8438a260762f2a5b050bd5a61ebaa7bec13f37c475ca1d6372a3b61d
    fff_target=aarch64-unknown-linux-musl
    fff_sha=35f8e05d6c865266bf451d13bfa5e1b0d98438fda7dc1c9bdbc1c6a83484577d
    gh_target=linux_arm64
    gh_sha=ee32df2323c8847f5fac6cb6b4b69ca75828e9329a8f22f677021f7b3306ce63
    gitleaks_target=linux_arm64
    gitleaks_sha=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
    ;;
  *) printf 'Unsupported tool architecture: %s\n' "${TARGETARCH:-unset}" >&2; exit 1 ;;
esac

# A destination argument permits isolated tests without writes to /usr/local.
destination=${1:-/usr/local/bin}
license_root="$(dirname "$destination")/share/licenses"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

download() {
  curl --fail --location --retry 3 --retry-max-time 600 \
    --connect-timeout 15 --max-time 180 --output "$scratch/$1" "$2"
  printf '%s  %s\n' "$3" "$scratch/$1" | sha256sum --check --status
}

download uv.tar.gz \
  "https://github.com/astral-sh/uv/releases/download/0.12.19/uv-$uv_target.tar.gz" "$uv_sha"
download rtk.tar.gz \
  "https://github.com/rtk-ai/rtk/releases/download/v1.0.0/rtk-oss-$rtk_target.tar.gz" "$rtk_sha"
download fff-mcp \
  "https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-$fff_target" "$fff_sha"
download gh.tar.gz \
  "https://github.com/cli/cli/releases/download/v2.103.3/gh_2.103.3_$gh_target.tar.gz" "$gh_sha"
download gitleaks.tar.gz \
  "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_$gitleaks_target.tar.gz" "$gitleaks_sha"

# Verify every download before extracting or installing any executable.
mkdir "$scratch/uv" "$scratch/rtk" "$scratch/gh" "$scratch/gitleaks"
tar -xzf "$scratch/uv.tar.gz" -C "$scratch/uv" "uv-$uv_target/uv" "uv-$uv_target/uvx"
tar -xzf "$scratch/rtk.tar.gz" -C "$scratch/rtk" rtk LICENSE
tar -xzf "$scratch/gh.tar.gz" -C "$scratch/gh" "gh_2.103.3_$gh_target/bin/gh" "gh_2.103.3_$gh_target/LICENSE"
tar -xzf "$scratch/gitleaks.tar.gz" -C "$scratch/gitleaks" gitleaks LICENSE
mkdir -p "$destination" "$license_root/rtk" "$license_root/gh" "$license_root/gitleaks"
install -m 0755 "$scratch/uv/uv-$uv_target/uv" "$destination/uv"
install -m 0755 "$scratch/uv/uv-$uv_target/uvx" "$destination/uvx"
install -m 0755 "$scratch/rtk/rtk" "$destination/rtk"
install -m 0755 "$scratch/fff-mcp" "$destination/fff-mcp"
install -m 0755 "$scratch/gh/gh_2.103.3_$gh_target/bin/gh" "$destination/gh"
install -m 0755 "$scratch/gitleaks/gitleaks" "$destination/gitleaks"
install -m 0644 "$scratch/rtk/LICENSE" "$license_root/rtk/LICENSE"
install -m 0644 "$scratch/gh/gh_2.103.3_$gh_target/LICENSE" "$license_root/gh/LICENSE"
install -m 0644 "$scratch/gitleaks/LICENSE" "$license_root/gitleaks/LICENSE"
