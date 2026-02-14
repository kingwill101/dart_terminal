# PTY — Pseudo-Terminal packages

Cross-platform PTY session control for Dart and Flutter.

## Packages

| Package | Description |
|---------|-------------|
| [`portable_pty`](portable_pty/) | Platform-agnostic PTY wrapper with native (Rust/FFI) and web transport support (WebSocket, WebTransport). Includes a `PortablePtyTransport` abstraction for custom backends. |
| [`portable_pty_flutter`](portable_pty_flutter/) | Flutter controller bindings (`PortablePtyController`) that wrap a PTY session with a `ChangeNotifier`-based API suitable for widgets. |

## Prerequisites

| Tool | Required for | Install |
|------|-------------|---------|
| **Dart SDK ≥ 3.10** | Both packages | [dart.dev/get-dart](https://dart.dev/get-dart) |
| **Flutter** | `portable_pty_flutter` | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Rust toolchain** | Building the native PTY library | [rustup.rs](https://rustup.rs/) |

## Quick start (native)

```dart
import 'package:portable_pty/portable_pty.dart';

void main() {
  final pty = PortablePty.open(rows: 24, cols: 80);
  pty.spawn('/bin/sh', args: ['-c', 'echo hello']);

  final out = pty.readSync(4096);
  print(String.fromCharCodes(out));

  pty.close();
}
```

## Quick start (web)

On web targets (both pure Dart and Flutter), PTY sessions are backed by
**remote transports** — browsers cannot spawn OS processes, so there is no
`.wasm` build of the native PTY library. Instead the client connects to a
server-side PTY over WebSocket or WebTransport:

```dart
import 'package:portable_pty/portable_pty.dart';

final pty = PortablePty.open(
  rows: 24,
  cols: 80,
  webSocketUrl: 'ws://localhost:8080/pty',
);
pty.spawn('ws://localhost:8080/pty');
```

A ready-made PTY WebSocket server is included for development:

```bash
dart run portable_pty_flutter/example/tooling/pty_web_server.dart
```

See the [portable_pty README → Web usage](portable_pty/README.md#web-usage)
for the full walkthrough, architecture diagram, and pure-Dart-web setup
instructions.

## Extending

Implement `PortablePtyTransport` for SSH bridges, proxies, or test doubles. See
the [transport example](portable_pty/example/transport_example.dart).

## Flutter usage

```dart
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

final controller = PortablePtyController(defaultShell: '/bin/bash');
await controller.start();
controller.write('ls -la\n');
final output = controller.readOutput();
```

The controller provides reactive state (`lines`, `lineCount`, `revision`) and
works identically on native and web targets.

## Package docs

- [portable_pty README](portable_pty/README.md) — API reference, transport details
- [portable_pty_flutter README](portable_pty_flutter/README.md) — controller API, web wiring, example app
