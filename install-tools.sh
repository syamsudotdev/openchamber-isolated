#!/bin/sh
set -eu

case "${TARGETARCH:-}" in
  amd64)
    uv_target=x86_64-unknown-linux-gnu
    uv_sha=23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8
    rtk_target=x86_64-unknown-linux-musl
    rtk_sha=d19762b5e4aec8f13d5da25631f03bc6ac672d5fec8d67dff704e8c92182e2c9
    fff_target=x86_64-unknown-linux-musl
    fff_sha=d1e8671f40c89c445aaa1728a21ec04b74be2e5f99091485caeabcc97f99aceb
    ;;
  arm64)
    uv_target=aarch64-unknown-linux-gnu
    uv_sha=0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436
    rtk_target=aarch64-unknown-linux-gnu
    rtk_sha=49beb391151f696e0b30c60593cf571afed9ba4e868656633200a8b10bd3c482
    fff_target=aarch64-unknown-linux-musl
    fff_sha=35f8e05d6c865266bf451d13bfa5e1b0d98438fda7dc1c9bdbc1c6a83484577d
    ;;
  *) printf 'Unsupported tool architecture: %s\n' "${TARGETARCH:-unset}" >&2; exit 1 ;;
esac

# A destination argument permits isolated tests without writes to /usr/local.
destination=${1:-/usr/local/bin}
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
  "https://github.com/rtk-ai/rtk/releases/download/v0.23.0/rtk-$rtk_target.tar.gz" "$rtk_sha"
download fff-mcp \
  "https://github.com/dmtrKovalenko/fff/releases/download/v0.11.0/fff-mcp-$fff_target" "$fff_sha"

# Verify every download before extracting or installing any executable.
mkdir "$scratch/uv" "$scratch/rtk"
tar -xzf "$scratch/uv.tar.gz" -C "$scratch/uv" "uv-$uv_target/uv" "uv-$uv_target/uvx"
tar -xzf "$scratch/rtk.tar.gz" -C "$scratch/rtk" rtk
mkdir -p "$destination"
install -m 0755 "$scratch/uv/uv-$uv_target/uv" "$destination/uv"
install -m 0755 "$scratch/uv/uv-$uv_target/uvx" "$destination/uvx"
install -m 0755 "$scratch/rtk/rtk" "$destination/rtk"
install -m 0755 "$scratch/fff-mcp" "$destination/fff-mcp"
