import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_uv_flutter/ghostty_uv_flutter.dart';

void main() {
  testWidgets('terminal view sends backspace through the key bridge', (
    WidgetTester tester,
  ) async {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(written, <int>[127]);
  });

  testWidgets(
    'terminal view uses application cursor keys when screen asks for it',
    (WidgetTester tester) async {
      final written = <int>[];
      final controller = GhosttyUvTerminalController(
        writeSink: (data) {
          written.addAll(data);
          return data.length;
        },
      );
      addTearDown(controller.dispose);
      controller.feedOutput(utf8.encode('\u001B[?1h'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 320,
              child: GhosttyUvTerminalView(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(written, <int>[27, 79, 68]);
    },
  );

  testWidgets('terminal view copies selected text through callback', (
    WidgetTester tester,
  ) async {
    String? copied;
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('hello world'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              onCopySelection: (text) async {
                copied = text;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final terminal = find.byType(GhosttyUvTerminalView);
    final start = tester.getTopLeft(terminal) + const Offset(14, 24);
    await tester.dragFrom(start, const Offset(72, 0));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('hello'));
  });

  testWidgets('terminal view sends bracketed paste when shell enables it', (
    WidgetTester tester,
  ) async {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('\u001B[?2004h'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              onPasteRequest: () async => 'echo \$(safe paste)',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(utf8.decode(written), '\u001B[200~echo \$(safe paste)\u001B[201~');
  });

  testWidgets('terminal view accepts shifted underscore and plus', (
    WidgetTester tester,
  ) async {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

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

    expect(utf8.decode(written), '_+');
  });

  testWidgets('terminal view opens hyperlinks via callback', (
    WidgetTester tester,
  ) async {
    String? opened;
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(
      utf8.encode('\u001B]8;;https://ghostty.org\u0007link\u001B]8;;\u0007'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              onOpenHyperlink: (uri) async {
                opened = uri;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final terminal = find.byType(GhosttyUvTerminalView);
    await tester.tapAt(tester.getTopLeft(terminal) + const Offset(24, 24));
    await tester.pump(const Duration(milliseconds: 350));

    expect(opened, 'https://ghostty.org');
  });

  testWidgets(
    'terminal view double tap selects a word and reports selection changes',
    (WidgetTester tester) async {
      String? copied;
      final selections = <GhosttyUvTerminalSelection?>[];
      final controller = GhosttyUvTerminalController();
      addTearDown(controller.dispose);
      controller.feedOutput(utf8.encode('hello world'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 320,
              child: GhosttyUvTerminalView(
                controller: controller,
                autofocus: true,
                onCopySelection: (text) async {
                  copied = text;
                },
                onSelectionChanged: selections.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final terminal = find.byType(GhosttyUvTerminalView);
      final target = tester.getTopLeft(terminal) + const Offset(24, 24);
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 350));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copied, 'hello');
      expect(selections, isNotEmpty);
      expect(selections.last, isNotNull);

      await tester.tapAt(tester.getTopLeft(terminal) + const Offset(220, 140));
      await tester.pump(const Duration(milliseconds: 350));

      expect(selections.last, isNull);
    },
  );

  testWidgets('terminal view double tap honors custom word boundary policy', (
    WidgetTester tester,
  ) async {
    String? copied;
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('hello-world'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              wordBoundaryPolicy: const GhosttyUvWordBoundaryPolicy(
                extraWordCharacters: '',
              ),
              onCopySelection: (text) async {
                copied = text;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final terminal = find.byType(GhosttyUvTerminalView);
    final target = tester.getTopLeft(terminal) + const Offset(24, 24);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 350));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copied, 'hello');
  });

  testWidgets('terminal view select-all shortcut selects transcript content', (
    WidgetTester tester,
  ) async {
    String? copied;
    final selections = <GhosttyUvTerminalSelection?>[];
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('one\r\ntwo\r\nthree'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              onCopySelection: (text) async {
                copied = text;
              },
              onSelectionChanged: selections.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(selections, isNotEmpty);
    expect(selections.last, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copied, 'one\ntwo\nthree');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(selections.last, isNull);
  });

  testWidgets(
    'terminal view long press selects a full line and reports content changes',
    (WidgetTester tester) async {
      String? copied;
      final contents = <GhosttyUvTerminalSelectionContent?>[];
      final controller = GhosttyUvTerminalController();
      addTearDown(controller.dispose);
      controller.feedOutput(utf8.encode('alpha beta'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 320,
              child: GhosttyUvTerminalView(
                controller: controller,
                autofocus: true,
                onCopySelection: (text) async {
                  copied = text;
                },
                onSelectionContentChanged: contents.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final terminal = find.byType(GhosttyUvTerminalView);
      await tester.longPressAt(
        tester.getTopLeft(terminal) + const Offset(24, 24),
      );
      await tester.pump(const Duration(milliseconds: 350));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copied, 'alpha beta');
      expect(contents, isNotEmpty);
      expect(contents.last?.text, 'alpha beta');

      await tester.tapAt(tester.getTopLeft(terminal) + const Offset(220, 140));
      await tester.pump(const Duration(milliseconds: 350));

      expect(contents.last, isNull);
    },
  );

  testWidgets('terminal view long press drag selects full lines across rows', (
    WidgetTester tester,
  ) async {
    String? copied;
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('one\r\ntwo\r\nthree'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 80,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              padding: EdgeInsets.zero,
              fontSize: 16,
              lineHeight: 1,
              onCopySelection: (text) async {
                copied = text;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final terminal = find.byType(GhosttyUvTerminalView);
    final start = tester.getTopLeft(terminal) + const Offset(16, 10);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getTopLeft(terminal) + const Offset(16, 28));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copied, 'one\ntwo');
  });

  testWidgets('terminal view auto-scrolls selection into scrollback', (
    WidgetTester tester,
  ) async {
    String? copied;
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 24,
            child: GhosttyUvTerminalView(
              controller: controller,
              autofocus: true,
              padding: EdgeInsets.zero,
              fontSize: 16,
              lineHeight: 1,
              onCopySelection: (text) async {
                copied = text;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    controller.feedOutput(utf8.encode('one\r\ntwo\r\nthree'));
    await tester.pump();

    expect(controller.screen.maxScrollOffset, greaterThan(0));

    final terminal = find.byType(GhosttyUvTerminalView);
    final start = tester.getTopLeft(terminal) + const Offset(10, 10);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(tester.getTopLeft(terminal) + const Offset(120, -48));
    await tester.pump(const Duration(milliseconds: 160));
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('one'));
    expect(copied, contains('two'));
    expect(copied, contains('t'));
  });

  testWidgets('terminal view paints incoming output without crashing', (
    WidgetTester tester,
  ) async {
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    controller.feedOutput(utf8.encode('\u001B[32mready\u001B[0m'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 320,
            child: GhosttyUvTerminalView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GhosttyUvTerminalView), findsOneWidget);
  });
}
