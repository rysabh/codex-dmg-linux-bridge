#!/usr/bin/env bash
set -euo pipefail

# Install the macOS Codex desktop payload from a DMG on Linux.
#
# The script does four broad things:
#   1. Convert the DMG into a mountable image and copy Codex.app out of it.
#   2. Extract the Electron app payload from app.asar.
#   3. Replace macOS-native Node modules with Linux-buildable sources.
#   4. Rebuild those native modules for the Electron version shipped by Codex.
#
# Current Codex DMGs may use APFS, while older images may use HFS+. The script
# detects the converted filesystem instead of assuming either one.
#
# Build caches are kept under WORKDIR so test runs and failed installs are easy
# to clean up and do not leave stale Electron or npm state scattered elsewhere.

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-dmg>" >&2
  exit 1
fi

# Primary paths used by every install stage.
DMG="$(realpath "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="$REPO/Codex"
DMG_IMG="$WORKDIR/Codex.img"
MNT="$WORKDIR/mnt"
SRCFIX="$WORKDIR/native-src-fix"

# Values discovered during the install. They are global so the top-level flow
# can stay small while each stage writes the information it owns.
APP_RES=""
APP_SRC=""
ELECTRON_VER=""
SQLITE_VER=""
PTY_VER=""
BETTER_SQLITE_SELECTED=""
SUDO_KEEPALIVE=""

