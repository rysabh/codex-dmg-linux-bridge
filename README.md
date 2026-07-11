# codex-dmg-linux-bridge

A practical guide to run the Codex desktop payload (from `Codex.dmg`) on Linux/Ubuntu.
## Install instructions by Rishabh

Run the installer from the cloned repo and pass the path to your downloaded DMG:

```bash
./scripts/codex-install-dmg.sh "$HOME/Downloads/Codex-latest-x64.dmg"
```

The installer creates the Linux-ready Codex payload inside this repo: `./Codex`

Launch Codex with the desktop-safe wrapper:

```bash
./scripts/codex-desktop-launch.sh
```

For a desktop entry, point `Exec` to the absolute path of the wrapper:

```ini
Exec=/absolute/path/to/codex-dmg-linux-bridge/scripts/codex-desktop-launch.sh
```

## 1) What this project does

`Codex.dmg` is built for macOS. This project provides a Linux bridge that helps you:

- extract the required content from `Codex.dmg`
- run the Electron payload on Linux
- wire it to the correct `codex` CLI binary

## 2) Before you start

- You must have your own `Codex.dmg` from the official source.
- This repo does not include DMG/app binaries.
- If anything does not match your machine, check `docs/TROUBLESHOOTING.md`.

## 3) Requirements

- Ubuntu/Linux x64
- `bash`
- `git`
- `node` + `npm` + `npx`
- `dmg2img` (to convert DMG contents)
- `codex` CLI

Install dependencies on Ubuntu:

```bash
sudo apt update
sudo apt install -y dmg2img build-essential python3 make g++ pkg-config libsqlite3-dev git curl
```

Verify your environment:

```bash
node -v
npm -v
npx -v
codex --version
```

For an APFS-formatted DMG, also install `apfs-fuse` using the package or build
method appropriate for your Linux distribution. HFS+-formatted DMGs use the
kernel's `hfsplus` driver, which is available on standard Ubuntu kernels.

## 4) Clone this repository

```bash
git clone https://github.com/Mina-Sayed/codex-dmg-linux-bridge.git
cd codex-dmg-linux-bridge
chmod +x scripts/*.sh
```

## 5) Get `Codex.dmg`

Download `Codex.dmg` from your official account source, then place it on Linux.

Example:

```bash
mkdir -p "$HOME/codex-dmg-attempt-latest"
cp /path/to/Codex.dmg "$HOME/codex-dmg-attempt-latest/Codex.dmg"
```

## 6) Prepare the runtime payload from DMG

The launcher expects a workdir containing:

- `asar-unpacked/`
- `tools/node/runtime/bin/npx`

### 6.1 Extract DMG

```bash
cd "$HOME/codex-dmg-attempt-latest"
7z x Codex.dmg -oextract
```

### 6.2 Extract `app.asar` into `asar-unpacked`

Find `app.asar`:

```bash
APP_ASAR="$(find extract -type f -name app.asar | head -n 1)"
echo "$APP_ASAR"
```

If the path is valid, extract it:

```bash
npx --yes @electron/asar extract "$APP_ASAR" asar-unpacked
```

### 6.3 Ensure `tools/node/runtime/bin/npx` exists

If missing, symlink to your system `npx`:

```bash
mkdir -p tools/node/runtime/bin
ln -sf "$(command -v npx)" tools/node/runtime/bin/npx
```

## 7) Pick the correct Codex CLI binary

Check all installed Codex binaries:

```bash
which -a codex
codex --version
```

If you have multiple binaries, use the newest one (example):

`/home/linuxbrew/.linuxbrew/bin/codex`

## 8) Authenticate Codex CLI

```bash
codex login
```

## 9) First launch

From this repo directory:

```bash
CODEX_DMG_WORKDIR="$HOME/codex-dmg-attempt-latest" \
CODEX_CLI_PATH="/home/linuxbrew/.linuxbrew/bin/codex" \
./scripts/codex-dmg-linux-launcher.sh
```

## 10) Validate that it works

Quick app-server validation:

```bash
codex debug app-server send-message-v2 "reply with one word: ok"
```

Expected final response contains: `ok`.

## 11) Optional: install a global launcher command

```bash
mkdir -p ~/.local/bin
cp scripts/codex-dmg-linux-launcher.sh ~/.local/bin/codex-dmg-linux
chmod +x ~/.local/bin/codex-dmg-linux
```

Run it from anywhere:

```bash
CODEX_DMG_WORKDIR="$HOME/codex-dmg-attempt-latest" \
CODEX_CLI_PATH="/home/linuxbrew/.linuxbrew/bin/codex" \
~/.local/bin/codex-dmg-linux
```

## 12) Common errors (quick map)

- `Missing app payload at .../asar-unpacked`
  - `app.asar` was not extracted correctly.
- `Could not find an application bundle containing Contents/Resources/app.asar`
  - The DMG did not contain a supported Electron application bundle. The
    installer accepts either `Codex.app`, `ChatGPT.app`, or another bundle name;
    it identifies the payload by `app.asar`, not by the bundle's display name.
- `Missing Node runtime at .../tools/node/runtime/bin`
  - Create the `npx` symlink step in section 6.3.
- `Unable to locate the Codex CLI binary`
  - Set `CODEX_CLI_PATH` to a valid `codex` binary.
- `model_not_found`
  - Usually wrong/old CLI binary or incompatible model configuration.

More details: `docs/TROUBLESHOOTING.md`.

## 13) Important files in this repo

- `scripts/codex-dmg-linux-launcher.sh`: main Linux launcher
- `scripts/codex-desktop-launch.sh`: desktop-safe launcher wrapper
- `scripts/codex-install-dmg.sh`: installer that prepares the DMG payload
- `docs/SETUP.md`: additional setup notes
- `docs/TROUBLESHOOTING.md`: fixes for common issues

## License

MIT (see `LICENSE`).
