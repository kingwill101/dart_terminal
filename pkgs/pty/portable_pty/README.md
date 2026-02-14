# portable_pty

Cross-platform PTY (pseudo-terminal) session control for Dart.

`portable_pty` is the core package in this workspace. It exposes a single,
platform-agnostic API (`PortablePty`) plus a transport abstraction (`PortablePtyTransport`)
that works on native and web targets.

---

## Features

- Native PTY sessions on desktop/server platforms.
- Browser support via pluggable remote transport (WebSocket or WebTransport).
- Inject custom backends by implementing `PortablePtyTransport`.
- Synchronous read/write API for simple, low-latency integrations.
- Explicit resource lifecycle (`close`, `kill`) and exit detection (`tryWait`).

---

## Install

```yaml
dependencies:
  portable_pty:
    path: ../portable_pty
```

---

## Quick start

```dart
import 'package:portable_pty/portable_pty.dart';

void main() {
  final pty = PortablePty.open(rows: 24, cols: 80);
  pty.spawn('/bin/sh', args: ['-c', 'echo hello from portable_pty']);

  final out = pty.readSync(4096);
  print(String.fromCharCodes(out));

  final written = pty.writeString('echo back\n');
  print('written: $written bytes');

  print('pid: ${pty.childPid}');
  print('mode: ${pty.getMode()}');
  pty.close();
}
```

---

## Web usage

On web targets, **there is no local PTY** — browsers cannot spawn OS
processes. Instead `portable_pty` communicates with a server-side PTY over a
remote transport (WebSocket or WebTransport). This applies equally to
**pure Dart web** apps and Flutter web apps.

### Why there is no `.wasm` file

The native backend is built from a Rust crate (`portable-pty`) that calls
POSIX `forkpty`/`openpty` on Unix and ConPTY on Windows. Those system calls
do not exist inside a WebAssembly sandbox, so the crate cannot be compiled
to `wasm32`. Instead, the web variant of `PortablePty` delegates all I/O to a
`PortablePtyTransport` implementation that talks to a real PTY running on a
server.

### Architecture

```
┌──────────────┐         ws / webtransport         ┌──────────────┐
│  Browser app │  ◄──────────────────────────────►  │  PTY server  │
│  (Dart web)  │   PortablePtyWebSocketTransport    │  (dart:io /  │
│              │   or WebTransportTransport          │   Node/Go/…) │
└──────────────┘                                    └──────────────┘
```

### Getting started (pure Dart web, no Flutter)

1. **Add the dependency** — `portable_pty` works in any Dart web project,
   Flutter is _not_ required:

   ```yaml
   # pubspec.yaml
   dependencies:
     portable_pty:
       path: ../portable_pty   # or a published version
   ```

2. **Run a PTY server** — you need a backend that upgrades HTTP connections
   to WebSocket and bridges them to a local PTY. A ready-made example server
   is included in the workspace:

   ```bash
   dart run pkgs/pty/portable_pty_flutter/example/tooling/pty_web_server.dart
   # ⇒ mock PTY websocket server on ws://0.0.0.0:8080/pty
   ```

   You can also write your own in any language — the protocol is a
   bidirectional byte stream over WebSocket (or WebTransport datagrams).

3. **Connect from your Dart web app**:

   ```dart
   import 'package:portable_pty/portable_pty.dart';

   void main() {
     final pty = PortablePty.open(
       rows: 24,
       cols: 80,
       webSocketUrl: 'ws://localhost:8080/pty',
     );
     pty.spawn('ws://localhost:8080/pty');

     // read / write just like on native
     pty.writeString('echo hello\n');
     final out = pty.readSync(4096);
     print(String.fromCharCodes(out));

     pty.close();
   }
   ```

4. **Compile and serve** with `dart compile js` or `webdev serve` — no
   special WASM flags are needed.

### Using the controller on web

`PortablePtyController` (exported from `portable_pty`) also works in pure
Dart web apps without Flutter. It manages the connection lifecycle and
buffers output lines for you:

```dart
import 'package:portable_pty/portable_pty.dart';

void main() async {
  final controller = PortablePtyController(
    webSocketUrl: 'ws://localhost:8080/pty',
  );

  await controller.start(shell: 'ws://localhost:8080/pty');
  controller.write('ls\n');

  // poll for output
  final text = controller.readOutput();
  print(text);

  await controller.stop();
  controller.dispose();
}
```

### Custom transport

If the built-in WebSocket / WebTransport transports don't fit your setup
(e.g. you use SSH or a proprietary protocol), implement
`PortablePtyTransport` and pass it to `PortablePty.open(transport: …)`.
See the [transport example](example/transport_example.dart).

---

## Related packages

- [portable_pty_flutter](../portable_pty_flutter/README.md): Flutter helpers that
  consume this package and expose PTY sessions as a `ChangeNotifier` controller.
