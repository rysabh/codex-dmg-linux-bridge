#!/usr/bin/env bash
set -euo pipefail

# Why: .desktop launches do not inherit the terminal environment Codex needs.
# What: Start Codex through the main launcher from desktop entries.
# How: Set CODEX_DMG_WORKDIR, CODEX_CLI_PATH, and ELECTRON_FORCE_IS_PACKAGED.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

find_codex_bin() {
  local candidate

  if candidate="$(command -v codex 2>/dev/null)" && [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(find "$HOME/.nvm/versions/node" -path "*/bin/codex" -type f -executable 2>/dev/null | sort -V | tail -n 1)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  echo "Missing codex CLI binary. Install codex or set CODEX_CLI_PATH." >&2
  return 1
}

export CODEX_DMG_WORKDIR="$REPO/Codex"
export CODEX_CLI_PATH="${CODEX_CLI_PATH:-$(find_codex_bin)}"
export ELECTRON_FORCE_IS_PACKAGED=1

exec "$REPO/scripts/codex-dmg-linux-launcher.sh"
