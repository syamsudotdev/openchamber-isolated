#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
entrypoint=${BOOTSTRAP_ENTRYPOINT:-$root/entrypoint.sh}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_file() {
  [ -f "$1" ] || fail "missing file: $1"
  [ "$(cat "$1")" = "$2" ] || fail "unexpected contents: $1"
}

mkdir -p "$temporary/source/agents" "$temporary/source/skills/example/assets" "$temporary/bin"
# Fixed examples are independent of the entrypoint implementation.
printf '%s\n' '{"example":"bundled"}' > "$temporary/source/opencode.jsonc"
printf '%s\n' '# Bundled agent' > "$temporary/source/agents/example.md"
printf '%s\n' '# Bundled skill' > "$temporary/source/skills/example/SKILL.md"
printf '%s\n' 'nested asset example' > "$temporary/source/skills/example/assets/reference.txt"
printf '%s\n' 'hidden asset example' > "$temporary/source/skills/example/.reference"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$@" > "$START_LOG"' > "$temporary/bin/openchamber"
chmod +x "$temporary/bin/openchamber"
export PATH="$temporary/bin:$PATH"
export OPENCODE_BOOTSTRAP_DIR="$temporary/source"
export OPENCODE_DATA_DIR="$temporary/data"
export XDG_CACHE_HOME="$temporary/cache"
export OPENCHAMBER_DATA_DIR="$temporary/chamber"
export START_LOG="$temporary/start.log"
export OPENCODE_CONFIG_DIR="$temporary/clean"

start() {
  sh "$entrypoint"
}

start
expect_file "$OPENCODE_CONFIG_DIR/opencode.jsonc" '{"example":"bundled"}'
expect_file "$OPENCODE_CONFIG_DIR/agents/example.md" '# Bundled agent'
expect_file "$OPENCODE_CONFIG_DIR/skills/example/SKILL.md" '# Bundled skill'
expect_file "$OPENCODE_CONFIG_DIR/skills/example/assets/reference.txt" 'nested asset example'
expect_file "$OPENCODE_CONFIG_DIR/skills/example/.reference" 'hidden asset example'
expect_file "$START_LOG" "$(printf '%s\n' --foreground --host 0.0.0.0 --port 3000)"
[ -d "$OPENCODE_DATA_DIR" ] && [ -d "$XDG_CACHE_HOME/opencode" ] && [ -d "$OPENCHAMBER_DATA_DIR" ] || fail 'missing runtime directories'

export OPENCODE_CONFIG_DIR="$temporary/partial"
mkdir -p "$OPENCODE_CONFIG_DIR/skills/example/assets"
printf '%s\n' 'user configuration' > "$OPENCODE_CONFIG_DIR/opencode.jsonc"
printf '%s\n' 'user asset' > "$OPENCODE_CONFIG_DIR/skills/example/assets/reference.txt"
printf '%s\n' 'user-only file' > "$OPENCODE_CONFIG_DIR/local.txt"
start
start
expect_file "$OPENCODE_CONFIG_DIR/opencode.jsonc" 'user configuration'
expect_file "$OPENCODE_CONFIG_DIR/skills/example/assets/reference.txt" 'user asset'
expect_file "$OPENCODE_CONFIG_DIR/local.txt" 'user-only file'
expect_file "$OPENCODE_CONFIG_DIR/agents/example.md" '# Bundled agent'
expect_file "$OPENCODE_CONFIG_DIR/skills/example/SKILL.md" '# Bundled skill'

# File symlinks, including dangling symlinks, must remain untouched.
export OPENCODE_CONFIG_DIR="$temporary/file-links"
mkdir -p "$OPENCODE_CONFIG_DIR/agents" "$temporary/outside"
printf '%s\n' 'outside contents' > "$temporary/outside/existing"
ln -s "$temporary/outside/missing" "$OPENCODE_CONFIG_DIR/opencode.jsonc"
ln -s "$temporary/outside/existing" "$OPENCODE_CONFIG_DIR/agents/example.md"
start
[ -L "$OPENCODE_CONFIG_DIR/opencode.jsonc" ] || fail 'dangling symlink replaced'
[ ! -e "$temporary/outside/missing" ] || fail 'dangling symlink target written'
[ -L "$OPENCODE_CONFIG_DIR/agents/example.md" ] || fail 'existing symlink replaced'
expect_file "$temporary/outside/existing" 'outside contents'

expect_rejection() {
  rm -f "$START_LOG"
  if start > "$temporary/error" 2>&1; then
    fail 'unsafe collision accepted'
  fi
  [ ! -e "$START_LOG" ] || fail 'application started after unsafe collision'
  case "$(cat "$temporary/error")" in
    *'OpenCode bootstrap:'*) ;;
    *) fail 'missing bootstrap error' ;;
  esac
}

export OPENCODE_CONFIG_DIR="$temporary/directory-link"
mkdir -p "$OPENCODE_CONFIG_DIR"
ln -s "$temporary/outside" "$OPENCODE_CONFIG_DIR/skills"
expect_rejection
[ ! -e "$temporary/outside/example" ] || fail 'destination directory symlink followed'

export OPENCODE_CONFIG_DIR="$temporary/dangling-directory-link"
mkdir -p "$OPENCODE_CONFIG_DIR"
ln -s "$temporary/outside/missing-directory" "$OPENCODE_CONFIG_DIR/skills"
expect_rejection
[ ! -e "$temporary/outside/missing-directory" ] || fail 'dangling directory target created'

export OPENCODE_CONFIG_DIR="$temporary/collision"
mkdir -p "$OPENCODE_CONFIG_DIR"
printf '%s\n' 'user file' > "$OPENCODE_CONFIG_DIR/skills"
expect_rejection
expect_file "$OPENCODE_CONFIG_DIR/skills" 'user file'

export OPENCODE_CONFIG_DIR="$temporary/root-link"
ln -s "$temporary/outside" "$OPENCODE_CONFIG_DIR"
expect_rejection
[ ! -e "$temporary/outside/opencode.jsonc" ] || fail 'configuration root symlink followed'

export OPENCODE_CONFIG_DIR="$temporary/root-link/"
expect_rejection
[ ! -e "$temporary/outside/opencode.jsonc" ] || fail 'trailing-slash root symlink followed'

export OPENCODE_CONFIG_DIR="$temporary/root-link/child"
expect_rejection
[ ! -e "$temporary/outside/child" ] || fail 'configuration ancestor symlink followed'

printf '%s\n' 'PASS: bootstrap tests'
