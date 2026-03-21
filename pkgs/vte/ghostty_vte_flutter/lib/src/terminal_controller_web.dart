import 'package:flutter/foundation.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

import 'pty_session.dart';
import 'shell_launch.dart';
import 'terminal_snapshot.dart';
import 'terminal_surface_contract.dart';

/// Web-compatible terminal controller.
///
/// This keeps a real [VtTerminal] alive on web but does not spawn local
/// processes. It is intended to be connected to a remote transport by feeding
/// output via [appendDebugOutput] and sending input through [write]/[sendKey].
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

  final int maxLines;
  final int maxScrollback;
  final int initialCols;
  final int initialRows;

  /// Placeholder for API parity with native controller construction.
  final bool preferPty;

  /// Optional shell hint for remote backends.
  final String? defaultShell;

  VtTerminal? _terminal;
  VtTerminalFormatter? _plainFormatter;
  VtTerminalFormatter? _styledFormatter;
  VtKeyEncoder? _encoder;
  GhosttyTerminalShellLaunch? _activeShellLaunch;

  final List<String> _lines = <String>[''];
  String _plainText = '';
  GhosttyTerminalSnapshot _snapshot = const GhosttyTerminalSnapshot.empty();
  String _title = 'Terminal (Web)';
  bool _running = false;
  int _revision = 0;
  int _cols;
  int _rows;

  @override
  int get revision => _revision;
  @override
  String get title => _title;
  @override
  bool get isRunning => _running;
  @override
  int get cols => _cols;
  @override
  int get rows => _rows;
  VtTerminal get terminal => _ensureTerminal();
  String get plainText => _plainText;
  GhosttyTerminalSnapshot get snapshot => _snapshot;
  List<String> get lines => List<String>.unmodifiable(_lines);
  int get lineCount => _lines.length;
  GhosttyTerminalShellLaunch? get activeShellLaunch => _activeShellLaunch;
  GhosttyTerminalPtySession? get ptySession => null;

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

  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
    Map<String, String>? environment,
  }) async {
    if (_running) {
      return;
    }
    _ensureTerminal();
    final resolvedShell = shell ?? defaultShell ?? 'web transport demo';
    _activeShellLaunch = GhosttyTerminalShellLaunch(
      label: resolvedShell,
      shell: resolvedShell,
      arguments: List<String>.unmodifiable(arguments),
      environment: environment == null
          ? null
          : Map<String, String>.unmodifiable(environment),
    );
    _running = true;
    _markDirty();
  }

  /// Starts a resolved launch plan and stores its metadata on the controller.
  Future<void> startLaunch(GhosttyTerminalShellLaunch launch) async {
    await start(
      shell: launch.shell,
      arguments: launch.arguments,
      environment: launch.environment,
    );
    _activeShellLaunch = GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: List<String>.unmodifiable(launch.arguments),
      environment: launch.environment == null
          ? null
          : Map<String, String>.unmodifiable(launch.environment!),
      setupCommand: launch.setupCommand,
    );
    _markDirty();
  }

  /// Restarts the controller using a resolved launch plan.
  Future<void> restartLaunch(GhosttyTerminalShellLaunch launch) async {
    await stop();
    await startLaunch(launch);
  }

  /// Web keeps transport setup separate, so profile starts are a no-op wrapper.
  Future<GhosttyTerminalShellLaunch?> startShellProfile({
    required GhosttyTerminalShellProfile profile,
    Map<String, String>? platformEnvironment,
    Map<String, String> environmentOverrides = const <String, String>{
      'TERM': 'xterm-256color',
    },
  }) async {
    final launches = ghosttyTerminalShellLaunches(
      profile: profile,
      platformEnvironment: platformEnvironment,
      environmentOverrides: environmentOverrides,
    );
    if (launches.isNotEmpty) {
      await startLaunch(launches.first);
      return activeShellLaunch;
    }
    await start();
    return activeShellLaunch;
  }

  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    _markDirty();
  }

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
      _refreshSnapshot();
    }
    _markDirty();
  }

  @override
  bool write(String text, {bool sanitizePaste = false}) {
    if (!_running) {
      return false;
    }
    if (sanitizePaste && !GhosttyVt.isPasteSafe(text)) {
      return false;
    }
    // Placeholder for a transport write. The remote side should eventually
    // feed output back through appendDebugOutput/bytes.
    return true;
  }

  @override
  bool writeBytes(List<int> bytes) {
    if (!_running) {
      return false;
    }
    return true;
  }

  bool sendKey({
    required GhosttyKey key,
    GhosttyKeyAction action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
    int mods = 0,
    int consumedMods = 0,
    bool composing = false,
    String utf8Text = '',
    int unshiftedCodepoint = 0,
  }) {
    if (!_running) {
      return false;
    }

    _encoder ??= VtKeyEncoder();
    final terminal = _terminal;
    if (terminal != null) {
      _encoder!.setOptionsFromTerminal(terminal);
    }

    final event = VtKeyEvent()
      ..action = action
      ..key = key
      ..mods = mods
      ..consumedMods = consumedMods
      ..composing = composing
      ..utf8Text = utf8Text
      ..unshiftedCodepoint = unshiftedCodepoint;
    final encoded = _encoder!.encode(event);
    event.close();
    return encoded.isNotEmpty;
  }

  void appendDebugOutput(String text) {
    if (text.isEmpty) {
      return;
    }
    _consumeOscText(text);
    _ensureTerminal().write(text);
    _refreshSnapshot();
    _markDirty();
  }

  void _consumeOscText(String text) {
    for (final match in _oscRegex.allMatches(text)) {
      final payload = match.group(1);
      if (payload == null || payload.isEmpty) {
        continue;
      }
      final separator = payload.indexOf(';');
      if (separator <= 0 || separator >= payload.length - 1) {
        continue;
      }
      final code = payload.substring(0, separator);
      final data = payload.substring(separator + 1);
      if ((code == '0' || code == '2') && data.isNotEmpty) {
        _title = data;
      }
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
    notifyListeners();
  }

  @override
  void dispose() {
    _encoder?.close();
    _styledFormatter?.close();
    _plainFormatter?.close();
    _terminal?.close();
    _running = false;
    super.dispose();
  }
}

final RegExp _oscRegex = RegExp(r'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)');
