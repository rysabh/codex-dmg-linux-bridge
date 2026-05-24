#!/usr/bin/env bash
set -euo pipefail

RAW_WORKDIR="${CODEX_DMG_WORKDIR:-$HOME/codex-dmg-attempt-latest}"
if command -v readlink >/dev/null 2>&1; then
  WORKDIR="$(readlink -f "$RAW_WORKDIR" 2>/dev/null || printf '%s' "$RAW_WORKDIR")"
else
  WORKDIR="$RAW_WORKDIR"
fi
APP_DIR="$WORKDIR/asar-unpacked"
NODE_BIN="$WORKDIR/tools/node/runtime/bin"
DEFAULT_CODEX_BIN="/home/linuxbrew/.linuxbrew/bin/codex"

if [[ -n "${CODEX_CLI_PATH:-}" ]]; then
  CODEX_BIN="$CODEX_CLI_PATH"
else
  CODEX_BIN="$DEFAULT_CODEX_BIN"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app payload at: $APP_DIR"
  echo "Expected setup dir: $WORKDIR"
  exit 1
fi

if [[ ! -x "$NODE_BIN/npx" ]]; then
  echo "Missing Node runtime at: $NODE_BIN"
  exit 1
fi

if [[ ! -x "$CODEX_BIN" ]]; then
  echo "Missing codex CLI binary at: $CODEX_BIN"
  echo "Set CODEX_CLI_PATH to a valid codex binary and retry."
  exit 1
fi

export PATH="$NODE_BIN:$PATH"
export BUILD_FLAVOR=prod
export NODE_ENV=production
export ELECTRON_RENDERER_URL="file://$APP_DIR/webview/index.html"
export CODEX_CLI_PATH="$CODEX_BIN"

ELECTRON_FLAGS=(
  --no-sandbox
  --ozone-platform=x11
  --disable-features=UseOzonePlatform,CanvasOopRasterization
  --disable-gpu-compositing
  --disable-gpu-rasterization
  --disable-accelerated-2d-canvas
  --disable-accelerated-compositing
  --disable-zero-copy
)

exec "$NODE_BIN/npx" --yes electron@42.1.0 "$APP_DIR" \
  "${ELECTRON_FLAGS[@]}"
