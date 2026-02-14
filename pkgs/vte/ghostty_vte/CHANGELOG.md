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
