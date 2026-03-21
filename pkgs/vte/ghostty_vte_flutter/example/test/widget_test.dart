import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders terminal studio shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Ghostty VT Studio'), findsOneWidget);
    expect(find.text('Evaluate All'), findsOneWidget);
    expect(find.text('Paste Safety'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('OSC'), findsOneWidget);
    expect(find.text('SGR'), findsOneWidget);
    expect(find.text('Key Encoder'), findsOneWidget);
  });
}
