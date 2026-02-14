import 'package:ghostty_vte/ghostty_vte.dart';
import 'package:test/test.dart';

void main() {
  test('safe paste for plain text', () {
    expect(GhosttyVt.isPasteSafe('echo hello'), isTrue);
  });

  test('unsafe paste when newline is present', () {
    expect(GhosttyVt.isPasteSafe('echo hello\nrm -rf /'), isFalse);
  });

  test('OSC parser parses window title command', () {
    final parser = VtOscParser();
    addTearDown(parser.close);

    parser.addText('0;ghostty');
    final command = parser.end();

    expect(
      command.type,
      GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE,
    );
    expect(command.windowTitle, 'ghostty');
  });

  test('OSC parser returns INVALID for garbage input without crashing', () {
    final parser = VtOscParser();
    addTearDown(parser.close);

    // Feed ESC/control bytes that don't form a valid OSC payload —
    // this previously caused a segfault in ghostty_osc_command_data.
    parser.addByte(0x1B); // ESC
    parser.addByte(0x5D); // ]
    parser.addText('not-a-real-osc');

    final command = parser.end();

    expect(
      command.type,
      GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
    );
    expect(command.windowTitle, isNull);
  });

  test('OSC parser returns INVALID when end() is called with no data', () {
    final parser = VtOscParser();
    addTearDown(parser.close);

    final command = parser.end();
    expect(
      command.type,
      GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
    );
  });

  test('SGR parser parses bold + red foreground', () {
    final parser = VtSgrParser();
    addTearDown(parser.close);

    final attrs = parser.parseParams(<int>[1, 31]);
    expect(
      attrs.any((a) => a.tag == GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BOLD),
      isTrue,
    );

    final color = attrs.firstWhere(
      (a) =>
          a.tag == GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_8 ||
          a.tag == GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_8,
    );
    expect(color.paletteIndex, GhosttyNamedColor.red);
  });

  test('key event setters/getters work', () {
    final event = VtKeyEvent();
    addTearDown(event.close);

    event
      ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
      ..key = GhosttyKey.GHOSTTY_KEY_A
      ..mods = GhosttyModsMask.shift | GhosttyModsMask.ctrl
      ..consumedMods = GhosttyModsMask.shift
      ..composing = true
      ..utf8Text = 'A'
      ..unshiftedCodepoint = 0x61;

    expect(event.action, GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS);
    expect(event.key, GhosttyKey.GHOSTTY_KEY_A);
    expect(event.mods, GhosttyModsMask.shift | GhosttyModsMask.ctrl);
    expect(event.consumedMods, GhosttyModsMask.shift);
    expect(event.composing, isTrue);
    expect(event.utf8Text, 'A');
    expect(event.unshiftedCodepoint, 0x61);
  });

  test('key encoder produces bytes for Ctrl+C', () {
    final encoder = VtKeyEncoder();
    final event = VtKeyEvent();
    addTearDown(encoder.close);
    addTearDown(event.close);

    encoder.kittyFlags = GhosttyKittyFlags.all;
    event
      ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
      ..key = GhosttyKey.GHOSTTY_KEY_C
      ..mods = GhosttyModsMask.ctrl
      ..utf8Text = 'c'
      ..unshiftedCodepoint = 0x63;

    final encoded = encoder.encode(event);
    expect(encoded, isNotEmpty);
  });
}
