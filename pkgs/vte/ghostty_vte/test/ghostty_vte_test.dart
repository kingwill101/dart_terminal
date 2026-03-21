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

    expect(command.type, GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID);
    expect(command.windowTitle, isNull);
  });

  test('OSC parser returns INVALID when end() is called with no data', () {
    final parser = VtOscParser();
    addTearDown(parser.close);

    final command = parser.end();
    expect(command.type, GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID);
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

  test('key encoder emits DEL for plain backspace', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    final encoder = VtKeyEncoder();
    final event = VtKeyEvent();
    addTearDown(terminal.close);
    addTearDown(encoder.close);
    addTearDown(event.close);

    encoder.setOptionsFromTerminal(terminal);
    event
      ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
      ..key = GhosttyKey.GHOSTTY_KEY_BACKSPACE
      ..mods = 0
      ..consumedMods = 0
      ..composing = false
      ..utf8Text = ''
      ..unshiftedCodepoint = 0;

    expect(encoder.encode(event), [0x7F]);
  });

  test('terminal formatter outputs plain text', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('Hello');

    expect(formatter.formatText(), 'Hello');
  });

  test('terminal formatter reflects terminal changes', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('Hello');
    expect(formatter.formatText(), 'Hello');

    terminal.write('\r\nWorld');
    expect(formatter.formatText(), 'Hello\nWorld');
  });

  test('terminal formatter allocation helper matches buffer helper', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('Hello\r\nWorld');

    expect(formatter.formatTextAllocated(), formatter.formatText());
    expect(formatter.formatBytesAllocated(), formatter.formatBytes());
  });

  test('terminal formatter allocation helper accepts explicit allocator', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('Hello\r\nWorld');

    expect(
      formatter.formatTextAllocatedWith(VtAllocator.dartMalloc),
      formatter.formatText(),
    );
    expect(
      formatter.formatBytesAllocatedWith(VtAllocator.dartMalloc),
      formatter.formatBytes(),
    );
  });

  test('terminal formatter can emit VT output', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter(
      const VtFormatterTerminalOptions(
        emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_VT,
        extra: VtFormatterTerminalExtra(
          screen: VtFormatterScreenExtra(style: true),
        ),
      ),
    );
    addTearDown(formatter.close);

    terminal.write('Hello\r\n\x1b[31mWorld\x1b[0m');

    final output = formatter.formatText();
    expect(output, contains('Hello'));
    expect(output, contains('World'));
    expect(output, contains('\x1b['));
  });

  test('terminal formatter can emit HTML output', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter(
      const VtFormatterTerminalOptions(
        emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_HTML,
      ),
    );
    addTearDown(formatter.close);

    terminal.write('Html');

    final output = formatter.formatText();
    expect(output.toLowerCase(), contains('html'));
    expect(output.toLowerCase(), contains('<div'));
  });

  test('terminal resize updates tracked dimensions', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    terminal.resize(cols: 40, rows: 12);

    expect(terminal.cols, 40);
    expect(terminal.rows, 12);
  });

  test('terminal reset clears formatter output', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    addTearDown(terminal.close);

    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('Hello');
    expect(formatter.formatText(), 'Hello');

    terminal.reset();
    expect(formatter.formatText(), '');
  });

  test('terminal scroll viewport APIs are callable', () {
    final terminal = GhosttyVt.newTerminal(cols: 5, rows: 2);
    addTearDown(terminal.close);
    final formatter = terminal.createFormatter();
    addTearDown(formatter.close);

    terminal.write('hello');
    terminal.write('\x1bD\x1bD\x1bD');

    expect(() => terminal.scrollToTop(), returnsNormally);
    expect(() => terminal.scrollToBottom(), returnsNormally);
    expect(() => terminal.scrollBy(-3), returnsNormally);
    expect(formatter.formatText(), 'hello');
  });

  test('key encoder can mirror terminal cursor key mode', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    final encoder = GhosttyVt.newKeyEncoder();
    final event = GhosttyVt.newKeyEvent();
    addTearDown(terminal.close);
    addTearDown(encoder.close);
    addTearDown(event.close);

    terminal.write('\x1b[?1h');
    encoder.setOptionsFromTerminal(terminal);

    event
      ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
      ..key = GhosttyKey.GHOSTTY_KEY_ARROW_UP;

    expect(String.fromCharCodes(encoder.encode(event)), '\x1bOA');
  });

  test('closing terminal invalidates borrowed formatter', () {
    final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
    final formatter = terminal.createFormatter();

    terminal.close();

    expect(formatter.formatText, throwsStateError);
  });
}
