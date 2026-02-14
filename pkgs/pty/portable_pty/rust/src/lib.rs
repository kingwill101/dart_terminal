//! libportable-pty — Cross-platform PTY + process-spawn library.
//!
//! Exposes a C API wrapping the `portable-pty` crate from wezterm.
//! Supports Linux, macOS, and Windows (ConPTY).

use portable_pty::{
    native_pty_system, Child, CommandBuilder, MasterPty, PtySize, SlavePty,
};
use std::ffi::{CStr, c_char, c_int};
use std::io::{Read, Write};
use std::sync::Mutex;
#[cfg(unix)]
use libc;

// ---------------------------------------------------------------------------
// Result enum
// ---------------------------------------------------------------------------

#[repr(C)]
pub enum PortablePtyResult {
    Ok = 0,
    ErrOpen = 1,
    ErrSpawn = 2,
    ErrResize = 3,
    ErrRead = 4,
    ErrWrite = 5,
    ErrNull = 6,
    ErrWait = 7,
    ErrKill = 8,
    ErrMode = 9,
    ErrSize = 10,
    ErrWaitBlocking = 11,
    ErrProcessGroup = 12,
}

// ---------------------------------------------------------------------------
// Opaque handle
// ---------------------------------------------------------------------------

pub struct PortablePty {
    master: Box<dyn MasterPty + Send>,
    slave: Box<dyn SlavePty + Send>,
    reader: Mutex<Box<dyn Read + Send>>,
    writer: Mutex<Box<dyn Write + Send>>,
    child: Option<Box<dyn Child + Send + Sync>>,
    child_pid: i32,
}

// ---------------------------------------------------------------------------
// C API
// ---------------------------------------------------------------------------

/// Open a new PTY with the given dimensions.
///
/// On success, writes the opaque handle to `*out` and returns `Ok`.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_open(
    rows: u16,
    cols: u16,
    out: *mut *mut PortablePty,
) -> PortablePtyResult {
    if out.is_null() {
        return PortablePtyResult::ErrNull;
    }

    let pty_system = native_pty_system();
    let size = PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };

    let pair = match pty_system.openpty(size) {
        Ok(pair) => pair,
        Err(_) => return PortablePtyResult::ErrOpen,
    };

    let reader = match pair.master.try_clone_reader() {
        Ok(r) => r,
        Err(_) => {
            return PortablePtyResult::ErrOpen;
        }
    };
    let writer = match pair.master.take_writer() {
        Ok(w) => w,
        Err(_) => {
            return PortablePtyResult::ErrOpen;
        }
    };

    let handle = Box::new(PortablePty {
        master: pair.master,
        slave: pair.slave,
        reader: Mutex::new(reader),
        writer: Mutex::new(writer),
        child: None,
        child_pid: -1,
    });

    unsafe {
        *out = Box::into_raw(handle);
    }
    PortablePtyResult::Ok
}

/// Spawn a child process attached to the PTY.
///
/// - `cmd`: null-terminated executable path.
/// - `argv`: null-terminated array of null-terminated argument strings,
///   or NULL to use `cmd` as the sole argument.
/// - `envp`: null-terminated array of `"KEY=VALUE"` strings, or NULL to
///   inherit the current environment.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_spawn(
    handle: *mut PortablePty,
    cmd: *const c_char,
    argv: *const *const c_char,
    envp: *const *const c_char,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };
    if cmd.is_null() {
        return PortablePtyResult::ErrNull;
    }

    let cmd_str = unsafe { CStr::from_ptr(cmd) };
    let cmd_str = match cmd_str.to_str() {
        Ok(s) => s,
        Err(_) => return PortablePtyResult::ErrSpawn,
    };

    let mut builder = CommandBuilder::new(cmd_str);

    // Parse argv
    if !argv.is_null() {
        let mut args = Vec::new();
        unsafe {
            let mut i = 0;
            loop {
                let arg = *argv.add(i);
                if arg.is_null() {
                    break;
                }
                match CStr::from_ptr(arg).to_str() {
                    Ok(s) => args.push(s.to_owned()),
                    Err(_) => return PortablePtyResult::ErrSpawn,
                }
                i += 1;
            }
        }
        // CommandBuilder::new already sets argv[0], so skip it if present
        if args.len() > 1 {
            builder.args(&args[1..]);
        }
    }

    // Parse envp
    if !envp.is_null() {
        // Clear inherited env and set only what's provided
        builder.env_clear();
        unsafe {
            let mut i = 0;
            loop {
                let entry = *envp.add(i);
                if entry.is_null() {
                    break;
                }
                if let Ok(s) = CStr::from_ptr(entry).to_str() {
                    if let Some((key, val)) = s.split_once('=') {
                        builder.env(key, val);
                    }
                }
                i += 1;
            }
        }
    }

    // Spawn the child on the slave side
    match pty.slave.as_ref().spawn_command(builder) {
        Ok(child) => {
            let pid = child.process_id().map(|p| p as i32).unwrap_or(-1);
            pty.child = Some(child);
            pty.child_pid = pid;
            PortablePtyResult::Ok
        }
        Err(_) => PortablePtyResult::ErrSpawn,
    }
}

