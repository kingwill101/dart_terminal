import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  group('GhosttyTerminalView', () {
    late GhosttyTerminalController controller;

    setUp(() {
      controller = GhosttyTerminalController();
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildView({
      bool autofocus = false,
      FocusNode? focusNode,
      Color? backgroundColor,
      Color? foregroundColor,
      double? fontSize,
      double? lineHeight,
      GhosttyTerminalCopyOptions copyOptions =
          const GhosttyTerminalCopyOptions(),
      GhosttyTerminalWordBoundaryPolicy wordBoundaryPolicy =
          const GhosttyTerminalWordBoundaryPolicy(),
      EdgeInsets? padding,
      ValueChanged<GhosttyTerminalSelection?>? onSelectionChanged,
      ValueChanged<GhosttyTerminalSelectionContent<GhosttyTerminalSelection>?>?
      onSelectionContentChanged,
      Future<void> Function(String uri)? onOpenHyperlink,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: GhosttyTerminalView(
              controller: controller,
              autofocus: autofocus,
              focusNode: focusNode,
              backgroundColor: backgroundColor ?? const Color(0xFF0A0F14),
              foregroundColor: foregroundColor ?? const Color(0xFFE6EDF3),
              fontSize: fontSize ?? 14,
              lineHeight: lineHeight ?? 1.35,
              copyOptions: copyOptions,
              wordBoundaryPolicy: wordBoundaryPolicy,
              padding: padding ?? const EdgeInsets.all(12),
              onSelectionChanged: onSelectionChanged,
              onSelectionContentChanged: onSelectionContentChanged,
              onOpenHyperlink: onOpenHyperlink,
            ),
          ),
        ),
      );
    }

    testWidgets('renders and reports a terminal grid', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(controller.cols, greaterThan(0));
      expect(controller.rows, greaterThan(0));
    });

    testWidgets('renders VT-backed controller output', (tester) async {
      controller.appendDebugOutput('hello\r\nsecond line');
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(controller.lines, ['hello', 'second line']);
      expect(controller.plainText, 'hello\nsecond line');
    });

    testWidgets('exposes native render-state data while the view renders', (
      tester,
    ) async {
      controller.appendDebugOutput('\u001b[31mhello\u001b[0m\r\nsecond line');
      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
      expect(controller.renderSnapshot, isNotNull);
      expect(controller.snapshot.lines, isNotEmpty);
      expect(controller.snapshot.lines.first.text, contains('hello'));
    });

    testWidgets('updates when controller notifies', (tester) async {
      await tester.pumpWidget(buildView());

      final initialRevision = controller.revision;
      controller.appendDebugOutput('new output');
      await tester.pump();

      expect(controller.revision, greaterThan(initialRevision));
      expect(controller.lines.single, 'new output');
    });

    testWidgets('autofocus requests focus on build', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildView(autofocus: true, focusNode: focusNode));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('switches controllers correctly', (tester) async {
      final controller2 = GhosttyTerminalController();
      addTearDown(controller2.dispose);

      controller.appendDebugOutput('from controller 1');
      await tester.pumpWidget(buildView());
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(controller: controller2),
            ),
          ),
        ),
      );

      controller2.appendDebugOutput('from controller 2');
      await tester.pump();

      expect(controller2.lines.single, 'from controller 2');
    });

    testWidgets('applies custom styling props', (tester) async {
      await tester.pumpWidget(
        buildView(
          backgroundColor: const Color(0xFF000000),
          foregroundColor: const Color(0xFFFFFFFF),
          fontSize: 18,
          lineHeight: 1.5,
          padding: const EdgeInsets.all(24),
        ),
      );

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('cell width scale changes the reported grid columns', (
      tester,
    ) async {
      final defaultController = GhosttyTerminalController();
      addTearDown(defaultController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(controller: defaultController),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final defaultCols = defaultController.cols;

      final scaledController = GhosttyTerminalController();
      addTearDown(scaledController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: scaledController,
                fontFamily: 'monospace',
                cellWidthScale: 1.25,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scaledController.cols, lessThan(defaultCols));
    });

    testWidgets('handles many lines without overflow', (tester) async {
      final manyLines = List.generate(200, (i) => 'Line $i').join('\r\n');
      controller.appendDebugOutput(manyLines);

      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(controller.lineCount, 200);
      expect(controller.lines.first, 'Line 0');
      expect(controller.lines.last, 'Line 199');
    });

    testWidgets('handles empty lines and explicit line starts', (tester) async {
      controller.appendDebugOutput('line1\r\n\r\n\r\nline4');

      await tester.pumpWidget(buildView());
      await tester.pump();

      expect(controller.lines, ['line1', '', '', 'line4']);
    });

    testWidgets('select-all and escape expose selection callbacks', (
      tester,
    ) async {
      GhosttyTerminalSelection? currentSelection;
      GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;
      controller.appendDebugOutput('hello  \r\nsecond line');

      await tester.pumpWidget(
        buildView(
          autofocus: true,
          onSelectionChanged: (selection) => currentSelection = selection,
          onSelectionContentChanged: (content) => currentContent = content,
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(currentSelection, isNotNull);
      expect(currentContent?.text, 'hello\nsecond line');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(currentSelection, isNull);
      expect(currentContent, isNull);
    });
  });

  group('GhosttyTerminalSnapshot', () {
    test('word selection respects custom boundary policy', () {
      const snapshot = GhosttyTerminalSnapshot(
        lines: <GhosttyTerminalLine>[
          GhosttyTerminalLine(<GhosttyTerminalRun>[
            GhosttyTerminalRun(text: 'alpha-beta gamma', cells: 16),
          ]),
        ],
        cursor: GhosttyTerminalCursor(row: 0, col: 0),
      );

      final defaultSelection = snapshot.wordSelectionAt(
        const GhosttyTerminalCellPosition(row: 0, col: 5),
      );
      final strictSelection = snapshot.wordSelectionAt(
        const GhosttyTerminalCellPosition(row: 0, col: 5),
        policy: const GhosttyTerminalWordBoundaryPolicy(
          extraWordCharacters: '._/~:@%#?&=+',
        ),
      );

      expect(snapshot.textForSelection(defaultSelection!), 'alpha-beta');
      expect(snapshot.textForSelection(strictSelection!), '-');
    });

    test('line selection and copy options are exposed from the snapshot', () {
      const snapshot = GhosttyTerminalSnapshot(
        lines: <GhosttyTerminalLine>[
          GhosttyTerminalLine(<GhosttyTerminalRun>[
            GhosttyTerminalRun(text: 'hello  ', cells: 7),
          ]),
          GhosttyTerminalLine(<GhosttyTerminalRun>[
            GhosttyTerminalRun(text: 'second', cells: 6),
          ]),
        ],
        cursor: GhosttyTerminalCursor(row: 1, col: 6),
      );

      final selection = snapshot.lineSelectionBetweenRows(0, 1);
      expect(selection, isNotNull);
      expect(snapshot.textForSelection(selection!), 'hello\nsecond');
      expect(
        snapshot.textForSelection(
          selection,
          options: const GhosttyTerminalCopyOptions(trimTrailingSpaces: false),
        ),
        'hello  \nsecond',
      );
      expect(snapshot.selectAllSelection(), selection);
    });
  });

  group('GhosttyTerminalView keyboard handling', () {
    late GhosttyTerminalController controller;

    setUp(() {
      controller = GhosttyTerminalController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('ignores key events when process not running', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('key up events are ignored', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('backspace is sent without printable text payload', (
      tester,
    ) async {
      final controller = _RecordingTerminalController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.lastKey, GhosttyKey.GHOSTTY_KEY_BACKSPACE);
      expect(controller.lastAction, GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS);
      expect(controller.lastUtf8Text, isEmpty);
      expect(controller.lastUnshiftedCodepoint, 0);
    });

    testWidgets('shifted underscore and plus are written as printable text', (
      tester,
    ) async {
      final controller = _InteractiveEchoTerminalController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.minus,
        physicalKey: PhysicalKeyboardKey.minus,
        character: '_',
      );
      await tester.sendKeyEvent(
        LogicalKeyboardKey.equal,
        physicalKey: PhysicalKeyboardKey.equal,
        character: '+',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.snapshot.lines.single.text, 'abc_+');
      expect(
        controller.snapshot.cursor,
        const GhosttyTerminalCursor(row: 0, col: 5),
      );
    });

    testWidgets(
      'backspace in the terminal area erases and the next key overwrites it',
      (tester) async {
        final controller = _InteractiveEchoTerminalController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: GhosttyTerminalView(
                  controller: controller,
                  autofocus: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(
          controller.snapshot.cursor,
          const GhosttyTerminalCursor(row: 0, col: 2),
        );
        expect(controller.snapshot.lines.single.text, 'ab ');

        await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
        await tester.pump();

        expect(
          controller.snapshot.cursor,
          const GhosttyTerminalCursor(row: 0, col: 3),
        );
        expect(controller.snapshot.lines.single.text, 'abd');
      },
    );
  });

  group('GhosttyTerminalController', () {
    late GhosttyTerminalController controller;

    setUp(() {
      controller = GhosttyTerminalController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial state', () {
      expect(controller.title, 'Terminal');
      expect(controller.isRunning, isFalse);
      expect(controller.lines, ['']);
      expect(controller.lineCount, 1);
      expect(controller.revision, 0);
      expect(controller.cols, 80);
      expect(controller.rows, 24);
    });

    test('appendDebugOutput increments revision and creates VT state', () {
      expect(controller.revision, 0);
      controller.appendDebugOutput('hello');
      expect(controller.revision, 1);
      expect(controller.terminal.cols, 80);
      expect(controller.terminal.rows, 24);
    });

    test('line feed preserves the current column in VT mode', () {
      controller.appendDebugOutput('a\nb\nc');

      expect(controller.lines, ['a', ' b', '  c']);
      expect(controller.plainText, 'a\n b\n  c');
    });

    test('carriage return overwrites the current line', () {
      controller.appendDebugOutput('hello\rworld');

      expect(controller.lines, ['world']);
    });

    test('backspace moves the cursor left without truncating the tail', () {
      controller.appendDebugOutput('abc\b\bd');

      expect(controller.lines, ['adc']);
    });

    test('shell erase echo clears the cell and leaves the cursor there', () {
      controller.appendDebugOutput('abc\b \b');

      expect(controller.lines, ['ab']);
      expect(
        controller.snapshot.cursor,
        const GhosttyTerminalCursor(row: 0, col: 2),
      );
    });

    test('clear resets lines', () {
      controller.appendDebugOutput('some\r\ntext');
      expect(controller.lineCount, 2);

      controller.clear();
      expect(controller.lines, ['']);
      expect(controller.lineCount, 1);
    });

    test('resize updates the live terminal grid', () {
      controller.resize(cols: 132, rows: 40);

      expect(controller.cols, 132);
      expect(controller.rows, 40);
      expect(controller.terminal.cols, 132);
      expect(controller.terminal.rows, 40);
    });

    test('OSC title commands are parsed', () {
      controller.appendDebugOutput('\x1b]0;My Title\x07');
      expect(controller.title, 'My Title');

      controller.appendDebugOutput('\x1b]2;Another Title\x07');
      expect(controller.title, 'Another Title');

      controller.appendDebugOutput('\x1b]0;ST Title\x1b\\');
      expect(controller.title, 'ST Title');
    });

    test('plain formatting strips CSI while VT formatting preserves it', () {
      controller.appendDebugOutput('\x1b[31;1mred bold\x1b[0m normal');

      expect(controller.lines.single, 'red bold normal');
      final vtOutput = controller.formatTerminal(
        emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_VT,
        trim: false,
      );
      expect(vtOutput, contains('red bold'));
      expect(vtOutput, contains('\x1b['));
    });

    test('styled snapshot keeps ANSI colors, emphasis, and cursor info', () {
      controller.appendDebugOutput(
        '\x1b[31;1mred\x1b[0m normal\r\nplain \x1b[4;34mblue\x1b[0m',
      );

      final snapshot = controller.snapshot;
      expect(snapshot.cursor, isNotNull);
      expect(snapshot.lines, hasLength(2));

      final firstLine = snapshot.lines[0].runs;
      expect(firstLine[0].text, 'red');
      expect(firstLine[0].style.bold, isTrue);
      expect(
        firstLine[0].style.foreground,
        const GhosttyTerminalColor.palette(1),
      );
      expect(firstLine[1].text, ' normal');

      final secondLine = snapshot.lines[1].runs;
      expect(secondLine[0].text, 'plain ');
      expect(secondLine[1].text, 'blue');
      expect(secondLine[1].style.underline, isNotNull);
      expect(
        secondLine[1].style.foreground,
        const GhosttyTerminalColor.palette(4),
      );
    });

    test('snapshot selection extracts multi-line text ranges', () {
      controller.appendDebugOutput('alpha\r\nbravo\r\ncharlie');

      final text = controller.snapshot.textForSelection(
        const GhosttyTerminalSelection(
          base: GhosttyTerminalCellPosition(row: 0, col: 2),
          extent: GhosttyTerminalCellPosition(row: 1, col: 2),
        ),
      );

      expect(text, 'pha\nbra');
    });

    test(
      'snapshot hyperlink lookup and word selection detect visible URLs',
      () {
        controller.appendDebugOutput('see https://example.com/docs now');

        final snapshot = controller.snapshot;
        expect(
          snapshot.hyperlinkAt(
            const GhosttyTerminalCellPosition(row: 0, col: 8),
          ),
          'https://example.com/docs',
        );

        final selection = snapshot.wordSelectionAt(
          const GhosttyTerminalCellPosition(row: 0, col: 12),
        );
        expect(selection, isNotNull);
        expect(
          snapshot.textForSelection(selection!),
          'https://example.com/docs',
        );
      },
    );

    test('maxLines truncates old lines from formatted snapshots', () {
      final small = GhosttyTerminalController(maxLines: 5);
      addTearDown(small.dispose);

      small.appendDebugOutput('1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7\r\n8');
      expect(small.lineCount, 5);
      expect(small.lines.first, '4');
      expect(small.lines.last, '8');
    });

    test('notifyListeners called on appendDebugOutput and clear', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.appendDebugOutput('test');
      controller.clear();

      expect(notifications, 2);
    });

    test('write, writeBytes, and sendKey return false when not running', () {
      expect(controller.write('hello'), isFalse);
      expect(controller.writeBytes([0x68, 0x69]), isFalse);
      expect(controller.sendKey(key: GhosttyKey.GHOSTTY_KEY_ENTER), isFalse);
    });

    test(
      'carriage return plus line feed starts the next line at column zero',
      () {
        controller.appendDebugOutput('hello\r\nworld');

        expect(controller.lines, ['hello', 'world']);
      },
    );

    test('interactive shell backspace rewrites the prompt line', () async {
      if (!(Platform.isLinux || Platform.isMacOS)) {
        return;
      }

      final shellController = GhosttyTerminalController(
        defaultShell: '/bin/bash',
      );
      addTearDown(shellController.dispose);

      await shellController.start(
        shell: '/bin/bash',
        arguments: const <String>['--noprofile', '--norc', '-i'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(shellController.write("PS1='> '\n"), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(shellController.write('abc'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_BACKSPACE),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shellController.write('d'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(_lastNonEmptyLine(shellController.lines), endsWith('abd'));
    });

    test('interactive clean zsh handles arrow editing and backspace', () async {
      if (!(Platform.isLinux || Platform.isMacOS)) {
        return;
      }

      final shellController = GhosttyTerminalController(defaultShell: 'zsh');
      addTearDown(shellController.dispose);

      try {
        await shellController.start(
          shell: 'zsh',
          arguments: const <String>['-f', '-i'],
        );
      } on ProcessException {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        shellController.write(
          "PROMPT='%# '\n"
          "RPROMPT=\n"
          "unsetopt TRANSIENT_RPROMPT\n",
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(shellController.write('ac'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_ARROW_LEFT),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shellController.write('b'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_BACKSPACE),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shellController.write('c'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(_lastNonEmptyLine(shellController.lines), endsWith('abc'));
    });

    test('interactive clean zsh handles editing with a right prompt', () async {
      if (!(Platform.isLinux || Platform.isMacOS)) {
        return;
      }

      final shellController = GhosttyTerminalController(defaultShell: 'zsh');
      addTearDown(shellController.dispose);

      try {
        await shellController.start(
          shell: 'zsh',
          arguments: const <String>['-f', '-i'],
        );
      } on ProcessException {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        shellController.write(
          "PROMPT='%# '\n"
          "RPROMPT='R'\n"
          "unsetopt TRANSIENT_RPROMPT\n",
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(shellController.write('ac'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_ARROW_LEFT),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shellController.write('b'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        shellController.sendKey(key: GhosttyKey.GHOSTTY_KEY_BACKSPACE),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shellController.write('c'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      final line = _lastNonEmptyLine(shellController.lines);
      expect(line, contains('% abc'));
    });
  });

  group('decodeHexBytes', () {
    test('empty string returns empty bytes', () {
      expect(decodeHexBytes(''), isEmpty);
    });

    test('whitespace only returns empty bytes', () {
      expect(decodeHexBytes('   '), isEmpty);
    });

    test('single byte', () {
      expect(decodeHexBytes('1b'), [0x1b]);
    });

    test('multiple bytes', () {
      expect(decodeHexBytes('1b 5b 41'), [0x1b, 0x5b, 0x41]);
    });

    test('handles extra whitespace', () {
      expect(decodeHexBytes('  0a   0d  '), [0x0a, 0x0d]);
    });
  });
}

class _RecordingTerminalController extends GhosttyTerminalController {
  GhosttyKey? lastKey;
  GhosttyKeyAction? lastAction;
  String lastUtf8Text = '';
  int lastUnshiftedCodepoint = 0;

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
    lastKey = key;
    lastAction = action;
    lastUtf8Text = utf8Text;
    lastUnshiftedCodepoint = unshiftedCodepoint;
    return true;
  }
}

class _InteractiveEchoTerminalController extends GhosttyTerminalController {
  _InteractiveEchoTerminalController() : super() {
    appendDebugOutput('abc');
  }

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
    if (action == GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS &&
        key == GhosttyKey.GHOSTTY_KEY_BACKSPACE) {
      appendDebugOutput('\b \b');
      return true;
    }
    return false;
  }

  @override
  bool write(String text, {bool sanitizePaste = false}) {
    appendDebugOutput(text);
    return true;
  }
}

List<int> decodeHexBytes(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const <int>[];
  }
  return trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => int.parse(part, radix: 16))
      .toList(growable: false);
}

String _lastNonEmptyLine(List<String> lines) {
  return lines
      .lastWhere(
        (line) => line.trim().isNotEmpty,
        orElse: () => lines.isEmpty ? '' : lines.last,
      )
      .trimRight();
}
