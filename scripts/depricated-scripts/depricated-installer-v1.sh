sudo apt update #so you dont have to enter password later (MAYBE this is what is causing crash)
# --- 1) Install required tools ---
# dmg2img: converts macOS DMG -> a mountable image
# build-essential, python3, etc: needed to compile native modules
sudo apt install -y dmg2img build-essential python3 make g++ pkg-config libsqlite3-dev
#----------------#

## prepwork
cd "$HOME/Applications/"
DMG="$HOME/Downloads/Codex-latest-x64.dmg"
WORKDIR="$HOME/Applications/Codex"
# Where the repo with the launcher script lives:
REPO="${WORKDIR}/codex-dmg-linux-bridge"
# Which Codex CLI to use (system install by default):
CODEX_CLI_PATH="$(command -v codex)"


## cleanup 
rm -rf "${WORKDIR}" 

# Where we build the Linux‑ready payload:
mkdir -p "${WORKDIR}" 
cd "${WORKDIR}"

# =========================
# Codex DMG -> Ubuntu (Working Recipe)
# =========================
## IMPORTAND TODO: if the REPO directory already exists, then backup the current setup, by transfering it to a ./backup_applications folder %%
git clone "git@github.com:Mina-Sayed/codex-dmg-linux-bridge.git" codex-dmg-linux-bridge

set -euo pipefail
# --- 0) Configure paths ---
# DMG file you already have:



# --- 2) Convert DMG into a mountable HFS+ image ---
##################################
# !!!!!! THIS STEP FREQUENTLY CRASHES %%
##################################
dmg2img -p 4 "$DMG" "$WORKDIR/Codex-hfs.img"
##################################


# --- 3) Mount the image and copy the app out ---
sudo mkdir -p /mnt/codexdmg
sudo modprobe hfsplus

#error happens here
sudo mount -t hfsplus -o loop "$WORKDIR/Codex-hfs.img" /mnt/codexdmg

# Copy the macOS app bundle out of the mounted image
cp -a "/mnt/codexdmg/Codex.app" "$WORKDIR/Codex.app"

# Unmount when done
sudo umount /mnt/codexdmg

# --- 4) Extract the app payload ---
APP_RES="$WORKDIR/Codex.app/Contents/Resources"

# Copy raw payload files
sudo cp "$APP_RES/app.asar" "$WORKDIR/app.asar"
sudo cp -a "$APP_RES/app.asar.unpacked" "$WORKDIR/app.asar.unpacked"

# Extract app.asar into a real folder
npx --yes asar extract "$WORKDIR/app.asar" "$WORKDIR/asar-unpacked"

# Merge the unpacked folder over the extracted app
cp -a "$WORKDIR/app.asar.unpacked/." "$WORKDIR/asar-unpacked/"

# --- 5) Replace stripped native module sources ---
# Create a temp project that downloads full Linux build sources
SRCFIX="$WORKDIR/native-src-fix"
mkdir -p "$SRCFIX"
cd "$SRCFIX"
[ -f package.json ] || npm init -y
npm install --ignore-scripts better-sqlite3@12.4.6 node-pty@1.1.0

# Replace the stripped versions inside the app
cd "$WORKDIR/asar-unpacked/node_modules"
mv better-sqlite3 better-sqlite3.macos.stripped
mv node-pty node-pty.macos.stripped
cp -a "$SRCFIX/node_modules/better-sqlite3" .
cp -a "$SRCFIX/node_modules/node-pty" .

# --- 6) Rebuild native modules for Electron 40 (Linux) ---
cd "$WORKDIR/asar-unpacked"
npx --yes @electron/rebuild@4.0.3 -f -v 40.0.0 -w better-sqlite3,node-pty

# --- 7) Provide the runtime path the launcher expects ---
mkdir -p "$WORKDIR/tools/node/runtime/bin"
ln -sf "$(command -v node)" "$WORKDIR/tools/node/runtime/bin/node"
ln -sf "$(command -v npx)" "$WORKDIR/tools/node/runtime/bin/npx"

# --- 8) Launch Codex ---
cd "$REPO"
CODEX_DMG_WORKDIR="$WORKDIR" \
CODEX_CLI_PATH="$CODEX_CLI_PATH" \
ELECTRON_FORCE_IS_PACKAGED=1 \
./scripts/codex-dmg-linux-launcher.sh