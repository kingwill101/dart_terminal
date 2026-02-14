# portable_pty_flutter

[![CI](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml)
[![pub package](https://img.shields.io/pub/v/portable_pty_flutter.svg)](https://pub.dev/packages/portable_pty_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/pty/portable_pty_flutter/LICENSE)

Flutter controller for [`portable_pty`](https://pub.dev/packages/portable_pty)
sessions. Wraps the PTY behind a `ChangeNotifier` so terminal state
integrates seamlessly with Flutter's widget tree.

## Features

- **`FlutterPtyController`** — `ChangeNotifier` wrapper around
  `PortablePtyController` for reactive UI updates.
- Same API on native (real shell) and web (remote transport).
- Buffered output lines, revision counter, and automatic cleanup.
- Re-exports all of [`portable_pty`](https://pub.dev/packages/portable_pty)
  so you only need one import.

### Platform support

| Platform | Native shell | Web transport |
|----------|:------------:|:-------------:|
| Linux    | ✅           | ✅             |
| macOS    | ✅           | ✅             |
| Windows  | ✅           | ✅             |
| Android  | ✅           | ✅             |
| iOS      | —            | ✅             |

## Installation

```yaml
dependencies:
  portable_pty_flutter: ^0.0.1
```

No separate `portable_pty` dependency is needed — it's re-exported
automatically.

## Quick start

### Native

```dart
import 'package:flutter/material.dart';
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});
  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _ctrl = FlutterPtyController(
    rows: 24,
    cols: 80,
    defaultShell: '/bin/bash',
  );

  @override
  void initState() {
    super.initState();
    _ctrl.start();
    _ctrl.addListener(() => setState(() {}));
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
      body: ListView.builder(
        itemCount: _ctrl.lineCount,
        itemBuilder: (_, i) => Text(
          _ctrl.lines[i],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    );
  }
}
```

### Web

On web targets, pass a WebSocket URL to connect to a remote PTY server:

```dart
final controller = FlutterPtyController(
  rows: 24,
  cols: 80,
  webSocketUrl: 'ws://localhost:8080/pty',
);

await controller.start();
controller.write('ls\n');
```

## FlutterPtyController

`FlutterPtyController` extends Flutter's `ChangeNotifier` and delegates to
the platform-resolved `PortablePtyController` from `portable_pty`.

| Property / Method | Description |
|-------------------|-------------|
| `start({shell, arguments})` | Start a shell subprocess (native) or connect transport (web) |
| `stop()` | Kill the subprocess / disconnect |
| `write(text)` | Write text to stdin |
| `writeBytes(bytes)` | Write raw bytes to stdin |
| `readOutput()` | Read buffered output as a string |
| `clear()` | Clear the output buffer |
| `lines` | Current buffered output lines |
| `lineCount` | Number of buffered lines |
| `revision` | Monotonic counter, increments on every change |
| `dispose()` | Stop the session and release resources |

## Related packages

| Package | Description |
|---------|-------------|
| [`portable_pty`](https://pub.dev/packages/portable_pty) | Core PTY library (re-exported by this package) |
| [`ghostty_vte`](https://pub.dev/packages/ghostty_vte) | Terminal VT engine — paste safety, OSC/SGR parsing, key encoding |
| [`ghostty_vte_flutter`](https://pub.dev/packages/ghostty_vte_flutter) | Flutter terminal widgets powered by Ghostty |

## License

MIT — see [LICENSE](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/pty/portable_pty_flutter/LICENSE).