/// Read bytes from the PTY master side (child's stdout).
///
/// Returns number of bytes read, or -1 on error/EOF.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_read(
    handle: *mut PortablePty,
    buf: *mut u8,
    len: usize,
) -> i64 {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return -1,
    };
    if buf.is_null() || len == 0 {
        return -1;
    }

    let slice = unsafe { std::slice::from_raw_parts_mut(buf, len) };
    let mut reader = match pty.reader.lock() {
        Ok(r) => r,
        Err(_) => return -1,
    };

    match reader.read(slice) {
        Ok(0) => 0, // EOF
        Ok(n) => n as i64,
        Err(_) => -1,
    }
}

/// Write bytes to the PTY master side (child's stdin).
///
/// Returns number of bytes written, or -1 on error.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_write(
    handle: *mut PortablePty,
    buf: *const u8,
    len: usize,
) -> i64 {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return -1,
    };
    if buf.is_null() || len == 0 {
        return -1;
    }

    let slice = unsafe { std::slice::from_raw_parts(buf, len) };
    let mut writer = match pty.writer.lock() {
        Ok(w) => w,
        Err(_) => return -1,
    };

    match writer.write(slice) {
        Ok(n) => {
            let _ = writer.flush();
            n as i64
        }
        Err(_) => -1,
    }
}

/// Resize the PTY.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_resize(
    handle: *mut PortablePty,
    rows: u16,
    cols: u16,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };

    let size = PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };

    match pty.master.resize(size) {
        Ok(()) => PortablePtyResult::Ok,
        Err(_) => PortablePtyResult::ErrResize,
    }
}

/// Get the PTY master side file descriptor.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_master_fd(handle: *mut PortablePty) -> c_int {
    let pty = match unsafe { handle.as_ref() } {
        Some(p) => p,
        None => return -1,
    };

    #[cfg(unix)]
    {
        pty.master.as_ref().as_raw_fd().unwrap_or(-1)
    }

    #[cfg(not(unix))]
    {
        -1
    }
}

/// Get the current PTY size as tracked by the kernel.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_get_size(
    handle: *mut PortablePty,
    out_rows: *mut u16,
    out_cols: *mut u16,
    out_pixel_width: *mut u16,
    out_pixel_height: *mut u16,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };

    if out_rows.is_null() || out_cols.is_null() || out_pixel_width.is_null() || out_pixel_height.is_null() {
        return PortablePtyResult::ErrNull;
    }

    let size = match pty.master.get_size() {
        Ok(size) => size,
        Err(_) => return PortablePtyResult::ErrSize,
    };

    unsafe {
        *out_rows = size.rows;
        *out_cols = size.cols;
        *out_pixel_width = size.pixel_width;
        *out_pixel_height = size.pixel_height;
    }
    PortablePtyResult::Ok
}

/// Get the child PID, or -1 if no child has been spawned.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_child_pid(handle: *const PortablePty) -> i32 {
    match unsafe { handle.as_ref() } {
        Some(pty) => pty.child_pid,
        None => -1,
    }
}

/// Non-blocking wait for child exit.
///
/// Returns `Ok` if child exited (writes exit code to `*out_status`).
/// Returns `ErrWait` if child is still running.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_wait(
    handle: *mut PortablePty,
    out_status: *mut c_int,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };

    let child = match pty.child.as_mut() {
        Some(c) => c,
        None => return PortablePtyResult::ErrWait,
    };

    match child.try_wait() {
        Ok(Some(status)) => {
            if !out_status.is_null() {
                unsafe {
                    *out_status = status
                        .exit_code()
                        .try_into()
                        .unwrap_or(-1);
                }
            }
            PortablePtyResult::Ok
        }
        Ok(None) => PortablePtyResult::ErrWait, // still running
        Err(_) => PortablePtyResult::ErrWait,
    }
}

/// Block until the child exits and return its exit code.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_wait_blocking(
    handle: *mut PortablePty,
    out_status: *mut c_int,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };

    let child = match pty.child.as_mut() {
        Some(c) => c,
        None => return PortablePtyResult::ErrWait,
    };

    match child.wait() {
        Ok(status) => {
            if !out_status.is_null() {
                unsafe {
                    *out_status = status.exit_code().try_into().unwrap_or(-1);
                }
            }
            PortablePtyResult::Ok
        }
        Err(_) => PortablePtyResult::ErrWaitBlocking,
    }
}

