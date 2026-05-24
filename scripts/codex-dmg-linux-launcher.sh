#!/usr/bin/env bash
set -euo pipefail

# Why: Codex ships a macOS payload, but Linux needs a Linux Electron runtime.
# What: Launch the prepared Codex payload from CODEX_DMG_WORKDIR.
# How: Read Electron from package.json, set runtime env, then exec npx electron.

RAW_WORKDIR="${CODEX_DMG_WORKDIR:-$HOME/codex-dmg-attempt-latest}"
if command -v readlink >/dev/null 2>&1; then
  WORKDIR="$(readlink -f "$RAW_WORKDIR" 2>/dev/null || printf '%s' "$RAW_WORKDIR")"
else
  WORKDIR="$RAW_WORKDIR"
fi
APP_DIR="$WORKDIR/asar-unpacked"
NODE_BIN="$WORKDIR/tools/node/runtime/bin"
DEFAULT_CODEX_BIN="/home/linuxbrew/.linuxbrew/bin/codex"

resolve_electron_version() {
  local package_json="$APP_DIR/package.json"
  local version=""

  if [[ -n "${CODEX_ELECTRON_VERSION:-}" ]]; then
    printf '%s\n' "${CODEX_ELECTRON_VERSION#v}"
    return 0
  fi

  if [[ -f "$package_json" && -x "$NODE_BIN/node" ]]; then
    version="$("$NODE_BIN/node" -p "const pkg = require(process.argv[1]); const version = pkg.devDependencies?.electron || pkg.dependencies?.electron || ''; String(version).replace(/^[~^v]+/, '')" "$package_json")"
  fi

  if [[ -n "$version" && "$version" != "undefined" ]]; then
    printf '%s\n' "$version"
    return 0
  fi

  echo "Could not detect Electron version from: $package_json" >&2
  echo "Set CODEX_ELECTRON_VERSION to a valid Electron version and retry." >&2
  return 1
}

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

if [[ ! -x "$NODE_BIN/node" ]]; then
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

ELECTRON_VERSION="$(resolve_electron_version)"

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

exec "$NODE_BIN/npx" --yes "electron@$ELECTRON_VERSION" "$APP_DIR" \
  "${ELECTRON_FLAGS[@]}"
