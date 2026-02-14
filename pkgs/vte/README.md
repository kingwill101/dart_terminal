# VTE — Virtual Terminal Emulator packages

Dart and Flutter packages for terminal emulation powered by
[Ghostty](https://github.com/ghostty-org/ghostty)'s VT library.

## Packages

| Package | Description |
|---------|-------------|
| [`ghostty_vte`](ghostty_vte/) | Low-level FFI bindings + high-level Dart API for paste-safety checks, OSC/SGR parsing, and key encoding. Works on native **and** web (via wasm). |
| [`ghostty_vte_flutter`](ghostty_vte_flutter/) | Flutter widgets (`GhosttyTerminalView`, `GhosttyTerminalController`) and a web asset loader that initializes the wasm module. |

## Prerequisites

| Tool | Required for | Install |
|------|-------------|---------|
| **Dart SDK ≥ 3.10** | Both packages | [dart.dev/get-dart](https://dart.dev/get-dart) |
| **Flutter** | `ghostty_vte_flutter` | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Zig** | Building `libghostty-vt` (native & wasm) | [ziglang.org/download](https://ziglang.org/download/) |
| **Git** | If using the Ghostty submodule | Bundled with most OS toolchains |

## Providing the Ghostty source

The build hook (`ghostty_vte/hook/build.dart`) resolves the Ghostty source tree
using the following strategy (first match wins):

| Priority | Method | Details |
|----------|--------|---------|
| 1 | `GHOSTTY_SRC` env var | `export GHOSTTY_SRC=/path/to/ghostty` |
| 2 | `third_party/ghostty` | Submodule or symlink at `ghostty_vte/third_party/ghostty` |
| 3 | Ancestor directory walk | Walks up looking for `build.zig` + `include/ghostty/vt.h` |

### Set up the submodule

```bash
cd pkgs/vte/ghostty_vte
git submodule add https://github.com/ghostty-org/ghostty third_party/ghostty
git submodule update --init --recursive
```

### Or use auto-fetch

```bash
export GHOSTTY_SRC_AUTO_FETCH=1
```

## Build & pipeline overview

```
Ghostty C source (build.zig + include/ghostty/vt.h)
        │                              │
  zig build lib-vt              zig build lib-vt
  (native target)               (wasm32-freestanding)
        │                              │
        ▼                              ▼
  libghostty-vt.so/.dylib       ghostty-vt.wasm
  (bundled via code assets)     (Flutter assets)
```

| Step | Command | What happens |
|------|---------|--------------|
| Generate FFI bindings | `task ffigen` | Regenerates `ghostty_vte_bindings_generated.dart` from C headers. |
| Build wasm module | `task wasm` | Builds wasm and copies to `ghostty_vte_flutter/assets/`. |
| Native build | _automatic_ | Dart/Flutter build hooks run `zig build lib-vt` on demand. |

## Platform matrix

| Scenario | Import | Init required? | How the library loads |
|----------|--------|---------------|----------------------|
| **Dart native** (CLI, server) | `package:ghostty_vte/ghostty_vte.dart` | No | Dynamic library via code assets |
| **Dart web** (without Flutter) | `package:ghostty_vte/ghostty_vte.dart` | **Yes** – `GhosttyVtWasm.initializeFromBytes(…)` | You build & supply the wasm bytes |
| **Flutter native** | `package:ghostty_vte_flutter/ghostty_vte_flutter.dart` | No | Same as Dart native |
| **Flutter web** | `package:ghostty_vte_flutter/ghostty_vte_flutter.dart` | **Yes** – `await initializeGhosttyVteWeb()` | Fetches bundled `assets/ghostty-vt.wasm` |

## Package docs

- [ghostty_vte README](ghostty_vte/README.md) — API guide, code examples, build details
- [ghostty_vte_flutter README](ghostty_vte_flutter/README.md) — widgets, controllers, web setup