# Print a timestamped progress message. These logs are intentionally visible
# because DMG conversion and native module rebuilds can otherwise look stuck.
log() {
  printf '\nINFO: [%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

# Print a clear fatal error and stop the install.
fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# Best-effort cleanup for mounts and the background sudo keepalive process.
# This runs on every script exit, including failures during npm or compilation.
cleanup_mounts() {
  if [[ -n "${SUDO_KEEPALIVE:-}" ]]; then
    kill "$SUDO_KEEPALIVE" 2>/dev/null || true
  fi
  fusermount -u "$MNT" 2>/dev/null || true
  sudo umount /mnt/codexdmg 2>/dev/null || true
}

# Ask for sudo once and keep it fresh while long conversion/build steps run.
# Without this, a later mount or package-install step may block for a password.
start_sudo_keepalive() {
  log "Requesting sudo access."
  sudo -v
  ( while true; do sudo -v; sleep 60; done ) &
  SUDO_KEEPALIVE=$!
  trap cleanup_mounts EXIT
}

# Install Ubuntu packages required to convert, mount, and compile the payload.
# npm packages are handled later because their versions depend on the DMG.
install_system_dependencies() {
  log "Installing system dependencies."
  sudo apt-get update -qq
  sudo apt-get install -y dmg2img build-essential python3 make g++ pkg-config libsqlite3-dev
}

# Remove any previous install output and create the work directory for this run.
prepare_workdir() {
  log "Preparing clean work directory at $WORKDIR."
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
}

# Keep npm downloads and Electron headers inside WORKDIR. This makes retries more
# reproducible and lets a simple WORKDIR cleanup remove most generated artifacts.
configure_build_environment() {
  export npm_config_cache="$WORKDIR/npm-cache"
  export NPM_CONFIG_CACHE="$WORKDIR/npm-cache"
  export npm_config_devdir="$WORKDIR/electron-gyp"
  mkdir -p "$npm_config_cache" "$npm_config_devdir"
  log "Using isolated npm cache: $npm_config_cache"
  log "Using isolated Electron header cache: $npm_config_devdir"
}

# Convert the input DMG to a raw filesystem image. dmg2img prints very noisy
# progress output, so its output is written to a log file instead of the terminal.
convert_dmg() {
  log "Converting DMG to mountable image. Conversion log: $WORKDIR/dmg2img.log"
  dmg2img -p 4 "$DMG" "$DMG_IMG" > "$WORKDIR/dmg2img.log" 2>&1
}

# Mount an APFS image with FUSE and copy Codex.app out of it.
# Current Codex DMGs have used this layout, with Codex.app under root/.
copy_app_from_apfs() {
  command -v apfs-fuse >/dev/null 2>&1 || fail "Converted DMG is APFS, but apfs-fuse is not installed."

  log "Mounting APFS image with apfs-fuse."
  apfs-fuse -o uid="$(id -u)",gid="$(id -g)" "$DMG_IMG" "$MNT"

  APP_SRC="$(find "$MNT" -maxdepth 3 -type d -name "Codex.app" -print -quit)"
  [[ -n "$APP_SRC" ]] || fail "Could not find Codex.app inside APFS image."

  log "Copying Codex.app from APFS image: $APP_SRC"
  cp -a "$APP_SRC" "$WORKDIR/Codex.app"

  log "Unmounting APFS image."
  fusermount -u "$MNT"
}

# Mount an HFS+ image with the Linux kernel hfsplus driver and copy Codex.app.
# This keeps compatibility with older or differently-packaged DMG images.
copy_app_from_hfs() {
  log "Mounting HFS+ image with kernel hfsplus support."
  sudo mkdir -p /mnt/codexdmg
  sudo modprobe hfsplus
  sudo mount -t hfsplus -o loop,ro "$DMG_IMG" /mnt/codexdmg

  log "Copying Codex.app from HFS+ image."
  sudo cp -a /mnt/codexdmg/Codex.app "$WORKDIR/Codex.app"

  log "Unmounting HFS+ image."
  sudo umount /mnt/codexdmg
  sudo chown -R "$USER":"$USER" "$WORKDIR/Codex.app"
}

# Detect the converted image filesystem and dispatch to the matching copy path.
copy_app_from_image() {
  local img_kind

  img_kind="$(file -b "$DMG_IMG")"
  log "Converted image type: $img_kind"
  mkdir -p "$MNT"

  if [[ "$img_kind" == *"Apple File System"* ]]; then
    copy_app_from_apfs
  elif [[ "$img_kind" == *"Hierarchical File System"* || "$img_kind" == *"HFS"* ]]; then
    copy_app_from_hfs
  else
    fail "Unsupported converted image type: $img_kind"
  fi
}

# Extract the Electron application from app.asar and merge unpacked resources.
# Native modules usually live under app.asar.unpacked and must be present before
# version detection and rebuilding.
unpack_app_payload() {
  APP_RES="$WORKDIR/Codex.app/Contents/Resources"
  log "Extracting app.asar into $WORKDIR/asar-unpacked."
  npx --yes asar extract "$APP_RES/app.asar" "$WORKDIR/asar-unpacked"

  log "Copying unpacked app.asar resources."
  cp -a "$APP_RES/app.asar.unpacked/." "$WORKDIR/asar-unpacked/"
}

# Read the Electron and native module versions from the extracted app payload.
# These versions drive the launcher patch and the native module rebuild process.
detect_versions() {
  log "Detecting Electron and native module versions from the app payload."
  ELECTRON_VER=$(node -p "require('$WORKDIR/asar-unpacked/package.json').devDependencies.electron" | tr -d '^~')
  SQLITE_VER=$(node -p "require('$WORKDIR/asar-unpacked/node_modules/better-sqlite3/package.json').version")
  PTY_VER=$(node -p "require('$WORKDIR/asar-unpacked/node_modules/node-pty/package.json').version")
  log "Detected: electron@$ELECTRON_VER  better-sqlite3@$SQLITE_VER  node-pty@$PTY_VER"
}

# Make the bridge launcher use the Electron version required by this Codex app.
# Running a mismatched Electron version can cause ABI or runtime incompatibility.
patch_launcher_electron_version() {
  log "Patching launcher to use electron@$ELECTRON_VER."
  sed -i "s/electron@[0-9][0-9.]*/electron@${ELECTRON_VER}/g" "$REPO/scripts/codex-dmg-linux-launcher.sh"
}

# Create a temporary npm project that holds Linux source packages for modules
# that were originally bundled for macOS inside the DMG.
prepare_native_source_dir() {
  log "Preparing Linux-compatible native module sources in $SRCFIX."
  mkdir -p "$SRCFIX"
  cd "$SRCFIX"
  npm init -y
}

# Install a source package into SRCFIX without running its package scripts.
# Actual compilation is delegated to electron-rebuild so it targets Codex's
# Electron ABI rather than the system Node.js ABI.
install_source_package() {
  local package_name="$1"
  local package_version="$2"

  log "Installing $package_name@$package_version source package."
  cd "$SRCFIX"
  rm -rf "$SRCFIX/node_modules/$package_name"
  npm install --ignore-scripts --no-save "$package_name@$package_version"
}

# Replace one native module in the extracted app with the Linux source copy from
# SRCFIX. The replaced module is rebuilt in place in the app payload.
copy_native_source() {
  local module_name="$1"

  cd "$WORKDIR/asar-unpacked/node_modules"
  rm -rf "$module_name"
  cp -a "$SRCFIX/node_modules/$module_name" .
}

# Patch better-sqlite3 source for newer V8 headers when necessary.
#
# Electron 42 ships V8 14.x, where v8::External requires an external pointer tag
# for New() and Value(). Some better-sqlite3 releases still use the older
# two-argument API. This function adds compatibility macros only when the old
# source pattern is present, then normalizes a null setter argument to nullptr to
# avoid overload ambiguity in newer V8.
patch_better_sqlite_source() {
  local module_dir="$WORKDIR/asar-unpacked/node_modules/better-sqlite3"
  local macros_file="$module_dir/src/util/macros.cpp"
  local helper_file="$module_dir/src/util/helpers.cpp"
  local entry_file="$module_dir/src/better_sqlite3.cpp"

  [[ -f "$macros_file" && -f "$helper_file" && -f "$entry_file" ]] || return 0

  log "Applying better-sqlite3 V8 compatibility patch if needed."

  # Add compatibility wrappers around v8::External::Value() and New().
  if grep -q "info\\.Data()\\.As<v8::External>()->Value()" "$macros_file"; then
    perl -0pi -e 's@#define OnlyAddon static_cast<Addon\*>\(info\.Data\(\)\.As<v8::External>\(\)->Value\(\)\)@#if defined(V8_MAJOR_VERSION) \&\& V8_MAJOR_VERSION >= 14\n#define BETTER_SQLITE3_EXTERNAL_VALUE(external) ((external)->Value(v8::kExternalPointerTypeTagDefault))\n#define BETTER_SQLITE3_NEW_EXTERNAL(isolate, value) v8::External::New((isolate), (value), v8::kExternalPointerTypeTagDefault)\n#else\n#define BETTER_SQLITE3_EXTERNAL_VALUE(external) ((external)->Value())\n#define BETTER_SQLITE3_NEW_EXTERNAL(isolate, value) v8::External::New((isolate), (value))\n#endif\n#define OnlyAddon static_cast<Addon*>(BETTER_SQLITE3_EXTERNAL_VALUE(info.Data().As<v8::External>()))@' "$macros_file"
  fi

  # Route direct v8::External::New() calls through the compatibility wrapper.
  if grep -q "v8::External::New(isolate, addon)" "$entry_file"; then
    sed -i 's/v8::External::New(isolate, addon)/BETTER_SQLITE3_NEW_EXTERNAL(isolate, addon)/g' "$entry_file"
  fi

  # Use nullptr for native property setters so V8 chooses the intended overload.
  sed -i 's/^\([[:space:]]*\)0,\([[:space:]]*\)$/\1nullptr,\2/' "$helper_file"
}

# Rebuild one native module against the detected Electron version.
rebuild_module() {
  local module_name="$1"

  log "Rebuilding $module_name for electron@$ELECTRON_VER."
  cd "$WORKDIR/asar-unpacked"
  npx --yes @electron/rebuild -f -v "$ELECTRON_VER" -w "$module_name"
}

# Remove native modules that cannot be reused directly from the macOS DMG.
# They are replaced with Linux source packages and rebuilt for this Electron ABI.
remove_replaced_native_modules() {
  log "Removing native modules that will be replaced for Linux."
  cd "$WORKDIR/asar-unpacked/node_modules"
  rm -rf better-sqlite3 node-pty objc-js
}

# Replace and rebuild node-pty for Linux.
rebuild_node_pty() {
  install_source_package "node-pty" "$PTY_VER"
  copy_native_source "node-pty"
  rebuild_module "node-pty"
}

# Try one better-sqlite3 package candidate: install source, copy it into the app,
# patch for Electron/V8 compatibility if required, then rebuild it.
try_better_sqlite_candidate() {
  local candidate="$1"

  log "Trying better-sqlite3@$candidate for electron@$ELECTRON_VER."
  install_source_package "better-sqlite3" "$candidate" || return 1
  copy_native_source "better-sqlite3"
  patch_better_sqlite_source
  rebuild_module "better-sqlite3"
}

# Rebuild better-sqlite3 using the version shipped by Codex first, then fall back
# to npm's latest release. This preserves app compatibility when possible while
# still giving future Electron/V8 changes a chance to succeed.
rebuild_better_sqlite() {
  local candidate
  local candidates=("$SQLITE_VER" "latest")

  for candidate in "${candidates[@]}"; do
    if try_better_sqlite_candidate "$candidate"; then
      BETTER_SQLITE_SELECTED="$(node -p "require('$WORKDIR/asar-unpacked/node_modules/better-sqlite3/package.json').version")"
      log "Selected better-sqlite3@$BETTER_SQLITE_SELECTED for electron@$ELECTRON_VER."
      return 0
    fi

    log "better-sqlite3@$candidate failed; trying the next candidate if one exists."
  done

  echo "Could not rebuild better-sqlite3 for electron@$ELECTRON_VER." >&2
  echo "Tried candidates: ${candidates[*]}" >&2
  return 1
}

# Run every native-module replacement/rebuild step in dependency order.
rebuild_native_modules() {
  prepare_native_source_dir
  remove_replaced_native_modules
  rebuild_node_pty
  rebuild_better_sqlite
}

# Provide the Node and npx paths expected by the bridge launcher.
create_runtime_links() {
  log "Creating local Node runtime links."
  mkdir -p "$WORKDIR/tools/node/runtime/bin"
  ln -sf "$(command -v node)" "$WORKDIR/tools/node/runtime/bin/node"
  ln -sf "$(command -v npx)"  "$WORKDIR/tools/node/runtime/bin/npx"
}

# Print the exact command the user can run after a successful install.
print_completion() {
  echo ""
  echo "Installation complete. Run Codex with:"
  echo ""
  echo "  env CODEX_DMG_WORKDIR=\"${WORKDIR}\" CODEX_CLI_PATH=\"$(command -v codex)\" ELECTRON_FORCE_IS_PACKAGED=1 \"${REPO}/scripts/codex-dmg-linux-launcher.sh\""
  echo ""
}

# High-level install sequence. Each step is intentionally small and named so
# failures in the log point to the stage that needs attention.
main() {
  start_sudo_keepalive # Keep sudo available during long-running install steps.
  install_system_dependencies # Install OS packages needed for conversion, mounting, and native builds.
  prepare_workdir # Remove old install output and create a clean work directory.
  configure_build_environment # Keep npm and Electron build caches inside the work directory.
  convert_dmg # Convert the DMG into a raw filesystem image.
  copy_app_from_image # Detect APFS or HFS+ and copy Codex.app out of the image.
  unpack_app_payload # Extract app.asar and merge unpacked resources.
  detect_versions # Read Electron and native module versions from the payload.
  patch_launcher_electron_version # Make the launcher use the payload's Electron version.
  rebuild_native_modules # Replace macOS-native modules and rebuild them for Linux.
  create_runtime_links # Provide node and npx paths expected by the launcher.
  print_completion # Show the command that launches the installed app.
}

main "$@"
