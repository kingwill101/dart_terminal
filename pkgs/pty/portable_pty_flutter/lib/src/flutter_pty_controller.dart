import 'package:flutter/foundation.dart';
import 'package:portable_pty/portable_pty.dart'
    as base
    show PortablePtyController, PtyListenable, PortablePtyTransport;

/// Flutter-friendly [ChangeNotifier] adapter around the pure-Dart
/// [base.PortablePtyController].
///
/// This class exists solely to bridge [base.PtyListenable] (from
/// `portable_pty`) with Flutter's [ChangeNotifier] / [Listenable] so the
/// controller can be used with [ListenableBuilder], [AnimatedBuilder],
/// and other framework utilities.
///
/// All business logic lives in `portable_pty`; this wrapper simply forwards
/// every method call and relays [base.PtyListenable] notifications into
/// [ChangeNotifier.notifyListeners].
class FlutterPtyController extends ChangeNotifier {
  /// Wraps a platform-resolved [base.PortablePtyController].
  FlutterPtyController({
    int maxLines = 1000,
    String? defaultShell,
    int rows = 24,
    int cols = 80,
    String? webSocketUrl,
    String? webTransportUrl,
    base.PortablePtyTransport? transport,
  }) : _inner = base.PortablePtyController(
         maxLines: maxLines,
         defaultShell: defaultShell,
         rows: rows,
         cols: cols,
         webSocketUrl: webSocketUrl,
         webTransportUrl: webTransportUrl,
         transport: transport,
       ) {
    _inner.addListener(_onInnerChanged);
  }

  final base.PortablePtyController _inner;

  void _onInnerChanged() {
    notifyListeners();
  }

  // ── Forwarded getters ──────────────────────────────────────────────

  /// See [base.PortablePtyController.revision].
  int get revision => _inner.revision;

  /// See [base.PortablePtyController.isRunning].
  bool get isRunning => _inner.isRunning;

  /// See [base.PortablePtyController.lines].
  List<String> get lines => _inner.lines;

  /// See [base.PortablePtyController.lineCount].
  int get lineCount => _inner.lineCount;

  // ── Forwarded methods ──────────────────────────────────────────────

  /// See [base.PortablePtyController.start].
  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
  }) => _inner.start(shell: shell, arguments: arguments);

  /// See [base.PortablePtyController.stop].
  Future<void> stop() => _inner.stop();

  /// See [base.PortablePtyController.readOutput].
  String readOutput({int maxBytes = 4096}) =>
      _inner.readOutput(maxBytes: maxBytes);

  /// See [base.PortablePtyController.write].
  bool write(String text) => _inner.write(text);

  /// See [base.PortablePtyController.writeBytes].
  bool writeBytes(Uint8List bytes) => _inner.writeBytes(bytes);

  /// See [base.PortablePtyController.appendDebugOutput].
  void appendDebugOutput(String text) => _inner.appendDebugOutput(text);

  /// See [base.PortablePtyController.tryWait].
  int? tryWait() => _inner.tryWait();

  /// See [base.PortablePtyController.clear].
  void clear() => _inner.clear();

  @override
  void dispose() {
    _inner.removeListener(_onInnerChanged);
    _inner.dispose();
    super.dispose();
  }
}
