import 'package:flutter/foundation.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

/// Web-compatible terminal controller.
///
/// This provides the same API surface as the native controller but does not
/// spawn local processes. It is intended to be connected to a remote transport
/// (WebSocket/SSH proxy) by feeding output via [appendDebugOutput] and sending
/// input through [write]/[sendKey].
/// 
/// The default implementation keeps an internal line buffer so widgets can render
/// incremental output without a full terminal emulation dependency.
class GhosttyTerminalController extends ChangeNotifier {
  /// Creates a web terminal controller.
  GhosttyTerminalController({
    this.maxLines = 2000,
    this.preferPty = true,
    this.defaultShell,
  }) : assert(maxLines > 0);

  final int maxLines;
  /// Optional hard cap on the number of cached lines.
  final bool preferPty;
  /// Optional shell override when wiring remote endpoints.
  final String? defaultShell;

  final List<String> _lines = <String>[''];
  String _title = 'Terminal (Web)';
  bool _running = false;
  int _revision = 0;

  VtKeyEncoder? _encoder;

  int get revision => _revision;
  String get title => _title;
  bool get isRunning => _running;
  List<String> get lines => List<String>.unmodifiable(_lines);
  int get lineCount => _lines.length;

  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
  }) async {
    if (_running) {
      return;
    }
    _running = true;
    _appendLine('[web] terminal started (attach remote backend)');
    _markDirty();
  }

  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    _appendLine('[web] terminal stopped');
    _markDirty();
  }

  void clear() {
    _lines
      ..clear()
      ..add('');
    _markDirty();
  }

  bool write(String text, {bool sanitizePaste = false}) {
    if (!_running) {
      return false;
    }
    if (sanitizePaste && !GhosttyVt.isPasteSafe(text)) {
      return false;
    }
    // On web this is a placeholder for transport write.
    _appendLine('[stdin] $text');
    _markDirty();
    return true;
  }

  bool writeBytes(List<int> bytes) {
    if (!_running) {
      return false;
    }
    _appendLine('[stdin bytes] ${bytes.length}');
    _markDirty();
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

    final event = VtKeyEvent()
      ..action = action
      ..key = key
      ..mods = mods
      ..consumedMods = consumedMods
      ..composing = composing
      ..utf8Text = utf8Text
      ..unshiftedCodepoint = unshiftedCodepoint;

    _encoder ??= VtKeyEncoder();
    final encoded = _encoder!.encode(event);
    event.close();
    _appendLine('[key] ${encoded.length} bytes');
    _markDirty();
    return true;
  }

  void appendDebugOutput(String text) {
    _ingestText(text);
  }

  void _ingestText(String text) {
    var chunk = text;
    chunk = chunk.replaceAllMapped(_oscRegex, (match) {
      final payload = match.group(1);
      if (payload != null) {
        final separator = payload.indexOf(';');
        if (separator > 0 && separator < payload.length - 1) {
          final code = payload.substring(0, separator);
          if (code == '0' || code == '2') {
            _title = payload.substring(separator + 1);
          }
        }
      }
      return '';
    });
    chunk = chunk.replaceAll(_csiRegex, '');
    chunk = chunk.replaceAll(_singleEscapeRegex, '');

    for (final rune in chunk.runes) {
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
    _markDirty();
  }

  void _appendLine(String line) {
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  void _markDirty() {
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _encoder?.close();
    _running = false;
    super.dispose();
  }
}

final RegExp _oscRegex = RegExp(r'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)');
final RegExp _csiRegex = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');
final RegExp _singleEscapeRegex = RegExp(r'\x1b[@-Z\\-_]');
