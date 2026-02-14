# ghostty_vte_flutter

Flutter widget package for building terminal UIs on top of
[`ghostty_vte`](../ghostty_vte/). Provides a painter-based terminal view,
a controller that manages a subprocess (native) or remote transport (web),
and a one-liner web initializer for the wasm module.

---

## Table of contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Widgets & controllers](#widgets--controllers)
  - [GhosttyTerminalView](#ghosttyterminalview)
  - [GhosttyTerminalController](#ghosttyterminalcontroller)
  - [GhosttyTerminalWidget (legacy)](#ghosttyterminalwidget-legacy)
- [Web setup](#web-setup)
- [Native setup](#native-setup)
- [Full example](#full-example)
- [Commands](#commands)
- [Troubleshooting](#troubleshooting)

---

## Features

| Widget / Class | Description |
|---------------|-------------|
| `GhosttyTerminalView` | `CustomPaint`-based terminal rendering widget with keyboard input handling |
| `GhosttyTerminalController` | `ChangeNotifier` that manages a shell subprocess (native) or placeholder transport (web), buffers output, strips ANSI sequences, and encodes keyboard events via Ghostty |
| `initializeGhosttyVteWeb()` | One-liner that loads `ghostty-vt.wasm` from Flutter assets on web |
| `GhosttyTerminalWidget` | Simple legacy widget for quick paste-safety demos |

---

## Prerequisites

- **Flutter SDK**
- **Zig** on your `PATH` (for native `libghostty-vt` builds via the `ghostty_vte` build hook)
- Ghostty source available (see the [`ghostty_vte` README](../ghostty_vte/README.md#ghostty-source-location))
- The wasm asset built for web targets (see [Web setup](#web-setup))

---

## Installation

This package is part of the `dart_terminal` workspace. From the workspace root:

```bash
dart pub get
```

To depend on it in your own Flutter project:

```yaml
dependencies:
  ghostty_vte_flutter:
    path: /path/to/workspace/pkgs/vte/ghostty_vte_flutter
  ghostty_vte:
    path: /path/to/workspace/pkgs/vte/ghostty_vte
```

---

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGhosttyVteWeb();  // no-op on native, loads wasm on web
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: TerminalPage());
  }
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
    _ctrl.start(); // spawns shell on native, placeholder on web
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
      body: GhosttyTerminalView(
        controller: _ctrl,
        autofocus: true,
      ),
    );
  }
}
```

---

## Widgets & controllers

### GhosttyTerminalView

A `CustomPaint` widget that renders terminal output and routes keyboard events
through the Ghostty key encoder.

```dart
GhosttyTerminalView(
  controller: myController,
  autofocus: true,
  backgroundColor: const Color(0xFF0A0F14),
  foregroundColor: const Color(0xFFE6EDF3),
  chromeColor: const Color(0xFF121A24),   // title bar color
  fontSize: 14,
  lineHeight: 1.35,
  padding: const EdgeInsets.all(12),
)
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `controller` | `GhosttyTerminalController` | _required_ | The terminal session to render |
| `autofocus` | `bool` | `false` | Whether to request focus on mount |
| `focusNode` | `FocusNode?` | `null` | Custom focus node |
| `backgroundColor` | `Color` | `#0A0F14` | Canvas background |
| `foregroundColor` | `Color` | `#E6EDF3` | Text color |
| `chromeColor` | `Color` | `#121A24` | Title bar background |
| `fontSize` | `double` | `14` | Monospace font size |
| `lineHeight` | `double` | `1.35` | Line height multiplier |
| `padding` | `EdgeInsets` | `all(12)` | Content padding |

### GhosttyTerminalController

A `ChangeNotifier` that manages a terminal session.

**On native (Linux, macOS, Windows):** spawns a real shell subprocess via `script`
(for PTY behavior) with fallback to `Process.start`.

**On web:** provides the same API surface but does not spawn local processes.
Connect a remote backend (WebSocket / SSH proxy) by feeding output through
`appendDebugOutput()` and reading input sent via `write()` / `sendKey()`.

```dart
final controller = GhosttyTerminalController(
  maxLines: 2000,      // max buffered lines
  preferPty: true,     // try PTY-like spawn via 'script' on Unix
  defaultShell: null,  // defaults to $SHELL or /bin/bash
);

// Start a shell
await controller.start();

// Write text to stdin (with optional paste safety check)
controller.write('ls -la\n', sanitizePaste: true);

// Send an encoded key event
controller.sendKey(
  key: GhosttyKey.GHOSTTY_KEY_C,
  mods: GhosttyModsMask.ctrl,
  utf8Text: 'c',
  unshiftedCodepoint: 0x63,
);

// Read state
print(controller.title);     // window title from OSC
print(controller.lines);     // buffered output lines
print(controller.isRunning); // subprocess alive?

// Stop and clean up
await controller.stop();
controller.dispose();
```

| Property / Method | Description |
|-------------------|-------------|
| `start({shell, arguments})` | Start a shell subprocess |
| `stop()` | Kill the subprocess |
| `write(text, {sanitizePaste})` | Write text to stdin |
| `writeBytes(bytes)` | Write raw bytes to stdin |
| `sendKey(...)` | Encode and send a key event via Ghostty key encoder |
| `clear()` | Clear the output buffer |
| `appendDebugOutput(text)` | Inject text (for testing or web remote feeds) |
| `title` | Current terminal title (from OSC 0/2) |
| `lines` | Buffered output lines |
| `isRunning` | Whether the subprocess is active |
| `revision` | Monotonic counter, increments on every change |

### GhosttyTerminalWidget (legacy)

A simple demo widget. Prefer `GhosttyTerminalView` + `GhosttyTerminalController`
for real use.

```dart
GhosttyTerminalWidget(
  sampleInput: 'echo hello',
  isPasteSafe: GhosttyVt.isPasteSafe,  // optional override
)
```

---

## Web setup

1. **Build the wasm module** from the workspace root:

   ```bash
   task wasm
   ```

   This produces `pkgs/vte/ghostty_vte_flutter/assets/ghostty-vt.wasm`.

2. **Initialize before `runApp`:**

   ```dart
   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await initializeGhosttyVteWeb();
     runApp(const MyApp());
   }
   ```

   `initializeGhosttyVteWeb()` is a no-op on native platforms.

3. **Build for web:**

   ```bash
   flutter build web --wasm
   ```

The wasm file is declared in this package's `pubspec.yaml` under `flutter.assets`
and is automatically included in web builds.

---

## Native setup

No manual build steps are needed. The `ghostty_vte` build hook runs
automatically during `flutter run`, `flutter build`, and `flutter test`,
producing the correct native dynamic library for your target platform.

Just make sure Zig and the Ghostty source are available (see
[ghostty_vte README](../ghostty_vte/README.md#ghostty-source-location)).

---

## Full example

See the [example/](example/) directory for a complete Flutter app (the "Ghostty
VT Studio") that demonstrates:

- **PTY terminal** — live shell interaction with `GhosttyTerminalView`
- **OSC parser workbench** — parse OSC payloads and inspect results
- **SGR parser workbench** — parse SGR params and see parsed attributes
- **Key encoder workbench** — configure key events + encoder options and inspect
  encoded byte sequences

Run it:

```bash
# Native (Linux)
cd pkgs/vte/ghostty_vte_flutter/example
flutter run

# Web
cd /path/to/workspace/root
task wasm
cd pkgs/vte/ghostty_vte_flutter/example
flutter run -d chrome
```

---

## Commands

```bash
flutter test       # Run tests
flutter analyze    # Static analysis
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Wasm missing at runtime | Run `task wasm` from the workspace root and confirm `assets/ghostty-vt.wasm` exists. |
| Native build fails | Ensure Zig is installed and the Ghostty source is available. See the `ghostty_vte` troubleshooting guide. |
| `initializeGhosttyVteWeb` hangs | Check the browser console for wasm fetch errors. Ensure the asset path is correct. |
| Controller doesn't produce output (web) | On web, `GhosttyTerminalController` is a placeholder. Connect a remote backend via `appendDebugOutput()`. |
