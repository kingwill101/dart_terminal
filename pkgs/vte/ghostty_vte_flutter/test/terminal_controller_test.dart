import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:image/image.dart' as image;

final bool _hasNativeTerminal = _hasNativeTerminalSupport();

bool _hasNativeTerminalSupport() {
  try {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    terminal.close();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('controller parses OSC title and CRLF-delimited line buffer', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('\x1b]0;Studio Title\x07hello\r\nworld');

    expect(controller.title, 'Studio Title');
    expect(controller.lines, isNotEmpty);
    expect(controller.lines[0], 'hello');
    expect(controller.lines[1], 'world');
  });

  test(
    'controller exposes a native render snapshot for live viewport data',
    () {
      if (!_hasNativeTerminal) {
        return;
      }

      final controller = GhosttyTerminalController();
      addTearDown(controller.dispose);

      controller.appendDebugOutput('\x1b[31mA\x1b[0mB');

      final renderSnapshot = controller.renderSnapshot;
      expect(renderSnapshot, isNotNull);
      expect(renderSnapshot!.rowsData, isNotEmpty);
      expect(renderSnapshot.rowsData.first.cells.first.text, 'A');
    },
  );

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
    expect(
      controller.sendMouse(
        action: GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_PRESS,
        button: GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_LEFT,
        position: const VtMousePosition(x: 10, y: 10),
        size: const VtMouseEncoderSize(
          screenWidth: 800,
          screenHeight: 600,
          cellWidth: 10,
          cellHeight: 20,
        ),
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
    if (!_hasNativeTerminal) {
      return;
    }

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

  test('render snapshot resolves hyperlink cells and explicit color flags', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput(
      '\x1b]8;;https://example.com\x07open\x1b]8;;\x07\x1b[31mred\x1b[0m',
    );
    final renderSnapshot = controller.renderSnapshot;
    expect(renderSnapshot, isNotNull);

    final rows = renderSnapshot!.rowsData;
    expect(rows, isNotEmpty);
    final cells = rows.first.cells;
    expect(cells, isNotEmpty);

    final openCell = cells.firstWhere((cell) => cell.text == 'o');
    expect(openCell.hasHyperlink, isTrue);
    expect(openCell.style.hasExplicitForeground, isFalse);
    expect(openCell.style.hasExplicitBackground, isFalse);

    final redCell = cells.firstWhere(
      (cell) => cell.text == 'r' && !cell.hasHyperlink,
    );
    expect(redCell.style.hasExplicitForeground, isTrue);
  });

  test(
    'render snapshot distinguishes explicit and implicit underline colors',
    () {
      if (!_hasNativeTerminal) {
        return;
      }

      final controller = GhosttyTerminalController();
      addTearDown(controller.dispose);

      controller.appendDebugOutput(
        '\x1b[58;2;255;0;0mexplicit\x1b[0mintrinsic',
      );

      final renderSnapshot = controller.renderSnapshot;
      expect(renderSnapshot, isNotNull);
      final row = renderSnapshot!.rowsData.first;
      final textCells = row.cells
          .where((cell) => cell.text.isNotEmpty)
          .toList(growable: false);
      final explicitCell = textCells.firstWhere((cell) => cell.text == 'e');
      final implicitCell = textCells[8];

      expect(explicitCell.style.hasExplicitUnderlineColor, isTrue);
      expect(implicitCell.style.hasExplicitUnderlineColor, isFalse);
      expect(
        explicitCell.style.underlineColor,
        isNot(equals(implicitCell.style.underlineColor)),
      );
      expect(
        implicitCell.style.underlineColor,
        equals(const Color(0x00000000)),
      );
    },
  );

  test('render snapshot preserves unresolved background as transparent', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('hello');
    final renderSnapshot = controller.renderSnapshot;
    expect(renderSnapshot, isNotNull);

    final cells = renderSnapshot!.rowsData.first.cells;
    final firstTextCell = cells.firstWhere((cell) => cell.text.isNotEmpty);
    expect(firstTextCell.style.hasExplicitBackground, isFalse);
    expect(firstTextCell.style.background, equals(const Color(0x00000000)));
  });

  test(
    'render snapshot preserves wide-cell widths for native viewport data',
    () {
      if (!_hasNativeTerminal) {
        return;
      }

      final controller = GhosttyTerminalController();
      addTearDown(controller.dispose);

      controller.appendDebugOutput('A🙂B');
      final renderSnapshot = controller.renderSnapshot;
      expect(renderSnapshot, isNotNull);

      final textCells = renderSnapshot!.rowsData.first.cells
          .where((cell) => cell.text.isNotEmpty)
          .toList(growable: false);
      expect(textCells.map((cell) => cell.text).toList(), ['A', '🙂', 'B']);
      expect(textCells.map((cell) => cell.width).toList(), [1, 2, 1]);
    },
  );

  test(
    'render snapshot copies Kitty RGB image pixels and placement geometry',
    () {
      if (!_hasNativeTerminal) {
        return;
      }

      final controller = GhosttyTerminalController();
      addTearDown(controller.dispose);
      if (!controller.buildInfo.kittyGraphics) {
        return;
      }

      controller.resize(cols: 80, rows: 24, cellWidthPx: 10, cellHeightPx: 20);
      controller.appendDebugOutput(
        '\x1b_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=10,r=1;////////\x1b\\',
      );

      final snapshot = controller.renderSnapshot!;
      final kittyImage = snapshot.kittyImages[1];
      expect(kittyImage, isNotNull);
      expect(kittyImage!.width, 1);
      expect(kittyImage.height, 2);
      expect(kittyImage.rgba, <int>[
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
      ]);

      expect(snapshot.kittyPlacements, hasLength(1));
      final placement = snapshot.kittyPlacements.single;
      expect(placement.imageId, 1);
      expect(placement.placementId, 1);
      expect(placement.layer, GhosttyTerminalKittyPlacementLayer.aboveText);
      expect(placement.viewportCol, 0);
      expect(placement.viewportRow, 0);
      expect(placement.gridCols, 10);
      expect(placement.gridRows, 1);
      expect(placement.sourceWidth, 1);
      expect(placement.sourceHeight, 2);
    },
  );

  test('controller installs the synchronous PNG decoder for Kitty images', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);
    if (!controller.buildInfo.kittyGraphics) {
      return;
    }

    final source = image.Image(width: 1, height: 1)
      ..setPixelRgba(0, 0, 0x12, 0x34, 0x56, 0xFF);
    final encoded = base64Encode(image.encodePng(source));
    controller.appendDebugOutput(
      '\x1b_Ga=T,t=d,f=100,i=2,p=2,c=1,r=1;$encoded\x1b\\',
    );

    final kittyImage = controller.renderSnapshot!.kittyImages[2];
    expect(kittyImage, isNotNull);
    expect(kittyImage!.width, 1);
    expect(kittyImage.height, 1);
    expect(kittyImage.rgba, <int>[0x12, 0x34, 0x56, 0xFF]);
  });

  test('render snapshot reconstructs Kitty Unicode virtual placements', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);
    if (!controller.buildInfo.kittyGraphics) {
      return;
    }

    controller.appendDebugOutput(
      '\x1b_Ga=t,t=d,f=24,i=3,s=1,v=1;/wAA\x1b\\'
      '\x1b_Ga=p,i=3,p=3,U=1,c=1,r=1\x1b\\'
      '\x1b[38;5;3m\u{10EEEE}\u0305\u0305\x1b[39m',
    );

    final snapshot = controller.renderSnapshot!;
    expect(snapshot.hasUnresolvedKittyVirtualPlacements, isFalse);
    expect(snapshot.kittyPlacements, hasLength(1));
    final placement = snapshot.kittyPlacements.single;
    expect(placement.isVirtual, isTrue);
    expect(placement.imageId, 3);
    expect(placement.placementId, 3);
    expect(placement.layer, GhosttyTerminalKittyPlacementLayer.aboveText);
    expect(placement.z, 0);
    expect(placement.viewportCol, 0);
    expect(placement.viewportRow, 0);
    expect(placement.virtualSourceCol, 0);
    expect(placement.virtualSourceRow, 0);
  });

  test('render snapshot exposes the native cursor color and blink state', () {
    if (!_hasNativeTerminal) {
      return;
    }

    final controller = GhosttyTerminalController();
    addTearDown(controller.dispose);

    controller.appendDebugOutput('\x1b]12;#f04a7f\x07\x1b[1 q');

    expect(controller.renderSnapshot?.cursor.color, const Color(0xFFF04A7F));
    expect(controller.renderSnapshot?.cursor.blinking, isTrue);
  });

  testWidgets('terminal view renders custom painter', (tester) async {
    if (!_hasNativeTerminal) {
      return;
    }

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
    expect(find.byKey(const ValueKey('terminalPainter')), findsOneWidget);
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
