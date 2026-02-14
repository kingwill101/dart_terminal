import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

/// Controller for a terminal session backed by a subprocess.
///
/// On Unix-like platforms this prefers spawning via `script` to get PTY-like
/// behavior. If that fails, it falls back to a regular process.
///
/// This class parses terminal output into a simple line buffer to keep rendering
/// dependencies small and to support lightweight terminal previews.
///
/// ```dart
/// final controller = GhosttyTerminalController();
/// controller.addListener(() {
///   print('Output lines: ${controller.lineCount}');
/// });
///
/// await controller.start(shell: '/bin/bash');
/// controller.write('echo hello\n');
///
/// // Later…
/// await controller.stop();
/// controller.dispose();
/// ```
class GhosttyTerminalController extends ChangeNotifier {
  /// Creates a native terminal controller with optional PTY and shell options.
  GhosttyTerminalController({
    this.maxLines = 2000,
    this.preferPty = true,
    this.defaultShell,
  }) : assert(maxLines > 0);

  /// Maximum retained line count in the in-memory terminal buffer.
  final int maxLines;

  /// Whether to attempt PTY launch (via `script`) when possible.
  final bool preferPty;

  /// Optional default shell path for [start].
  final String? defaultShell;

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  StreamSubscription<int>? _exitSub;

  final List<String> _lines = <String>[''];
  String _title = 'Terminal';
  bool _running = false;
  bool _disposed = false;
  int _revision = 0;

  VtKeyEncoder? _encoder;

  /// Monotonic value that increments whenever buffered output/state changes.
  int get revision => _revision;

  /// Terminal title (updated from OSC commands when available).
  String get title => _title;

  /// Whether a subprocess is currently active.
  bool get isRunning => _running;

  /// Current buffered terminal lines.
  List<String> get lines => List<String>.unmodifiable(_lines);

  /// Number of buffered lines.
  int get lineCount => _lines.length;

  /// Starts a terminal subprocess.
  ///
  /// If [shell] is omitted, falls back to [defaultShell] or the system
  /// default (`$SHELL`, or `/bin/bash`).
  ///
  /// ```dart
  /// await controller.start(shell: '/bin/zsh', arguments: ['-l']);
  /// ```
  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
  }) async {
    if (_running) {
      return;
    }

    final resolvedShell = shell ?? defaultShell ?? _defaultShell();
    final process = await _spawnProcess(resolvedShell, arguments);
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

  /// Stops the subprocess if running.
  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      return;
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    await _exitSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _exitSub = null;

    process.kill(ProcessSignal.sigterm);
    _process = null;
    _running = false;
    _markDirty();
  }

  /// Clears the buffered output.
  void clear() {
    _lines
      ..clear()
      ..add('');
    _markDirty();
  }

  /// Writes raw text to terminal stdin.
  ///
  /// Returns `true` if written, `false` if the terminal isn't running or
  /// [sanitizePaste] is true and the text is unsafe per Ghostty paste rules.
  ///
  /// ```dart
  /// final sent = controller.write('ls -la\n');
  /// if (!sent) print('terminal not running');
  /// ```
  bool write(String text, {bool sanitizePaste = false}) {
    final process = _process;
    if (process == null) {
      return false;
    }

    if (sanitizePaste && !GhosttyVt.isPasteSafe(text)) {
      return false;
    }

    process.stdin.add(utf8.encode(text));
    return true;
  }

  /// Writes raw bytes directly to terminal stdin.
  bool writeBytes(List<int> bytes) {
    final process = _process;
    if (process == null) {
      return false;
    }
    process.stdin.add(bytes);
    return true;
  }

  /// Encodes and sends a key event using Ghostty key encoding.
  ///
  /// Returns `true` if the encoded bytes were sent to the subprocess.
  ///
  /// ```dart
  /// controller.sendKey(
  ///   key: GhosttyKey.GHOSTTY_KEY_ENTER,
  ///   mods: GhosttyModsMask.ctrl,
  /// );
  /// ```
  bool sendKey({
    required GhosttyKey key,
    GhosttyKeyAction action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
    int mods = 0,
    int consumedMods = 0,
    bool composing = false,
    String utf8Text = '',
    int unshiftedCodepoint = 0,
  }) {
    final process = _process;
    if (process == null) {
      return false;
    }

    _encoder ??= VtKeyEncoder();

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
      process.stdin.add(encoded);
      return true;
    } finally {
      event.close();
    }
  }

  /// Test/debug helper to inject terminal output text directly.
  ///
  /// ```dart
  /// controller.appendDebugOutput('\$ whoami\nuser\n');
  /// ```
  void appendDebugOutput(String text) {
    _ingestText(text);
  }

  void _onProcessBytes(List<int> bytes) {
    _ingestText(utf8.decode(bytes, allowMalformed: true));
  }

  void _ingestText(String text) {
    var chunk = text;
    chunk = _consumeOscAndStrip(chunk);
    chunk = _stripAnsi(chunk);
    _appendToBuffer(chunk);
    _markDirty();
  }

  String _consumeOscAndStrip(String text) {
    return text.replaceAllMapped(_oscRegex, (match) {
      final payload = match.group(1);
      if (payload != null && payload.isNotEmpty) {
        _consumeOscPayload(payload);
      }
      return '';
    });
  }

  void _consumeOscPayload(String payload) {
    final separator = payload.indexOf(';');
    if (separator <= 0 || separator >= payload.length - 1) {
      return;
    }
    final code = payload.substring(0, separator);
    final data = payload.substring(separator + 1);
    // OSC 0 and 2 both represent window title updates in common terminals.
    if ((code == '0' || code == '2') && data.isNotEmpty) {
      _title = data;
    }
  }

  String _stripAnsi(String text) {
    var out = text;
    out = out.replaceAll(_csiRegex, '');
    out = out.replaceAll(_singleEscapeRegex, '');
    return out;
  }

  void _appendToBuffer(String text) {
    if (_lines.isEmpty) {
      _lines.add('');
    }

    for (final rune in text.runes) {
      switch (rune) {
        case 0x0A: // \n
          _lines.add('');
          break;
        case 0x0D: // \r
          _lines[_lines.length - 1] = '';
          break;
        case 0x08: // \b
          final current = _lines[_lines.length - 1];
          if (current.isNotEmpty) {
            _lines[_lines.length - 1] = current.substring(
              0,
              current.length - 1,
            );
          }
          break;
        default:
          _lines[_lines.length - 1] += String.fromCharCode(rune);
          break;
      }
    }

    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  void _markDirty() {
    _revision++;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<Process> _spawnProcess(String shell, List<String> arguments) async {
    if (preferPty && (Platform.isLinux || Platform.isMacOS)) {
      final command = _shellJoin(<String>[shell, ...arguments]);
      try {
        return await Process.start('script', <String>[
          '-qefc',
          command,
          '/dev/null',
        ]);
      } on ProcessException {
        // Fall back to direct process launch below.
      }
    }

    return Process.start(shell, arguments, runInShell: true);
  }

  String _defaultShell() {
    if (Platform.isWindows) {
      return 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/bash';
  }

  String _shellJoin(List<String> parts) {
    return parts.map(_shellEscape).join(' ');
  }

  String _shellEscape(String value) {
    final escaped = value.replaceAll("'", "'\"'\"'");
    return "'$escaped'";
  }

  @override
  void dispose() {
    _disposed = true;
    _encoder?.close();
    unawaited(stop());
    super.dispose();
  }
}

final RegExp _oscRegex = RegExp(r'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)');
final RegExp _csiRegex = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');
final RegExp _singleEscapeRegex = RegExp(r'\x1b[@-Z\\-_]');
