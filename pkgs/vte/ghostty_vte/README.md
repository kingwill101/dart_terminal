# ghostty_vte

Dart FFI package for [Ghostty](https://github.com/ghostty-org/ghostty)'s
virtual terminal library (`libghostty-vt`). Provides paste-safety checking,
OSC parsing, SGR attribute parsing, and full keyboard event encoding — on
native platforms **and** on the web via WebAssembly.

---

## Table of contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Ghostty source location](#ghostty-source-location)
- [How the build works](#how-the-build-works)
- [API guide](#api-guide)
  - [Paste safety](#paste-safety)
  - [OSC parser](#osc-parser)
  - [SGR parser](#sgr-parser)
  - [Key events & encoding](#key-events--encoding)
- [Web usage (wasm)](#web-usage-wasm)
- [Regenerate bindings](#regenerate-bindings)
- [Tasks reference](#tasks-reference)
- [Troubleshooting](#troubleshooting)

---

## Features

| Feature | Class / API | Description |
|---------|-------------|-------------|
| Paste safety | `GhosttyVt.isPasteSafe()` | Detects dangerous control sequences in pasted text |
| OSC parsing | `VtOscParser` | Streaming parser for Operating System Command sequences |
| SGR parsing | `VtSgrParser` | Parses Select Graphic Rendition attributes (colors, bold, underline, etc.) |
| Key encoding | `VtKeyEvent` + `VtKeyEncoder` | Encodes keyboard events to terminal byte sequences (legacy, xterm, Kitty protocol) |
| Web support | `GhosttyVtWasm` | Loads the wasm build of libghostty-vt for use in browsers |

---

## Prerequisites

- **Dart SDK ≥ 3.10**
- **Zig** on your `PATH`
- Ghostty source available (see below)

---

## Installation

This package is part of the `dart_terminal` workspace. From the workspace root:

```bash
dart pub get
```

To depend on it in your own project:

```yaml
dependencies:
  ghostty_vte:
    path: /path/to/workspace/pkgs/vte/ghostty_vte
    # or from pub.dev once published:
    # ghostty_vte: ^0.0.1
```

---

## Ghostty source location

The build hook resolves the Ghostty source in this order:

1. **`GHOSTTY_SRC` environment variable** — set this to any directory
   containing `build.zig` and `include/ghostty/vt.h`.
2. **`third_party/ghostty`** — a git submodule or symlink inside this package.
3. **Ancestor directory walk** — walks up from the package root looking for the
   same marker files.

### Set up the submodule

```bash
cd pkgs/vte/ghostty_vte
git submodule add https://github.com/ghostty-org/ghostty third_party/ghostty
git submodule update --init --recursive
```

### Or use auto-fetch

```bash
export GHOSTTY_SRC_AUTO_FETCH=1
# Optional:
export GHOSTTY_SRC_URL=https://github.com/ghostty-org/ghostty
export GHOSTTY_SRC_REF=main
```

The build hook will `git clone` into `third_party/ghostty` automatically.

---

## How the build works

The native asset build hook at `hook/build.dart`:

1. Resolves the Ghostty source root (see above).
2. Runs `zig build lib-vt` targeting your host OS/architecture.
3. Copies the resulting dynamic library (`.so`, `.dylib`, `.dll`) to the output
   directory.
4. Registers it as a Dart **code asset** via `DynamicLoadingBundled()`.

This happens automatically whenever you run `dart run`, `dart test`,
`flutter run`, or `flutter build`. No manual native build step needed.

### Supported native targets

| OS | Architectures |
|----|--------------|
| Linux | x64, arm64, arm, ia32 |
| macOS | arm64, x64 |
| Windows | x64, arm64, ia32 |
| Android | arm64, arm, x64, ia32 |

---

## API guide

### Paste safety

Check whether text is safe to paste into a terminal (no dangerous control
sequences like bracketed paste escapes or embedded newlines):

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

void main() {
  print(GhosttyVt.isPasteSafe('echo hello'));         // true
  print(GhosttyVt.isPasteSafe('echo hello\nworld'));  // false — newline
  print(GhosttyVt.isPasteSafe('safe text'));           // true

  // Raw bytes variant:
  final bytes = utf8.encode('echo hello');
  print(GhosttyVt.isPasteSafeBytes(bytes));            // true
}
```

### OSC parser

Parse [Operating System Command](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC)
sequences (e.g., window title changes):

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

void main() {
  final parser = GhosttyVt.newOscParser();

  // Feed an OSC payload: "0;My Terminal Title"
  parser.addText('0;My Terminal Title');

  // End with BEL terminator (0x07)
  final command = parser.end(terminator: 0x07);

  print(command.type);         // GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE
  print(command.windowTitle);  // "My Terminal Title"

  parser.close();
}
```

You can also feed bytes incrementally with `addByte()` / `addBytes()` for
streaming use cases.

### SGR parser

Parse [SGR (Select Graphic Rendition)](https://en.wikipedia.org/wiki/ANSI_escape_code#SGR)
parameters into structured attributes:

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

void main() {
  final parser = GhosttyVt.newSgrParser();

  // Parse "ESC[1;31;4m" parameters: bold, red foreground, underline
  final attrs = parser.parseParams([1, 31, 4]);
  for (final attr in attrs) {
    print('${attr.tag}');
    if (attr.paletteIndex != null) print('  palette: ${attr.paletteIndex}');
    if (attr.underline != null) print('  underline: ${attr.underline}');
  }
  // Output:
  //   GHOSTTY_SGR_ATTR_BOLD
  //   GHOSTTY_SGR_ATTR_FG_8
  //     palette: 1
  //   GHOSTTY_SGR_ATTR_UNDERLINE
  //     underline: GHOSTTY_SGR_UNDERLINE_SINGLE

  // 24-bit true color: "ESC[38;2;255;128;0m" (orange foreground)
  final trueColor = parser.parseParams([38, 2, 255, 128, 0]);
  final fg = trueColor.first;
  print('${fg.tag} rgb: ${fg.rgb}');
  // GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG rgb: VtRgbColor(r: 255, g: 128, b: 0)

  parser.close();
}
```

### Key events & encoding

Build key events and encode them to the byte sequences a terminal expects:

```dart
import 'package:ghostty_vte/ghostty_vte.dart';

void main() {
  final encoder = GhosttyVt.newKeyEncoder();
  final event = GhosttyVt.newKeyEvent();

  // Encode Ctrl+C
  event
    ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
    ..key = GhosttyKey.GHOSTTY_KEY_C
    ..mods = GhosttyModsMask.ctrl
    ..utf8Text = 'c'
    ..unshiftedCodepoint = 0x63;

  final bytes = encoder.encode(event);
  print(bytes);  // [3] — ETX (Ctrl+C)

  // Encode arrow up
  event
    ..key = GhosttyKey.GHOSTTY_KEY_ARROW_UP
    ..mods = 0
    ..utf8Text = '';
  final arrowBytes = encoder.encode(event);
  print(arrowBytes);  // [27, 91, 65] — ESC [ A

  // Configure encoder options
  encoder
    ..cursorKeyApplication = true  // DEC mode 1
    ..kittyFlags = GhosttyKittyFlags.all;

  // Re-encode with Kitty protocol
  event
    ..key = GhosttyKey.GHOSTTY_KEY_ENTER
    ..utf8Text = '\n'
    ..unshiftedCodepoint = 0x0D;
  final kittyBytes = encoder.encode(event);
  print(String.fromCharCodes(kittyBytes));

  event.close();
  encoder.close();
}
```

**Encoder options:**

| Option | Property | Description |
|--------|----------|-------------|
| Cursor key application | `cursorKeyApplication` | DEC mode 1 — arrows emit `ESC O` instead of `ESC [` |
| Keypad application | `keypadKeyApplication` | DEC mode 66 |
| Alt ESC prefix | `altEscPrefix` | Alt key sends `ESC` prefix before the key |
| modifyOtherKeys | `modifyOtherKeysState2` | xterm modifyOtherKeys mode 2 |
| Kitty protocol | `kittyFlags` | Bit flags from `GhosttyKittyFlags` |

---

## Web usage (wasm)

On web, the same APIs work but you must first load the wasm module via
`GhosttyVtWasm.initializeFromBytes(wasmBytes)`. **How** you obtain those bytes
depends on whether you're using Flutter or plain Dart web.

### Flutter web

The companion package **`ghostty_vte_flutter`** handles everything:

```dart
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
await initializeGhosttyVteWeb(); // fetches ghostty-vt.wasm from Flutter assets
```

See the [`ghostty_vte_flutter` README](../ghostty_vte_flutter/README.md) for
full instructions.

### Dart web (without Flutter)

Without Flutter's asset system you must **build, host, and fetch** the wasm
module yourself.

**Step 1 — Build the wasm file:**

```bash
# Default output goes to the Flutter assets dir.
# Pass an explicit path to place it wherever you need:
cd pkgs/vte/ghostty_vte
dart run tool/build_wasm.dart web/ghostty-vt.wasm
```

Or use the workspace task (outputs to the Flutter assets folder by default):

```bash
task wasm
```

**Step 2 — Serve the `.wasm` file** alongside your compiled Dart web app (for
example, place it in your `web/` directory).

**Step 3 — Fetch and initialize at startup:**

```dart
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:ghostty_vte/ghostty_vte.dart';

Future<void> main() async {
  // Fetch the wasm module you built and deployed
  final response = await web.window.fetch('ghostty-vt.wasm'.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  final wasmBytes = buffer.toDart.asUint8List();

  // Initialize once before any API call
  await GhosttyVtWasm.initializeFromBytes(wasmBytes);

  // All GhosttyVt APIs now work
  print(GhosttyVt.isPasteSafe('hello'));
}
```

> **Note:** You can load the bytes any way you like (`package:http`,
> `HttpRequest`, a bundler, etc.) — the only requirement is that you pass a
> `Uint8List` of the wasm binary to `initializeFromBytes` before calling any
> `GhosttyVt` API.

---

## Regenerate bindings

When the Ghostty C headers (`include/ghostty/vt.h`) change:

```bash
# From the package root:
dart run tool/ffigen.dart

# Or from the workspace root:
task ffigen
```

This regenerates `lib/ghostty_vte_bindings_generated.dart`.

---

## Tasks reference

Run from the **package** root (`pkgs/vte/ghostty_vte`):

```bash
task ffigen               # Regenerate FFI bindings
task wasm                 # Build wasm module → flutter package assets
task analyze              # Static analysis
task test                 # Run tests (triggers native build)
task example:analyze      # Analyze example app
task example:run          # Run the example CLI app
task submodule:init       # Add + init Ghostty submodule
```

---

## Source layout

```
hook/
  build.dart                          # Native asset build hook
tool/
  ffigen.dart                         # Binding generator script
  build_wasm.dart                     # Wasm build script
lib/
  ghostty_vte.dart                    # Package entry point (conditional export)
  ghostty_vte_bindings_generated.dart # Generated FFI bindings (native)
  src/
    api_native.dart                   # Native exports (FFI + high-level)
    api_web.dart                      # Web exports (wasm runtime)
    high_level.dart                   # GhosttyVt, VtOscParser, VtSgrParser, etc.
    web_api.dart                      # Full wasm implementation
    wasm_support_stub.dart            # Stub for conditional import
third_party/
  ghostty                            # Ghostty source (submodule/symlink)
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Unable to locate Ghostty source root` | Set `GHOSTTY_SRC`, init the submodule, or enable `GHOSTTY_SRC_AUTO_FETCH=1`. |
| `zig: command not found` | Install Zig and ensure it is on your `PATH`. |
| `Static linking is not implemented` | Only dynamic loading is supported. Check your build mode preference. |
| Wasm not found at runtime | Run `task wasm` and verify the `.wasm` file exists. |
| Bindings don't match C headers | Run `task ffigen` to regenerate. |
