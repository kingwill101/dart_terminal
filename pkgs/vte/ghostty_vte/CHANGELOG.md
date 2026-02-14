## 0.0.1

- Initial release.
- Dart FFI bindings for Ghostty's libghostty-vt.
- Paste-safety checking via `GhosttyVt.isPasteSafe()`.
- OSC (Operating System Command) streaming parser.
- SGR (Select Graphic Rendition) attribute parser.
- Keyboard event encoding (legacy, xterm, Kitty protocol).
- Web support via WebAssembly.
- Prebuilt library support — skip Zig with downloaded binaries.
