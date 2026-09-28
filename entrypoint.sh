#!/bin/sh
set -eu

mkdir -p \
  "$OPENCODE_CONFIG_DIR" \
  "$OPENCODE_DATA_DIR" \
  "$XDG_CACHE_HOME/opencode" \
  "$OPENCHAMBER_DATA_DIR"

if [ ! -e "$OPENCODE_CONFIG_DIR/opencode.jsonc" ]; then
  cp /opt/bootstrap/opencode.jsonc \
    "$OPENCODE_CONFIG_DIR/opencode.jsonc"
fi

exec openchamber \
  --foreground \
  --host 0.0.0.0 \
  --port 3000
