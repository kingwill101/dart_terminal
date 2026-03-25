// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:ghostty_pty_terminal_suite/main.dart';

void main() {
  testWidgets('renders terminal suite tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const TerminalSuiteApp(autoInspect: false));

    expect(find.text('Ghostty + Portable PTY Suite'), findsOneWidget);
    expect(find.text('Ghostty'), findsOneWidget);
    expect(find.text('Ghostty Formatter Extras'), findsOneWidget);
    expect(find.text('Selection First'), findsOneWidget);
    expect(find.text('Terminal Mouse'), findsOneWidget);
    expect(find.textContaining('Mouse reporting'), findsOneWidget);
    expect(find.text('Ghostty Mouse Tracking'), findsOneWidget);
    expect(find.text('Ghostty Mouse Format'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('SGR Pixels'), findsOneWidget);
    expect(find.text('Focus Events'), findsOneWidget);
    expect(find.text('Alt Scroll'), findsOneWidget);
    expect(find.text('PTY'), findsOneWidget);
    expect(find.text('Parsers'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);

    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();

    expect(find.text('Mouse Encoder', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Parsers'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ghostty Render Semantics', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('toggles ghostty interaction policy', (WidgetTester tester) async {
    await tester.pumpWidget(const TerminalSuiteApp(autoInspect: false));
    await tester.pumpAndSettle();

    expect(find.text('Interaction: auto'), findsOneWidget);

    await tester.ensureVisible(find.text('Selection First').first);
    await tester.tap(find.text('Selection First').first);
    await tester.pumpAndSettle();
    expect(find.text('Interaction: selectionFirst'), findsOneWidget);

    await tester.ensureVisible(find.text('Terminal Mouse').first);
    await tester.tap(find.text('Terminal Mouse').first);
    await tester.pumpAndSettle();
    expect(find.text('Interaction: terminalMouseFirst'), findsOneWidget);
  });
}
