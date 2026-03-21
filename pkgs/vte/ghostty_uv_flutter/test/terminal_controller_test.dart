import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_uv_flutter/ghostty_uv_flutter.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:ultraviolet/ultraviolet.dart' as uv;

void main() {
  test('controller feeds output into the screen', () {
    final controller = GhosttyUvTerminalController();
    addTearDown(controller.dispose);

    controller.feedOutput(utf8.encode('hello\nworld'));

    expect(controller.plainText, contains('hello'));
    expect(controller.plainText, contains('world'));
  });

  test('controller uses write sink when no session is attached', () {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    final sent = controller.write('echo test\n');

    expect(sent, isTrue);
    expect(utf8.decode(written), 'echo test\n');
  });

  test(
    'controller sends cursor-application arrows after screen mode change',
    () {
      final written = <int>[];
      final controller = GhosttyUvTerminalController(
        writeSink: (data) {
          written.addAll(data);
          return data.length;
        },
      );
      addTearDown(controller.dispose);

      controller.feedOutput(utf8.encode('\u001B[?1h'));
      final sent = controller.sendKey(const uv.Key(code: uv.keyLeft));

      expect(sent, isTrue);
      expect(Uint8List.fromList(written), Uint8List.fromList([27, 79, 68]));
    },
  );

  test('controller wraps paste when bracketed paste mode is enabled', () {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    controller.feedOutput(utf8.encode('\u001B[?2004h'));
    final sent = controller.paste('hello');

    expect(sent, isTrue);
    expect(utf8.decode(written), '\u001B[200~hello\u001B[201~');
  });

  test('controller sends shifted underscore through the key bridge', () {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    final sent = controller.sendKey(
      const uv.Key(code: 0x5F, text: '_', mod: uv.KeyMod.shift),
    );

    expect(sent, isTrue);
    expect(utf8.decode(written), '_');
  });

  test('controller sends shifted plus through the key bridge', () {
    final written = <int>[];
    final controller = GhosttyUvTerminalController(
      writeSink: (data) {
        written.addAll(data);
        return data.length;
      },
    );
    addTearDown(controller.dispose);

    final sent = controller.sendKey(
      const uv.Key(code: 0x2B, text: '+', mod: uv.KeyMod.shift),
    );

    expect(sent, isTrue);
    expect(utf8.decode(written), '+');
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
}

class _LaunchMetadataController extends GhosttyUvTerminalController {
  _LaunchMetadataController() : super();

  @override
  Future<void> start({
    required String command,
    List<String> args = const <String>[],
    Map<String, String>? environment,
    GhosttyUvPtySessionConfig config = const GhosttyUvPtySessionConfig(),
  }) async {}
}
