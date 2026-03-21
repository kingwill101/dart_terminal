import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  test('controller parses OSC title and CRLF-delimited line buffer', () {
    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('\x1b]0;Studio Title\x07hello\r\nworld');

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

  test('controller stores explicit launch metadata from startLaunch', () async {
    final controller = _LaunchMetadataController();
    addTearDown(controller.dispose);

    await controller.startLaunch(
      const GhosttyTerminalShellLaunch(
        label: 'clean bash shell',
        shell: '/bin/bash',
        arguments: <String>['--noprofile', '--norc', '-i'],
        environment: <String, String>{
          'HOME': '/tmp/demo-home',
          'TERM': 'xterm-256color',
        },
      ),
    );

    expect(controller.activeShellLaunch?.label, 'clean bash shell');
    expect(
      controller.activeShellLaunch?.commandLine,
      '/bin/bash --noprofile --norc -i',
    );
    expect(
      controller.activeShellLaunch?.environment?['HOME'],
      '/tmp/demo-home',
    );
  });

  test('native controller uses the shared PTY backend on Unix', () async {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    final controller = GhosttyTerminalController(defaultShell: '/bin/bash');
    addTearDown(controller.dispose);

    await controller.start(
      shell: '/bin/bash',
      arguments: const <String>['--noprofile', '--norc', '-i'],
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(controller.ptySession, isNotNull);
    expect(controller.isRunning, isTrue);

    await controller.stop();
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

class _LaunchMetadataController extends GhosttyTerminalController {
  _LaunchMetadataController() : super();

  @override
  Future<void> start({
    String? shell,
    List<String> arguments = const <String>[],
    Map<String, String>? environment,
  }) async {}
}
