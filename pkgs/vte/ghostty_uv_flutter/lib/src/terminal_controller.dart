library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart'
    show GhosttyTerminalSessionController, GhosttyTerminalShellLaunch;
import 'package:ultraviolet/ultraviolet.dart' as uv;

import 'key_bridge.dart';
import 'pty_session.dart';
import 'terminal_screen.dart';

typedef GhosttyUvWriteSink = int Function(Uint8List data);

/// Controller for a UV-backed terminal session.
class GhosttyUvTerminalController extends ChangeNotifier
    implements GhosttyTerminalSessionController {
  GhosttyUvTerminalController({
    this.initialRows = 24,
    this.initialCols = 80,
    this.maxScrollback = 10_000,
    this.writeSink,
    GhosttyUvPtySession? session,
    GhosttyUvKeyBridge? keyBridge,
    GhosttyUvTerminalScreen? screen,
  }) : _screen =
           screen ??
           GhosttyUvTerminalScreen(
             rows: initialRows,
             cols: initialCols,
             maxScrollback: maxScrollback,
           ),
       _keyBridge = keyBridge ?? GhosttyUvKeyBridge(),
       _session = session;

  final int initialRows;
  final int initialCols;
  final int maxScrollback;
  final GhosttyUvWriteSink? writeSink;

  final GhosttyUvTerminalScreen _screen;
  final GhosttyUvKeyBridge _keyBridge;
  GhosttyUvPtySession? _session;
  StreamSubscription<GhosttyUvPtySessionEvent>? _sessionSub;

  bool _ownsSession = false;
  bool _disposed = false;
  int _revision = 0;
  String? _lastError;
  int? _exitCode;
  GhosttyTerminalShellLaunch? _activeShellLaunch;

  @override
  int get revision => _revision;
  GhosttyUvTerminalScreen get screen => _screen;
  @override
  String get title => _activeShellLaunch?.label ?? 'UV Terminal';
  String get plainText => _screen.plainText;
  String get styledText => _screen.styledText;
  @override
  int get rows => _screen.rows;
  @override
  int get cols => _screen.cols;
  int get cursorX => _screen.cursorX;
  int get cursorY => _screen.cursorY;
  bool get bracketedPasteMode => _screen.bracketedPasteMode;
  @override
  bool get isRunning => _session?.state == GhosttyUvPtySessionState.running;
  String? get lastError => _lastError;
  int? get exitCode => _exitCode;
  GhosttyUvPtySession? get session => _session;
  GhosttyTerminalShellLaunch? get activeShellLaunch => _activeShellLaunch;

  Future<void> start({
    required String command,
    List<String> args = const <String>[],
    Map<String, String>? environment,
    GhosttyUvPtySessionConfig config = const GhosttyUvPtySessionConfig(),
  }) async {
    await _bindSession(
      _session ?? GhosttyUvPtySession(config: config),
      ownsSession: _session == null,
    );
    _activeShellLaunch = _freezeLaunch(
      GhosttyTerminalShellLaunch(
        label: _shellLabel(command),
        shell: command,
        arguments: args,
        environment: environment,
      ),
    );
    _session!.spawn(command, args: args, environment: environment);
    _markDirty();
  }

  Future<void> startLaunch(
    GhosttyTerminalShellLaunch launch, {
    GhosttyUvPtySessionConfig config = const GhosttyUvPtySessionConfig(),
  }) async {
    await start(
      command: launch.shell,
      args: launch.arguments,
      environment: launch.environment,
      config: config,
    );
    _activeShellLaunch = _freezeLaunch(launch);
    final setupCommand = launch.setupCommand;
    if (setupCommand != null && setupCommand.isNotEmpty) {
      write(setupCommand);
    }
    _markDirty();
  }

  Future<void> attachSession(GhosttyUvPtySession session) {
    return _bindSession(session, ownsSession: false);
  }

  Future<void> restart({
    required String command,
    List<String> args = const <String>[],
    Map<String, String>? environment,
    GhosttyUvPtySessionConfig config = const GhosttyUvPtySessionConfig(),
  }) async {
    await stop();
    _screen.reset();
    _lastError = null;
    _exitCode = null;
    await start(
      command: command,
      args: args,
      environment: environment,
      config: config,
    );
  }

  Future<void> restartLaunch(
    GhosttyTerminalShellLaunch launch, {
    GhosttyUvPtySessionConfig config = const GhosttyUvPtySessionConfig(),
  }) async {
    await stop();
    _screen.reset();
    _lastError = null;
    _exitCode = null;
    await startLaunch(launch, config: config);
  }

  Future<void> stop() async {
    await _sessionSub?.cancel();
    _sessionSub = null;

    if (_ownsSession) {
      _session?.close();
      _session = null;
      _ownsSession = false;
    }
    _markDirty();
  }

  void clear() {
    _screen.reset();
    _exitCode = null;
    _lastError = null;
    _markDirty();
  }

  @override
  void resize({required int rows, required int cols}) {
    final checkedRows = rows.clamp(1, 5000);
    final checkedCols = cols.clamp(1, 5000);
    _screen.resize(rows: checkedRows, cols: checkedCols);
    _session?.resize(rows: checkedRows, cols: checkedCols);
    _markDirty();
  }

  void feedOutput(List<int> bytes) {
    _screen.write(Uint8List.fromList(bytes));
    _keyBridge.syncFromScreen(_screen);
    _markDirty();
  }

  @override
  bool write(String text, {bool sanitizePaste = false}) {
    if (sanitizePaste && text.isEmpty) {
      return false;
    }
    final encoded = Uint8List.fromList(utf8.encode(text));
    return writeBytes(encoded);
  }

  bool paste(String text) {
    if (text.isEmpty) {
      return false;
    }
    if (!_screen.bracketedPasteMode) {
      return write(text);
    }
    return writeBytes(
      Uint8List.fromList(utf8.encode('\u001B[200~$text\u001B[201~')),
    );
  }

  @override
  bool writeBytes(List<int> data) {
    final encoded = data is Uint8List ? data : Uint8List.fromList(data);
    final session = _session;
    if (session != null && session.state == GhosttyUvPtySessionState.running) {
      return session.writeBytes(encoded) > 0;
    }
    final sink = writeSink;
    if (sink != null) {
      return sink(encoded) > 0;
    }
    return false;
  }

  bool sendKey(uv.Key key) {
    _keyBridge.syncFromScreen(_screen);
    final bytes = _keyBridge.encode(key);
    if (bytes.isEmpty) {
      return false;
    }
    return writeBytes(bytes);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(stop());
    _keyBridge.close();
    super.dispose();
  }

  Future<void> _bindSession(
    GhosttyUvPtySession session, {
    required bool ownsSession,
  }) async {
    if (identical(_session, session) && _ownsSession == ownsSession) {
      return;
    }

    await _sessionSub?.cancel();
    if (_ownsSession) {
      _session?.close();
    }

    _session = session;
    _ownsSession = ownsSession;
    _sessionSub = session.events.listen(_handleSessionEvent);
  }

  void _handleSessionEvent(GhosttyUvPtySessionEvent event) {
    switch (event) {
      case GhosttyUvPtyOutputEvent(:final data):
        feedOutput(data);
      case GhosttyUvPtyExitEvent(:final exitCode):
        _exitCode = exitCode;
        _markDirty();
      case GhosttyUvPtyErrorEvent(:final error):
        _lastError = error.toString();
        _markDirty();
      case GhosttyUvPtyStateChangeEvent():
        _markDirty();
    }
  }

  void _markDirty() {
    _revision++;
    if (!_disposed) {
      notifyListeners();
    }
  }

  GhosttyTerminalShellLaunch _freezeLaunch(GhosttyTerminalShellLaunch launch) {
    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: List<String>.unmodifiable(launch.arguments),
      environment: launch.environment == null
          ? null
          : Map<String, String>.unmodifiable(launch.environment!),
      setupCommand: launch.setupCommand,
    );
  }

  String _shellLabel(String shell) {
    final parts = shell.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? shell : parts.last;
  }
}
