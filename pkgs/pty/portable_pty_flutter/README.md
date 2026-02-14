# portable_pty_flutter

Flutter session controller package for `portable_pty`.

`portable_pty_flutter` wraps the PTY transport layer behind a
`ChangeNotifier` controller that is convenient for Flutter widgets and app state
management.

---

## What it provides

- `PortablePtyController` with identical API shape on native and web.
- Reactive state (`lines`, `lineCount`, `revision`) for terminal UI rendering.
- `start`, `readOutput`, `write`, `writeBytes`, `appendDebugOutput`,
  `clear`, `stop`, `tryWait`.
- Dedicated web wiring parameters:
  - `webSocketUrl`
  - `webTransportUrl`
  - `transport` (custom `PortablePtyTransport` injection)

---

## Install

```yaml
dependencies:
  portable_pty_flutter:
    path: ../portable_pty_flutter
```

`portable_pty_flutter` depends on `portable_pty`, which must be available in the
same workspace.

---

## Native usage

```dart
import 'package:flutter/material.dart';
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

final controller = PortablePtyController(
  rows: 24,
  cols: 80,
  defaultShell: '/bin/bash',
);

await controller.start();
controller.write('ls -la\\n');
final output = controller.readOutput();
```

---

## Web usage

Web targets require a remote backend. Use one of:

- `webSocketUrl` (default transport is WebSocket)
- `webTransportUrl` (WebTransport)
- custom `transport`

```dart
final controller = PortablePtyController(
  rows: 24,
  cols: 80,
  webSocketUrl: 'ws://localhost:8080/pty',
);

await controller.start();
controller.write('ls\\n');
```

If no transport target is available, `start()` emits a diagnostic line in the
output buffer and remains safe.

---

## Example app

Run the included example and local tooling server to test browser PTY transport:

- `pkgs/pty/portable_pty_flutter/example/tooling/pty_web_server.dart`
- `pkgs/pty/portable_pty_flutter/example/README.md`

---

## Related

- [portable_pty](../portable_pty/README.md): transport abstraction and core PTY
  primitives used by this package.
