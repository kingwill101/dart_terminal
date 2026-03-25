## 0.1.0+1

- Fixed Linux/macOS/Windows prebuilt artifact selection to only package the
  real dynamic library, not the similarly named static archive.
- Added dynamic-library header validation in the build hook and setup tooling
  so broken release artifacts fail fast instead of surfacing as runtime FFI
  load errors.
- `dart run ghostty_vte:setup` now clears stale `hooks_runner` cache entries so
  the next app build picks up the extracted prebuilt library.
- Updated `ghostty_vte:setup` to default to the `v0.1.0+1` release artifacts.

## 0.1.0

- **BREAKING**: `resize()` now requires `cellWidthPx` and `cellHeightPx`
  parameters (matching ghostty's updated 5-arg `ghostty_terminal_resize`).
- Updated ghostty submodule from `efb352359` to `bebca8466` (162 upstream
  commits) with major API expansion.
- Regenerated FFI bindings (4747 → 5484 lines).
- All 8 terminal effect callbacks via `NativeCallable.isolateLocal`:
  `onBell`, `onWritePty`, `onTitleChanged`, `onSize`, `onColorScheme`,
  `onDeviceAttributes`, `onEnquiry`, `onXtversion`.
- Terminal data getters: `title`, `pwd`, `mouseTracking`, `totalRows`,
  `scrollbackRows`, `widthPx`, `heightPx`.
- New types: `VtDeviceAttributes`, `VtColorScheme`, `VtSizeReportSize`.
- Updated zig build step from `lib-vt` to `-Demit-lib-vt=true`.

## 0.0.3+1

- Auto-download prebuilt native libraries from GitHub Releases during
  the build hook — no more manual `dart run ghostty_vte:setup` required.
- Build hook resolution order: env var → local `.prebuilt/` → auto-download
  (cached in `outputDirectoryShared`) → build from source.
- SHA256 hash verification of downloaded artifacts.
- Fixed `_findPrebuiltInProjectRoots()` to also match directories with
  `pubspec.yaml` + `pkgs/` (monorepo/workspace roots).
- Updated setup script default tag to `v0.0.3`.

## 0.0.2

- Added `dart run ghostty_vte:setup` command to download prebuilt native
  libraries for downstream consumers.
- Build hook now finds prebuilt libraries at the consuming project's
  `.prebuilt/<platform>/` directory, eliminating the need to modify the
  pub cache.
- Build hook search order: env var, monorepo `.prebuilt/`, project `.prebuilt/`.

## 0.0.1+1

- Bumped package version to `0.0.1+1`.

## 0.0.1

- Initial release.
- Dart FFI bindings for Ghostty's libghostty-vt.
- Paste-safety checking via `GhosttyVt.isPasteSafe()`.
- OSC (Operating System Command) streaming parser.
- SGR (Select Graphic Rendition) attribute parser.
- Keyboard event encoding (legacy, xterm, Kitty protocol).
- Web support via WebAssembly.
- Prebuilt library support — skip Zig with downloaded binaries.
