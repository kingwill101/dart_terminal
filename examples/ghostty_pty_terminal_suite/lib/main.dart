import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGhosttyVteWeb();
  runApp(const TerminalSuiteApp());
}

class TerminalSuiteApp extends StatelessWidget {
  const TerminalSuiteApp({super.key, this.autoInspect = true});

  final bool autoInspect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostty + Portable PTY Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: TerminalSuiteHome(autoInspect: autoInspect),
    );
  }
}

enum _RemoteTransportMode { webSocket, webTransport }

enum _DemoMouseTrackingProfile { disabled, x10, normal, button, any }

enum _DemoMouseFormatProfile { x10, utf8, sgr, urxvt, sgrPixels }

class TerminalSuiteHome extends StatefulWidget {
  const TerminalSuiteHome({super.key, this.autoInspect = true});

  final bool autoInspect;

  @override
  State<TerminalSuiteHome> createState() => _TerminalSuiteHomeState();
}

class _TerminalSuiteHomeState extends State<TerminalSuiteHome>
    with SingleTickerProviderStateMixin {
  static const String _defaultWebSocketEndpoint = 'ws://localhost:8080/pty';
  static const String _defaultWebTransportEndpoint =
      'https://localhost:8080/pty';

  late final TabController _tabs;
  late GhosttyTerminalController _ghostty;
  late FlutterPtyController _pty;

  late final TextEditingController _shellController;
  late final TextEditingController _argsController;
  late final TextEditingController _writeController;
  late final TextEditingController _endpointController;

  late final TextEditingController _oscController;
  late final TextEditingController _sgrController;
  late final TextEditingController _pasteController;
  late final TextEditingController _keyUtf8Controller;
  late final TextEditingController _keyUnshiftedController;

  _RemoteTransportMode _transportMode = _RemoteTransportMode.webSocket;

  Timer? _ptyPollTimer;
  bool _autoPollPty = false;
  int _pollIntervalMs = 200;
  bool _bridgePtyToGhostty = true;
  bool _sanitizePaste = true;
  GhosttyTerminalRendererMode _ghosttyRendererMode =
      GhosttyTerminalRendererMode.formatter;
  GhosttyTerminalInteractionPolicy _ghosttyInteractionPolicy =
      GhosttyTerminalInteractionPolicy.auto;
  _DemoMouseTrackingProfile _ghosttyMouseTrackingProfile =
      _DemoMouseTrackingProfile.disabled;
  _DemoMouseFormatProfile _ghosttyMouseFormatProfile =
      _DemoMouseFormatProfile.sgr;
  bool _ghosttyMouseFocusEvents = false;
  bool _ghosttyMouseAltScroll = false;

  int _ptyReads = 0;
  int _ptyBytesRead = 0;
  int _ptyWrites = 0;
  int _ghosttyWrites = 0;

  bool _pasteSafe = true;
  VtOscCommand? _oscResult;
  String _oscError = '';
  List<VtSgrAttributeData> _sgrAttributes = <VtSgrAttributeData>[];
  String _sgrError = '';

  GhosttyKey _selectedKey = GhosttyKey.GHOSTTY_KEY_ENTER;
  GhosttyKeyAction _selectedAction = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
  final Set<int> _mods = <int>{};
  final Set<int> _consumedMods = <int>{};
  GhosttyMouseAction _selectedMouseAction =
      GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_PRESS;
  GhosttyMouseButton? _selectedMouseButton =
      GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_LEFT;
  GhosttyMouseTrackingMode _mouseTrackingMode =
      GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_NORMAL;
  GhosttyMouseFormat _mouseFormat = GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_SGR;
  bool _mouseAnyButtonPressed = false;
  bool _mouseTrackLastCell = true;
  double _mouseX = 48;
  double _mouseY = 32;

  bool _keyComposing = false;
  bool _cursorKeyApplication = false;
  bool _keypadKeyApplication = false;
  bool _ignoreKeypadWithNumLock = false;
  bool _altEscPrefix = true;
  bool _modifyOtherKeysState2 = false;
  GhosttyOptionAsAlt _macosOptionAsAlt =
      GhosttyOptionAsAlt.GHOSTTY_OPTION_AS_ALT_TRUE;

  final Set<int> _kittyFlags = <int>{};

  Uint8List _lastEncodedBytes = Uint8List(0);
  Uint8List _lastMouseEncodedBytes = Uint8List(0);
  final List<String> _activity = <String>[];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);

    _shellController = TextEditingController();
    _argsController = TextEditingController();
    _writeController = TextEditingController();
    _endpointController = TextEditingController(
      text: _defaultWebSocketEndpoint,
    );

    _oscController = TextEditingController(text: ']0;Ghostty VTE Suite');
    _sgrController = TextEditingController(text: '1;4;38;2;12;200;180');
    _pasteController = TextEditingController(text: 'echo "hello suite"\n');
    _keyUtf8Controller = TextEditingController();
    _keyUnshiftedController = TextEditingController();

    _ghostty = GhosttyTerminalController(maxLines: 4000, preferPty: true)
      ..addListener(_onGhosttyChange);

    _pty = _createPtyController()..addListener(_onPtyChange);

    if (widget.autoInspect) {
      _recomputeParsers();
    } else {
      _oscError = 'OSC parser unavailable without native assets.';
      _sgrError = 'SGR parser unavailable without native assets.';
      _lastEncodedBytes = Uint8List(0);
      _lastMouseEncodedBytes = Uint8List(0);
    }
    _appendActivity('Initialized terminal suite');
  }

  FlutterPtyController _createPtyController() {
    if (!kIsWeb) {
      return FlutterPtyController(maxLines: 4000);
    }

    return switch (_transportMode) {
      _RemoteTransportMode.webSocket => FlutterPtyController(
        maxLines: 4000,
        webSocketUrl: _endpointController.text.trim(),
      ),
      _RemoteTransportMode.webTransport => FlutterPtyController(
        maxLines: 4000,
        webTransportUrl: _endpointController.text.trim(),
      ),
    };
  }

  Future<void> _recreatePtyController() async {
    final FlutterPtyController previous = _pty;
    previous.removeListener(_onPtyChange);
    _stopPtyPolling();
    await _safeStopPtyController(previous, reason: 'controller recreate');
    previous.dispose();

    _pty = _createPtyController()..addListener(_onPtyChange);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _safeStopPtyController(
    FlutterPtyController controller, {
    required String reason,
  }) async {
    try {
      await controller.stop();
    } catch (error) {
      _appendActivity('PTY stop recovered ($reason): $error');
    }
  }

  void _appendActivity(String line) {
    final DateTime now = DateTime.now();
    final String timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _activity.insert(0, '[$timestamp] $line');
    if (_activity.length > 350) {
      _activity.removeLast();
    }
  }

  bool _safeGhosttyMode(VtMode mode) {
    try {
      return _ghostty.terminal.getMode(mode);
    } catch (_) {
      return false;
    }
  }

  void _applyGhosttyMouseModes() {
    try {
      final terminal = _ghostty.terminal;
      terminal.setMode(VtModes.x10Mouse, false);
      terminal.setMode(VtModes.normalMouse, false);
      terminal.setMode(VtModes.buttonMouse, false);
      terminal.setMode(VtModes.anyMouse, false);
      terminal.setMode(VtModes.utf8Mouse, false);
      terminal.setMode(VtModes.sgrMouse, false);
      terminal.setMode(VtModes.urxvtMouse, false);
      terminal.setMode(VtModes.sgrPixelsMouse, false);

      switch (_ghosttyMouseTrackingProfile) {
        case _DemoMouseTrackingProfile.disabled:
          break;
        case _DemoMouseTrackingProfile.x10:
          terminal.setMode(VtModes.x10Mouse, true);
        case _DemoMouseTrackingProfile.normal:
          terminal.setMode(VtModes.normalMouse, true);
        case _DemoMouseTrackingProfile.button:
          terminal.setMode(VtModes.buttonMouse, true);
        case _DemoMouseTrackingProfile.any:
          terminal.setMode(VtModes.anyMouse, true);
      }

      switch (_ghosttyMouseFormatProfile) {
        case _DemoMouseFormatProfile.x10:
          break;
        case _DemoMouseFormatProfile.utf8:
          terminal.setMode(VtModes.utf8Mouse, true);
        case _DemoMouseFormatProfile.sgr:
          terminal.setMode(VtModes.sgrMouse, true);
        case _DemoMouseFormatProfile.urxvt:
          terminal.setMode(VtModes.urxvtMouse, true);
        case _DemoMouseFormatProfile.sgrPixels:
          terminal.setMode(VtModes.sgrPixelsMouse, true);
      }

      terminal.setMode(VtModes.focusEvent, _ghosttyMouseFocusEvents);
      terminal.setMode(VtModes.altScroll, _ghosttyMouseAltScroll);
    } catch (_) {}
  }

  void _syncGhosttyMouseModeControls() {
    if (_safeGhosttyMode(VtModes.anyMouse)) {
      _ghosttyMouseTrackingProfile = _DemoMouseTrackingProfile.any;
    } else if (_safeGhosttyMode(VtModes.buttonMouse)) {
      _ghosttyMouseTrackingProfile = _DemoMouseTrackingProfile.button;
    } else if (_safeGhosttyMode(VtModes.normalMouse)) {
      _ghosttyMouseTrackingProfile = _DemoMouseTrackingProfile.normal;
    } else if (_safeGhosttyMode(VtModes.x10Mouse)) {
      _ghosttyMouseTrackingProfile = _DemoMouseTrackingProfile.x10;
    } else {
      _ghosttyMouseTrackingProfile = _DemoMouseTrackingProfile.disabled;
    }

    if (_safeGhosttyMode(VtModes.sgrPixelsMouse)) {
      _ghosttyMouseFormatProfile = _DemoMouseFormatProfile.sgrPixels;
    } else if (_safeGhosttyMode(VtModes.sgrMouse)) {
      _ghosttyMouseFormatProfile = _DemoMouseFormatProfile.sgr;
    } else if (_safeGhosttyMode(VtModes.urxvtMouse)) {
      _ghosttyMouseFormatProfile = _DemoMouseFormatProfile.urxvt;
    } else if (_safeGhosttyMode(VtModes.utf8Mouse)) {
      _ghosttyMouseFormatProfile = _DemoMouseFormatProfile.utf8;
    } else {
      _ghosttyMouseFormatProfile = _DemoMouseFormatProfile.x10;
    }

    _ghosttyMouseFocusEvents = _safeGhosttyMode(VtModes.focusEvent);
    _ghosttyMouseAltScroll = _safeGhosttyMode(VtModes.altScroll);
  }

  void _onGhosttyChange() {
    if (!mounted) {
      return;
    }
    _syncGhosttyMouseModeControls();
    setState(() {});
  }

  void _onPtyChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  List<String> _parseArgs(String raw) {
    return raw
        .split(RegExp(r'\s+'))
        .map((String token) => token.trim())
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
  }

  int _parseMaybeInt(String text) {
    final String normalized = text.trim().toLowerCase();
    if (normalized.startsWith('0x')) {
      return int.tryParse(normalized.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(normalized) ?? 0;
  }

  int _maskFrom(Set<int> values) {
    int mask = 0;
    for (final int value in values) {
      mask |= value;
    }
    return mask;
  }

  String _hexBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '(empty)';
    }
    return bytes
        .map((int value) => value.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  String _escaped(Uint8List bytes) {
    final StringBuffer out = StringBuffer();
    for (final int unit in bytes) {
      switch (unit) {
        case 9:
          out.write(r'\t');
          break;
        case 10:
          out.write(r'\n');
          break;
        case 13:
          out.write(r'\r');
          break;
        case 27:
          out.write(r'\e');
          break;
        default:
          if (unit < 32 || unit == 127) {
            out.write('\\x${unit.toRadixString(16).padLeft(2, '0')}');
          } else {
            out.writeCharCode(unit);
          }
      }
    }
    return out.toString();
  }

  void _recomputeParsers() {
    final String paste = _pasteController.text;
    _pasteSafe = GhosttyVt.isPasteSafe(paste);

    _oscError = '';
    try {
      final VtOscParser parser = GhosttyVt.newOscParser();
      parser.addText(_oscController.text);
      _oscResult = parser.end();
      parser.close();
    } catch (error) {
      _oscResult = null;
      _oscError = '$error';
    }

    _sgrError = '';
    try {
      final List<int> params = _sgrController.text
          .split(';')
          .map((String token) => token.trim())
          .where((String token) => token.isNotEmpty)
          .map((String token) => int.tryParse(token) ?? 0)
          .toList(growable: false);
      final VtSgrParser parser = GhosttyVt.newSgrParser();
      parser.setParams(params);
      _sgrAttributes = parser.parseAll();
      parser.close();
    } catch (error) {
      _sgrAttributes = <VtSgrAttributeData>[];
      _sgrError = '$error';
    }

    _encodeKey();
    _encodeMouse();
  }

  void _encodeKey() {
    final VtKeyEvent event = GhosttyVt.newKeyEvent()
      ..key = _selectedKey
      ..action = _selectedAction
      ..mods = _maskFrom(_mods)
      ..consumedMods = _maskFrom(_consumedMods)
      ..composing = _keyComposing
      ..utf8Text = _keyUtf8Controller.text
      ..unshiftedCodepoint = _parseMaybeInt(_keyUnshiftedController.text);

    final VtKeyEncoder encoder = GhosttyVt.newKeyEncoder();
    VtKeyEncoderOptions(
      cursorKeyApplication: _cursorKeyApplication,
      keypadKeyApplication: _keypadKeyApplication,
      ignoreKeypadWithNumLock: _ignoreKeypadWithNumLock,
      altEscPrefix: _altEscPrefix,
      modifyOtherKeysState2: _modifyOtherKeysState2,
      kittyFlags: _maskFrom(_kittyFlags),
      macosOptionAsAlt: _macosOptionAsAlt,
    ).applyTo(encoder);

    _lastEncodedBytes = encoder.encode(event);
    encoder.close();
    event.close();
  }

  void _encodeMouse() {
    final VtMouseEvent event = GhosttyVt.newMouseEvent()
      ..action = _selectedMouseAction
      ..button = _selectedMouseButton
      ..mods = _maskFrom(_mods)
      ..position = VtMousePosition(x: _mouseX, y: _mouseY);

    final VtMouseEncoder encoder = GhosttyVt.newMouseEncoder();
    VtMouseEncoderOptions(
      trackingMode: _mouseTrackingMode,
      format: _mouseFormat,
      size: const VtMouseEncoderSize(
        screenWidth: 1280,
        screenHeight: 720,
        cellWidth: 10,
        cellHeight: 20,
      ),
      anyButtonPressed: _mouseAnyButtonPressed,
      trackLastCell: _mouseTrackLastCell,
    ).applyTo(encoder);

    _lastMouseEncodedBytes = encoder.encode(event);
    encoder.close();
    event.close();
  }

  Future<void> _startGhostty() async {
    final String shell = _shellController.text.trim();
    final List<String> args = _parseArgs(_argsController.text);
    await _ghostty.start(shell: shell.isEmpty ? null : shell, arguments: args);
    _appendActivity('Ghostty shell started (args: ${args.length})');
    setState(() {});
  }

  Future<void> _stopGhostty() async {
    await _ghostty.stop();
    _appendActivity('Ghostty shell stopped');
    setState(() {});
  }

  Future<void> _startPty() async {
    if (kIsWeb) {
      await _recreatePtyController();
    }

    final String shell = _shellController.text.trim();
    final List<String> args = _parseArgs(_argsController.text);
    await _pty.start(shell: shell.isEmpty ? null : shell, arguments: args);

    if (_autoPollPty) {
      _startPtyPolling();
    }

    _appendActivity('Portable PTY started (args: ${args.length})');
    setState(() {});
  }

  Future<void> _stopPty() async {
    _stopPtyPolling();
    await _safeStopPtyController(_pty, reason: 'user stop');
    _appendActivity('Portable PTY stopped');
    setState(() {});
  }

  void _startPtyPolling() {
    _stopPtyPolling();
    _ptyPollTimer = Timer.periodic(
      Duration(milliseconds: _pollIntervalMs),
      (_) => _readPtyOutput(),
    );
  }

  void _stopPtyPolling() {
    _ptyPollTimer?.cancel();
    _ptyPollTimer = null;
  }

  void _readPtyOutput() {
    if (!_pty.isRunning) {
      return;
    }

    try {
      final String chunk = _pty.readOutput(maxBytes: 16384);
      if (chunk.isEmpty) {
        return;
      }
      _ptyReads += 1;
      _ptyBytesRead += chunk.length;

      if (_bridgePtyToGhostty) {
        _ghostty.appendDebugOutput(chunk);
      }

      _appendActivity('PTY read ${chunk.length} chars');
      setState(() {});
    } catch (error) {
      _appendActivity('PTY read failed: $error');
      setState(() {});
    }
  }

  String _formatterExtrasSummary() {
    final extra = const VtFormatterTerminalExtra.all();
    return 'palette=${extra.palette}\n'
        'modes=${extra.modes}\n'
        'scrollingRegion=${extra.scrollingRegion}\n'
        'tabstops=${extra.tabstops}\n'
        'pwd=${extra.pwd}\n'
        'keyboard=${extra.keyboard}\n'
        'cursor=${extra.screen.cursor}\n'
        'style=${extra.screen.style}\n'
        'hyperlink=${extra.screen.hyperlink}\n'
        'protection=${extra.screen.protection}\n'
        'kittyKeyboard=${extra.screen.kittyKeyboard}\n'
        'charsets=${extra.screen.charsets}';
  }

  String _ghosttyMouseProtocolSummary() {
    try {
      final state = _ghostty.terminal.mouseProtocolState;
      if (!state.enabled) {
        return 'Mouse reporting: disabled';
      }
      return 'Mouse reporting: ${state.trackingMode?.name ?? 'unknown'}'
          ' • ${state.format?.name ?? 'unknown'}'
          ' • focus ${state.focusEvents ? 'on' : 'off'}'
          ' • altScroll ${state.altScroll ? 'on' : 'off'}';
    } catch (_) {
      return 'Mouse reporting unavailable before native terminal init.';
    }
  }

  String _renderSemanticSummary() {
    final snapshot = _ghostty.renderSnapshot;
    if (snapshot == null || !snapshot.hasViewportData) {
      return 'Render snapshot unavailable on this platform or before native viewport update.';
    }

    var promptRows = 0;
    var continuationRows = 0;
    var promptTextCells = 0;
    var promptInputCells = 0;
    var promptOutputCells = 0;

    for (final row in snapshot.rowsData) {
      if (row.isPrompt) {
        promptRows += 1;
      }
      if (row.isPromptContinuation) {
        continuationRows += 1;
      }
      for (final cell in row.cells) {
        if (cell.isPromptText) {
          promptTextCells += 1;
        }
        if (cell.isPromptInput) {
          promptInputCells += 1;
        }
        if (cell.isPromptOutput) {
          promptOutputCells += 1;
        }
      }
    }

    final cursor = snapshot.cursor;
    return 'rows=${snapshot.rowsData.length}\n'
        'promptRows=$promptRows\n'
        'promptContinuationRows=$continuationRows\n'
        'promptTextCells=$promptTextCells\n'
        'promptInputCells=$promptInputCells\n'
        'promptOutputCells=$promptOutputCells\n'
        'cursorVisible=${cursor.visible}\n'
        'cursorViewport=${cursor.hasViewportPosition ? '${cursor.row},${cursor.col}' : '(offscreen)'}';
  }

  Widget _inspectorCard(String title, String body) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMouseEncoderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Mouse Encoder', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<GhosttyMouseAction>(
              initialValue: _selectedMouseAction,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Mouse action',
              ),
              items: GhosttyMouseAction.values
                  .map(
                    (GhosttyMouseAction value) =>
                        DropdownMenuItem<GhosttyMouseAction>(
                          value: value,
                          child: Text(value.name),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (GhosttyMouseAction? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedMouseAction = value;
                  _encodeMouse();
                });
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GhosttyMouseButton?>(
              initialValue: _selectedMouseButton,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Mouse button',
              ),
              items: <DropdownMenuItem<GhosttyMouseButton?>>[
                const DropdownMenuItem<GhosttyMouseButton?>(
                  value: null,
                  child: Text('none'),
                ),
                ...GhosttyMouseButton.values.map(
                  (GhosttyMouseButton value) =>
                      DropdownMenuItem<GhosttyMouseButton?>(
                        value: value,
                        child: Text(value.name),
                      ),
                ),
              ],
              onChanged: (GhosttyMouseButton? value) {
                setState(() {
                  _selectedMouseButton = value;
                  _encodeMouse();
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<GhosttyMouseTrackingMode>(
                    initialValue: _mouseTrackingMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Tracking mode',
                    ),
                    items: GhosttyMouseTrackingMode.values
                        .map(
                          (GhosttyMouseTrackingMode value) =>
                              DropdownMenuItem<GhosttyMouseTrackingMode>(
                                value: value,
                                child: Text(value.name),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (GhosttyMouseTrackingMode? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _mouseTrackingMode = value;
                        _encodeMouse();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<GhosttyMouseFormat>(
                    initialValue: _mouseFormat,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Mouse format',
                    ),
                    items: GhosttyMouseFormat.values
                        .map(
                          (GhosttyMouseFormat value) =>
                              DropdownMenuItem<GhosttyMouseFormat>(
                                value: value,
                                child: Text(value.name),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (GhosttyMouseFormat? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _mouseFormat = value;
                        _encodeMouse();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('anyButtonPressed'),
              value: _mouseAnyButtonPressed,
              onChanged: (bool value) {
                setState(() {
                  _mouseAnyButtonPressed = value;
                  _encodeMouse();
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('trackLastCell'),
              value: _mouseTrackLastCell,
              onChanged: (bool value) {
                setState(() {
                  _mouseTrackLastCell = value;
                  _encodeMouse();
                });
              },
            ),
            Text(
              'Mouse position (${_mouseX.toStringAsFixed(0)}, ${_mouseY.toStringAsFixed(0)})',
            ),
            Slider(
              value: _mouseX,
              min: 0,
              max: 240,
              label: _mouseX.toStringAsFixed(0),
              onChanged: (double value) {
                setState(() {
                  _mouseX = value;
                  _encodeMouse();
                });
              },
            ),
            Slider(
              value: _mouseY,
              min: 0,
              max: 120,
              label: _mouseY.toStringAsFixed(0),
              onChanged: (double value) {
                setState(() {
                  _mouseY = value;
                  _encodeMouse();
                });
              },
            ),
            SelectableText('mouse hex: ${_hexBytes(_lastMouseEncodedBytes)}'),
            const SizedBox(height: 4),
            SelectableText('mouse escaped: ${_escaped(_lastMouseEncodedBytes)}'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _sendEncodedMouseToPty,
              child: const Text('Send encoded mouse bytes to PTY'),
            ),
          ],
        ),
      ),
    );
  }

  void _sendText({required bool addNewLine}) {
    final String raw = _writeController.text;
    if (raw.isEmpty) {
      return;
    }

    final String text = addNewLine ? '$raw\n' : raw;

    if (_pty.write(text)) {
      _ptyWrites += 1;
    }

    if (_ghostty.write(text, sanitizePaste: _sanitizePaste)) {
      _ghosttyWrites += 1;
    }

    _appendActivity(
      'Sent ${text.length} chars (sanitize=$_sanitizePaste newline=$addNewLine)',
    );
    setState(() {});
  }

  void _sendEncodedKeyToPty() {
    _encodeKey();
    if (_pty.writeBytes(_lastEncodedBytes)) {
      _ptyWrites += 1;
      _appendActivity(
        'Sent encoded key bytes to PTY (${_lastEncodedBytes.length})',
      );
      setState(() {});
    }
  }

  void _sendEncodedMouseToPty() {
    _encodeMouse();
    if (_pty.writeBytes(_lastMouseEncodedBytes)) {
      _ptyWrites += 1;
      _appendActivity(
        'Sent encoded mouse bytes to PTY (${_lastMouseEncodedBytes.length})',
      );
      setState(() {});
    }
  }

  void _sendEncodedKeyToGhostty() {
    final bool ok = _ghostty.sendKey(
      key: _selectedKey,
      action: _selectedAction,
      mods: _maskFrom(_mods),
      consumedMods: _maskFrom(_consumedMods),
      composing: _keyComposing,
      utf8Text: _keyUtf8Controller.text,
      unshiftedCodepoint: _parseMaybeInt(_keyUnshiftedController.text),
    );
    if (ok) {
      _ghosttyWrites += 1;
      _appendActivity('Sent key event to Ghostty');
      setState(() {});
    }
  }

  void _clearBuffers() {
    _ghostty.clear();
    _pty.clear();
    _appendActivity('Cleared Ghostty and PTY buffers');
    setState(() {});
  }

  void _toggleMod(Set<int> set, int value) {
    if (set.contains(value)) {
      set.remove(value);
    } else {
      set.add(value);
    }
  }

  Widget _buildMetrics() {
    final List<_MetricTileData> items = <_MetricTileData>[
      _MetricTileData(
        label: 'Ghostty running',
        value: _ghostty.isRunning ? 'yes' : 'no',
      ),
      _MetricTileData(
        label: 'PTY running',
        value: _pty.isRunning ? 'yes' : 'no',
      ),
      _MetricTileData(label: 'Ghostty lines', value: '${_ghostty.lineCount}'),
      _MetricTileData(label: 'PTY lines', value: '${_pty.lineCount}'),
      _MetricTileData(label: 'PTY reads', value: '$_ptyReads'),
      _MetricTileData(label: 'PTY bytes', value: '$_ptyBytesRead'),
      _MetricTileData(label: 'PTY writes', value: '$_ptyWrites'),
      _MetricTileData(label: 'Ghostty writes', value: '$_ghosttyWrites'),
      _MetricTileData(label: 'Paste safe', value: _pasteSafe ? 'yes' : 'no'),
      _MetricTileData(
        label: 'Encoded bytes',
        value: '${_lastEncodedBytes.length}',
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (_MetricTileData item) => Container(
              width: 170,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.value,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Session Controls',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _shellController,
                decoration: const InputDecoration(
                  labelText: 'Shell / command override (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _argsController,
                decoration: const InputDecoration(
                  labelText: 'Arguments (space-separated)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _startGhostty,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Ghostty'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _stopGhostty,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Ghostty'),
                  ),
                  FilledButton.icon(
                    onPressed: _startPty,
                    icon: const Icon(Icons.terminal),
                    label: const Text('Start PTY'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _stopPty,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Stop PTY'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _readPtyOutput,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Read PTY now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearBuffers,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clear buffers'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bridge PTY output into Ghostty view'),
                value: _bridgePtyToGhostty,
                onChanged: (bool value) {
                  setState(() {
                    _bridgePtyToGhostty = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-poll PTY output'),
                subtitle: const Text(
                  'Uses synchronous reads from portable_pty. Keep disabled if UI stalls.',
                ),
                value: _autoPollPty,
                onChanged: (bool value) {
                  setState(() {
                    _autoPollPty = value;
                    if (value) {
                      _startPtyPolling();
                    } else {
                      _stopPtyPolling();
                    }
                  });
                },
              ),
              Row(
                children: <Widget>[
                  const Text('Poll interval'),
                  Expanded(
                    child: Slider(
                      value: _pollIntervalMs.toDouble(),
                      min: 50,
                      max: 1000,
                      divisions: 19,
                      label: '$_pollIntervalMs ms',
                      onChanged: (double value) {
                        setState(() {
                          _pollIntervalMs = value.round();
                          if (_autoPollPty) {
                            _startPtyPolling();
                          }
                        });
                      },
                    ),
                  ),
                  Text('${_pollIntervalMs}ms'),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<GhosttyTerminalRendererMode>(
                segments: const <ButtonSegment<GhosttyTerminalRendererMode>>[
                  ButtonSegment<GhosttyTerminalRendererMode>(
                    value: GhosttyTerminalRendererMode.formatter,
                    label: Text('Formatter'),
                    icon: Icon(Icons.text_fields),
                  ),
                  ButtonSegment<GhosttyTerminalRendererMode>(
                    value: GhosttyTerminalRendererMode.renderState,
                    label: Text('Render State'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                ],
                selected: <GhosttyTerminalRendererMode>{_ghosttyRendererMode},
                onSelectionChanged: (Set<GhosttyTerminalRendererMode> modes) {
                  setState(() {
                    _ghosttyRendererMode = modes.first;
                  });
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<GhosttyTerminalInteractionPolicy>(
                segments: const <ButtonSegment<GhosttyTerminalInteractionPolicy>>[
                  ButtonSegment<GhosttyTerminalInteractionPolicy>(
                    value: GhosttyTerminalInteractionPolicy.auto,
                    label: Text('Auto'),
                    icon: Icon(Icons.tune),
                  ),
                  ButtonSegment<GhosttyTerminalInteractionPolicy>(
                    value: GhosttyTerminalInteractionPolicy.selectionFirst,
                    label: Text('Selection First'),
                    icon: Icon(Icons.select_all),
                  ),
                  ButtonSegment<GhosttyTerminalInteractionPolicy>(
                    value: GhosttyTerminalInteractionPolicy.terminalMouseFirst,
                    label: Text('Terminal Mouse'),
                    icon: Icon(Icons.mouse),
                  ),
                ],
                selected: <GhosttyTerminalInteractionPolicy>{
                  _ghosttyInteractionPolicy,
                },
                onSelectionChanged:
                    (Set<GhosttyTerminalInteractionPolicy> modes) {
                      setState(() {
                        _ghosttyInteractionPolicy = modes.first;
                      });
                    },
              ),
              const SizedBox(height: 4),
              Text('Interaction: ${_ghosttyInteractionPolicy.name}'),
              const SizedBox(height: 4),
              Text(_ghosttyMouseProtocolSummary()),
              const SizedBox(height: 8),
              const Text('Ghostty Mouse Tracking'),
              SegmentedButton<_DemoMouseTrackingProfile>(
                segments: const <ButtonSegment<_DemoMouseTrackingProfile>>[
                  ButtonSegment<_DemoMouseTrackingProfile>(
                    value: _DemoMouseTrackingProfile.disabled,
                    label: Text('Disabled'),
                  ),
                  ButtonSegment<_DemoMouseTrackingProfile>(
                    value: _DemoMouseTrackingProfile.x10,
                    label: Text('X10'),
                  ),
                  ButtonSegment<_DemoMouseTrackingProfile>(
                    value: _DemoMouseTrackingProfile.normal,
                    label: Text('Normal'),
                  ),
                  ButtonSegment<_DemoMouseTrackingProfile>(
                    value: _DemoMouseTrackingProfile.button,
                    label: Text('Button'),
                  ),
                  ButtonSegment<_DemoMouseTrackingProfile>(
                    value: _DemoMouseTrackingProfile.any,
                    label: Text('Any'),
                  ),
                ],
                selected: <_DemoMouseTrackingProfile>{
                  _ghosttyMouseTrackingProfile,
                },
                onSelectionChanged:
                    (Set<_DemoMouseTrackingProfile> modes) {
                      setState(() {
                        _ghosttyMouseTrackingProfile = modes.first;
                      });
                      _applyGhosttyMouseModes();
                    },
              ),
              const SizedBox(height: 8),
              const Text('Ghostty Mouse Format'),
              SegmentedButton<_DemoMouseFormatProfile>(
                segments: const <ButtonSegment<_DemoMouseFormatProfile>>[
                  ButtonSegment<_DemoMouseFormatProfile>(
                    value: _DemoMouseFormatProfile.x10,
                    label: Text('X10'),
                  ),
                  ButtonSegment<_DemoMouseFormatProfile>(
                    value: _DemoMouseFormatProfile.utf8,
                    label: Text('UTF8'),
                  ),
                  ButtonSegment<_DemoMouseFormatProfile>(
                    value: _DemoMouseFormatProfile.sgr,
                    label: Text('SGR'),
                  ),
                  ButtonSegment<_DemoMouseFormatProfile>(
                    value: _DemoMouseFormatProfile.urxvt,
                    label: Text('URXVT'),
                  ),
                  ButtonSegment<_DemoMouseFormatProfile>(
                    value: _DemoMouseFormatProfile.sgrPixels,
                    label: Text('SGR Pixels'),
                  ),
                ],
                selected: <_DemoMouseFormatProfile>{_ghosttyMouseFormatProfile},
                onSelectionChanged:
                    (Set<_DemoMouseFormatProfile> modes) {
                      setState(() {
                        _ghosttyMouseFormatProfile = modes.first;
                      });
                      _applyGhosttyMouseModes();
                    },
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilterChip(
                    label: const Text('Focus Events'),
                    selected: _ghosttyMouseFocusEvents,
                    onSelected: (selected) {
                      setState(() {
                        _ghosttyMouseFocusEvents = selected;
                      });
                      _applyGhosttyMouseModes();
                    },
                  ),
                  FilterChip(
                    label: const Text('Alt Scroll'),
                    selected: _ghosttyMouseAltScroll,
                    onSelected: (selected) {
                      setState(() {
                        _ghosttyMouseAltScroll = selected;
                      });
                      _applyGhosttyMouseModes();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (kIsWeb) ...<Widget>[
                const SizedBox(height: 8),
                SegmentedButton<_RemoteTransportMode>(
                  segments: const <ButtonSegment<_RemoteTransportMode>>[
                    ButtonSegment<_RemoteTransportMode>(
                      value: _RemoteTransportMode.webSocket,
                      label: Text('WebSocket'),
                      icon: Icon(Icons.wifi),
                    ),
                    ButtonSegment<_RemoteTransportMode>(
                      value: _RemoteTransportMode.webTransport,
                      label: Text('WebTransport'),
                      icon: Icon(Icons.cloud_sync),
                    ),
                  ],
                  selected: <_RemoteTransportMode>{_transportMode},
                  onSelectionChanged:
                      (Set<_RemoteTransportMode> selection) async {
                        final _RemoteTransportMode mode = selection.first;
                        setState(() {
                          _transportMode = mode;
                          _endpointController.text =
                              mode == _RemoteTransportMode.webSocket
                              ? _defaultWebSocketEndpoint
                              : _defaultWebTransportEndpoint;
                        });
                        await _recreatePtyController();
                      },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _endpointController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: _transportMode == _RemoteTransportMode.webSocket
                        ? 'WebSocket endpoint'
                        : 'WebTransport endpoint',
                  ),
                  onSubmitted: (_) async {
                    await _recreatePtyController();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGhosttyTab() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double terminalHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * 0.52).clamp(220.0, 420.0)
            : 320.0;
        return ListView(
          children: <Widget>[
            _inspectorCard('Ghostty Formatter Extras', _formatterExtrasSummary()),
            const SizedBox(height: 8),
            SizedBox(
              height: terminalHeight,
              child: Card(
                clipBehavior: Clip.hardEdge,
                child: GhosttyTerminalView(
                  controller: _ghostty,
                  autofocus: false,
                  fontSize: 14,
                  lineHeight: 1.35,
                  renderer: _ghosttyRendererMode,
                  interactionPolicy: _ghosttyInteractionPolicy,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _writeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Input text',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Switch(
                      value: _sanitizePaste,
                      onChanged: (bool value) {
                        setState(() {
                          _sanitizePaste = value;
                        });
                      },
                    ),
                    const Text('sanitizePaste'),
                  ],
                ),
                FilledButton(
                  onPressed: () => _sendText(addNewLine: false),
                  child: const Text('Send'),
                ),
                OutlinedButton(
                  onPressed: () => _sendText(addNewLine: true),
                  child: const Text('Send + newline'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPtyTab() {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Portable PTY Transcript (${_pty.lines.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1115),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _pty.lines.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParserTab() {
    return ListView(
      children: <Widget>[
        _inspectorCard('Ghostty Render Semantics', _renderSemanticSummary()),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Paste Safety',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pasteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Paste payload',
                  ),
                  onChanged: (_) {
                    setState(_recomputeParsers);
                  },
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text(_pasteSafe ? 'Safe' : 'Unsafe'),
                  backgroundColor: _pasteSafe
                      ? Colors.green.withValues(alpha: 0.25)
                      : Colors.red.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'OSC Parser',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _oscController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'OSC content (without ESC prefix)',
                  ),
                  onChanged: (_) {
                    setState(_recomputeParsers);
                  },
                ),
                const SizedBox(height: 8),
                if (_oscError.isNotEmpty)
                  Text('Error: $_oscError')
                else if (_oscResult != null)
                  Text(
                    'Type: ${_oscResult!.type}\nWindow title: ${_oscResult!.windowTitle}',
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SGR Parser',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sgrController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'SGR params (semicolon-separated ints)',
                  ),
                  onChanged: (_) {
                    setState(_recomputeParsers);
                  },
                ),
                const SizedBox(height: 8),
                if (_sgrError.isNotEmpty)
                  Text('Error: $_sgrError')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sgrAttributes
                        .map(
                          (VtSgrAttributeData attr) => Chip(
                            label: Text(
                              '${attr.tag} rgb=${attr.rgb} palette=${attr.paletteIndex} underline=${attr.underline}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyTab() {
    return ListView(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Key Event',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      <GhosttyKey>[
                            GhosttyKey.GHOSTTY_KEY_C,
                            GhosttyKey.GHOSTTY_KEY_V,
                            GhosttyKey.GHOSTTY_KEY_ENTER,
                            GhosttyKey.GHOSTTY_KEY_TAB,
                            GhosttyKey.GHOSTTY_KEY_BACKSPACE,
                            GhosttyKey.GHOSTTY_KEY_ESCAPE,
                            GhosttyKey.GHOSTTY_KEY_ARROW_UP,
                            GhosttyKey.GHOSTTY_KEY_ARROW_DOWN,
                            GhosttyKey.GHOSTTY_KEY_ARROW_LEFT,
                            GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT,
                            GhosttyKey.GHOSTTY_KEY_F1,
                            GhosttyKey.GHOSTTY_KEY_F2,
                            GhosttyKey.GHOSTTY_KEY_F3,
                            GhosttyKey.GHOSTTY_KEY_F4,
                          ]
                          .map(
                            (GhosttyKey key) => ChoiceChip(
                              label: Text(
                                key.name.replaceAll('GHOSTTY_KEY_', ''),
                              ),
                              selected: key == _selectedKey,
                              onSelected: (_) {
                                setState(() {
                                  _selectedKey = key;
                                  _encodeKey();
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GhosttyKeyAction>(
                  initialValue: _selectedAction,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Action',
                  ),
                  items: GhosttyKeyAction.values
                      .map(
                        (GhosttyKeyAction value) =>
                            DropdownMenuItem<GhosttyKeyAction>(
                              value: value,
                              child: Text(value.name),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (GhosttyKeyAction? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedAction = value;
                      _encodeKey();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _keyUtf8Controller,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'UTF-8 text override',
                        ),
                        onChanged: (_) {
                          setState(_encodeKey);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _keyUnshiftedController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'unshifted codepoint (decimal/0x)',
                        ),
                        onChanged: (_) {
                          setState(_encodeKey);
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _keyComposing,
                  onChanged: (bool value) {
                    setState(() {
                      _keyComposing = value;
                      _encodeKey();
                    });
                  },
                  title: const Text('Composing'),
                ),
              ],
            ),
          ),
        ),
        _buildMouseEncoderCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Modifier Masks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      <(String, int)>[
                            ('Shift', GhosttyModsMask.shift),
                            ('Ctrl', GhosttyModsMask.ctrl),
                            ('Alt', GhosttyModsMask.alt),
                            ('Super', GhosttyModsMask.superKey),
                          ]
                          .map(
                            ((String, int) entry) => FilterChip(
                              label: Text('mods:${entry.$1}'),
                              selected: _mods.contains(entry.$2),
                              onSelected: (_) {
                                setState(() {
                                  _toggleMod(_mods, entry.$2);
                                  _encodeKey();
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      <(String, int)>[
                            ('Shift', GhosttyModsMask.shift),
                            ('Ctrl', GhosttyModsMask.ctrl),
                            ('Alt', GhosttyModsMask.alt),
                            ('Super', GhosttyModsMask.superKey),
                          ]
                          .map(
                            ((String, int) entry) => FilterChip(
                              label: Text('consumed:${entry.$1}'),
                              selected: _consumedMods.contains(entry.$2),
                              onSelected: (_) {
                                setState(() {
                                  _toggleMod(_consumedMods, entry.$2);
                                  _encodeKey();
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Encoder Options',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('cursorKeyApplication'),
                  value: _cursorKeyApplication,
                  onChanged: (bool value) {
                    setState(() {
                      _cursorKeyApplication = value;
                      _encodeKey();
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('keypadKeyApplication'),
                  value: _keypadKeyApplication,
                  onChanged: (bool value) {
                    setState(() {
                      _keypadKeyApplication = value;
                      _encodeKey();
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ignoreKeypadWithNumLock'),
                  value: _ignoreKeypadWithNumLock,
                  onChanged: (bool value) {
                    setState(() {
                      _ignoreKeypadWithNumLock = value;
                      _encodeKey();
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('altEscPrefix'),
                  value: _altEscPrefix,
                  onChanged: (bool value) {
                    setState(() {
                      _altEscPrefix = value;
                      _encodeKey();
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('modifyOtherKeysState2'),
                  value: _modifyOtherKeysState2,
                  onChanged: (bool value) {
                    setState(() {
                      _modifyOtherKeysState2 = value;
                      _encodeKey();
                    });
                  },
                ),
                DropdownButtonFormField<GhosttyOptionAsAlt>(
                  initialValue: _macosOptionAsAlt,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'macosOptionAsAlt',
                  ),
                  items: GhosttyOptionAsAlt.values
                      .map(
                        (GhosttyOptionAsAlt value) =>
                            DropdownMenuItem<GhosttyOptionAsAlt>(
                              value: value,
                              child: Text(value.name),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (GhosttyOptionAsAlt? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _macosOptionAsAlt = value;
                      _encodeKey();
                    });
                  },
                ),
                const Divider(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      <(String, int)>[
                            ('disambiguate', GhosttyKittyFlags.disambiguate),
                            ('reportEvents', GhosttyKittyFlags.reportEvents),
                            (
                              'reportAlternates',
                              GhosttyKittyFlags.reportAlternates,
                            ),
                            ('reportAll', GhosttyKittyFlags.reportAll),
                            (
                              'reportAssociated',
                              GhosttyKittyFlags.reportAssociated,
                            ),
                          ]
                          .map(
                            ((String, int) entry) => FilterChip(
                              label: Text(entry.$1),
                              selected: _kittyFlags.contains(entry.$2),
                              onSelected: (_) {
                                setState(() {
                                  _toggleMod(_kittyFlags, entry.$2);
                                  _encodeKey();
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Encoded Output',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText('hex: ${_hexBytes(_lastEncodedBytes)}'),
                const SizedBox(height: 4),
                SelectableText('escaped: ${_escaped(_lastEncodedBytes)}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _sendEncodedKeyToGhostty,
                      child: const Text('Send key to Ghostty'),
                    ),
                    OutlinedButton(
                      onPressed: _sendEncodedKeyToPty,
                      child: const Text('Send encoded bytes to PTY'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityTab() {
    return Column(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Metrics', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _buildMetrics(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Activity (${_activity.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _activity.length,
                      itemBuilder: (BuildContext context, int index) {
                        return SelectableText(_activity[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = TabBarView(
      controller: _tabs,
      children: <Widget>[
        _buildGhosttyTab(),
        _buildPtyTab(),
        _buildParserTab(),
        _buildKeyTab(),
        _buildActivityTab(),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 1100;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ghostty + Portable PTY Suite'),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const <Tab>[
                Tab(text: 'Ghostty'),
                Tab(text: 'PTY'),
                Tab(text: 'Parsers'),
                Tab(text: 'Keys'),
                Tab(text: 'Activity'),
              ],
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: stacked
                ? Column(
                    children: <Widget>[
                      Expanded(flex: 3, child: content),
                      const SizedBox(height: 8),
                      Expanded(flex: 2, child: _buildControlPanel()),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Flexible(flex: 3, child: content),
                      const SizedBox(width: 8),
                      Flexible(flex: 2, child: _buildControlPanel()),
                    ],
                  ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _stopPtyPolling();

    _ghostty.removeListener(_onGhosttyChange);
    _ghostty.dispose();

    _pty.removeListener(_onPtyChange);
    _pty.dispose();

    _tabs.dispose();

    _shellController.dispose();
    _argsController.dispose();
    _writeController.dispose();
    _endpointController.dispose();
    _oscController.dispose();
    _sgrController.dispose();
    _pasteController.dispose();
    _keyUtf8Controller.dispose();
    _keyUnshiftedController.dispose();

    super.dispose();
  }
}

class _MetricTileData {
  _MetricTileData({required this.label, required this.value});

  final String label;
  final String value;
}
