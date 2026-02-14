# dart_terminal

Dart and Flutter packages for terminal tooling.

## Package groups

| Group | Packages | Description |
|-------|----------|-------------|
| [**vte**](pkgs/vte/) | `ghostty_vte`, `ghostty_vte_flutter` | Terminal emulation — Ghostty VT parser bindings, keyboard encoding, and Flutter rendering widgets. |
| [**pty**](pkgs/pty/) | `portable_pty`, `portable_pty_flutter` | Pseudo-terminal sessions — cross-platform PTY with native (Rust/FFI) and web transport support, plus a Flutter controller. |

## Quick start

```bash
# Clone
git clone <this-repo-url>
cd dart_terminal

# Ghostty source (needed by vte packages)
git submodule update --init --recursive

# Install dependencies
dart pub get

# Run tests
task test
```

## Prerequisites

| Tool | Required for | Install |
|------|-------------|---------|
| **Dart SDK ≥ 3.10** | All packages | [dart.dev/get-dart](https://dart.dev/get-dart) |
| **Flutter** | Flutter packages & examples | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Zig** | Building `libghostty-vt` (native & wasm) | [ziglang.org/download](https://ziglang.org/download/) |
| **Rust** | Building the native PTY library | [rustup.rs](https://rustup.rs/) |
| **Task** *(optional)* | Running Taskfile shortcuts | [taskfile.dev/installation](https://taskfile.dev/installation/) |

## Common tasks

```bash
task get          # dart pub get
task ffigen       # regenerate VTE FFI bindings
task wasm         # build wasm module → Flutter assets
task analyze      # static analysis
task test         # run all tests
```

## Development workflow

1. Make changes to source, bindings, or widgets.
2. `task ffigen` — if Ghostty C headers changed.
3. `task wasm` — if targeting web.
4. `task test` — verify.
5. `task analyze` — before committing.

## Documentation

Detailed docs live alongside each package group:

- **[pkgs/vte/README.md](pkgs/vte/README.md)** — VTE build pipeline, platform matrix, Ghostty source setup
- **[pkgs/pty/README.md](pkgs/pty/README.md)** — PTY quick start, transport architecture, Flutter usage
- [pkgs/vte/ghostty_vte/README.md](pkgs/vte/ghostty_vte/README.md) — full API guide with code examples
- [pkgs/vte/ghostty_vte_flutter/README.md](pkgs/vte/ghostty_vte_flutter/README.md) — widgets, controllers, web setup
- [pkgs/pty/portable_pty/README.md](pkgs/pty/portable_pty/README.md) — PTY API, web transports, extending
- [pkgs/pty/portable_pty_flutter/README.md](pkgs/pty/portable_pty_flutter/README.md) — controller API, example app
