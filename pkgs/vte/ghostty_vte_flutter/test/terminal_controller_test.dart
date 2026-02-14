import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  test('controller parses OSC title and line buffer from debug output', () {
    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('\x1b]0;Studio Title\x07hello\nworld');

    expect(controller.title, 'Studio Title');
    expect(controller.lines, isNotEmpty);
    expect(controller.lines[0], 'hello');
    expect(controller.lines[1], 'world');
  });

  test('write/sendKey return false when process is not running', () {
    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    expect(controller.write('echo hello'), isFalse);
    expect(
      controller.sendKey(
        key: GhosttyKey.GHOSTTY_KEY_C,
        mods: GhosttyModsMask.ctrl,
      ),
      isFalse,
    );
  });

  testWidgets('terminal view renders custom painter', (tester) async {
    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);
    controller.appendDebugOutput('line one\nline two');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 500,
          height: 220,
          child: GhosttyTerminalView(controller: controller),
        ),
      ),
    );

    expect(find.byType(GhosttyTerminalView), findsOneWidget);
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
