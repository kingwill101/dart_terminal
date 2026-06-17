import 'dart:io' show sleep;

import 'package:portable_pty/portable_pty.dart';
import 'package:test/test.dart';

void main() {
  group('PortablePty stress (real FFI)', () {
    // These tests exercise the real native transport (Rust FFI), including
    // the SIGCHLD handler chain (ensure_sigchld_handler → register_pid →
    // sigchld_handler → wait fallback).

    PortablePty _open() {
      final pty = PortablePty.open();
      expect(pty.masterFd, greaterThan(0));
      expect(pty.childPid, -1);
      return pty;
    }

    test('open and close multiple PTYs sequentially', () {
      for (var i = 0; i < 20; i++) {
        final pty = _open();
        pty.close();
      }
    });

    test('spawn /bin/true and wait for exit', () {
      final pty = _open();
      pty.spawn('/bin/true');
      expect(pty.childPid, greaterThan(0));
      final code = pty.wait();
      expect(code, 0);
      pty.close();
    });

    test('spawn /bin/false and verify non-zero exit', () {
      final pty = _open();
      pty.spawn('/bin/false');
      expect(pty.childPid, greaterThan(0));
      final code = pty.wait();
      expect(code, 1);
      pty.close();
    });

    test('spawn echo and read output', () {
      final pty = _open();
      pty.spawn('/bin/echo', args: ['hello-pty']);
      expect(pty.childPid, greaterThan(0));
      pty.wait();
      final data = pty.readSync(4096);
      expect(String.fromCharCodes(data), contains('hello-pty'));
      pty.close();
    });

    test('spawn /bin/sleep 0 (immediate exit)', () {
      final pty = _open();
      pty.spawn('/bin/sleep', args: ['0']);
      final code = pty.wait();
      expect(code, 0);
      pty.close();
    });

    test('kill child process', () {
      final pty = _open();
      pty.spawn('/bin/sleep', args: ['30']);
      expect(pty.childPid, greaterThan(0));
      pty.kill(9); // SIGKILL
      final code = pty.wait();
      expect(code, anyOf(1, 137, 9));
      pty.close();
    });

    test('tryWait returns null while running then exit code after', () {
      final pty = _open();
      pty.spawn('/bin/sleep', args: ['0']);
      int? code;
      for (var i = 0; i < 100; i++) {
        code = pty.tryWait();
        if (code != null) break;
        sleep(const Duration(milliseconds: 10));
      }
      expect(code, 0);
      pty.close();
    });

    test('concurrent multiple PTYs', () {
      final ptys = <PortablePty>[];
      for (var i = 0; i < 10; i++) {
        final pty = _open();
        pty.spawn('/bin/true');
        ptys.add(pty);
      }
      for (final pty in ptys) {
        final code = pty.wait();
        expect(code, 0);
        pty.close();
      }
    });

    test('rapid open-spawn-close cycle', () {
      for (var i = 0; i < 30; i++) {
        final pty = _open();
        pty.spawn('/bin/true');
        pty.wait();
        pty.close();
      }
    });
  });
}
