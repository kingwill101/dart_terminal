# portable_pty

[![CI](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml)
[![pub package](https://img.shields.io/pub/v/portable_pty.svg)](https://pub.dev/packages/portable_pty)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/pty/portable_pty/LICENSE)

Cross-platform pseudo-terminal (PTY) for Dart. Spawn shell subprocesses on
Linux, macOS, and Windows with full terminal I/O — or connect to a remote
PTY server on the web via WebSocket / WebTransport.

## Features

- **Native PTY** — `forkpty` / `openpty` on Unix, ConPTY on Windows, via a
  Rust native library ([`portable-pty`](https://crates.io/crates/portable-pty)).
- **Web transport** — plug in WebSocket, WebTransport, or any custom
  `PortablePtyTransport` to talk to a server-side PTY from the browser.
- **Unified API** — same `PortablePty` / `PortablePtyController` interface
  regardless of platform.
- **Synchronous read/write** for low-latency integrations.
- **Window resize**, mode queries, and explicit lifecycle management.

### Platform support

| Platform | Backend | Build toolchain |
|----------|---------|-----------------|
| Linux | Native PTY (Rust) | Rust (or [prebuilt](#prebuilt-libraries)) |
| macOS | Native PTY (Rust) | Rust (or prebuilt) |
| Windows | ConPTY (Rust) | Rust (or prebuilt) |
| Android | Native PTY (Rust) | Rust + cross (or prebuilt) |
| iOS | Static lib (Rust) | Rust (or prebuilt) |
| Web | WebSocket / WebTransport | None (pure Dart) |

## Installation

```yaml
dependencies:
  portable_pty: ^0.0.1
```

The Rust native library is compiled automatically by a
[Dart build hook](https://dart.dev/interop/c-interop#native-assets)
using [`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust).
You need **Rust ≥ 1.92** installed.

> **Tip:** If you don't want to install Rust, download a
> [prebuilt library](#prebuilt-libraries) instead.

## Quick start

```dart
import 'package:portable_pty/portable_pty.dart';

void main() {
  final pty = PortablePty.open(rows: 24, cols: 80);
  pty.spawn('/bin/sh', args: ['-c', 'echo hello from portable_pty']);

  final out = pty.readSync(4096);
  print(String.fromCharCodes(out));

  print('pid: ${pty.childPid}');
  print('mode: ${pty.getMode()}');

  pty.close();
}
```

## API overview

### Opening a PTY

```dart
final pty = PortablePty.open(
  rows: 24,
  cols: 80,
  // Web-only options:
  webSocketUrl: 'ws://localhost:8080/pty',
  // webTransportUrl: 'https://localhost:4433/pty',
  // transport: MyCustomTransport(),
);
```

### Spawning a process

```dart
pty.spawn('/bin/bash', args: ['-l']);
pty.spawn('cmd.exe');  // Windows
```

### Reading & writing

```dart
// Synchronous
final bytes = pty.readSync(4096);
pty.writeString('ls -la\n');
pty.writeBytes(Uint8List.fromList([0x03]));  // Ctrl+C

// Written byte count
final n = pty.writeString('echo hello\n');
print('wrote $n bytes');
```

### Window resize

```dart
pty.resize(rows: 40, cols: 120);
```

### PTY mode

```dart
final mode = pty.getMode();
print('canonical: ${mode.canonical}, echo: ${mode.echo}');
```

### Process lifecycle

```dart
print('running: ${pty.childPid}');

final exitCode = pty.tryWait();   // non-blocking, returns null if still running
print('exited: $exitCode');

pty.kill();    // SIGKILL
pty.close();   // close file descriptors
```

### Controller (with buffered output)

```dart
final controller = PortablePtyController(
  rows: 24,
  cols: 80,
  defaultShell: '/bin/bash',
);

await controller.start();
controller.write('ls\n');
final output = controller.readOutput();
print(output);

await controller.stop();
controller.dispose();
```

## Prebuilt libraries

Prebuilt binaries for every platform are attached to each
[GitHub release](https://github.com/kingwill101/dart_terminal/releases).
Download them into the `.prebuilt/` directory and the build hook will skip
Rust compilation entirely — **no Rust install required**.

```bash
# Download prebuilt libs for your host platform
dart run tool/prebuilt.dart --tag v0.0.1 --lib pty

# Or download for all platforms
dart run tool/prebuilt.dart --tag v0.0.1 --lib pty --all-platforms
```

You can also set the `PORTABLE_PTY_PREBUILT` environment variable to point
directly at a prebuilt library file.

## Web usage

Browsers cannot spawn OS processes. On web, `portable_pty` connects to a
**remote PTY server** over WebSocket or WebTransport.

```
┌──────────────┐       ws / webtransport       ┌──────────────┐
│  Browser app │  ◄──────────────────────────►  │  PTY server  │
│  (Dart web)  │                                │  (any lang)  │
└──────────────┘                                └──────────────┘
```

```dart
final pty = PortablePty.open(
  rows: 24,
  cols: 80,
  webSocketUrl: 'ws://localhost:8080/pty',
);
pty.spawn('ws://localhost:8080/pty');
pty.writeString('echo hello\n');
```

### Custom transport

Implement `PortablePtyTransport` for any protocol (SSH, proprietary, etc.):

```dart
class MySshTransport implements PortablePtyTransport {
  @override
  void write(Uint8List data) { /* ... */ }

  @override
  Uint8List readSync(int maxBytes) { /* ... */ }

  // ...
}

final pty = PortablePty.open(transport: MySshTransport());
```

## Related packages

| Package | Description |
|---------|-------------|
| [`portable_pty_flutter`](https://pub.dev/packages/portable_pty_flutter) | Flutter `ChangeNotifier` controller for PTY sessions |
| [`ghostty_vte`](https://pub.dev/packages/ghostty_vte) | Terminal VT engine — paste safety, OSC/SGR parsing, key encoding |
| [`ghostty_vte_flutter`](https://pub.dev/packages/ghostty_vte_flutter) | Flutter terminal widgets powered by Ghostty |

## License

MIT — see [LICENSE](https://github.com/kingwill101/dart_terminal/blob/master/pkgs/pty/portable_pty/LICENSE).
