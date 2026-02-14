# ghostty_vte

[![CI](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml)
[![pub package](https://img.shields.io/pub/v/ghostty_vte.svg)](https://pub.dev/packages/ghostty_vte)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/vte/ghostty_vte/LICENSE)

Dart FFI bindings for [Ghostty](https://github.com/ghostty-org/ghostty)'s
virtual-terminal engine (`libghostty-vt`). Works on **native platforms** and
on the **web** via WebAssembly.

## Features

| Feature | API | Description |
|---------|-----|-------------|
| **Paste safety** | `GhosttyVt.isPasteSafe()` | Detect dangerous control sequences in pasted text |
| **OSC parsing** | `VtOscParser` | Streaming parser for Operating System Command sequences |
| **SGR parsing** | `VtSgrParser` | Parse Select Graphic Rendition attributes (colors, bold, etc.) |
| **Key encoding** | `VtKeyEvent` / `VtKeyEncoder` | Encode keyboard events to terminal byte sequences |
| **Web support** | `GhosttyVtWasm` | Load `libghostty-vt` compiled to WebAssembly |

### Platform support

| Platform | Architectures | Build toolchain |
|----------|---------------|-----------------|
| Linux | x64, arm64 | Zig (or [prebuilt](#prebuilt-libraries)) |
| macOS | x64, arm64 | Zig (or prebuilt) |
| Windows | x64, arm64 | Zig (or prebuilt) |
| Android | arm64, arm, x64 | Zig (or prebuilt) |
| Web | wasm32 | Zig (or prebuilt) |

## Installation

```yaml
dependencies:
  ghostty_vte: ^0.0.2
```

The native library is compiled automatically by a
[Dart build hook](https://dart.dev/interop/c-interop#native-assets)
the first time you run `dart run`, `dart test`, `flutter run`, or
`flutter build`. You need **Zig ≥ 0.15** on your `PATH` and access to the
Ghostty source (see [Ghostty source](#ghostty-source) below).

> **Tip:** If you don't want to install Zig, download a
> [prebuilt library](#prebuilt-libraries) instead.

## Quick start

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

void main() {
  // Paste safety
  print(GhosttyVt.isPasteSafe('echo hello'));         // true
  print(GhosttyVt.isPasteSafe('echo hello\nworld'));  // false

  // OSC parsing
  final osc = GhosttyVt.newOscParser();
  osc.addText('0;My Terminal Title');
  final cmd = osc.end(terminator: 0x07);
  print(cmd.windowTitle);  // "My Terminal Title"
  osc.close();

  // SGR parsing
  final sgr = GhosttyVt.newSgrParser();
  final attrs = sgr.parseParams([1, 31, 4]);  // bold + red fg + underline
  for (final a in attrs) {
    print(a.tag);
  }
  sgr.close();

  // Key encoding
  final encoder = GhosttyVt.newKeyEncoder();
  final event = GhosttyVt.newKeyEvent()
    ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
    ..key = GhosttyKey.GHOSTTY_KEY_C
    ..mods = GhosttyModsMask.ctrl
    ..utf8Text = 'c'
    ..unshiftedCodepoint = 0x63;
  final bytes = encoder.encode(event);
  print(bytes);  // [3] — ETX (Ctrl+C)
  event.close();
  encoder.close();
}
```

## Ghostty source

The build hook looks for Ghostty source code in this order:

1. **`$GHOSTTY_SRC`** environment variable pointing to a directory with
   `build.zig` and `include/ghostty/vt.h`.
2. **`third_party/ghostty/`** git submodule inside the package.
3. **Auto-fetch** — set `GHOSTTY_SRC_AUTO_FETCH=1` and the build hook will
   `git clone` Ghostty automatically.

```bash
# Option A: submodule
git submodule add https://github.com/ghostty-org/ghostty third_party/ghostty

# Option B: environment variable
export GHOSTTY_SRC=/path/to/ghostty

# Option C: auto-fetch
export GHOSTTY_SRC_AUTO_FETCH=1
```

## Prebuilt libraries

Prebuilt binaries for every platform are attached to each
[GitHub release](https://github.com/kingwill101/dart_terminal/releases).

The easiest way to get them is the built-in setup command:

```bash
dart run ghostty_vte:setup
```

This downloads the correct library for your host platform into
`.prebuilt/<platform>/` at your project root. The build hook will find it
automatically — **no Zig install required**.

You can also specify a release tag or target platform:

```bash
dart run ghostty_vte:setup --tag v0.0.2 --platform macos-arm64
```

**Monorepo users** can download all prebuilt libs at once:

```bash
dart run tool/prebuilt.dart --tag v0.0.2
```

You can also set the `GHOSTTY_VTE_PREBUILT` environment variable to point
directly at a prebuilt `libghostty-vt.so` / `.dylib` / `.dll` file.

> **Tip:** Add `.prebuilt/` to your `.gitignore`.

## Web usage

On web, the same API surface works after loading the wasm module:

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

Future<void> main() async {
  // Fetch and initialise the wasm module
  final response = await window.fetch('ghostty-vt.wasm'.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  await GhosttyVtWasm.initializeFromBytes(buffer.toDart.asUint8List());

  // All APIs now work
  print(GhosttyVt.isPasteSafe('hello'));
}
```

> **Flutter web?** Use the companion package
> [`ghostty_vte_flutter`](https://pub.dev/packages/ghostty_vte_flutter) which
> handles wasm loading from Flutter assets automatically.

## API overview

### Paste safety

```dart
GhosttyVt.isPasteSafe('echo hello');       // true
GhosttyVt.isPasteSafeBytes(utf8Bytes);     // true
```

### OSC parser

```dart
final parser = GhosttyVt.newOscParser();
parser.addText('0;Window Title');
final cmd = parser.end(terminator: 0x07);
print(cmd.windowTitle);
parser.close();
```

### SGR parser

```dart
final parser = GhosttyVt.newSgrParser();
final attrs = parser.parseParams([38, 2, 255, 128, 0]);  // orange fg
print(attrs.first.rgb);  // VtRgbColor(r: 255, g: 128, b: 0)
parser.close();
```

### Key encoder

```dart
final encoder = GhosttyVt.newKeyEncoder();
final event = GhosttyVt.newKeyEvent();

event
  ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
  ..key = GhosttyKey.GHOSTTY_KEY_ARROW_UP
  ..mods = 0
  ..utf8Text = '';

print(encoder.encode(event));  // [27, 91, 65] — ESC [ A

// Encoder options
encoder
  ..cursorKeyApplication = true   // DEC mode 1
  ..keypadKeyApplication = true   // DEC mode 66
  ..altEscPrefix = true           // Alt sends ESC prefix
  ..kittyFlags = GhosttyKittyFlags.all;

event.close();
encoder.close();
```

| Option | Property | Description |
|--------|----------|-------------|
| Cursor key application | `cursorKeyApplication` | DEC mode 1 — arrows emit `ESC O` instead of `ESC [` |
| Keypad application | `keypadKeyApplication` | DEC mode 66 |
| Alt ESC prefix | `altEscPrefix` | Alt key sends `ESC` prefix |
| modifyOtherKeys | `modifyOtherKeysState2` | xterm modifyOtherKeys mode 2 |
| Kitty protocol | `kittyFlags` | Bit flags from `GhosttyKittyFlags` |

## Related packages

| Package | Description |
|---------|-------------|
| [`ghostty_vte_flutter`](https://pub.dev/packages/ghostty_vte_flutter) | Flutter terminal widgets + wasm initialiser |
| [`portable_pty`](https://pub.dev/packages/portable_pty) | Cross-platform PTY subprocess control |
| [`portable_pty_flutter`](https://pub.dev/packages/portable_pty_flutter) | Flutter controller for PTY sessions |

## License

MIT — see [LICENSE](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/vte/ghostty_vte/LICENSE).
