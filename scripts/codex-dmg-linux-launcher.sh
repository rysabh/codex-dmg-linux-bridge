#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

RAW_WORKDIR="${CODEX_DMG_WORKDIR:-$REPO/Codex}"
if command -v readlink >/dev/null 2>&1; then
  WORKDIR="$(readlink -f "$RAW_WORKDIR" 2>/dev/null || printf '%s' "$RAW_WORKDIR")"
else
  WORKDIR="$RAW_WORKDIR"
fi
APP_DIR="$WORKDIR/asar-unpacked"
NODE_BIN="$WORKDIR/tools/node/runtime/bin"
DEFAULT_CODEX_BIN="$(command -v codex 2>/dev/null || true)"

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

if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
  echo "Missing codex CLI binary at: ${CODEX_BIN:-<not found>}"
  echo "Set CODEX_CLI_PATH to a valid codex binary and retry."
  exit 1
fi

export PATH="$NODE_BIN:$PATH"
export BUILD_FLAVOR=prod
export NODE_ENV=production
export ELECTRON_RENDERER_URL="file://$APP_DIR/webview/index.html"
export CODEX_CLI_PATH="$CODEX_BIN"
export ELECTRON_FORCE_IS_PACKAGED="${ELECTRON_FORCE_IS_PACKAGED:-1}"

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
