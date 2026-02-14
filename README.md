# dart_terminal

[![Analyze](https://github.com/kingwill101/dart_terminal/actions/workflows/analyze.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/analyze.yml)
[![VTE](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/vte.yml)
[![PTY](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml/badge.svg)](https://github.com/kingwill101/dart_terminal/actions/workflows/pty.yml)

Dart & Flutter packages for building terminal applications. This monorepo
provides two complementary package groups — a **VT engine** powered by
[Ghostty](https://github.com/ghostty-org/ghostty) and a **cross-platform
PTY** backed by Rust — that together give you everything needed to embed a
fully functional terminal in any Dart or Flutter app.

## Packages

| Package | pub.dev | Description |
|---------|---------|-------------|
| [`ghostty_vte`](pkgs/vte/ghostty_vte/) | [![pub](https://img.shields.io/pub/v/ghostty_vte.svg)](https://pub.dev/packages/ghostty_vte) | Dart FFI bindings for Ghostty's VT engine — paste safety, OSC/SGR parsing, key encoding |
| [`ghostty_vte_flutter`](pkgs/vte/ghostty_vte_flutter/) | [![pub](https://img.shields.io/pub/v/ghostty_vte_flutter.svg)](https://pub.dev/packages/ghostty_vte_flutter) | Flutter terminal widgets + wasm initialiser |
| [`portable_pty`](pkgs/pty/portable_pty/) | [![pub](https://img.shields.io/pub/v/portable_pty.svg)](https://pub.dev/packages/portable_pty) | Cross-platform PTY — native shells on desktop, WebSocket/WebTransport on web |
| [`portable_pty_flutter`](pkgs/pty/portable_pty_flutter/) | [![pub](https://img.shields.io/pub/v/portable_pty_flutter.svg)](https://pub.dev/packages/portable_pty_flutter) | Flutter `ChangeNotifier` controller for PTY sessions |

## Quick start

```bash
git clone https://github.com/kingwill101/dart_terminal.git
cd dart_terminal
git submodule update --init --recursive
flutter pub get
```

### Run the VTE tests

```bash
cd pkgs/vte/ghostty_vte
dart test
```

### Run the PTY example

```bash
cd pkgs/pty/portable_pty
dart run example/pty_example.dart
```

### Run the Flutter example

```bash
cd pkgs/vte/ghostty_vte_flutter/example
flutter run
```

## Prerequisites

| Tool | Required for | Install |
|------|-------------|---------|
| **Dart SDK ≥ 3.10** | All packages | [dart.dev/get-dart](https://dart.dev/get-dart) |
| **Flutter** | Flutter packages & examples | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Zig ≥ 0.15** | Building `libghostty-vt` | [ziglang.org/download](https://ziglang.org/download/) |
| **Rust ≥ 1.92** | Building the PTY library | [rustup.rs](https://rustup.rs/) |

> **Don't want to install Zig or Rust?** Download
> [prebuilt libraries](https://github.com/kingwill101/dart_terminal/releases)
> for your platform — the build hooks will use them automatically.
>
> ```bash
> dart run tool/prebuilt.dart --tag v0.0.2
> ```

### Prebuilt assets for downstream consumers

When `ghostty_vte` or `portable_pty` are consumed from **pub.dev**, you don't
need Zig or Rust installed — each package ships a setup command that downloads
the correct prebuilt library for your platform:

```bash
dart run ghostty_vte:setup
dart run portable_pty:setup
```

This places the native libraries in `.prebuilt/<platform>/` at your project
root, where the build hooks find them automatically.

The build hooks search for prebuilt libraries in this order:

1. **Environment variable** — `GHOSTTY_VTE_PREBUILT` / `PORTABLE_PTY_PREBUILT`
   pointing directly to the `.so` / `.dylib` file.
2. **Monorepo `.prebuilt/`** — `.prebuilt/<platform>/<lib>` at the monorepo
   root (found by walking up looking for `pubspec.yaml` + `pkgs/`).
3. **Project `.prebuilt/`** — `.prebuilt/<platform>/<lib>` at your project
   root (derived from the build system's output directory). **This is the
   recommended approach for downstream consumers.**

You can also specify a release tag or target platform:

```bash
dart run ghostty_vte:setup --tag v0.0.2 --platform macos-arm64
dart run portable_pty:setup --tag v0.0.2 --platform macos-arm64
```

Platform labels follow the pattern `{os}-{arch}`:
`linux-x64`, `linux-arm64`, `macos-arm64`, `macos-x64`, `windows-x64`, etc.

> **Tip:** Add `.prebuilt/` to your `.gitignore` — these are binary artifacts
> that should be downloaded as needed, not committed.

## Architecture

```
dart_terminal/
├── pkgs/
│   ├── vte/                        # Terminal VT engine
│   │   ├── ghostty_vte/            # Core Dart FFI bindings
│   │   └── ghostty_vte_flutter/    # Flutter widgets & controllers
│   └── pty/                        # Pseudo-terminal
│       ├── portable_pty/           # Core PTY library (Rust FFI + web transport)
│       └── portable_pty_flutter/   # Flutter ChangeNotifier controller
└── tool/
    └── prebuilt.dart               # Download prebuilt native libraries
```

## License

MIT