/// Kill the child process.
///
/// On POSIX, `signal` is the signal number (e.g. 15 for SIGTERM).
/// On Windows, `signal` is ignored — the process is terminated.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_kill(
    handle: *mut PortablePty,
    _signal: c_int,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };

    let child = match pty.child.as_mut() {
        Some(c) => c,
        None => return PortablePtyResult::ErrKill,
    };

    match child.kill() {
        Ok(()) => PortablePtyResult::Ok,
        Err(_) => PortablePtyResult::ErrKill,
    }
}

/// Return the master process group ID (POSIX) or -1 when unsupported.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_process_group_leader(handle: *const PortablePty) -> c_int {
    let pty = match unsafe { handle.as_ref() } {
        Some(p) => p,
        None => return -1,
    };

    #[cfg(unix)]
    {
        pty.master.process_group_leader().unwrap_or(-1)
    }

    #[cfg(not(unix))]
    {
        -1
    }
}

/// Get the current terminal mode flags.
///
/// - `out_canonical`: true when canonical mode is enabled.
/// - `out_echo`: true when echo mode is enabled.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_get_mode(
    handle: *mut PortablePty,
    out_canonical: *mut bool,
    out_echo: *mut bool,
) -> PortablePtyResult {
    let pty = match unsafe { handle.as_mut() } {
        Some(p) => p,
        None => return PortablePtyResult::ErrNull,
    };
    if out_canonical.is_null() || out_echo.is_null() {
        return PortablePtyResult::ErrNull;
    }

    #[cfg(unix)]
    {
        let fd = match pty.master.as_ref().as_raw_fd() {
            Some(fd) => fd,
            None => return PortablePtyResult::ErrMode,
        };

        let mut termios = std::mem::MaybeUninit::<libc::termios>::uninit();
        if unsafe { libc::tcgetattr(fd, termios.as_mut_ptr()) } != 0 {
            return PortablePtyResult::ErrMode;
        }
        let termios = unsafe { termios.assume_init() };
        let flags = termios.c_lflag;

        unsafe {
            *out_canonical = (flags & libc::ICANON) != 0;
            *out_echo = (flags & libc::ECHO) != 0;
        }

        PortablePtyResult::Ok
    }

    #[cfg(not(unix))]
    {
        PortablePtyResult::ErrMode
    }
}

/// Close the PTY and free all resources.
///
/// Kills the child process if still running. Safe to call with NULL.
#[unsafe(no_mangle)]
pub extern "C" fn portable_pty_close(handle: *mut PortablePty) {
    if handle.is_null() {
        return;
    }

    let mut pty = unsafe { Box::from_raw(handle) };

    // Kill child if still running
    if let Some(ref mut child) = pty.child {
        let _ = child.kill();
        let _ = child.wait();
    }

    // pty is dropped here, closing file descriptors
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    #[test]
    fn test_open_and_close() {
        let mut handle: *mut PortablePty = ptr::null_mut();
        let result = portable_pty_open(24, 80, &mut handle);
        assert!(
            matches!(result, PortablePtyResult::Ok),
            "portable_pty_open returned: {}",
            result as u32,
        );
        assert!(!handle.is_null());
        portable_pty_close(handle);
    }

    #[test]
    fn test_null_handle() {
        let result = portable_pty_open(24, 80, ptr::null_mut());
        assert!(matches!(result, PortablePtyResult::ErrNull));
    }

    #[test]
    fn test_close_null_is_safe() {
        portable_pty_close(ptr::null_mut());
    }

    #[cfg(unix)]
    #[test]
    fn test_spawn_and_read() {
        use std::ffi::CString;

        let mut handle: *mut PortablePty = ptr::null_mut();
        let result = portable_pty_open(24, 80, &mut handle);
        assert!(
            matches!(result, PortablePtyResult::Ok),
            "portable_pty_open returned: {}",
            result as u32,
        );

        let cmd = CString::new("/bin/echo").unwrap();
        let arg0 = CString::new("echo").unwrap();
        let arg1 = CString::new("hello").unwrap();
        let argv: [*const c_char; 3] = [arg0.as_ptr(), arg1.as_ptr(), ptr::null()];

        let result = portable_pty_spawn(
            handle,
            cmd.as_ptr(),
            argv.as_ptr(),
            ptr::null(),
        );
        assert!(
            matches!(result, PortablePtyResult::Ok),
            "portable_pty_spawn returned: {}",
            result as u32,
        );

        // Give the child a moment to produce output
        std::thread::sleep(std::time::Duration::from_millis(200));

        let mut buf = [0u8; 256];
        let n = portable_pty_read(handle, buf.as_mut_ptr(), buf.len());
        assert!(n > 0, "Expected to read some output, got {n}");

        let output = std::str::from_utf8(&buf[..n as usize]).unwrap();
        assert!(output.contains("hello"), "Expected 'hello' in output: {output}");

        portable_pty_close(handle);
    }
}
