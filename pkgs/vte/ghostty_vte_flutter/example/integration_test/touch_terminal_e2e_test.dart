import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders native terminal content on Android', (tester) async {
    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('Android startup smoke\r\nready');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      renderer: GhosttyTerminalRendererMode.renderState,
    );

    expect(find.byKey(_terminalViewKey), findsOneWidget);
    expect(controller.cols, greaterThan(0));
    expect(controller.rows, greaterThan(0));
    expect(controller.plainText, contains('Android startup smoke'));
    expect(controller.renderSnapshot?.hasViewportData, isTrue);
  });

  testWidgets('tap actions focus, select words, and clear selection', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    final editorFocusNode = FocusNode();
    final terminalFocusNode = FocusNode();
    GhosttyTerminalSelection? currentSelection;
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);
    addTearDown(editorFocusNode.dispose);
    addTearDown(terminalFocusNode.dispose);

    controller.appendDebugOutput('alpha beta gamma');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      editorFocusNode: editorFocusNode,
      terminalFocusNode: terminalFocusNode,
      onSelectionChanged: (selection) {
        currentSelection = selection;
      },
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    await tester.tap(find.byKey(_editorFieldKey));
    await _settleInteraction(tester);
    expect(editorFocusNode.hasFocus, isTrue);

    await _tapTerminalCell(tester, column: 13);
    await _settleInteraction(tester);

    expect(terminalFocusNode.hasFocus, isTrue);
    expect(editorFocusNode.hasFocus, isFalse);
    expect(currentSelection, isNull);
    expect(currentContent, isNull);

    await tester.pump(const Duration(milliseconds: 500));
    final alphaTarget = _terminalCellCenter(_terminalRect(tester), column: 2);
    await _doubleTapAt(tester, alphaTarget);
    await _waitForSelectionText(
      tester,
      selectedText: () => currentContent?.text,
      expected: 'alpha',
    );

    expect(currentSelection, isNotNull);
    expect(currentContent?.text, 'alpha');

    await tester.pump(const Duration(milliseconds: 500));
    await _tapTerminalCell(tester, column: 13);
    await _settleInteraction(tester);

    expect(currentSelection, isNull);
    expect(currentContent, isNull);
  });

  testWidgets('touch drag scrolls by default and long press selects', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    final editorFocusNode = FocusNode();
    final terminalFocusNode = FocusNode();
    final scrollController = ScrollController();
    GhosttyTerminalSelection? currentSelection;
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);
    addTearDown(editorFocusNode.dispose);
    addTearDown(terminalFocusNode.dispose);
    addTearDown(scrollController.dispose);

    controller.appendDebugOutput(_lines('Android touch validation line', 180));

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      editorFocusNode: editorFocusNode,
      terminalFocusNode: terminalFocusNode,
      scrollController: scrollController,
      onSelectionChanged: (selection) {
        currentSelection = selection;
      },
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    await tester.tap(find.byKey(_editorFieldKey));
    await _settleInteraction(tester);
    expect(editorFocusNode.hasFocus, isTrue);

    final terminalRect = _terminalRect(tester);
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    final scrollStart = Offset(
      terminalRect.center.dx,
      terminalRect.bottom - 80,
    );
    final scrollEnd = Offset(terminalRect.center.dx, terminalRect.top + 80);
    await gesture.down(scrollStart);
    await tester.pump();

    expect(terminalFocusNode.hasFocus, isTrue);
    expect(editorFocusNode.hasFocus, isFalse);

    await _moveTouchInSteps(tester, gesture, from: scrollStart, to: scrollEnd);
    await gesture.up();
    await _settleInteraction(tester);

    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    expect(scrollController.offset, greaterThan(0));
    expect(currentSelection, isNull);

    await tester.longPressAt(
      Offset(terminalRect.left + 40, terminalRect.top + 40),
    );
    await _settleInteraction(tester);

    expect(currentContent?.text, isNotEmpty);
  });

  testWidgets('touch selection exposes the context menu copy action', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    String? copiedText;

    addTearDown(controller.dispose);

    controller.appendDebugOutput('copyable terminal text');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      onCopySelection: (text) async {
        copiedText = text;
      },
    );

    final terminalRect = _terminalRect(tester);
    await tester.longPressAt(
      Offset(terminalRect.left + 40, terminalRect.top + 40),
    );
    await _settleInteraction(tester);

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await _settleInteraction(tester);

    expect(copiedText, 'copyable terminal text');
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
  });

  testWidgets('touch selection exposes custom context menu actions', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    String? actionText;

    addTearDown(controller.dispose);

    controller.appendDebugOutput('custom terminal action');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      selectionContextMenuButtonItemsBuilder: (details) {
        return <ContextMenuButtonItem>[
          ...details.defaultButtonItems,
          ContextMenuButtonItem(
            label: 'Inspect',
            onPressed: () {
              actionText = details.selectedText;
              details.hideToolbar();
            },
          ),
        ];
      },
    );

    final terminalRect = _terminalRect(tester);
    await tester.longPressAt(
      Offset(terminalRect.left + 40, terminalRect.top + 40),
    );
    await _settleInteraction(tester);

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Inspect'), findsOneWidget);

    await tester.tap(find.text('Inspect'));
    await _settleInteraction(tester);

    expect(actionText, 'custom terminal action');
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
  });

  testWidgets('touch selection handles can pan the highlighted range', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);

    controller.appendDebugOutput('alpha beta\r\nsecond line\r\nthird line');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    final terminalRect = _terminalRect(tester);
    await tester.longPressAt(
      Offset(terminalRect.left + 40, terminalRect.top + 44),
    );
    await _settleInteraction(tester);

    expect(currentContent?.text, 'second line');
    final endHandle = find.byKey(
      const ValueKey<String>('ghostty-terminal-selection-end-handle'),
    );
    expect(endHandle, findsOneWidget);

    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.down(tester.getCenter(endHandle));
    await tester.pump();
    await gesture.moveTo(
      Offset(terminalRect.left + 120, terminalRect.top + 82),
    );
    await tester.pump();
    await gesture.up();
    await _settleInteraction(tester);

    expect(currentContent?.text, contains('second line'));
    expect(currentContent?.text, contains('third'));
    expect(
      find.byKey(
        const ValueKey<String>('ghostty-terminal-selection-start-handle'),
      ),
      findsOneWidget,
    );
    expect(endHandle, findsOneWidget);
  });

  testWidgets('touch selection handles auto-pan near the viewport edge', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);

    controller.appendDebugOutput(
      List<String>.generate(180, (index) => 'Line $index').join('\r\n'),
    );

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    final terminalRect = _terminalRect(tester);
    await tester.longPressAt(
      Offset(terminalRect.left + 40, terminalRect.bottom - 16),
    );
    await _settleInteraction(tester);

    expect(currentContent?.text, 'Line 179');
    final startHandle = find.byKey(
      const ValueKey<String>('ghostty-terminal-selection-start-handle'),
    );
    expect(startHandle, findsOneWidget);

    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.down(tester.getCenter(startHandle));
    await tester.pump();
    await gesture.moveTo(Offset(terminalRect.left + 40, terminalRect.top + 4));
    await tester.pump();
    final textBeforeAutoPan = currentContent?.text;

    await tester.pump(const Duration(milliseconds: 300));

    final beforeLines = textBeforeAutoPan?.split('\n') ?? const <String>[];
    final afterLines = currentContent?.text.split('\n') ?? const <String>[];
    expect(currentContent?.text, isNot(textBeforeAutoPan));
    expect(currentContent?.text, contains('Line 179'));
    expect(afterLines.length, greaterThan(beforeLines.length));

    await gesture.up();
    await _settleInteraction(tester);
  });

  testWidgets('bottom-edge long press does not flash viewport selection', (
    tester,
  ) async {
    final controller = GhosttyTerminalController();
    final scrollController = ScrollController();
    var selectionChanges = 0;
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    controller.appendDebugOutput(
      List<String>.generate(180, (index) => 'Bottom $index').join('\r\n'),
    );

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      scrollController: scrollController,
      onSelectionChanged: (_) {
        selectionChanges++;
      },
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    final terminalRect = _terminalRect(tester);
    final holdTarget = Offset(terminalRect.left + 40, terminalRect.bottom - 16);
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.down(holdTarget);
    await tester.pump(const Duration(milliseconds: 650));

    expect(currentContent?.text, 'Bottom 179');
    final changesAfterLongPress = selectionChanges;

    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollController.offset, 0);
    expect(currentContent?.text, 'Bottom 179');
    expect(selectionChanges, changesAfterLongPress);

    await gesture.up();
    await _settleInteraction(tester);
  });

  testWidgets('touch drag selection can be opted in', (tester) async {
    final controller = GhosttyTerminalController();
    final scrollController = ScrollController();
    GhosttyTerminalSelection? currentSelection;
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>? currentContent;

    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    controller.appendDebugOutput(_lines('Touch select line', 24));

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      scrollController: scrollController,
      touchDragBehavior: GhosttyTerminalTouchDragBehavior.selection,
      onSelectionChanged: (selection) {
        currentSelection = selection;
      },
      onSelectionContentChanged: (content) {
        currentContent = content;
      },
    );

    final terminalRect = _terminalRect(tester);
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    final selectionStart = Offset(
      terminalRect.left + 16,
      terminalRect.top + 48,
    );
    final selectionEnd = Offset(terminalRect.left + 260, terminalRect.top + 48);
    await gesture.down(selectionStart);
    await tester.pump();
    await _moveTouchInSteps(
      tester,
      gesture,
      from: selectionStart,
      to: selectionEnd,
    );
    await gesture.up();
    await _settleInteraction(tester);

    expect(scrollController.offset, 0);
    expect(currentSelection, isNotNull);
    expect(currentContent?.text, contains('Touch select line'));
  });

  testWidgets('auto mode does not forward touch as terminal mouse events', (
    tester,
  ) async {
    final controller = _RecordingTerminalController();
    addTearDown(controller.dispose);

    controller
      ..appendDebugOutput('Mouse auto policy')
      ..terminal.setMode(VtModes.normalMouse, true)
      ..terminal.setMode(VtModes.sgrMouse, true);

    await _pumpTerminalHarness(tester, controller: controller);

    final terminalRect = _terminalRect(tester);
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.down(terminalRect.center);
    await tester.pump();
    await gesture.moveTo(
      Offset(terminalRect.center.dx + 40, terminalRect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await _settleInteraction(tester);

    expect(controller.mouseEvents, isEmpty);
  });

  testWidgets('terminalMouseFirst forwards touch terminal mouse events', (
    tester,
  ) async {
    final controller = _RecordingTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('Mouse terminal policy');

    await _pumpTerminalHarness(
      tester,
      controller: controller,
      interactionPolicy: GhosttyTerminalInteractionPolicy.terminalMouseFirst,
    );

    final terminalRect = _terminalRect(tester);
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.down(terminalRect.center);
    await tester.pump();
    await gesture.moveTo(
      Offset(terminalRect.center.dx + 40, terminalRect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await _settleInteraction(tester);

    expect(controller.mouseEvents, isNotEmpty);
    expect(
      controller.mouseEvents.first.button,
      GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_LEFT,
    );
    expect(
      controller.mouseEvents.map((event) => event.action),
      containsAll(<GhosttyMouseAction>[
        GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_PRESS,
        GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_MOTION,
        GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_RELEASE,
      ]),
    );
  });
}

const _editorFieldKey = ValueKey<String>('editor-field');
const _terminalViewKey = ValueKey<String>('terminal-view');

Future<void> _pumpTerminalHarness(
  WidgetTester tester, {
  required GhosttyTerminalController controller,
  FocusNode? editorFocusNode,
  FocusNode? terminalFocusNode,
  ScrollController? scrollController,
  GhosttyTerminalRendererMode renderer = GhosttyTerminalRendererMode.formatter,
  GhosttyTerminalInteractionPolicy interactionPolicy =
      GhosttyTerminalInteractionPolicy.auto,
  GhosttyTerminalTouchDragBehavior touchDragBehavior =
      GhosttyTerminalTouchDragBehavior.scroll,
  ValueChanged<GhosttyTerminalSelection?>? onSelectionChanged,
  ValueChanged<GhosttyTerminalSelectionContent<GhosttyTerminalSelection>?>?
  onSelectionContentChanged,
  Future<void> Function(String text)? onCopySelection,
  GhosttyTerminalSelectionContextMenuButtonItemsBuilder?
  selectionContextMenuButtonItemsBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 72,
                child: TextField(
                  key: _editorFieldKey,
                  focusNode: editorFocusNode,
                ),
              ),
              Expanded(
                child: GhosttyTerminalView(
                  key: _terminalViewKey,
                  controller: controller,
                  focusNode: terminalFocusNode,
                  showHeader: false,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  lineHeight: 1.35,
                  scrollController: scrollController,
                  renderer: renderer,
                  interactionPolicy: interactionPolicy,
                  touchDragBehavior: touchDragBehavior,
                  onSelectionChanged: onSelectionChanged,
                  onSelectionContentChanged: onSelectionContentChanged,
                  onCopySelection: onCopySelection,
                  selectionContextMenuButtonItemsBuilder:
                      selectionContextMenuButtonItemsBuilder,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await _settleInteraction(tester);
}

Rect _terminalRect(WidgetTester tester) {
  return tester.getRect(find.byKey(_terminalViewKey));
}

Offset _terminalCellCenter(
  Rect terminalRect, {
  required int column,
  int row = 0,
}) {
  const padding = 12.0;
  const fontSize = 14.0;
  const lineHeight = 1.35;
  final charWidth = _measureTerminalCharWidth();
  return Offset(
    terminalRect.left + padding + (column + 0.5) * charWidth,
    terminalRect.top + padding + (row + 0.5) * fontSize * lineHeight,
  );
}

double _measureTerminalCharWidth() {
  final painter = TextPainter(
    text: const TextSpan(
      text: 'W',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        height: 1.35,
        letterSpacing: 0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

Future<void> _tapTerminalCell(
  WidgetTester tester, {
  required int column,
  int row = 0,
}) async {
  await tester.tapAt(
    _terminalCellCenter(_terminalRect(tester), column: column, row: row),
    kind: ui.PointerDeviceKind.touch,
  );
}

Future<void> _doubleTapAt(WidgetTester tester, Offset target) async {
  await tester.tapAt(target, kind: ui.PointerDeviceKind.touch);
  await tester.pump(const Duration(milliseconds: 120));
  await tester.tapAt(target, kind: ui.PointerDeviceKind.touch);
  await _settleInteraction(tester);
}

Future<void> _settleInteraction(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 300),
}) async {
  const step = Duration(milliseconds: 50);
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> _waitForSelectionText(
  WidgetTester tester, {
  required String? Function() selectedText,
  required String expected,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (selectedText() == expected) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(selectedText(), expected);
}

String _lines(String prefix, int count) {
  return List<String>.generate(count, (index) => '$prefix $index').join('\r\n');
}

Future<void> _moveTouchInSteps(
  WidgetTester tester,
  TestGesture gesture, {
  required Offset from,
  required Offset to,
  int steps = 8,
}) async {
  for (var step = 1; step <= steps; step++) {
    final t = step / steps;
    await gesture.moveTo(Offset.lerp(from, to, t)!);
    await tester.pump(const Duration(milliseconds: 32));
  }
}

class _RecordingTerminalController extends GhosttyTerminalController {
  final List<_RecordedMouseEvent> mouseEvents = <_RecordedMouseEvent>[];

  @override
  bool sendMouse({
    required GhosttyMouseAction action,
    GhosttyMouseButton? button,
    int mods = 0,
    required VtMousePosition position,
    required VtMouseEncoderSize size,
    GhosttyMouseTrackingMode? trackingMode,
    GhosttyMouseFormat? format,
    bool? anyButtonPressed,
    bool? trackLastCell,
  }) {
    mouseEvents.add(_RecordedMouseEvent(action: action, button: button));
    return true;
  }
}

class _RecordedMouseEvent {
  const _RecordedMouseEvent({required this.action, required this.button});

  final GhosttyMouseAction action;
  final GhosttyMouseButton? button;
}
