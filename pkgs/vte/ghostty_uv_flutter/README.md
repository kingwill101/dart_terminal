# ghostty_uv_flutter

`ghostty_uv_flutter` is an experimental native-first Flutter terminal package.
It combines:

- the shared `ghostty_vte_flutter` PTY session layer
- `ghostty_vte` for terminal-grade key encoding
- `ultraviolet` for cell-buffer storage and canvas rendering

The package exists as a separate prototype so the UV-backed renderer can evolve
independently before any of it is folded into `ghostty_vte_flutter`.

## What It Includes

- `GhosttyUvTerminalController`
- `GhosttyUvTerminalView`
- `GhosttyUvPtySession`
- `GhosttyUvTerminalScreen`
- `GhosttyUvKeyBridge`
- `GhosttyUvTerminalSelection`

The controller now stores the active launch metadata from shared shell presets
or explicit launch plans through `activeShellLaunch`, `startLaunch(...)`, and
`restartLaunch(...)`.

## Current Feature Set

- Native desktop PTY sessions through the shared core PTY layer
- UV cell-buffer rendering on a custom canvas
- Resize-aware terminal grid sizing
- Ghostty key encoding for arrows, backspace, function keys, and modifiers
- Basic VT parsing for text, cursor movement, colors, alt screen, insert and
  delete sequences, and OSC 8 hyperlinks
- Scrollback in the screen model with mouse-wheel and `Shift+PageUp/PageDown`
  navigation in the widget
- Drag selection with edge auto-scroll and copy shortcut support
- Bracketed paste support when the shell enables DECSET `?2004`
- Double-tap word selection with configurable word-boundary rules
- Long-press line selection
- Selection change callbacks, including extracted selection text, for host-side
  integrations
- Configurable copy semantics for trailing spaces, wrapped-line joins, and
  wrapped-line join separators
- Standard terminal shortcuts for select-all and escape-to-clear-selection
- Hyperlink hit-testing with callback hooks

## Rough Edges

- The screen parser is still lightweight. It is good enough for real shell
  editing and common redraw traffic, but it is not a full Ghostty screen model.
- Web is intentionally out of scope for this first package.
- The package exposes hyperlink callbacks, but it does not force a launcher
  dependency or open URLs automatically.
- Wrapped-line copy joins depend on the package's internal wrap tracking. That
  works for the VT traffic covered by the current parser, but it is not yet a
  full terminal-emulator reflow model.
- Word selection uses a terminal-oriented token classifier, not shell-aware
  parsing. It handles common identifiers and URLs well, but it is still more
  limited than shell-aware tokenization.
- Line selection currently maps to full transcript rows, not visual wrapped
  sub-lines.

## Example

Run the example app:

```sh
cd pkgs/vte/ghostty_uv_flutter/example
flutter run -d linux
```

The example Session panel shows the resolved launch command, effective
environment, and exposes `Copy Environment`.
