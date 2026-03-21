import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders terminal studio shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(autoStart: false));
    await tester.pumpAndSettle();

    expect(find.text('Ghostty VT Studio'), findsOneWidget);
    expect(find.text('Send Command'), findsOneWidget);
    expect(find.text('Inject VT Demo'), findsOneWidget);
    expect(find.text('Restart Shell'), findsOneWidget);
    expect(find.text('Snapshots', skipOffstage: false), findsOneWidget);
    expect(find.text('Key Encoder', skipOffstage: false), findsOneWidget);
    expect(find.text('Parsers', skipOffstage: false), findsOneWidget);
    expect(find.text('Session', skipOffstage: false), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Formatter Paint'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Render Paint'), findsOneWidget);
  });

  testWidgets('toggles between renderer modes', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(autoStart: false));
    await tester.pumpAndSettle();

    final formatterFinder = find.widgetWithText(ChoiceChip, 'Formatter Paint');
    final renderFinder = find.widgetWithText(ChoiceChip, 'Render Paint');

    expect(tester.widget<ChoiceChip>(formatterFinder).selected, isTrue);
    expect(tester.widget<ChoiceChip>(renderFinder).selected, isFalse);

    await tester.tap(renderFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(formatterFinder).selected, isFalse);
    expect(tester.widget<ChoiceChip>(renderFinder).selected, isTrue);
  });
}
