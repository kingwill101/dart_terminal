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
      EdgeInsets? padding,
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
              padding: padding ?? const EdgeInsets.all(12),
            ),
          ),
        ),
      );
    }

    testWidgets('renders with empty controller', (tester) async {
      await tester.pumpWidget(buildView());

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders lines from controller', (tester) async {
      controller.appendDebugOutput('hello world\nsecond line');
      await tester.pumpWidget(buildView());

      // The widget uses CustomPaint so lines aren't in the widget tree,
      // but we can verify the controller state is correct.
      expect(controller.lines, ['hello world', 'second line']);
      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('updates when controller notifies', (tester) async {
      await tester.pumpWidget(buildView());

      final initialRevision = controller.revision;
      controller.appendDebugOutput('new output');
      await tester.pump();

      expect(controller.revision, greaterThan(initialRevision));
      expect(controller.lines.last, 'new output');
    });

    testWidgets('autofocus requests focus on build', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildView(autofocus: true, focusNode: focusNode));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('tapping the view requests focus', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildView(focusNode: focusNode));
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.byType(GhosttyTerminalView));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('uses provided focus node', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildView(focusNode: focusNode));

      await tester.tap(find.byType(GhosttyTerminalView));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('creates own focus node when none provided', (tester) async {
      await tester.pumpWidget(buildView());

      await tester.tap(find.byType(GhosttyTerminalView));
      await tester.pump();

      // Should not throw — the widget manages its own focus node.
      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('disposes own focus node on unmount', (tester) async {
      await tester.pumpWidget(buildView());
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Should not throw during teardown.
      expect(find.byType(GhosttyTerminalView), findsNothing);
    });

    testWidgets('switches controllers correctly', (tester) async {
      final controller2 = GhosttyTerminalController();
      addTearDown(controller2.dispose);

      controller.appendDebugOutput('from controller 1');
      await tester.pumpWidget(buildView());

      // Replace with new controller.
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

      expect(controller2.lines.last, 'from controller 2');
    });

    testWidgets('switches focus node correctly', (tester) async {
      final node1 = FocusNode();
      final node2 = FocusNode();
      addTearDown(node1.dispose);
      addTearDown(node2.dispose);

      await tester.pumpWidget(buildView(focusNode: node1));

      await tester.pumpWidget(buildView(focusNode: node2));
      await tester.tap(find.byType(GhosttyTerminalView));
      await tester.pump();

      expect(node2.hasFocus, isTrue);
    });

    testWidgets('applies custom styling props', (tester) async {
      const bg = Color(0xFF000000);
      const fg = Color(0xFFFFFFFF);

      await tester.pumpWidget(
        buildView(
          backgroundColor: bg,
          foregroundColor: fg,
          fontSize: 18,
          lineHeight: 1.5,
          padding: const EdgeInsets.all(24),
        ),
      );

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('handles many lines without overflow', (tester) async {
      // Generate more lines than can fit in the view.
      final manyLines = List.generate(200, (i) => 'Line $i').join('\n');
      controller.appendDebugOutput(manyLines);

      await tester.pumpWidget(buildView());

      expect(controller.lineCount, 200);
      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });

    testWidgets('handles empty lines and special characters', (tester) async {
      controller.appendDebugOutput('line1\n\n\nline4');

      await tester.pumpWidget(buildView());

      expect(controller.lines, ['line1', '', '', 'line4']);
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
      await tester.pump();

      // Simulate a key event — should not crash even without a process.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      // No crash means the handler gracefully returned.
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

      // Send a full key down + up cycle — the up event should be ignored
      // by the handler (only down/repeat are processed).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
    });
  });

  group('GhosttyTerminalController (detailed)', () {
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
    });

    test('appendDebugOutput increments revision', () {
      expect(controller.revision, 0);
      controller.appendDebugOutput('hello');
      expect(controller.revision, 1);
      controller.appendDebugOutput(' world');
      expect(controller.revision, 2);
    });

    test('appendDebugOutput handles newlines', () {
      controller.appendDebugOutput('a\nb\nc');
      expect(controller.lines, ['a', 'b', 'c']);
    });

    test('appendDebugOutput handles carriage return', () {
      controller.appendDebugOutput('hello\rworld');
      // \r clears the current line, then 'world' is written.
      expect(controller.lines, ['world']);
    });

    test('appendDebugOutput handles backspace', () {
      controller.appendDebugOutput('abc\b\bd');
      // 'abc' → backspace → 'ab' → backspace → 'a' → 'd' → 'ad'
      expect(controller.lines, ['ad']);
    });

    test('clear resets lines', () {
      controller.appendDebugOutput('some\ntext');
      expect(controller.lineCount, greaterThan(1));

      controller.clear();
      expect(controller.lines, ['']);
      expect(controller.lineCount, 1);
    });

    test('OSC 0 sets title', () {
      controller.appendDebugOutput('\x1b]0;My Title\x07');
      expect(controller.title, 'My Title');
    });

    test('OSC 2 sets title', () {
      controller.appendDebugOutput('\x1b]2;Another Title\x07');
      expect(controller.title, 'Another Title');
    });

    test('OSC with ST terminator sets title', () {
      controller.appendDebugOutput('\x1b]0;ST Title\x1b\\');
      expect(controller.title, 'ST Title');
    });

    test('strips CSI sequences', () {
      // Bold "hello" with SGR reset
      controller.appendDebugOutput('\x1b[1mhello\x1b[0m');
      expect(controller.lines, ['hello']);
    });

    test('strips complex CSI sequences', () {
      // Cursor movement, colors, etc.
      controller.appendDebugOutput('\x1b[31;1mred bold\x1b[0m normal');
      expect(controller.lines, ['red bold normal']);
    });

    test('maxLines truncates old lines', () {
      final small = GhosttyTerminalController(maxLines: 5);
      addTearDown(small.dispose);

      small.appendDebugOutput('1\n2\n3\n4\n5\n6\n7\n8');
      expect(small.lineCount, 5);
      expect(small.lines.first, '4');
      expect(small.lines.last, '8');
    });

    test('notifyListeners called on appendDebugOutput', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.appendDebugOutput('test');
      expect(notified, isTrue);
    });

    test('notifyListeners called on clear', () {
      controller.appendDebugOutput('data');
      var notified = false;
      controller.addListener(() => notified = true);
      controller.clear();
      expect(notified, isTrue);
    });

    test('write returns false when not running', () {
      expect(controller.write('hello'), isFalse);
    });

    test('writeBytes returns false when not running', () {
      expect(controller.writeBytes([0x68, 0x69]), isFalse);
    });

    test('sendKey returns false when not running', () {
      expect(controller.sendKey(key: GhosttyKey.GHOSTTY_KEY_ENTER), isFalse);
    });

    test('multiple OSC sequences in one chunk', () {
      controller.appendDebugOutput(
        '\x1b]0;First\x07hello\x1b]0;Second\x07world',
      );
      // The last title wins.
      expect(controller.title, 'Second');
      expect(controller.lines, ['helloworld']);
    });

    test('interleaved output and escape sequences', () {
      controller.appendDebugOutput('start\x1b[32m green \x1b[0mend');
      expect(controller.lines, ['start green end']);
    });

    test('backspace on empty line is a no-op', () {
      controller.appendDebugOutput('\b');
      expect(controller.lines, ['']);
    });

    test('carriage return followed by newline', () {
      controller.appendDebugOutput('hello\r\nworld');
      expect(controller.lines, ['', 'world']);
    });
  });

  group('_GhosttyTerminalPainter shouldRepaint', () {
    late GhosttyTerminalController controller;

    setUp(() {
      controller = GhosttyTerminalController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('repaints when revision changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(controller: controller),
            ),
          ),
        ),
      );

      controller.appendDebugOutput('trigger repaint');
      await tester.pump();

      // The widget should have rebuilt.
      expect(controller.revision, greaterThan(0));
    });

    testWidgets('repaints when styling changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                backgroundColor: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      );

      // Change background color — triggers shouldRepaint.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: GhosttyTerminalView(
                controller: controller,
                backgroundColor: const Color(0xFFFF0000),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GhosttyTerminalView), findsOneWidget);
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
