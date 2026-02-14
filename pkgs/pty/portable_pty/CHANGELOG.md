## 0.0.2

- Added `dart run portable_pty:setup` command to download prebuilt native
  libraries for downstream consumers.
- Build hook now finds prebuilt libraries at the consuming project's
  `.prebuilt/<platform>/` directory, eliminating the need to modify the
  pub cache.
- Build hook search order: env var, monorepo `.prebuilt/`, project `.prebuilt/`.

## 0.0.1+1

- Bumped package version to `0.0.1+1`.

## 0.0.1

- Initial release.
- Cross-platform PTY via Rust FFI (Linux, macOS, Windows).
- `PortablePty` — open, spawn, read/write, resize, close.
- `PortablePtyController` — buffered output with listener support.
- `PortablePtyTransport` — pluggable web transport interface.
- Built-in WebSocket and WebTransport backends for web targets.
- Prebuilt library support — skip Rust with downloaded binaries.
