import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'package:example/main.dart';

void main() {
  String? clipboardText;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              clipboardText =
                  (methodCall.arguments as Map<Object?, Object?>)['text']
                      as String?;
              return null;
            case 'Clipboard.getData':
              return clipboardText == null
                  ? null
                  : <String, Object?>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('renders terminal studio shell', (WidgetTester tester) async {
    final controller = _FakeTerminalController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MyApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    expect(find.text('Ghostty VT Studio'), findsOneWidget);
    expect(find.text('Send Command'), findsOneWidget);
    expect(find.text('Inject VT Demo'), findsOneWidget);
    expect(find.text('Restart Shell'), findsOneWidget);
    expect(find.text('Snapshots', skipOffstage: false), findsOneWidget);
    expect(find.text('Key Encoder', skipOffstage: false), findsOneWidget);
    expect(find.text('Parsers', skipOffstage: false), findsOneWidget);
    expect(find.text('Session', skipOffstage: false), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Ghostty Paint'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'UV Paint'), findsOneWidget);
  });

  testWidgets('switches shell profiles from the selector', (
    WidgetTester tester,
  ) async {
    final controller = _FakeTerminalController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MyApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Auto'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Bash'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Zsh'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'User Shell'), findsOneWidget);
    expect(find.text('Terminal font family'), findsOneWidget);
    expect(find.textContaining('Cell width scale'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Ghostty Paint'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'UV Paint'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Zsh'));
    await tester.pumpAndSettle();

    expect(find.text('clean zsh shell'), findsOneWidget);
    expect(controller.startCalls, greaterThanOrEqualTo(1));
    expect(controller.stopCalls, greaterThanOrEqualTo(1));

    await tester.tap(find.widgetWithText(ChoiceChip, 'UV Paint'));
    await tester.pumpAndSettle();

    final terminalView = tester.widget<GhosttyTerminalView>(
      find.byType(GhosttyTerminalView),
    );
    expect(terminalView.renderer, GhosttyTerminalRendererMode.ultraviolet);
  });

  testWidgets('session tab exposes launch environment details', (
    WidgetTester tester,
  ) async {
    final controller = _FakeTerminalController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MyApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Session', skipOffstage: false));
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bash'));
    await tester.pumpAndSettle();

    expect(find.textContaining('profile=Bash'), findsOneWidget);
    expect(find.textContaining('TERM=xterm-256color'), findsOneWidget);
    expect(find.textContaining('HOME=/tmp/demo-home'), findsOneWidget);
  });

  testWidgets('session tab can copy the effective environment', (
    WidgetTester tester,
  ) async {
    final controller = _FakeTerminalController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MyApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Session', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bash'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.text('Copy Environment', skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Environment', skipOffstage: false));
    await tester.pump();

    expect(clipboardText, contains('TERM=xterm-256color'));
    expect(clipboardText, contains('HOME=/tmp/demo-home'));
  });
}

class _FakeTerminalController extends GhosttyTerminalController {
  _FakeTerminalController() : super();

  final List<String> _lines = <String>['demo shell ready'];
  bool _running = true;
  int _revision = 0;
  int _cols = 80;
  int _rows = 24;
  final String _title = 'Ghostty VT Studio';
  int startCalls = 0;
  int stopCalls = 0;

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

  @override
  String get plainText => _lines.join('\n');

  @override
  List<String> get lines => List<String>.unmodifiable(_lines);

  @override
  int get lineCount => _lines.length;

  @override
  VtTerminal get terminal =>
      throw UnsupportedError('VT terminal is not used in widget tests.');

  @override
  String formatTerminal({
    GhosttyFormatterFormat emit =
        GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_PLAIN,
    bool unwrap = false,
    bool trim = true,
    VtFormatterTerminalExtra extra = const VtFormatterTerminalExtra(),
  }) {
    return switch (emit) {
      GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_HTML =>
        '<pre>$plainText</pre>',
      GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_VT =>
        '\u001b[32m$plainText\u001b[0m',
      _ => plainText,
    };
  }

  @override
  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
    Map<String, String>? environment,
  }) async {
    startCalls++;
    _running = true;
    _touch();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _running = false;
    _touch();
  }

  @override
  Future<GhosttyTerminalShellLaunch?> startShellProfile({
    required GhosttyTerminalShellProfile profile,
    Map<String, String>? platformEnvironment,
    Map<String, String> environmentOverrides = const <String, String>{
      'TERM': 'xterm-256color',
    },
  }) async {
    final environment = ghosttyTerminalShellEnvironment(
      platformEnvironment: const <String, String>{
        'HOME': '/tmp/demo-home',
        'SHELL': '/bin/zsh',
      },
      overrides: environmentOverrides,
    );
    final launch = GhosttyTerminalShellLaunch(
      label: switch (profile) {
        GhosttyTerminalShellProfile.cleanZsh => 'clean zsh shell',
        GhosttyTerminalShellProfile.cleanBash => 'clean bash shell',
        GhosttyTerminalShellProfile.userShell => 'user shell',
        GhosttyTerminalShellProfile.auto => 'clean bash shell',
      },
      shell: switch (profile) {
        GhosttyTerminalShellProfile.cleanZsh => '/bin/zsh',
        GhosttyTerminalShellProfile.cleanBash => '/bin/bash',
        GhosttyTerminalShellProfile.userShell => '/bin/zsh',
        GhosttyTerminalShellProfile.auto => '/bin/bash',
      },
      arguments: switch (profile) {
        GhosttyTerminalShellProfile.cleanZsh => const <String>['-f', '-i'],
        GhosttyTerminalShellProfile.cleanBash => const <String>[
          '--noprofile',
          '--norc',
          '-i',
        ],
        GhosttyTerminalShellProfile.userShell => const <String>['-i'],
        GhosttyTerminalShellProfile.auto => const <String>[
          '--noprofile',
          '--norc',
          '-i',
        ],
      },
      environment: environment,
    );
    await start(
      shell: launch.shell,
      arguments: launch.arguments,
      environment: environment,
    );
    return launch;
  }

  @override
  void clear() {
    _lines
      ..clear()
      ..add('');
    _touch();
  }

  @override
  void resize({required int cols, required int rows}) {
    _cols = cols;
    _rows = rows;
    _touch();
  }

  @override
  bool write(String text, {bool sanitizePaste = false}) {
    if (!_running) {
      return false;
    }
    final normalized = text.trimRight();
    if (normalized.isNotEmpty) {
      _lines.add(normalized);
    }
    _touch();
    return true;
  }

  @override
  bool writeBytes(List<int> bytes) => _running;

  @override
  bool sendKey({
    required GhosttyKey key,
    GhosttyKeyAction action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
    int mods = 0,
    int consumedMods = 0,
    bool composing = false,
    String utf8Text = '',
    int unshiftedCodepoint = 0,
  }) {
    return _running;
  }

  @override
  void appendDebugOutput(String text) {
    if (text.isEmpty) {
      return;
    }
    _lines.addAll(text.split('\n'));
    _touch();
  }

  void _touch() {
    _revision++;
    notifyListeners();
  }
}
