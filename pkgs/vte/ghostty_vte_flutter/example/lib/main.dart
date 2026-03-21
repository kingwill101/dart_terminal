import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGhosttyVteWeb();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.controller, this.autoStart = true});

  final GhosttyTerminalController? controller;
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostty VT Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E8F74),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF071019),
        useMaterial3: true,
      ),
      home: TerminalStudioPage(controller: controller, autoStart: autoStart),
    );
  }
}

class TerminalStudioPage extends StatefulWidget {
  const TerminalStudioPage({super.key, this.controller, this.autoStart = true});

  final GhosttyTerminalController? controller;
  final bool autoStart;

  @override
  State<TerminalStudioPage> createState() => _TerminalStudioPageState();
}

class _TerminalStudioPageState extends State<TerminalStudioPage>
    with SingleTickerProviderStateMixin {
  late final GhosttyTerminalController _terminal;
  late final bool _ownsTerminal;
  GhosttyTerminalShellProfile _selectedShellProfile =
      GhosttyTerminalShellProfile.auto;
  String _activeShellLabel = 'not started';
  String _activeShellCommand = '(not started)';
  Map<String, String> _activeShellEnvironment = const <String, String>{};
  final TextEditingController _commandController = TextEditingController(
    text:
        'printf "\\e]2;Ghostty VT Studio\\a\\e[32mreal terminal ready\\e[0m\\n"',
  );
  final TextEditingController _oscController = TextEditingController(
    text: '2;Ghostty VT Studio',
  );
  final TextEditingController _sgrController = TextEditingController(
    text: '1;38;2;14;143;116;4',
  );
  final TextEditingController _utf8Controller = TextEditingController(
    text: 'c',
  );
  final TextEditingController _codepointController = TextEditingController(
    text: '0x63',
  );
  final TextEditingController _fontFamilyController = TextEditingController();

  static const List<_ActionOption> _actions = <_ActionOption>[
    _ActionOption('Press', GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS),
    _ActionOption('Repeat', GhosttyKeyAction.GHOSTTY_KEY_ACTION_REPEAT),
    _ActionOption('Release', GhosttyKeyAction.GHOSTTY_KEY_ACTION_RELEASE),
  ];

  static const List<_KeyOption> _keys = <_KeyOption>[
    _KeyOption('C', GhosttyKey.GHOSTTY_KEY_C),
    _KeyOption('Enter', GhosttyKey.GHOSTTY_KEY_ENTER),
    _KeyOption('Tab', GhosttyKey.GHOSTTY_KEY_TAB),
    _KeyOption('Up', GhosttyKey.GHOSTTY_KEY_ARROW_UP),
    _KeyOption('Down', GhosttyKey.GHOSTTY_KEY_ARROW_DOWN),
    _KeyOption('Left', GhosttyKey.GHOSTTY_KEY_ARROW_LEFT),
    _KeyOption('Right', GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT),
    _KeyOption('F1', GhosttyKey.GHOSTTY_KEY_F1),
    _KeyOption('F2', GhosttyKey.GHOSTTY_KEY_F2),
  ];

  static const List<_ModOption> _mods = <_ModOption>[
    _ModOption('Shift', GhosttyModsMask.shift),
    _ModOption('Ctrl', GhosttyModsMask.ctrl),
    _ModOption('Alt', GhosttyModsMask.alt),
    _ModOption('Super', GhosttyModsMask.superKey),
  ];

  late final TabController _tabs = TabController(length: 4, vsync: this);

  final List<String> _activity = <String>[];
  GhosttyKeyAction _selectedAction = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
  GhosttyKey _selectedKey = GhosttyKey.GHOSTTY_KEY_C;
  final Set<int> _selectedMods = <int>{GhosttyModsMask.ctrl};
  bool _composing = false;
  bool _formatterPalette = false;
  bool _formatterModes = false;
  bool _formatterScrollingRegion = false;
  bool _formatterTabstops = false;
  bool _formatterPwd = false;
  bool _formatterKeyboard = false;
  bool _formatterCursor = false;
  bool _formatterStyle = false;
  bool _formatterHyperlink = false;
  bool _formatterProtection = false;
  bool _formatterKittyKeyboard = false;
  bool _formatterCharsets = false;
  Uint8List _encodedBytes = Uint8List(0);
  String _plainSnapshot = '';
  String _vtSnapshot = '';
  String _htmlSnapshot = '';
  bool _pasteSafe = true;
  double _cellWidthScale = 1;
  GhosttyTerminalRendererMode _renderer = GhosttyTerminalRendererMode.formatter;
  VtOscCommand? _oscCommand;
  String? _oscError;
  List<VtSgrAttributeData> _sgrAttributes = <VtSgrAttributeData>[];
  String? _sgrError;

  GhosttyTerminalShellLaunch? get _controllerLaunch =>
      _terminal.activeShellLaunch;

  String get _currentShellLabel =>
      _controllerLaunch?.label ?? _activeShellLabel;

  String get _currentShellCommand =>
      _controllerLaunch?.commandLine ?? _activeShellCommand;

  Map<String, String> get _currentShellEnvironment =>
      _controllerLaunch?.environment ?? _activeShellEnvironment;

  @override
  void initState() {
    super.initState();
    _terminal = widget.controller ?? GhosttyTerminalController();
    _ownsTerminal = widget.controller == null;
    _terminal.addListener(_onTerminalChanged);
    if (widget.autoStart) {
      _bootstrap();
    }
    _recomputeInspectorState(addLog: false);
  }

  @override
  void dispose() {
    _terminal.removeListener(_onTerminalChanged);
    if (_ownsTerminal) {
      _terminal.dispose();
    }
    _tabs.dispose();
    _commandController.dispose();
    _oscController.dispose();
    _sgrController.dispose();
    _utf8Controller.dispose();
    _codepointController.dispose();
    _fontFamilyController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final launch = await _startDemoShell();
    _activeShellLabel = launch.label;
    _activeShellCommand = launch.commandLine;
    _activeShellEnvironment = launch.environment ?? const <String, String>{};
    if (kIsWeb) {
      _terminal.appendDebugOutput(
        '\x1b]2;Ghostty VT Studio\x07'
        '\x1b[32mweb demo backend attached\x1b[0m\n'
        '\x1b[90mType into the terminal and inspect formatter outputs on the right.\x1b[0m\n',
      );
    }
    _appendLog('Terminal session started (${launch.label}).');
    _recomputeInspectorState(addLog: false);
    if (mounted) {
      setState(() {});
    }
  }

  Future<_DemoShellLaunch> _startDemoShell() async {
    if (kIsWeb) {
      await _terminal.start();
      return const _DemoShellLaunch(
        label: 'web transport demo',
        commandLine: 'web transport demo',
      );
    }

    final launch = await _terminal.startShellProfile(
      profile: _selectedShellProfile,
      platformEnvironment: ghosttyTerminalPlatformEnvironment(),
    );
    if (launch != null) {
      return _DemoShellLaunch(
        label: launch.label,
        commandLine: launch.commandLine,
        environment: launch.environment,
      );
    }

    final fallbackEnvironment = ghosttyTerminalShellEnvironment(
      platformEnvironment: ghosttyTerminalPlatformEnvironment(),
      overrides: const <String, String>{'TERM': 'xterm-256color'},
    );
    await _terminal.start(environment: fallbackEnvironment);
    return _DemoShellLaunch(
      label: 'default shell fallback',
      commandLine: '(default shell)',
      environment: fallbackEnvironment,
    );
  }

  Future<void> _selectShellProfile(GhosttyTerminalShellProfile profile) async {
    if (_selectedShellProfile == profile) {
      return;
    }
    setState(() {
      _selectedShellProfile = profile;
    });
    if (_terminal.isRunning) {
      await _restartTerminal();
    }
  }

  void _onTerminalChanged() {
    if (!mounted) {
      return;
    }
    _refreshSnapshots();
    setState(() {});
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _activity.insert(0, '$hh:$mm:$ss  $message');
    if (_activity.length > 120) {
      _activity.removeLast();
    }
  }

  void _refreshSnapshots() {
    _plainSnapshot = _terminal.plainText;
    final extra = VtFormatterTerminalExtra(
      palette: _formatterPalette,
      modes: _formatterModes,
      scrollingRegion: _formatterScrollingRegion,
      tabstops: _formatterTabstops,
      pwd: _formatterPwd,
      keyboard: _formatterKeyboard,
      screen: VtFormatterScreenExtra(
        cursor: _formatterCursor,
        style: _formatterStyle,
        hyperlink: _formatterHyperlink,
        protection: _formatterProtection,
        kittyKeyboard: _formatterKittyKeyboard,
        charsets: _formatterCharsets,
      ),
    );
    _vtSnapshot = _terminal.formatTerminal(
      emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_VT,
      extra: extra,
      trim: false,
    );
    _htmlSnapshot = _terminal.formatTerminal(
      emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_HTML,
      extra: extra,
      trim: false,
    );
  }

  void _recomputeInspectorState({bool addLog = true}) {
    _refreshSnapshots();
    _pasteSafe = GhosttyVt.isPasteSafe(_commandController.text);
    _parseOsc();
    _parseSgr();
    _encodeKeyPreview();
    if (addLog) {
      _appendLog('Refreshed formatter, parser, and key inspector state.');
    }
  }

  Future<void> _restartTerminal() async {
    await _terminal.stop();
    final launch = await _startDemoShell();
    _activeShellLabel = launch.label;
    _activeShellCommand = launch.commandLine;
    _activeShellEnvironment = launch.environment ?? const <String, String>{};
    _appendLog('Terminal session restarted (${launch.label}).');
    _recomputeInspectorState(addLog: false);
    setState(() {});
  }

  Future<void> _stopTerminal() async {
    await _terminal.stop();
    _appendLog('Terminal session stopped.');
    setState(() {});
  }

  Future<void> _copyShellEnvironment() async {
    final text = _formatEnvironment(_currentShellEnvironment);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied shell environment.')));
  }

  void _sendCommand() {
    final sent = _terminal.write(
      '${_commandController.text}\n',
      sanitizePaste: true,
    );
    if (sent) {
      _appendLog('Sent command to shell stdin.');
    } else {
      _appendLog(
        'Command send blocked (session stopped or paste safety failed).',
      );
    }
    setState(() {});
  }

  void _injectDemoOutput() {
    _terminal.appendDebugOutput(
      '\x1b]2;Ghostty VT Studio\x07'
      '\x1b[1;32mVT demo\x1b[0m  '
      '\x1b[4;38;2;255;190;92mwrapped formatter output\x1b[0m\n'
      'normal line\n'
      '\x1b[2Koverwritten line\rrepainted line\n'
      '\x1b[90mOSC title and SGR styling are feeding the live terminal.\x1b[0m\n',
    );
    _appendLog('Injected demo VT output into the terminal buffer.');
    _recomputeInspectorState(addLog: false);
    setState(() {});
  }

  void _clearTerminal() {
    _terminal.clear();
    _appendLog('Reset terminal and cleared scrollback snapshot.');
    _recomputeInspectorState(addLog: false);
    setState(() {});
  }

  void _sendQuickKey(GhosttyKey key, {int mods = 0, String utf8Text = ''}) {
    final sent = _terminal.sendKey(
      key: key,
      mods: mods,
      utf8Text: utf8Text,
      unshiftedCodepoint: utf8Text.isEmpty ? 0 : utf8Text.runes.first,
    );
    _appendLog(
      sent ? 'Sent key ${key.name}.' : 'Key send failed (terminal stopped).',
    );
    setState(() {});
  }

  void _encodeKeyPreview() {
    final encoder = VtKeyEncoder();
    final event = VtKeyEvent();
    try {
      encoder.setOptionsFromTerminal(_terminal.terminal);
      event
        ..action = _selectedAction
        ..key = _selectedKey
        ..mods = _maskFrom(_selectedMods)
        ..composing = _composing
        ..utf8Text = _utf8Controller.text
        ..unshiftedCodepoint = _parseCodepoint(_codepointController.text);
      _encodedBytes = encoder.encode(event);
    } catch (_) {
      _encodedBytes = Uint8List(0);
    } finally {
      event.close();
      encoder.close();
    }
  }

  int _maskFrom(Set<int> values) {
    var out = 0;
    for (final value in values) {
      out |= value;
    }
    return out;
  }

  int _parseCodepoint(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      return int.parse(trimmed.substring(2), radix: 16);
    }
    return int.parse(trimmed);
  }

  void _parseOsc() {
    final parser = VtOscParser();
    try {
      parser.addText(_oscController.text);
      _oscCommand = parser.end();
      _oscError = null;
    } catch (error) {
      _oscCommand = null;
      _oscError = error.toString();
    } finally {
      parser.close();
    }
  }

  void _parseSgr() {
    final matches = RegExp(r'\d+').allMatches(_sgrController.text);
    final values = matches.map((m) => int.parse(m.group(0)!)).toList();
    if (values.isEmpty) {
      _sgrAttributes = <VtSgrAttributeData>[];
      _sgrError = 'Enter one or more integer params such as 1;31;4.';
      return;
    }

    final parser = VtSgrParser();
    try {
      _sgrAttributes = parser.parseParams(values);
      _sgrError = null;
    } catch (error) {
      _sgrAttributes = <VtSgrAttributeData>[];
      _sgrError = error.toString();
    } finally {
      parser.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1180;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghostty VT Studio'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _terminal.isRunning ? _stopTerminal : _restartTerminal,
            icon: Icon(
              _terminal.isRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow_outlined,
            ),
            label: Text(_terminal.isRunning ? 'Stop' : 'Start'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 8, child: _buildTerminalColumn(theme)),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: _buildInspector(theme)),
                ],
              )
            : ListView(
                children: <Widget>[
                  SizedBox(height: 620, child: _buildTerminalColumn(theme)),
                  const SizedBox(height: 16),
                  SizedBox(height: 560, child: _buildInspector(theme)),
                ],
              ),
      ),
    );
  }

  Widget _buildTerminalColumn(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!kIsWeb) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: GhosttyTerminalShellProfile.values
                .map(
                  (profile) => ChoiceChip(
                    label: Text(profile.label),
                    selected: _selectedShellProfile == profile,
                    onSelected: (_) => _selectShellProfile(profile),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _sendCommand,
              icon: const Icon(Icons.subdirectory_arrow_left),
              label: const Text('Send Command'),
            ),
            OutlinedButton.icon(
              onPressed: _injectDemoOutput,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Inject VT Demo'),
            ),
            OutlinedButton.icon(
              onPressed: _clearTerminal,
              icon: const Icon(Icons.layers_clear),
              label: const Text('Reset'),
            ),
            OutlinedButton.icon(
              onPressed: _restartTerminal,
              icon: const Icon(Icons.refresh),
              label: const Text('Restart Shell'),
            ),
            _StatusPill(
              label: _terminal.isRunning ? 'Running' : 'Stopped',
              color: _terminal.isRunning
                  ? const Color(0xFF2BD576)
                  : const Color(0xFFD65C5C),
            ),
            _StatusPill(
              label: '${_terminal.cols} x ${_terminal.rows}',
              color: theme.colorScheme.secondary,
            ),
            _StatusPill(
              label: '${_terminal.lineCount} lines',
              color: theme.colorScheme.tertiary,
            ),
            _StatusPill(
              label: _currentShellLabel,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commandController,
          onChanged: (_) => setState(() {
            _pasteSafe = GhosttyVt.isPasteSafe(_commandController.text);
          }),
          decoration: InputDecoration(
            labelText: 'Shell command or pasted text',
            helperText: _pasteSafe
                ? 'Paste-safe input'
                : 'Paste safety would block this input',
            helperStyle: TextStyle(
              color: _pasteSafe
                  ? const Color(0xFF76E5B1)
                  : const Color(0xFFFFA899),
            ),
            border: const OutlineInputBorder(),
            suffixIcon: Icon(
              _pasteSafe ? Icons.verified : Icons.warning_amber_rounded,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 280,
              child: TextField(
                controller: _fontFamilyController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Terminal font family',
                  hintText: 'JetBrainsMono Nerd Font',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Cell width scale ${_cellWidthScale.toStringAsFixed(2)}',
                  ),
                  Slider(
                    value: _cellWidthScale,
                    min: 0.75,
                    max: 1.4,
                    divisions: 13,
                    label: _cellWidthScale.toStringAsFixed(2),
                    onChanged: (value) => setState(() {
                      _cellWidthScale = value;
                    }),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Ghostty Paint'),
                  selected: _renderer == GhosttyTerminalRendererMode.formatter,
                  onSelected: (_) => setState(() {
                    _renderer = GhosttyTerminalRendererMode.formatter;
                  }),
                ),
                ChoiceChip(
                  label: const Text('UV Paint'),
                  selected:
                      _renderer == GhosttyTerminalRendererMode.ultraviolet,
                  onSelected: (_) => setState(() {
                    _renderer = GhosttyTerminalRendererMode.ultraviolet;
                  }),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: GhosttyTerminalView(
                controller: _terminal,
                autofocus: true,
                chromeColor: const Color(0xFF10212C),
                backgroundColor: const Color(0xFF060D13),
                foregroundColor: const Color(0xFFE7F8F5),
                fontSize: 14,
                lineHeight: 1.32,
                fontFamily: _fontFamilyController.text.trim().isEmpty
                    ? null
                    : _fontFamilyController.text.trim(),
                cellWidthScale: _cellWidthScale,
                renderer: _renderer,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(GhosttyKey.GHOSTTY_KEY_ARROW_UP),
              child: const Text('Up'),
            ),
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(GhosttyKey.GHOSTTY_KEY_ARROW_LEFT),
              child: const Text('Left'),
            ),
            FilledButton.tonal(
              onPressed: () =>
                  _sendQuickKey(GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT),
              child: const Text('Right'),
            ),
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(GhosttyKey.GHOSTTY_KEY_BACKSPACE),
              child: const Text('Backspace'),
            ),
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(
                GhosttyKey.GHOSTTY_KEY_C,
                mods: GhosttyModsMask.ctrl,
                utf8Text: 'c',
              ),
              child: const Text('Ctrl+C'),
            ),
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(GhosttyKey.GHOSTTY_KEY_TAB),
              child: const Text('Tab'),
            ),
            FilledButton.tonal(
              onPressed: () => _sendQuickKey(GhosttyKey.GHOSTTY_KEY_ENTER),
              child: const Text('Enter'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInspector(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF09131C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          TabBar(
            controller: _tabs,
            tabs: const <Tab>[
              Tab(text: 'Snapshots'),
              Tab(text: 'Key Encoder'),
              Tab(text: 'Parsers'),
              Tab(text: 'Session'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: <Widget>[
                _buildSnapshotsTab(),
                _buildKeyTab(),
                _buildParserTab(),
                _buildSessionTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Formatter Extras',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _boolChip(
              'Palette',
              _formatterPalette,
              (v) => setState(() {
                _formatterPalette = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Modes',
              _formatterModes,
              (v) => setState(() {
                _formatterModes = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Scrolling Region',
              _formatterScrollingRegion,
              (v) => setState(() {
                _formatterScrollingRegion = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Tabstops',
              _formatterTabstops,
              (v) => setState(() {
                _formatterTabstops = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'PWD',
              _formatterPwd,
              (v) => setState(() {
                _formatterPwd = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Keyboard',
              _formatterKeyboard,
              (v) => setState(() {
                _formatterKeyboard = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Cursor',
              _formatterCursor,
              (v) => setState(() {
                _formatterCursor = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Style',
              _formatterStyle,
              (v) => setState(() {
                _formatterStyle = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Hyperlink',
              _formatterHyperlink,
              (v) => setState(() {
                _formatterHyperlink = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Protection',
              _formatterProtection,
              (v) => setState(() {
                _formatterProtection = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Kitty Keyboard',
              _formatterKittyKeyboard,
              (v) => setState(() {
                _formatterKittyKeyboard = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
            _boolChip(
              'Charsets',
              _formatterCharsets,
              (v) => setState(() {
                _formatterCharsets = v;
                _recomputeInspectorState(addLog: false);
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _snapshotCard('Plain Text', _plainSnapshot),
        const SizedBox(height: 12),
        _snapshotCard('VT Output', _vtSnapshot),
        const SizedBox(height: 12),
        _snapshotCard('HTML Output', _htmlSnapshot),
      ],
    );
  }

  Widget _buildKeyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<GhosttyKeyAction>(
                initialValue: _selectedAction,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(),
                ),
                items: _actions
                    .map(
                      (option) => DropdownMenuItem<GhosttyKeyAction>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedAction = value;
                    _encodeKeyPreview();
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<GhosttyKey>(
                initialValue: _selectedKey,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  border: OutlineInputBorder(),
                ),
                items: _keys
                    .map(
                      (option) => DropdownMenuItem<GhosttyKey>(
                        value: option.value,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedKey = value;
                    _encodeKeyPreview();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _mods
              .map(
                (option) => FilterChip(
                  label: Text(option.label),
                  selected: _selectedMods.contains(option.mask),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedMods.add(option.mask);
                      } else {
                        _selectedMods.remove(option.mask);
                      }
                      _encodeKeyPreview();
                    });
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _utf8Controller,
                decoration: const InputDecoration(
                  labelText: 'UTF-8 text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(_encodeKeyPreview),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _codepointController,
                decoration: const InputDecoration(
                  labelText: 'Unshifted codepoint',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(_encodeKeyPreview),
              ),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          value: _composing,
          title: const Text('Composing'),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _composing = value;
              _encodeKeyPreview();
            });
          },
        ),
        const SizedBox(height: 8),
        _snapshotCard(
          'Encoded bytes',
          _encodedBytes.isEmpty
              ? '(empty)'
              : _encodedBytes
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(' '),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            final sent = _terminal.sendKey(
              key: _selectedKey,
              action: _selectedAction,
              mods: _maskFrom(_selectedMods),
              composing: _composing,
              utf8Text: _utf8Controller.text,
              unshiftedCodepoint: _parseCodepoint(_codepointController.text),
            );
            _appendLog(
              sent ? 'Sent custom key event.' : 'Key event send failed.',
            );
            setState(() {});
          },
          icon: const Icon(Icons.keyboard),
          label: const Text('Send Key Event'),
        ),
      ],
    );
  }

  Widget _buildParserTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Paste Safety',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _pasteSafe
              ? 'Current command is safe to paste.'
              : 'Current command would be blocked by paste safety.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _oscController,
          decoration: const InputDecoration(
            labelText: 'OSC payload',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {
            _parseOsc();
          }),
        ),
        const SizedBox(height: 8),
        _snapshotCard(
          'OSC result',
          _oscError ??
              'type=${_oscCommand?.type.name ?? 'unknown'}\nwindowTitle=${_oscCommand?.windowTitle ?? '(none)'}',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _sgrController,
          decoration: const InputDecoration(
            labelText: 'SGR params',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {
            _parseSgr();
          }),
        ),
        const SizedBox(height: 8),
        _snapshotCard(
          'SGR attributes',
          _sgrError ??
              (_sgrAttributes.isEmpty
                  ? '(none)'
                  : _sgrAttributes
                        .map((attr) => _describeSgr(attr))
                        .join('\n')),
        ),
      ],
    );
  }

  Widget _buildSessionTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _snapshotCard(
          'Session Stats',
          'running=${_terminal.isRunning}\n'
              'title=${_terminal.title}\n'
              'size=${_terminal.cols}x${_terminal.rows}\n'
              'lines=${_terminal.lineCount}\n'
              'scrollback=${_terminal.maxScrollback}',
        ),
        const SizedBox(height: 12),
        _snapshotCard(
          'Launch',
          'profile=${_selectedShellProfile.label}\n'
              'label=$_currentShellLabel\n'
              'command=$_currentShellCommand',
        ),
        const SizedBox(height: 12),
        _snapshotCard(
          'Environment',
          _formatEnvironment(_currentShellEnvironment),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _copyShellEnvironment,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Environment'),
          ),
        ),
        const SizedBox(height: 12),
        _snapshotCard(
          'Recent Activity',
          _activity.isEmpty ? '(no activity yet)' : _activity.join('\n'),
        ),
      ],
    );
  }

  Widget _snapshotCard(String title, String body) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF193041)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boolChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
    );
  }

  String _describeSgr(VtSgrAttributeData attr) {
    final buffer = StringBuffer(attr.tag.name);
    if (attr.paletteIndex != null) {
      buffer.write(' index=${attr.paletteIndex}');
    }
    if (attr.rgb != null) {
      buffer.write(' rgb=${attr.rgb}');
    }
    if (attr.underline != null) {
      buffer.write(' underline=${attr.underline!.name}');
    }
    if (attr.unknown != null) {
      buffer.write(' unknown=${attr.unknown!.partial}');
    }
    return buffer.toString();
  }

  String _formatEnvironment(Map<String, String> environment) {
    if (environment.isEmpty) {
      return '(inherited or unavailable)';
    }
    final entries = environment.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
  }
}

class _DemoShellLaunch {
  const _DemoShellLaunch({
    required this.label,
    required this.commandLine,
    this.environment,
  });

  final String label;
  final String commandLine;
  final Map<String, String>? environment;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ActionOption {
  const _ActionOption(this.label, this.value);

  final String label;
  final GhosttyKeyAction value;
}

class _KeyOption {
  const _KeyOption(this.label, this.value);

  final String label;
  final GhosttyKey value;
}

class _ModOption {
  const _ModOption(this.label, this.mask);

  final String label;
  final int mask;
}
