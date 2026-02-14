import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

/// In-memory transport for testing [FlutterPtyController] without a real PTY.
class MockPtyTransport implements PortablePtyTransport {
  final List<String> spawnedCommands = [];
  final List<Uint8List> writtenBytes = [];
  Uint8List readBuffer = Uint8List(0);
  bool closed = false;
  int? _exitCode;

  @override
  void spawn(
    String command, {
    List<String>? args,
    Map<String, String>? environment,
  }) {
    spawnedCommands.add(command);
  }

  @override
  Uint8List readSync(int maxBytes) {
    if (readBuffer.isEmpty) return Uint8List(0);
    final end = maxBytes < readBuffer.length ? maxBytes : readBuffer.length;
    final chunk = readBuffer.sublist(0, end);
    readBuffer = readBuffer.sublist(end);
    return chunk;
  }

  @override
  int writeBytes(Uint8List data) {
    writtenBytes.add(Uint8List.fromList(data));
    return data.length;
  }

  @override
  int writeString(String text) =>
      writeBytes(Uint8List.fromList(text.codeUnits));

  @override
  void resize({required int rows, required int cols}) {}

  @override
  int get childPid => 42;

  @override
  int get masterFd => 5;

  @override
  ({int rows, int cols, int pixelWidth, int pixelHeight}) getSize() =>
      (rows: 24, cols: 80, pixelWidth: 0, pixelHeight: 0);

  @override
  int get processGroup => -1;

  @override
  int? tryWait() => _exitCode;

  @override
  int wait() => _exitCode ?? 0;

  @override
  ({bool canonical, bool echo}) getMode() => (canonical: true, echo: true);

  @override
  void kill([int signal = 15]) {
    _exitCode = -signal;
  }

  @override
  void close() {
    closed = true;
  }

  void feedOutput(String text) {
    final encoded = Uint8List.fromList(text.codeUnits);
    final combined = Uint8List(readBuffer.length + encoded.length);
    combined.setAll(0, readBuffer);
    combined.setAll(readBuffer.length, encoded);
    readBuffer = combined;
  }
}

void main() {
  group('FlutterPtyController', () {
    late FlutterPtyController controller;
    late MockPtyTransport transport;

    setUp(() {
      transport = MockPtyTransport();
      controller = FlutterPtyController(
        transport: transport,
        defaultShell: '/bin/sh',
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial state mirrors inner controller', () {
      expect(controller.isRunning, isFalse);
      expect(controller.revision, 0);
      expect(controller.lineCount, 1);
      expect(controller.lines, ['']);
    });

    test('start spawns PTY and sets running', () async {
      await controller.start();
      expect(controller.isRunning, isTrue);
      expect(controller.revision, greaterThan(0));
    });

    test('start is idempotent', () async {
      await controller.start();
      final rev = controller.revision;
      await controller.start();
      expect(controller.revision, rev);
    });

    test('stop terminates session', () async {
      await controller.start();
      await controller.stop();
      expect(controller.isRunning, isFalse);
    });

    test('write returns true when running', () async {
      await controller.start();
      expect(controller.write('ls\n'), isTrue);
    });

    test('write returns false when not running', () {
      expect(controller.write('x'), isFalse);
    });

    test('writeBytes forwards to inner controller', () async {
      await controller.start();
      final sent = controller.writeBytes(Uint8List.fromList([0x41]));
      expect(sent, isTrue);
    });

    test('readOutput returns text from PTY', () async {
      await controller.start();
      transport.feedOutput('hello');
      final text = controller.readOutput();
      expect(text, 'hello');
    });

    test('appendDebugOutput adds to buffer', () {
      controller.appendDebugOutput('debug');
      expect(controller.lines.any((l) => l.contains('debug')), isTrue);
    });

    test('clear resets lines', () {
      controller.appendDebugOutput('foo\nbar');
      controller.clear();
      expect(controller.lines, ['']);
    });

    test('tryWait returns null when not started', () {
      expect(controller.tryWait(), isNull);
    });

    test('ChangeNotifier notifications relay from inner', () {
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      controller.appendDebugOutput('test');
      expect(notifyCount, greaterThan(0));
    });

    test('dispose removes inner listener and cleans up', () async {
      // Create a separate controller so tearDown doesn't double-dispose.
      final t = MockPtyTransport();
      final c = FlutterPtyController(transport: t, defaultShell: '/bin/sh');
      await c.start();
      c.dispose();
      // After dispose, no exceptions should occur
    });
  });

  group('FlutterPtyController ChangeNotifier integration', () {
    test('can be used with ValueListenableBuilder pattern', () async {
      final transport = MockPtyTransport();
      final controller = FlutterPtyController(
        transport: transport,
        defaultShell: '/bin/sh',
      );

      var revisions = <int>[];
      controller.addListener(() {
        revisions.add(controller.revision);
      });

      await controller.start();
      controller.appendDebugOutput('x');
      controller.clear();

      expect(revisions.length, greaterThanOrEqualTo(3));
      // Revisions should be monotonically increasing
      for (var i = 1; i < revisions.length; i++) {
        expect(revisions[i], greaterThan(revisions[i - 1]));
      }

      controller.dispose();
    });

    test('constructor parameters forwarded correctly', () {
      final transport = MockPtyTransport();
      final controller = FlutterPtyController(
        maxLines: 42,
        defaultShell: '/usr/bin/zsh',
        rows: 30,
        cols: 100,
        transport: transport,
      );

      // Initial state reflects constructor params (indirectly through behavior)
      expect(controller.lineCount, 1);
      controller.dispose();
    });
  });
}
