# Troubleshooting

## Error: `cp: cannot stat .../Codex.app`

Cause:

- The installer assumed every download contained an application bundle named
  `Codex.app`. Some current downloads instead contain `ChatGPT.app`, even when
  the downloaded file is named `Codex-latest-x64.dmg`.

Fix:

- Update to the installer that discovers the unique `.app` bundle containing
  `Contents/Resources/app.asar`. Do not rename the bundle inside the DMG. The
  revised installer accepts either branding and copies the selected bundle to
  its stable local `Codex/Codex.app` path for the rest of the build.

## Error: `Converted DMG is APFS, but apfs-fuse is not installed`

Cause:

- APFS is Apple's newer filesystem format and needs the external `apfs-fuse`
  mount helper on Linux. HFS+ images do not need this helper.

Fix:

- Install `apfs-fuse` using your distribution's package manager or its upstream
  build instructions, then rerun the installer. The installer detects the image
  format and only requires `apfs-fuse` for APFS images.

## Error: `npm error code EROFS` while launching

Cause:

- `npx electron` attempted to write its cache under `~/.npm`, but the home
  directory is read-only or managed by the desktop environment.

Fix:

- Use the revised launcher. It stores npm's cache in
  `Codex/npm-cache`, alongside the prepared payload, so the launcher only needs
  write access to the repository's install directory.

## Error: `SingletonLock: Read-only file system` while launching

Cause:

- Electron attempted to create its profile under `~/.config/Codex`, but the
  desktop session cannot write to the home directory.

Fix:

- Use the revised launcher. Unless `XDG_CONFIG_HOME` or `XDG_CACHE_HOME` is
  already set, it creates both locations under the `Codex/` work directory.
  Set either variable before launching if you prefer a shared profile location.

## Error: model_not_found / requested model does not exist

Cause:

- app is pointing to an older Codex CLI binary
- model config references a model not visible to that binary/account state

Fix:

1. Verify active CLI:

```bash
which -a codex
codex --version
```

2. Force launcher to modern CLI:

```bash
CODEX_CLI_PATH="/home/linuxbrew/.linuxbrew/bin/codex"
```

3. Check available models via app-server `model/list`.

## Message send does nothing in UI

Cause:

- backend turn fails (often model mismatch)

Fix:

- fix model + CLI path
- restart app fully
- create a new conversation

## DBus warning: UnitExists

`org.freedesktop.systemd1.UnitExists` is typically a warning and not the root cause of message failures.

## DeprecationWarning: url.parse

Non-blocking warning from runtime dependency path. Safe to ignore for normal usage.

## MCP context7 failed to start

Non-blocking for core chat flow. Install missing dependency if you need that MCP only.
