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
    await tester.pumpWidget(const TerminalSuiteApp());

    expect(find.text('Ghostty + Portable PTY Suite'), findsOneWidget);
    expect(find.text('Ghostty'), findsOneWidget);
    expect(find.text('PTY'), findsOneWidget);
    expect(find.text('Parsers'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });
}
