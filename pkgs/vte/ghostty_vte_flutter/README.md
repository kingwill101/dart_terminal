# ghostty_vte_flutter

[![CI](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml)
[![pub package](https://img.shields.io/pub/v/ghostty_vte_flutter.svg)](https://pub.dev/packages/ghostty_vte_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/vte/ghostty_vte_flutter/LICENSE)

Flutter terminal UI widgets powered by
[Ghostty](https://github.com/ghostty-org/ghostty)'s VT engine.
Drop-in `GhosttyTerminalView` and `GhosttyTerminalController` for embedding
a terminal in any Flutter app — on desktop, mobile, and the web.

## Features

| Widget / Class | Description |
|----------------|-------------|
| `GhosttyTerminalView` | `CustomPaint`-based terminal renderer with keyboard input |
| `GhosttyTerminalController` | `ChangeNotifier` that manages a shell subprocess (native) or remote transport (web) |
| `initializeGhosttyVteWeb()` | One-liner that loads `ghostty-vt.wasm` from Flutter assets on web |

This package re-exports all of
[`ghostty_vte`](https://pub.dev/packages/ghostty_vte), so you only need a
single import.

### Platform support

| Platform | Native shell | Web (wasm) |
|----------|:------------:|:----------:|
| Linux    | ✅           | ✅          |
| macOS    | ✅           | ✅          |
| Windows  | ✅           | ✅          |
| Android  | ✅           | ✅          |
| iOS      | —            | ✅          |

## Installation

```yaml
dependencies:
  ghostty_vte_flutter: ^0.0.1
```

No separate `ghostty_vte` dependency is needed — it's re-exported
automatically.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGhosttyVteWeb(); // no-op on native, loads wasm on web
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: TerminalPage());
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});
  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _ctrl = GhosttyTerminalController();

  @override
  void initState() {
    super.initState();
    _ctrl.start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      body: GhosttyTerminalView(controller: _ctrl, autofocus: true),
    );
  }
}
```

## Widgets & controllers

### GhosttyTerminalView

A `CustomPaint` widget that renders terminal output and routes keyboard
events through the Ghostty key encoder.

```dart
GhosttyTerminalView(
  controller: myController,
  autofocus: true,
  backgroundColor: const Color(0xFF0A0F14),
  foregroundColor: const Color(0xFFE6EDF3),
  fontSize: 14,
  lineHeight: 1.35,
  padding: const EdgeInsets.all(12),
)
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `controller` | `GhosttyTerminalController` | *required* | Terminal session to render |
| `autofocus` | `bool` | `false` | Request focus on mount |
| `focusNode` | `FocusNode?` | `null` | Custom focus node |
| `backgroundColor` | `Color` | `#0A0F14` | Canvas background |
| `foregroundColor` | `Color` | `#E6EDF3` | Text color |
| `fontSize` | `double` | `14` | Monospace font size |
| `lineHeight` | `double` | `1.35` | Line height multiplier |
| `padding` | `EdgeInsets` | `all(12)` | Content padding |

### GhosttyTerminalController

A `ChangeNotifier` managing a terminal session.

- **Native:** spawns a real shell subprocess via `script` (for PTY behavior)
  with fallback to `Process.start`.
- **Web:** same API surface — feed output through `appendDebugOutput()` and
  read input via `write()` / `sendKey()` to connect a remote backend.

```dart
final controller = GhosttyTerminalController(
  maxLines: 2000,
  defaultShell: '/bin/bash',
);

await controller.start();
controller.write('ls -la\n', sanitizePaste: true);

controller.sendKey(
  key: GhosttyKey.GHOSTTY_KEY_C,
  mods: GhosttyModsMask.ctrl,
  utf8Text: 'c',
  unshiftedCodepoint: 0x63,
);

print(controller.title);     // window title from OSC
print(controller.lines);     // buffered output lines
print(controller.isRunning); // subprocess alive?

await controller.stop();
controller.dispose();
```

| Property / Method | Description |
|-------------------|-------------|
| `start({shell, arguments})` | Start a shell subprocess |
| `stop()` | Kill the subprocess |
| `write(text, {sanitizePaste})` | Write text to stdin |
| `writeBytes(bytes)` | Write raw bytes to stdin |
| `sendKey(...)` | Encode and send a key event |
| `clear()` | Clear the output buffer |
| `title` | Current terminal title (from OSC 0/2) |
| `lines` | Buffered output lines |
| `isRunning` | Whether the subprocess is active |

## Web setup

1. **Build the wasm module:**

   ```bash
   cd pkgs/vte/ghostty_vte
   dart run tool/build_wasm.dart
   ```

   This produces `ghostty-vt.wasm` in the Flutter assets directory.

2. **Initialise before `runApp`:**

   ```dart
   await initializeGhosttyVteWeb();
   ```

   This is a no-op on native platforms.

3. **Build for web:**

   ```bash
   flutter build web --wasm
   ```

## Native setup

No manual steps needed. The `ghostty_vte` build hook runs automatically
during `flutter run` and `flutter build`, producing the correct native
library for your target. Just make sure **Zig** and the **Ghostty source**
are available — see the
[`ghostty_vte` README](https://pub.dev/packages/ghostty_vte) for details.

Or download [prebuilt libraries](https://github.com/kingwill101/dart_terminal/releases)
to skip the Zig requirement entirely.

## Related packages

| Package | Description |
|---------|-------------|
| [`ghostty_vte`](https://pub.dev/packages/ghostty_vte) | Core Dart FFI bindings (re-exported by this package) |
| [`portable_pty`](https://pub.dev/packages/portable_pty) | Cross-platform PTY subprocess control |
| [`portable_pty_flutter`](https://pub.dev/packages/portable_pty_flutter) | Flutter controller for PTY sessions |

## License

MIT — see [LICENSE](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/vte/ghostty_vte_flutter/LICENSE).
