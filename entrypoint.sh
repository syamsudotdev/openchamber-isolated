#!/bin/sh
set -eu

bootstrap_error() {
  printf 'OpenCode bootstrap: %s\n' "$*" >&2
  exit 1
}

# Check each component before mkdir or copy can follow a destination symlink.
check_directory() (
  directory=$1
  while [ "$directory" != / ] && [ "${directory%/}" != "$directory" ]; do
    directory=${directory%/}
  done
  case "$directory" in
    /) return ;;
    '') bootstrap_error 'empty configuration directory' ;;
  esac
  parent=$(dirname "$directory")
  if [ "$parent" != "$directory" ]; then
    check_directory "$parent"
  fi
  if [ -L "$directory" ]; then
    bootstrap_error "unsafe directory symlink: $directory"
  fi
  if [ -e "$directory" ] && [ ! -d "$directory" ]; then
    bootstrap_error "directory collision: $directory"
  fi
)

seed_directory() (
  source_dir=$1
  destination_dir=$2
  check_directory "$destination_dir"
  mkdir -p "$destination_dir"
  for source in "$source_dir"/* "$source_dir"/.[!.]* "$source_dir"/..?*; do
    [ -e "$source" ] || [ -L "$source" ] || continue
    destination=$destination_dir/${source##*/}
    if [ -L "$source" ]; then
      bootstrap_error "unsupported bundled symlink: $source"
    elif [ -d "$source" ]; then
      seed_directory "$source" "$destination"
    elif [ -f "$source" ]; then
      # -L also detects dangling symlinks, which belong to the user.
      if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
        cp -n "$source" "$destination"
      fi
    else
      bootstrap_error "unsupported bundled file: $source"
    fi
  done
)

bootstrap_source=${OPENCODE_BOOTSTRAP_DIR:-/opt/bootstrap/opencode}
[ -d "$bootstrap_source" ] || bootstrap_error "missing source directory: $bootstrap_source"
seed_directory "$bootstrap_source" "$OPENCODE_CONFIG_DIR"

mkdir -p \
  "$OPENCODE_DATA_DIR" \
  "$XDG_CACHE_HOME/opencode" \
  "$OPENCHAMBER_DATA_DIR"

exec openchamber \
  --foreground \
  --host 0.0.0.0 \
  --port 3000
