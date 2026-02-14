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
