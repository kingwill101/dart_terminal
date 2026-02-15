## 0.0.3

- Fixed child process exit codes being incorrectly reported as 0 when
  running under the Dart test runner. The Dart VM's internal
  `waitpid(-1, 0)` thread was reaping PTY children before `tryWait()`
  could capture their exit status.
- SIGCHLD handler now extracts exit status from the `siginfo_t` structure
  (populated by the kernel at signal delivery time), unaffected by
  concurrent reaping from other threads.
- Added lock-free PID registry (64 slots) with signal chaining and
  automatic re-installation if overwritten.
- SIGCHLD is blocked during `spawn` to prevent a race between child exit
  and PID registration.
- Cached exit code on the PTY handle so repeated `tryWait`/`wait` calls
  return consistent results.
- Pre-emptive `waitpid` and `kill(pid, 0)` fallback paths for robustness
  when the SIGCHLD handler misses a coalesced signal.

## 0.0.2

- Added `dart run portable_pty:setup` command to download prebuilt native
  libraries for downstream consumers.
- Build hook now finds prebuilt libraries at the consuming project's
  `.prebuilt/<platform>/` directory, eliminating the need to modify the
  pub cache.
- Build hook search order: env var, monorepo `.prebuilt/`, project `.prebuilt/`.

## 0.0.1+1

- Bumped package version to `0.0.1+1`.

## 0.0.1

- Initial release.
- Cross-platform PTY via Rust FFI (Linux, macOS, Windows).
- `PortablePty` — open, spawn, read/write, resize, close.
- `PortablePtyController` — buffered output with listener support.
- `PortablePtyTransport` — pluggable web transport interface.
- Built-in WebSocket and WebTransport backends for web targets.
- Prebuilt library support — skip Rust with downloaded binaries.
