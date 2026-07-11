# Changelog

Notable changes to the Codex DMG → Linux bridge, grouped by the Codex desktop
version they were validated against. Format follows
[Keep a Changelog](https://keepachangelog.com/).

<!-- Add future changes above this entry as: ## Codex <version> — build <build>, Electron <version> (YYYY-MM-DD). Do not use an undated Unreleased section. -->

## Codex 26.707.41301 — build 5103, Electron 42.1.0 (2026-07-10)

### Fixed

- **HFS+ installs failed when the DMG used a non-`Codex.app` bundle name.** The
  installer now finds the unique `.app` bundle containing
  `Contents/Resources/app.asar`, so a `Codex-latest-x64.dmg` containing
  `ChatGPT.app` is handled correctly without relying on either filename.
- HFS+ mounts are now isolated under the install work directory instead of the
  shared `/mnt/codexdmg` path. This prevents concurrent installs and stale mounts
  in separate repository clones from interfering with one another.

### Changed

- The README dependency list now matches the installer (`dmg2img` rather than
  unused `p7zip-full`) and documents the APFS-specific `apfs-fuse` requirement.
- The launcher now keeps its `npx electron` cache under the prepared payload,
  avoiding writes to `~/.npm` in desktop or managed-account environments.
- The launcher also defaults Electron's XDG configuration and cache paths to
  the prepared payload, while preserving caller-supplied XDG paths.

## Codex 26.616.31447 — build 4133, Electron 42.1.0 (2026-06-18)

### Fixed

- **App aborted on launch with `No such binding was linked: electron_common_owl_features`.**
  This Codex build reads OpenAI's custom Electron "Owl feature" binding
  (`process._linkedBinding('electron_common_owl_features')`) during main-process
  startup. Stock npm Electron — which the bridge launches the macOS payload with
  — does not ship that binding, so startup aborted at `phase=bootstrap-import-main`
  and the desktop app showed "Codex failed to start". Earlier Codex builds did
  not call this binding, so the bridge worked without it.

### Added

- `patch_owl_feature_binding()` in `scripts/codex-install-dmg.sh` (run from
  `main()` right after the payload is unpacked). It prepends a small shim to the
  app's `main` entry that answers **only** the `electron_common_owl_features`
  binding with a no-op feature set — `{ isOwlFeatureEnabled: () => false }`, i.e.
  every Owl-gated experiment reported disabled (safe baseline) — and delegates
  all other bindings to the real implementation untouched. The shim is idempotent
  (guarded by a `codex-dmg-linux-bridge owl shim` marker) and resolves the entry
  file dynamically from `package.json`, so it survives future entry-point renames.

### Notes

- The two sibling Owl bindings, `electron_browser_owl_update_policies` and
  `electron_browser_owl_profile_importer`, already guard their own absence with
  `try/catch` and need no stub.
- This is a targeted fix: it is a no-op on older Codex builds and covers future
  builds that keep using this binding. A future build that introduces a different
  un-guarded custom binding, or that changes the shape this binding must return,
  would surface a new `No such binding was linked: …` error and require extending
  the shim.
