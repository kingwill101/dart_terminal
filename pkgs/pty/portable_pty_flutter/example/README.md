# portable_pty_flutter_example

A new Flutter project.

## Running a local web PTY backend for testing

Use the included mock websocket server to test the web example end-to-end:

1. Start the server:
   - `dart run tooling/pty_web_server.dart [port=8080] [host=0.0.0.0]`
2. In a separate terminal, run the example:
   - `flutter run -d chrome`
3. In the app, set **Transport** to **WebSocket** and set endpoint to:
   - `ws://localhost:8080/pty`

To run a command directly from the server endpoint (without opening an
interactive shell), use the `command` or `cmd` query parameter:

- `ws://localhost:8080/pty?command=echo%20portable_pty_flutter`

If omitted, the server starts the default shell (`/bin/sh` or `cmd.exe`) and
keeps the connection interactive.

Notes:
- This server is intentionally small and for local testing only.
- WebTransport mode in the example still needs a real WebTransport-capable backend.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
