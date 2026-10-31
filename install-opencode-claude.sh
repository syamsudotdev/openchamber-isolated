#!/bin/sh
set -eu

version=1.6.0
commit=507cb87bfe9f17ee1d560e4da42e4fd27b2ac5c4

# A destination argument permits isolated tests without writes to /opt.
destination=${1:-/opt/opencode-claude}
patches="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/patches/opencode-claude"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

[ ! -e "$destination" ] || { printf 'Destination exists: %s\n' "$destination" >&2; exit 1; }

# The image has no separate Bun; the OpenCode CLI runs as Bun with this variable.
export BUN_BE_BUN=1
export BUN_INSTALL_CACHE_DIR="$scratch/bun-cache"

git clone --quiet --depth 1 --branch "v$version" \
  https://github.com/openchamber/opencode-claude.git "$destination"
[ "$(git -C "$destination" rev-parse HEAD)" = "$commit" ] \
  || { printf 'Tag v%s does not point to %s\n' "$version" "$commit" >&2; exit 1; }
for patch in "$patches"/*.patch; do
  git -C "$destination" apply "$patch"
done

cd "$destination"
opencode install --frozen-lockfile
opencode run build
opencode test/entrypoint-regression.ts
# Keep only runtime dependencies in the image.
rm -rf node_modules .git
opencode install --frozen-lockfile --production
# The Agent SDK prefers the glibc binary on Debian; the musl copy is unused.
rm -rf node_modules/@anthropic-ai/claude-agent-sdk-linux-*-musl
