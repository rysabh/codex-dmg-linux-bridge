# Changelog

Notable changes to the Codex DMG → Linux bridge, grouped by the Codex desktop
version they were validated against. Format follows
[Keep a Changelog](https://keepachangelog.com/).

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
