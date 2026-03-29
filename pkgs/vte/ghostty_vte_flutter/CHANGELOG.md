## 0.1.1-dev.1

- Bumped the `ghostty_vte` dependency to `^0.1.1-dev.1` to expose the latest
  Ghostty VT binding sync, paste helpers, build metadata, and terminal color
  APIs through the Flutter package re-exports.

## 0.1.0+1

- Added external transport hooks on `GhosttyTerminalController` so Flutter apps
  can attach SSH or other remote backends while still using the built-in VT
  parser and renderer.
- Fixed control-key chord handling to send ASCII control bytes for common
  `Ctrl+` shortcuts, including copy-free terminal interactions like `Ctrl+C`.
- Improved snapshot parsing and web/native parity for cursor state, escape
  sequence handling, mouse modes, and formatter metadata.
- Updated the README quick start to a runnable minimal app and bumped the
  `ghostty_vte` dependency to `^0.1.0+2`.

## 0.1.0

- **BREAKING**: Removed regex-based OSC title tracking (`_consumeOscText`,
  `_consumeOscPayload`). Title is now driven by native `onTitleChanged`
  callback.
- **BREAKING**: `resize()` now requires `cellWidthPx` and `cellHeightPx`.
- 7 public callback properties on the controller: `onBell`,
  `onTitleChanged`, `onSize`, `onColorScheme`, `onDeviceAttributes`,
  `onEnquiry`, `onXtversion` (writePty handled internally).
- Controller data getters: `title`, `pwd`, `mouseTracking`, `totalRows`,
  `scrollbackRows`, `widthPx`, `heightPx`.
- New `TerminalRenderModel` abstraction (211 lines).
- Expanded example app with all 8 effect callbacks and live state display.
- Bumped `ghostty_vte` dependency to `^0.1.0`.

## 0.0.3+1

- Bumped `ghostty_vte` dependency to `^0.0.3` for auto-download support.

## 0.0.1+1

- Bumped package version to `0.0.1+1`.

## 0.0.1

- Initial release.
- `GhosttyTerminalView` — CustomPaint-based terminal renderer.
- `GhosttyTerminalController` — ChangeNotifier for shell sessions.
- `initializeGhosttyVteWeb()` — one-liner wasm loader for Flutter web.
- Re-exports all `ghostty_vte` APIs.
