import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

import 'pty_session.dart';
import 'shell_launch.dart';
import 'terminal_snapshot.dart';
import 'terminal_surface_contract.dart';

/// Controller for a terminal session backed by a subprocess.
///
/// On supported native platforms this prefers a shared PTY session backed by
/// `portable_pty`. If that is disabled, it falls back to a regular process.
///
/// Unlike the earlier preview-oriented controller, this controller keeps a real
/// [VtTerminal] alive and derives visible text from formatter snapshots so
/// cursor movement, clears, wrapping, and other VT semantics are preserved.
class GhosttyTerminalController extends ChangeNotifier
    implements GhosttyTerminalSessionController {
  GhosttyTerminalController({
    this.maxLines = 2000,
    this.maxScrollback = 10_000,
    this.initialCols = 80,
    this.initialRows = 24,
    this.preferPty = true,
    this.defaultShell,
  }) : assert(maxLines > 0),
       assert(maxScrollback >= 0),
       assert(initialCols > 0),
       assert(initialRows > 0),
       _cols = initialCols,
       _rows = initialRows;

  /// Maximum retained line count in the formatted terminal snapshot.
  final int maxLines;

  /// Maximum terminal scrollback depth retained by [VtTerminal].
  final int maxScrollback;

  /// Initial terminal width in cells before the view reports a real size.
  final int initialCols;

  /// Initial terminal height in cells before the view reports a real size.
  final int initialRows;

  /// Whether to attempt a native PTY launch when possible.
  final bool preferPty;

  /// Optional default shell path for [start].
  final String? defaultShell;

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  StreamSubscription<int>? _exitSub;
  GhosttyTerminalPtySession? _ptySession;
  StreamSubscription<GhosttyTerminalPtySessionEvent>? _ptySessionSub;

  VtTerminal? _terminal;
  VtTerminalFormatter? _plainFormatter;
  VtTerminalFormatter? _styledFormatter;
  VtKeyEncoder? _encoder;
  GhosttyTerminalShellLaunch? _activeShellLaunch;

  final List<String> _lines = <String>[''];
  String _plainText = '';
  GhosttyTerminalSnapshot _snapshot = const GhosttyTerminalSnapshot.empty();
  String _title = 'Terminal';
  bool _running = false;
  bool _disposed = false;
  int _revision = 0;
  int _cols;
  int _rows;

  /// Monotonic value that increments whenever buffered output/state changes.
  @override
  int get revision => _revision;

  /// Terminal title (updated from OSC commands when available).
  @override
  String get title => _title;

  /// Whether a subprocess is currently active.
  @override
  bool get isRunning => _running;

  /// Current terminal width in cells.
  @override
  int get cols => _cols;

  /// Current terminal height in cells.
  @override
  int get rows => _rows;

  /// Live VT terminal state backing this controller.
  VtTerminal get terminal => _ensureTerminal();

  /// Current formatted plain-text terminal snapshot.
  String get plainText => _plainText;

  /// Current styled terminal snapshot used by [GhosttyTerminalView].
  GhosttyTerminalSnapshot get snapshot => _snapshot;

  /// Most recent shell launch metadata associated with this controller.
  GhosttyTerminalShellLaunch? get activeShellLaunch => _activeShellLaunch;

  /// Active native PTY session when the shared PTY backend is in use.
  GhosttyTerminalPtySession? get ptySession => _ptySession;

  /// Current buffered terminal lines.
  List<String> get lines => List<String>.unmodifiable(_lines);

  /// Number of buffered lines.
  int get lineCount => _lines.length;

  VtTerminal _ensureTerminal() {
    final existing = _terminal;
    if (existing != null) {
      return existing;
    }

    final terminal = GhosttyVt.newTerminal(
      cols: _cols,
      rows: _rows,
      maxScrollback: maxScrollback,
    );
    final formatter = terminal.createFormatter();
    final styledFormatter = terminal.createFormatter(
      const VtFormatterTerminalOptions(
        emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_VT,
        trim: false,
        extra: VtFormatterTerminalExtra(
          screen: VtFormatterScreenExtra(
            cursor: true,
            style: true,
            hyperlink: true,
            protection: true,
            charsets: true,
          ),
        ),
      ),
    );
    _terminal = terminal;
    _plainFormatter = formatter;
    _styledFormatter = styledFormatter;
    _refreshSnapshot();
    return terminal;
  }

  /// Returns a formatted terminal snapshot using the requested formatter mode.
  String formatTerminal({
    GhosttyFormatterFormat emit =
        GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_PLAIN,
    bool unwrap = false,
    bool trim = true,
    VtFormatterTerminalExtra extra = const VtFormatterTerminalExtra(),
  }) {
    final terminal = _ensureTerminal();
    final formatter = terminal.createFormatter(
      VtFormatterTerminalOptions(
        emit: emit,
        unwrap: unwrap,
        trim: trim,
        extra: extra,
      ),
    );
    try {
      return formatter.formatText();
    } finally {
      formatter.close();
    }
  }

  /// Starts a terminal subprocess.
  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
    Map<String, String>? environment,
  }) async {
    if (_running) {
      return;
    }

    _ensureTerminal();

    final resolvedShell = shell ?? defaultShell ?? _defaultShell();
    _activeShellLaunch = _freezeLaunch(
      GhosttyTerminalShellLaunch(
        label: _shellLabel(resolvedShell),
        shell: resolvedShell,
        arguments: arguments,
        environment: environment,
      ),
    );

    if (_canUsePtyBackend()) {
      final session = GhosttyTerminalPtySession(
        config: GhosttyTerminalPtySessionConfig(rows: _rows, cols: _cols),
      );
      _ptySession = session;
      _ptySessionSub = session.events.listen(_onPtyEvent);
      session.spawn(resolvedShell, args: arguments, environment: environment);
      _running = true;
      _markDirty();
      return;
    }

    final process = await _spawnProcess(
      resolvedShell,
      arguments,
      environment: environment,
    );
    _process = process;
    _running = true;
    _markDirty();

    _stdoutSub = process.stdout.listen(_onProcessBytes);
    _stderrSub = process.stderr.listen(_onProcessBytes);
    _exitSub = process.exitCode.asStream().listen((exitCode) {
      _running = false;
      appendDebugOutput('\n[process exited: $exitCode]\n');
      _markDirty();
    });
  }

  void _onPtyEvent(GhosttyTerminalPtySessionEvent event) {
    switch (event) {
      case GhosttyTerminalPtyOutputEvent(:final data):
        _onProcessBytes(data);
      case GhosttyTerminalPtyExitEvent(:final exitCode):
        _running = false;
        appendDebugOutput('\n[process exited: $exitCode]\n');
        _markDirty();
      case GhosttyTerminalPtyErrorEvent():
        _markDirty();
      case GhosttyTerminalPtyStateChangeEvent(:final current):
        if (current != GhosttyTerminalPtySessionState.running) {
          _running = false;
        }
        _markDirty();
    }
  }

  /// Starts a resolved launch plan and stores its metadata on the controller.
  Future<void> startLaunch(GhosttyTerminalShellLaunch launch) async {
    await start(
      shell: launch.shell,
      arguments: launch.arguments,
      environment: launch.environment,
    );
    _activeShellLaunch = _freezeLaunch(launch);
    final setupCommand = launch.setupCommand;
    if (setupCommand != null && setupCommand.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      write(setupCommand);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    _markDirty();
  }

  /// Restarts the controller using a resolved launch plan.
  Future<void> restartLaunch(GhosttyTerminalShellLaunch launch) async {
    await stop();
    await startLaunch(launch);
  }

  /// Starts one of the shared shell profiles and returns the resolved launch.
  ///
  /// Returns `null` when no launch candidate was available or every candidate
  /// failed to start.
  Future<GhosttyTerminalShellLaunch?> startShellProfile({
    required GhosttyTerminalShellProfile profile,
    Map<String, String>? platformEnvironment,
    Map<String, String> environmentOverrides = const <String, String>{
      'TERM': 'xterm-256color',
    },
  }) async {
    Object? lastError;
    for (final launch in ghosttyTerminalShellLaunches(
      profile: profile,
      platformEnvironment: platformEnvironment,
      environmentOverrides: environmentOverrides,
    )) {
      try {
        await startLaunch(launch);
        return activeShellLaunch;
      } catch (error) {
        lastError = error;
        await stop();
      }
    }

    if (lastError != null) {
      appendDebugOutput('[shell profile failed: $lastError]\n');
    }
    return null;
  }

  /// Stops the subprocess if running.
  Future<void> stop() async {
    final process = _process;
    final session = _ptySession;
    if (process == null && session == null) {
      return;
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    await _exitSub?.cancel();
    await _ptySessionSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _exitSub = null;
    _ptySessionSub = null;

    process?.kill(ProcessSignal.sigterm);
    session?.close();
    _process = null;
    _ptySession = null;
    _running = false;
    _markDirty();
  }

  /// Clears terminal contents and scrollback while preserving dimensions.
  void clear() {
    final terminal = _terminal;
    if (terminal == null) {
      _lines
        ..clear()
        ..add('');
      _plainText = '';
      _markDirty();
      return;
    }

    terminal.reset();
    _refreshSnapshot();
    _markDirty();
  }

  /// Resizes the VT grid.
  @override
  void resize({required int cols, required int rows}) {
    final checkedCols = cols.clamp(1, 0xFFFF);
    final checkedRows = rows.clamp(1, 0xFFFF);
    if (checkedCols == _cols && checkedRows == _rows) {
      return;
    }

    _cols = checkedCols;
    _rows = checkedRows;

    final terminal = _terminal;
    if (terminal != null) {
      terminal.resize(cols: checkedCols, rows: checkedRows);
      _ptySession?.resize(rows: checkedRows, cols: checkedCols);
      _refreshSnapshot();
    }
    _markDirty();
  }

  /// Writes raw text to terminal stdin.
  @override
  bool write(String text, {bool sanitizePaste = false}) {
    if (sanitizePaste && !GhosttyVt.isPasteSafe(text)) {
      return false;
    }

    final session = _ptySession;
    if (session != null) {
      return session.write(text) > 0;
    }

    final process = _process;
    if (process == null) {
      return false;
    }
    process.stdin.add(utf8.encode(text));
    return true;
  }

  /// Writes raw bytes directly to terminal stdin.
  @override
  bool writeBytes(List<int> bytes) {
    final session = _ptySession;
    if (session != null) {
      return session.writeBytes(Uint8List.fromList(bytes)) > 0;
    }

    final process = _process;
    if (process == null) {
      return false;
    }
    process.stdin.add(bytes);
    return true;
  }

  /// Encodes and sends a key event using Ghostty key encoding.
  bool sendKey({
    required GhosttyKey key,
    GhosttyKeyAction action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
    int mods = 0,
    int consumedMods = 0,
    bool composing = false,
    String utf8Text = '',
    int unshiftedCodepoint = 0,
  }) {
    if (_process == null && _ptySession == null) {
      return false;
    }

    _encoder ??= VtKeyEncoder();
    final terminal = _terminal;
    if (terminal != null) {
      _encoder!.setOptionsFromTerminal(terminal);
    }

    final event = VtKeyEvent();
    try {
      event
        ..action = action
        ..key = key
        ..mods = mods
        ..consumedMods = consumedMods
        ..composing = composing
        ..utf8Text = utf8Text
        ..unshiftedCodepoint = unshiftedCodepoint;
      final encoded = _encoder!.encode(event);
      return writeBytes(encoded);
    } finally {
      event.close();
    }
  }

  /// Test/debug helper to inject terminal output text directly.
  void appendDebugOutput(String text) {
    _ingestBytes(utf8.encode(text), decodedText: text);
  }

  void _onProcessBytes(List<int> bytes) {
    _ingestBytes(bytes, decodedText: utf8.decode(bytes, allowMalformed: true));
  }

  void _ingestBytes(List<int> bytes, {required String decodedText}) {
    if (bytes.isEmpty) {
      return;
    }

    _consumeOscText(decodedText);
    _ensureTerminal().writeBytes(bytes);
    _refreshSnapshot();
    _markDirty();
  }

  void _consumeOscText(String text) {
    for (final match in _oscRegex.allMatches(text)) {
      final payload = match.group(1);
      if (payload != null && payload.isNotEmpty) {
        _consumeOscPayload(payload);
      }
    }
  }

  void _consumeOscPayload(String payload) {
    final separator = payload.indexOf(';');
    if (separator <= 0 || separator >= payload.length - 1) {
      return;
    }
    final code = payload.substring(0, separator);
    final data = payload.substring(separator + 1);
    if ((code == '0' || code == '2') && data.isNotEmpty) {
      _title = data;
    }
  }

  void _refreshSnapshot() {
    final formatter = _plainFormatter;
    final styledFormatter = _styledFormatter;
    if (formatter == null || styledFormatter == null) {
      _plainText = '';
      _lines
        ..clear()
        ..add('');
      _snapshot = const GhosttyTerminalSnapshot.empty();
      return;
    }

    final text = formatter.formatText();
    _plainText = text;

    final parts = text.isEmpty ? <String>[''] : text.split('\n');
    _lines
      ..clear()
      ..addAll(
        parts.length > maxLines
            ? parts.sublist(parts.length - maxLines)
            : parts,
      );
    if (_lines.isEmpty) {
      _lines.add('');
    }
    _snapshot = GhosttyTerminalSnapshot.fromFormattedVt(
      styledFormatter.formatText(),
      maxLines: maxLines,
    );
  }

  void _markDirty() {
    _revision++;
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _canUsePtyBackend() {
    if (!preferPty) {
      return false;
    }
    return Platform.isLinux || Platform.isMacOS;
  }

  Future<Process> _spawnProcess(
    String shell,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    return Process.start(
      shell,
      arguments,
      runInShell: true,
      environment: environment,
    );
  }

  String _defaultShell() {
    if (Platform.isWindows) {
      return 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/bash';
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

  Future<void> _disposeAsync() async {
    await stop();
    _encoder?.close();
    _encoder = null;
    _plainFormatter?.close();
    _plainFormatter = null;
    _styledFormatter?.close();
    _styledFormatter = null;
    _terminal?.close();
    _terminal = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_disposeAsync());
    super.dispose();
  }
}

final RegExp _oscRegex = RegExp(r'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)');
