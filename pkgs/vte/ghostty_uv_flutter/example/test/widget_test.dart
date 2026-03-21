import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_uv_flutter_example/main.dart';
import 'package:ghostty_uv_flutter/ghostty_uv_flutter.dart';

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

  testWidgets('example boots without auto-start side effects', (
    WidgetTester tester,
  ) async {
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      GhosttyUvStudioApp(controller: controller, autoStart: false),
    );
    await tester.pump();

    expect(find.text('Ghostty UV Studio'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Restart Shell'), findsOneWidget);
    expect(find.byType(GhosttyUvTerminalView), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
  });

  testWidgets('example can copy the effective environment', (
    WidgetTester tester,
  ) async {
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      GhosttyUvStudioApp(controller: controller, autoStart: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy Environment'));
    await tester.pump();

    expect(clipboardText, '(inherited or unavailable)');
  });
}
