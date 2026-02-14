// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Result status codes used by the web runtime shims.
enum GhosttyResult {
  GHOSTTY_SUCCESS(0),
  GHOSTTY_OUT_OF_MEMORY(-1),
  GHOSTTY_INVALID_VALUE(-2);

  const GhosttyResult(this.value);
  final int value;

  static GhosttyResult fromValue(int value) => switch (value) {
    0 => GHOSTTY_SUCCESS,
    -1 => GHOSTTY_OUT_OF_MEMORY,
    -2 => GHOSTTY_INVALID_VALUE,
    _ => throw ArgumentError('Unknown value for GhosttyResult: $value'),
  };
}

/// OSC command types recognized by the terminal parser runtime.
enum GhosttyOscCommandType {
  GHOSTTY_OSC_COMMAND_INVALID(0),
  GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE(1),
  GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON(2),
  GHOSTTY_OSC_COMMAND_SEMANTIC_PROMPT(3),
  GHOSTTY_OSC_COMMAND_CLIPBOARD_CONTENTS(4),
  GHOSTTY_OSC_COMMAND_REPORT_PWD(5),
  GHOSTTY_OSC_COMMAND_MOUSE_SHAPE(6),
  GHOSTTY_OSC_COMMAND_COLOR_OPERATION(7),
  GHOSTTY_OSC_COMMAND_KITTY_COLOR_PROTOCOL(8),
  GHOSTTY_OSC_COMMAND_SHOW_DESKTOP_NOTIFICATION(9),
  GHOSTTY_OSC_COMMAND_HYPERLINK_START(10),
  GHOSTTY_OSC_COMMAND_HYPERLINK_END(11),
  GHOSTTY_OSC_COMMAND_CONEMU_SLEEP(12),
  GHOSTTY_OSC_COMMAND_CONEMU_SHOW_MESSAGE_BOX(13),
  GHOSTTY_OSC_COMMAND_CONEMU_CHANGE_TAB_TITLE(14),
  GHOSTTY_OSC_COMMAND_CONEMU_PROGRESS_REPORT(15),
  GHOSTTY_OSC_COMMAND_CONEMU_WAIT_INPUT(16),
  GHOSTTY_OSC_COMMAND_CONEMU_GUIMACRO(17),
  GHOSTTY_OSC_COMMAND_CONEMU_RUN_PROCESS(18),
  GHOSTTY_OSC_COMMAND_CONEMU_OUTPUT_ENVIRONMENT_VARIABLE(19),
  GHOSTTY_OSC_COMMAND_CONEMU_XTERM_EMULATION(20),
  GHOSTTY_OSC_COMMAND_CONEMU_COMMENT(21),
  GHOSTTY_OSC_COMMAND_KITTY_TEXT_SIZING(22);

  const GhosttyOscCommandType(this.value);
  final int value;

  static GhosttyOscCommandType fromValue(int value) {
    for (final item in GhosttyOscCommandType.values) {
      if (item.value == value) {
        return item;
      }
    }
    throw ArgumentError('Unknown value for GhosttyOscCommandType: $value');
  }
}

/// OSC payload selectors returned by command helpers.
enum GhosttyOscCommandData {
  GHOSTTY_OSC_DATA_INVALID(0),
  GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR(1);

  const GhosttyOscCommandData(this.value);
  final int value;

  static GhosttyOscCommandData fromValue(int value) => switch (value) {
    0 => GHOSTTY_OSC_DATA_INVALID,
    1 => GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR,
    _ => throw ArgumentError('Unknown value for GhosttyOscCommandData: $value'),
  };
}

/// Tags produced by ANSI SGR parsing.
enum GhosttySgrAttributeTag {
  GHOSTTY_SGR_ATTR_UNSET(0),
  GHOSTTY_SGR_ATTR_UNKNOWN(1),
  GHOSTTY_SGR_ATTR_BOLD(2),
  GHOSTTY_SGR_ATTR_RESET_BOLD(3),
  GHOSTTY_SGR_ATTR_ITALIC(4),
  GHOSTTY_SGR_ATTR_RESET_ITALIC(5),
  GHOSTTY_SGR_ATTR_FAINT(6),
  GHOSTTY_SGR_ATTR_UNDERLINE(7),
  GHOSTTY_SGR_ATTR_RESET_UNDERLINE(8),
  GHOSTTY_SGR_ATTR_UNDERLINE_COLOR(9),
  GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256(10),
  GHOSTTY_SGR_ATTR_RESET_UNDERLINE_COLOR(11),
  GHOSTTY_SGR_ATTR_OVERLINE(12),
  GHOSTTY_SGR_ATTR_RESET_OVERLINE(13),
  GHOSTTY_SGR_ATTR_BLINK(14),
  GHOSTTY_SGR_ATTR_RESET_BLINK(15),
  GHOSTTY_SGR_ATTR_INVERSE(16),
  GHOSTTY_SGR_ATTR_RESET_INVERSE(17),
  GHOSTTY_SGR_ATTR_INVISIBLE(18),
  GHOSTTY_SGR_ATTR_RESET_INVISIBLE(19),
  GHOSTTY_SGR_ATTR_STRIKETHROUGH(20),
  GHOSTTY_SGR_ATTR_RESET_STRIKETHROUGH(21),
  GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG(22),
  GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG(23),
  GHOSTTY_SGR_ATTR_BG_8(24),
  GHOSTTY_SGR_ATTR_FG_8(25),
  GHOSTTY_SGR_ATTR_RESET_FG(26),
  GHOSTTY_SGR_ATTR_RESET_BG(27),
  GHOSTTY_SGR_ATTR_BRIGHT_BG_8(28),
  GHOSTTY_SGR_ATTR_BRIGHT_FG_8(29),
  GHOSTTY_SGR_ATTR_BG_256(30),
  GHOSTTY_SGR_ATTR_FG_256(31);

  const GhosttySgrAttributeTag(this.value);
  final int value;

  static GhosttySgrAttributeTag fromValue(int value) {
    for (final item in GhosttySgrAttributeTag.values) {
      if (item.value == value) {
        return item;
      }
    }
    throw ArgumentError('Unknown value for GhosttySgrAttributeTag: $value');
  }
}

/// Underline styles in SGR parser output.
enum GhosttySgrUnderline {
  GHOSTTY_SGR_UNDERLINE_NONE(0),
  GHOSTTY_SGR_UNDERLINE_SINGLE(1),
  GHOSTTY_SGR_UNDERLINE_DOUBLE(2),
  GHOSTTY_SGR_UNDERLINE_CURLY(3),
  GHOSTTY_SGR_UNDERLINE_DOTTED(4),
  GHOSTTY_SGR_UNDERLINE_DASHED(5);

  const GhosttySgrUnderline(this.value);
  final int value;

  static GhosttySgrUnderline fromValue(int value) {
    for (final item in GhosttySgrUnderline.values) {
      if (item.value == value) {
        return item;
      }
    }
    throw ArgumentError('Unknown value for GhosttySgrUnderline: $value');
  }
}

/// Key event action enum used by the key encoder.
enum GhosttyKeyAction {
  GHOSTTY_KEY_ACTION_RELEASE(0),
  GHOSTTY_KEY_ACTION_PRESS(1),
  GHOSTTY_KEY_ACTION_REPEAT(2);

  const GhosttyKeyAction(this.value);
  final int value;

  static GhosttyKeyAction fromValue(int value) => switch (value) {
    0 => GHOSTTY_KEY_ACTION_RELEASE,
    1 => GHOSTTY_KEY_ACTION_PRESS,
    2 => GHOSTTY_KEY_ACTION_REPEAT,
    _ => throw ArgumentError('Unknown value for GhosttyKeyAction: $value'),
  };
}

/// Stable keyboard key identifiers for cross-platform terminal input.
enum GhosttyKey {
  GHOSTTY_KEY_UNIDENTIFIED(0),
  GHOSTTY_KEY_BACKQUOTE(1),
  GHOSTTY_KEY_BACKSLASH(2),
  GHOSTTY_KEY_BRACKET_LEFT(3),
  GHOSTTY_KEY_BRACKET_RIGHT(4),
  GHOSTTY_KEY_COMMA(5),
  GHOSTTY_KEY_DIGIT_0(6),
  GHOSTTY_KEY_DIGIT_1(7),
  GHOSTTY_KEY_DIGIT_2(8),
  GHOSTTY_KEY_DIGIT_3(9),
  GHOSTTY_KEY_DIGIT_4(10),
  GHOSTTY_KEY_DIGIT_5(11),
  GHOSTTY_KEY_DIGIT_6(12),
  GHOSTTY_KEY_DIGIT_7(13),
  GHOSTTY_KEY_DIGIT_8(14),
  GHOSTTY_KEY_DIGIT_9(15),
  GHOSTTY_KEY_EQUAL(16),
  GHOSTTY_KEY_A(20),
  GHOSTTY_KEY_B(21),
  GHOSTTY_KEY_C(22),
  GHOSTTY_KEY_D(23),
  GHOSTTY_KEY_E(24),
  GHOSTTY_KEY_F(25),
  GHOSTTY_KEY_G(26),
  GHOSTTY_KEY_H(27),
  GHOSTTY_KEY_I(28),
  GHOSTTY_KEY_J(29),
  GHOSTTY_KEY_K(30),
  GHOSTTY_KEY_L(31),
  GHOSTTY_KEY_M(32),
  GHOSTTY_KEY_N(33),
  GHOSTTY_KEY_O(34),
  GHOSTTY_KEY_P(35),
  GHOSTTY_KEY_Q(36),
  GHOSTTY_KEY_R(37),
  GHOSTTY_KEY_S(38),
  GHOSTTY_KEY_T(39),
  GHOSTTY_KEY_U(40),
  GHOSTTY_KEY_V(41),
  GHOSTTY_KEY_W(42),
  GHOSTTY_KEY_X(43),
  GHOSTTY_KEY_Y(44),
  GHOSTTY_KEY_Z(45),
  GHOSTTY_KEY_MINUS(46),
  GHOSTTY_KEY_PERIOD(47),
  GHOSTTY_KEY_QUOTE(48),
  GHOSTTY_KEY_SEMICOLON(49),
  GHOSTTY_KEY_SLASH(50),
  GHOSTTY_KEY_BACKSPACE(53),
  GHOSTTY_KEY_ENTER(58),
  GHOSTTY_KEY_SPACE(63),
  GHOSTTY_KEY_TAB(64),
  GHOSTTY_KEY_DELETE(68),
  GHOSTTY_KEY_END(69),
  GHOSTTY_KEY_HOME(71),
  GHOSTTY_KEY_INSERT(72),
  GHOSTTY_KEY_PAGE_DOWN(73),
  GHOSTTY_KEY_PAGE_UP(74),
  GHOSTTY_KEY_ARROW_DOWN(75),
  GHOSTTY_KEY_ARROW_LEFT(76),
  GHOSTTY_KEY_ARROW_RIGHT(77),
  GHOSTTY_KEY_ARROW_UP(78),
  GHOSTTY_KEY_ESCAPE(120),
  GHOSTTY_KEY_F1(121),
  GHOSTTY_KEY_F2(122),
  GHOSTTY_KEY_F3(123),
  GHOSTTY_KEY_F4(124),
  GHOSTTY_KEY_F5(125),
  GHOSTTY_KEY_F6(126),
  GHOSTTY_KEY_F7(127),
  GHOSTTY_KEY_F8(128),
  GHOSTTY_KEY_F9(129),
  GHOSTTY_KEY_F10(130),
  GHOSTTY_KEY_F11(131),
  GHOSTTY_KEY_F12(132);

  const GhosttyKey(this.value);
  final int value;

  static GhosttyKey fromValue(int value) {
    for (final item in GhosttyKey.values) {
      if (item.value == value) {
        return item;
      }
    }
    throw ArgumentError('Unknown value for GhosttyKey: $value');
  }
}

/// Option handling for Alt/meta key behavior.
enum GhosttyOptionAsAlt {
  GHOSTTY_OPTION_AS_ALT_FALSE(0),
  GHOSTTY_OPTION_AS_ALT_TRUE(1),
  GHOSTTY_OPTION_AS_ALT_LEFT(2),
  GHOSTTY_OPTION_AS_ALT_RIGHT(3);

  const GhosttyOptionAsAlt(this.value);
  final int value;
}

/// Key encoder feature flags.
enum GhosttyKeyEncoderOption {
  GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION(0),
  GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION(1),
  GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK(2),
  GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX(3),
  GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2(4),
  GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS(5),
  GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT(6);

  const GhosttyKeyEncoderOption(this.value);
  final int value;
}

/// Named ANSI color constants.
const int GHOSTTY_COLOR_NAMED_BLACK = 0;
const int GHOSTTY_COLOR_NAMED_RED = 1;
const int GHOSTTY_COLOR_NAMED_GREEN = 2;
const int GHOSTTY_COLOR_NAMED_YELLOW = 3;
const int GHOSTTY_COLOR_NAMED_BLUE = 4;
const int GHOSTTY_COLOR_NAMED_MAGENTA = 5;
const int GHOSTTY_COLOR_NAMED_CYAN = 6;
const int GHOSTTY_COLOR_NAMED_WHITE = 7;
const int GHOSTTY_COLOR_NAMED_BRIGHT_BLACK = 8;
const int GHOSTTY_COLOR_NAMED_BRIGHT_RED = 9;
const int GHOSTTY_COLOR_NAMED_BRIGHT_GREEN = 10;
const int GHOSTTY_COLOR_NAMED_BRIGHT_YELLOW = 11;
const int GHOSTTY_COLOR_NAMED_BRIGHT_BLUE = 12;
const int GHOSTTY_COLOR_NAMED_BRIGHT_MAGENTA = 13;
const int GHOSTTY_COLOR_NAMED_BRIGHT_CYAN = 14;
const int GHOSTTY_COLOR_NAMED_BRIGHT_WHITE = 15;

/// Keyboard modifier mask constants for key events.
const int GHOSTTY_MODS_SHIFT = 1;
const int GHOSTTY_MODS_CTRL = 2;
const int GHOSTTY_MODS_ALT = 4;
const int GHOSTTY_MODS_SUPER = 8;
const int GHOSTTY_MODS_CAPS_LOCK = 16;
const int GHOSTTY_MODS_NUM_LOCK = 32;
const int GHOSTTY_MODS_SHIFT_SIDE = 64;
const int GHOSTTY_MODS_CTRL_SIDE = 128;
const int GHOSTTY_MODS_ALT_SIDE = 256;
const int GHOSTTY_MODS_SUPER_SIDE = 512;

/// Kitty keyboard feature mask constants.
const int GHOSTTY_KITTY_KEY_DISABLED = 0;
const int GHOSTTY_KITTY_KEY_DISAMBIGUATE = 1;
const int GHOSTTY_KITTY_KEY_REPORT_EVENTS = 2;
const int GHOSTTY_KITTY_KEY_REPORT_ALTERNATES = 4;
const int GHOSTTY_KITTY_KEY_REPORT_ALL = 8;
const int GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED = 16;
const int GHOSTTY_KITTY_KEY_ALL = 31;

final class GhosttyVtWasm {
  const GhosttyVtWasm._();

  static _GhosttyWasmRuntime? _runtime;

  static bool get isInitialized => _runtime != null;

  static Future<void> initializeFromBytes(Uint8List wasmBytes) async {
    if (_runtime != null) {
      return;
    }
    _runtime = await _GhosttyWasmRuntime.fromBytes(wasmBytes);
  }
}

final class _GhosttyWasmRuntime {
  _GhosttyWasmRuntime(this._exports, this._memory);

  final JSObject _exports;
  final JSObject _memory;

  static Future<_GhosttyWasmRuntime> fromBytes(Uint8List wasmBytes) async {
    final imports =
        <String, Object?>{
              'env': <String, Object?>{
                // Ghostty imports this symbol for logging in wasm builds.
                'log': ((JSAny? _, JSAny? _) {}).toJS,
              },
            }.jsify()!
            as JSObject;

    final webAssembly = globalContext['WebAssembly']! as JSObject;
    final instantiate = webAssembly['instantiate']! as JSFunction;
    final result =
        await (instantiate.callAsFunction(webAssembly, wasmBytes.toJS, imports)!
                as JSPromise<JSAny?>)
            .toDart;
    final resultObject = result! as JSObject;
    final instance = resultObject['instance']! as JSObject;
    final exports = instance['exports']! as JSObject;
    final memory = exports['memory']! as JSObject;
    return _GhosttyWasmRuntime(exports, memory);
  }

  int callInt(String fn, [List<Object?> args = const <Object?>[]]) {
    final result = _exports.callMethodVarArgs<JSAny?>(
      fn.toJS,
      args.map(_dartToJSAny).toList(growable: false),
    );
    if (result == null) {
      return 0;
    }
    final dartResult = result.dartify();
    if (dartResult is num) {
      return dartResult.toInt();
    }
    if (dartResult is bool) {
      return dartResult ? 1 : 0;
    }
    throw StateError('Unexpected return type from $fn');
  }

  bool callBool(String fn, [List<Object?> args = const <Object?>[]]) {
    return callInt(fn, args) != 0;
  }

  ByteBuffer get _buffer => (_memory['buffer']! as JSArrayBuffer).toDart;

  ByteData get _data => ByteData.view(_buffer);

  Uint8List u8View(int ptr, int len) => Uint8List.view(_buffer, ptr, len);

  int readPtr(int ptr) => _data.getUint32(ptr, Endian.little);

  int readU8(int ptr) => _data.getUint8(ptr);

  int readU16(int ptr) => _data.getUint16(ptr, Endian.little);

  int readUsize(int ptr) => _data.getUint32(ptr, Endian.little);

  int readI32(int ptr) => _data.getInt32(ptr, Endian.little);

  void writeU8(int ptr, int value) {
    _data.setUint8(ptr, value & 0xFF);
  }

  void writeU16(int ptr, int value) {
    _data.setUint16(ptr, value & 0xFFFF, Endian.little);
  }

  void writeU32(int ptr, int value) {
    _data.setUint32(ptr, value, Endian.little);
  }

  String readCString(int ptr) {
    if (ptr == 0) {
      return '';
    }
    final bytes = <int>[];
    var cursor = ptr;
    while (true) {
      final b = readU8(cursor++);
      if (b == 0) {
        break;
      }
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  List<int> readU16List(int ptr, int len) {
    if (ptr == 0 || len == 0) {
      return const <int>[];
    }
    final out = List<int>.filled(len, 0, growable: false);
    for (var i = 0; i < len; i++) {
      out[i] = readU16(ptr + (i * 2));
    }
    return out;
  }

  int allocOpaque() => callInt('ghostty_wasm_alloc_opaque');

  void freeOpaque(int ptr) =>
      callInt('ghostty_wasm_free_opaque', <Object>[ptr]);

  int allocU8Array(int len) =>
      callInt('ghostty_wasm_alloc_u8_array', <Object>[len]);

  void freeU8Array(int ptr, int len) =>
      callInt('ghostty_wasm_free_u8_array', <Object>[ptr, len]);

  int allocU16Array(int len) =>
      callInt('ghostty_wasm_alloc_u16_array', <Object>[len]);

  void freeU16Array(int ptr, int len) =>
      callInt('ghostty_wasm_free_u16_array', <Object>[ptr, len]);

  int allocU8() => callInt('ghostty_wasm_alloc_u8');

  void freeU8(int ptr) => callInt('ghostty_wasm_free_u8', <Object>[ptr]);

  int allocUsize() => callInt('ghostty_wasm_alloc_usize');

  void freeUsize(int ptr) => callInt('ghostty_wasm_free_usize', <Object>[ptr]);
}

_GhosttyWasmRuntime? _runtime() => GhosttyVtWasm._runtime;

JSAny? _dartToJSAny(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value.toJS;
  }
  if (value is num) {
    return value.toJS;
  }
  if (value is String) {
    return value.toJS;
  }
  if (value is ByteBuffer) {
    return value.toJS;
  }
  if (value is Uint8List) {
    return value.toJS;
  }
  throw ArgumentError('Unsupported JS argument type: ${value.runtimeType}');
}

final class GhosttyVtError implements Exception {
  GhosttyVtError(this.operation, this.result);

  final String operation;
  final GhosttyResult result;

  @override
  String toString() => 'GhosttyVtError(operation: $operation, result: $result)';
}

void _checkResult(int result, String operation) {
  final mapped = GhosttyResult.fromValue(result);
  if (mapped != GhosttyResult.GHOSTTY_SUCCESS) {
    throw GhosttyVtError(operation, mapped);
  }
}

final class GhosttyModsMask {
  const GhosttyModsMask._();

  static const int shift = GHOSTTY_MODS_SHIFT;
  static const int ctrl = GHOSTTY_MODS_CTRL;
  static const int alt = GHOSTTY_MODS_ALT;
  static const int superKey = GHOSTTY_MODS_SUPER;
  static const int capsLock = GHOSTTY_MODS_CAPS_LOCK;
  static const int numLock = GHOSTTY_MODS_NUM_LOCK;
  static const int shiftSide = GHOSTTY_MODS_SHIFT_SIDE;
  static const int ctrlSide = GHOSTTY_MODS_CTRL_SIDE;
  static const int altSide = GHOSTTY_MODS_ALT_SIDE;
  static const int superSide = GHOSTTY_MODS_SUPER_SIDE;
}

final class GhosttyKittyFlags {
  const GhosttyKittyFlags._();

  static const int disabled = GHOSTTY_KITTY_KEY_DISABLED;
  static const int disambiguate = GHOSTTY_KITTY_KEY_DISAMBIGUATE;
  static const int reportEvents = GHOSTTY_KITTY_KEY_REPORT_EVENTS;
  static const int reportAlternates = GHOSTTY_KITTY_KEY_REPORT_ALTERNATES;
  static const int reportAll = GHOSTTY_KITTY_KEY_REPORT_ALL;
  static const int reportAssociated = GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED;
  static const int all = GHOSTTY_KITTY_KEY_ALL;
}

final class GhosttyNamedColor {
  const GhosttyNamedColor._();

  static const int black = GHOSTTY_COLOR_NAMED_BLACK;
  static const int red = GHOSTTY_COLOR_NAMED_RED;
  static const int green = GHOSTTY_COLOR_NAMED_GREEN;
  static const int yellow = GHOSTTY_COLOR_NAMED_YELLOW;
  static const int blue = GHOSTTY_COLOR_NAMED_BLUE;
  static const int magenta = GHOSTTY_COLOR_NAMED_MAGENTA;
  static const int cyan = GHOSTTY_COLOR_NAMED_CYAN;
  static const int white = GHOSTTY_COLOR_NAMED_WHITE;
  static const int brightBlack = GHOSTTY_COLOR_NAMED_BRIGHT_BLACK;
  static const int brightRed = GHOSTTY_COLOR_NAMED_BRIGHT_RED;
  static const int brightGreen = GHOSTTY_COLOR_NAMED_BRIGHT_GREEN;
  static const int brightYellow = GHOSTTY_COLOR_NAMED_BRIGHT_YELLOW;
  static const int brightBlue = GHOSTTY_COLOR_NAMED_BRIGHT_BLUE;
  static const int brightMagenta = GHOSTTY_COLOR_NAMED_BRIGHT_MAGENTA;
  static const int brightCyan = GHOSTTY_COLOR_NAMED_BRIGHT_CYAN;
  static const int brightWhite = GHOSTTY_COLOR_NAMED_BRIGHT_WHITE;
}

final class VtRgbColor {
  const VtRgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  @override
  String toString() => 'VtRgbColor(r: $r, g: $g, b: $b)';
}

final class VtOscCommand {
  const VtOscCommand({required this.type, this.windowTitle});

  final GhosttyOscCommandType type;
  final String? windowTitle;
}

final class VtOscParser {
  VtOscParser() {
    final rt = _runtime();
    if (rt != null) {
      _wasm = rt;
      final out = rt.allocOpaque();
      if (out == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_opaque',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final result = rt.callInt('ghostty_osc_new', <Object>[0, out]);
        _checkResult(result, 'ghostty_osc_new');
        _handle = rt.readPtr(out);
      } finally {
        rt.freeOpaque(out);
      }
    }
  }

  _GhosttyWasmRuntime? _wasm;
  int _handle = 0;
  final List<int> _bytes = <int>[];
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtOscParser is already closed.');
    }
  }

  void reset() {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_osc_reset', <Object>[_handle]);
      return;
    }
    _bytes.clear();
  }

  void addByte(int byte) {
    _ensureOpen();
    if (byte < 0 || byte > 255) {
      throw RangeError.range(byte, 0, 255, 'byte');
    }
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_osc_next', <Object>[_handle, byte]);
      return;
    }
    _bytes.add(byte);
  }

  void addBytes(Iterable<int> bytes) {
    for (final byte in bytes) {
      addByte(byte);
    }
  }

  void addText(String text, {Encoding encoding = utf8}) {
    addBytes(encoding.encode(text));
  }

  VtOscCommand end({int terminator = 0x07}) {
    _ensureOpen();
    if (terminator < 0 || terminator > 255) {
      throw RangeError.range(terminator, 0, 255, 'terminator');
    }
    final rt = _wasm;
    if (rt != null) {
      final command = rt.callInt('ghostty_osc_end', <Object>[
        _handle,
        terminator,
      ]);

      // Guard: if the wasm call returned a null pointer, treat as invalid.
      if (command == 0) {
        return const VtOscCommand(
          type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
        );
      }

      final type = GhosttyOscCommandType.fromValue(
        rt.callInt('ghostty_osc_command_type', <Object>[command]),
      );

      // Guard: don't attempt to extract data from invalid/unrecognised
      // commands — the wasm library may crash if asked for data on a command
      // that doesn't carry it.
      if (type == GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID) {
        return const VtOscCommand(
          type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
        );
      }

      String? windowTitle;

      // Only query the window-title data field for command types that carry it.
      if (type ==
              GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE ||
          type ==
              GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON) {
        final out = rt.allocOpaque();
        if (out != 0) {
          try {
            final ok = rt.callBool('ghostty_osc_command_data', <Object>[
              command,
              GhosttyOscCommandData
                  .GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR
                  .value,
              out,
            ]);
            if (ok) {
              final strPtr = rt.readPtr(out);
              if (strPtr != 0) {
                windowTitle = rt.readCString(strPtr);
              }
            }
          } finally {
            rt.freeOpaque(out);
          }
        }
      }

      return VtOscCommand(type: type, windowTitle: windowTitle);
    }

    final payload = utf8.decode(_bytes, allowMalformed: true);
    final separator = payload.indexOf(';');
    if (separator <= 0 || separator >= payload.length - 1) {
      return const VtOscCommand(
        type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
      );
    }
    final code = payload.substring(0, separator);
    final data = payload.substring(separator + 1);
    switch (code) {
      case '0':
      case '2':
        return VtOscCommand(
          type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE,
          windowTitle: data,
        );
      case '1':
        return const VtOscCommand(
          type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON,
        );
      default:
        return const VtOscCommand(
          type: GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
        );
    }
  }

  void close() {
    final rt = _wasm;
    if (rt != null && _handle != 0) {
      rt.callInt('ghostty_osc_free', <Object>[_handle]);
      _handle = 0;
      _wasm = null;
    }
    _closed = true;
  }
}

final class VtSgrUnknownData {
  const VtSgrUnknownData({required this.full, required this.partial});

  final List<int> full;
  final List<int> partial;
}

final class VtSgrAttributeData {
  const VtSgrAttributeData({
    required this.tag,
    this.unknown,
    this.underline,
    this.rgb,
    this.paletteIndex,
  });

  final GhosttySgrAttributeTag tag;
  final VtSgrUnknownData? unknown;
  final GhosttySgrUnderline? underline;
  final VtRgbColor? rgb;
  final int? paletteIndex;
}

final class VtSgrParser {
  VtSgrParser() {
    final rt = _runtime();
    if (rt != null) {
      _wasm = rt;
      final out = rt.allocOpaque();
      if (out == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_opaque',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final result = rt.callInt('ghostty_sgr_new', <Object>[0, out]);
        _checkResult(result, 'ghostty_sgr_new');
        _handle = rt.readPtr(out);
      } finally {
        rt.freeOpaque(out);
      }
      _attrPtr = rt.callInt('ghostty_wasm_alloc_sgr_attribute');
      if (_attrPtr == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_sgr_attribute',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
    }
  }

  _GhosttyWasmRuntime? _wasm;
  int _handle = 0;
  int _attrPtr = 0;
  List<int> _params = <int>[];
  int _index = 0;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtSgrParser is already closed.');
    }
  }

  void reset() {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_sgr_reset', <Object>[_handle]);
      return;
    }
    _index = 0;
  }

  void setParams(List<int> params, {String? separators}) {
    _ensureOpen();
    if (separators != null && separators.length != params.length) {
      throw ArgumentError.value(
        separators,
        'separators',
        'Must have same length as params.',
      );
    }
    final rt = _wasm;
    if (rt != null) {
      final paramsPtr = rt.allocU16Array(params.length);
      if (paramsPtr == 0 && params.isNotEmpty) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_u16_array',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      var separatorsPtr = 0;
      try {
        for (var i = 0; i < params.length; i++) {
          final value = params[i];
          if (value < 0 || value > 0xFFFF) {
            throw RangeError.range(value, 0, 0xFFFF, 'params[$i]');
          }
          rt.writeU16(paramsPtr + (i * 2), value);
        }
        if (separators != null) {
          separatorsPtr = rt.allocU8Array(separators.length);
          if (separatorsPtr == 0 && separators.isNotEmpty) {
            throw GhosttyVtError(
              'ghostty_wasm_alloc_u8_array',
              GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
            );
          }
          for (var i = 0; i < separators.length; i++) {
            final value = separators.codeUnitAt(i);
            if (value > 0xFF) {
              throw RangeError.range(value, 0, 0xFF, 'separators[$i]');
            }
            rt.writeU8(separatorsPtr + i, value);
          }
        }
        final result = rt.callInt('ghostty_sgr_set_params', <Object>[
          _handle,
          paramsPtr,
          separatorsPtr,
          params.length,
        ]);
        _checkResult(result, 'ghostty_sgr_set_params');
      } finally {
        if (separatorsPtr != 0) {
          rt.freeU8Array(separatorsPtr, separators!.length);
        }
        if (paramsPtr != 0) {
          rt.freeU16Array(paramsPtr, params.length);
        }
      }
      return;
    }
    _params = List<int>.from(params);
    _index = 0;
  }

  VtSgrAttributeData? next() {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      final hasNext = rt.callBool('ghostty_sgr_next', <Object>[
        _handle,
        _attrPtr,
      ]);
      if (!hasNext) {
        return null;
      }

      final tag = GhosttySgrAttributeTag.fromValue(
        rt.callInt('ghostty_sgr_attribute_tag', <Object>[_attrPtr]),
      );
      final valuePtr = rt.callInt('ghostty_sgr_attribute_value', <Object>[
        _attrPtr,
      ]);
      switch (tag) {
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN:
          final fullPtr = rt.readPtr(valuePtr);
          final fullLen = rt.readUsize(valuePtr + 4);
          final partialPtr = rt.readPtr(valuePtr + 8);
          final partialLen = rt.readUsize(valuePtr + 12);
          return VtSgrAttributeData(
            tag: tag,
            unknown: VtSgrUnknownData(
              full: List<int>.unmodifiable(rt.readU16List(fullPtr, fullLen)),
              partial: List<int>.unmodifiable(
                rt.readU16List(partialPtr, partialLen),
              ),
            ),
          );
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE:
          return VtSgrAttributeData(
            tag: tag,
            underline: GhosttySgrUnderline.fromValue(rt.readI32(valuePtr)),
          );
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG:
          return VtSgrAttributeData(
            tag: tag,
            rgb: VtRgbColor(
              rt.readU8(valuePtr),
              rt.readU8(valuePtr + 1),
              rt.readU8(valuePtr + 2),
            ),
          );
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_8:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_8:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_BG_8:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_FG_8:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_256:
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_256:
          return VtSgrAttributeData(
            tag: tag,
            paletteIndex: rt.readU8(valuePtr),
          );
        default:
          return VtSgrAttributeData(tag: tag);
      }
    }
    if (_index >= _params.length) {
      return null;
    }
    final p = _params[_index++];
    switch (p) {
      case 0:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNSET,
        );
      case 1:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BOLD,
        );
      case 2:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FAINT,
        );
      case 3:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_ITALIC,
        );
      case 4:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_SINGLE,
        );
      case 5:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BLINK,
        );
      case 7:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_INVERSE,
        );
      case 8:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_INVISIBLE,
        );
      case 9:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_STRIKETHROUGH,
        );
      case 22:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BOLD,
        );
      case 23:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_ITALIC,
        );
      case 24:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_UNDERLINE,
        );
      case 25:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BLINK,
        );
      case 27:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_INVERSE,
        );
      case 28:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_INVISIBLE,
        );
      case 29:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_STRIKETHROUGH,
        );
      case 39:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_FG,
        );
      case 49:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BG,
        );
      case 53:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_OVERLINE,
        );
      case 55:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_OVERLINE,
        );
      case 59:
        return const VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_UNDERLINE_COLOR,
        );
      case 30:
      case 31:
      case 32:
      case 33:
      case 34:
      case 35:
      case 36:
      case 37:
        return VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_8,
          paletteIndex: p - 30,
        );
      case 40:
      case 41:
      case 42:
      case 43:
      case 44:
      case 45:
      case 46:
      case 47:
        return VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_8,
          paletteIndex: p - 40,
        );
      case 90:
      case 91:
      case 92:
      case 93:
      case 94:
      case 95:
      case 96:
      case 97:
        return VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_FG_8,
          paletteIndex: (p - 90) + 8,
        );
      case 100:
      case 101:
      case 102:
      case 103:
      case 104:
      case 105:
      case 106:
      case 107:
        return VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_BG_8,
          paletteIndex: (p - 100) + 8,
        );
      case 38:
        return _parseComplexColor(fg: true, fallbackAt: _index - 1);
      case 48:
        return _parseComplexColor(fg: false, fallbackAt: _index - 1);
      case 58:
        return _parseUnderlineColor(fallbackAt: _index - 1);
      default:
        return VtSgrAttributeData(
          tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN,
          unknown: VtSgrUnknownData(
            full: List<int>.from(_params),
            partial: List<int>.from(_params.sublist(_index - 1)),
          ),
        );
    }
  }

  VtSgrAttributeData _parseUnderlineColor({required int fallbackAt}) {
    if (_index + 1 < _params.length && _params[_index] == 5) {
      final palette = _params[_index + 1].clamp(0, 255);
      _index += 2;
      return VtSgrAttributeData(
        tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256,
        paletteIndex: palette,
      );
    }
    if (_index + 3 < _params.length && _params[_index] == 2) {
      final r = _params[_index + 1].clamp(0, 255);
      final g = _params[_index + 2].clamp(0, 255);
      final b = _params[_index + 3].clamp(0, 255);
      _index += 4;
      return VtSgrAttributeData(
        tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR,
        rgb: VtRgbColor(r, g, b),
      );
    }
    return VtSgrAttributeData(
      tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN,
      unknown: VtSgrUnknownData(
        full: List<int>.from(_params),
        partial: List<int>.from(_params.sublist(fallbackAt)),
      ),
    );
  }

  VtSgrAttributeData _parseComplexColor({
    required bool fg,
    required int fallbackAt,
  }) {
    if (_index + 1 < _params.length && _params[_index] == 5) {
      final palette = _params[_index + 1].clamp(0, 255);
      _index += 2;
      return VtSgrAttributeData(
        tag: fg
            ? GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_256
            : GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_256,
        paletteIndex: palette,
      );
    }
    if (_index + 3 < _params.length && _params[_index] == 2) {
      final r = _params[_index + 1].clamp(0, 255);
      final g = _params[_index + 2].clamp(0, 255);
      final b = _params[_index + 3].clamp(0, 255);
      _index += 4;
      return VtSgrAttributeData(
        tag: fg
            ? GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG
            : GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG,
        rgb: VtRgbColor(r, g, b),
      );
    }
    return VtSgrAttributeData(
      tag: GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN,
      unknown: VtSgrUnknownData(
        full: List<int>.from(_params),
        partial: List<int>.from(_params.sublist(fallbackAt)),
      ),
    );
  }

  List<VtSgrAttributeData> parseAll() {
    final out = <VtSgrAttributeData>[];
    while (true) {
      final attr = next();
      if (attr == null) {
        break;
      }
      out.add(attr);
    }
    return out;
  }

  List<VtSgrAttributeData> parseParams(List<int> params, {String? separators}) {
    setParams(params, separators: separators);
    return parseAll();
  }

  void close() {
    final rt = _wasm;
    if (rt != null) {
      if (_handle != 0) {
        rt.callInt('ghostty_sgr_free', <Object>[_handle]);
        _handle = 0;
      }
      if (_attrPtr != 0) {
        rt.callInt('ghostty_wasm_free_sgr_attribute', <Object>[_attrPtr]);
        _attrPtr = 0;
      }
      _wasm = null;
    }
    _closed = true;
  }
}

final class VtKeyEvent {
  VtKeyEvent() {
    final rt = _runtime();
    if (rt != null) {
      _wasm = rt;
      final out = rt.allocOpaque();
      if (out == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_opaque',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final result = rt.callInt('ghostty_key_event_new', <Object>[0, out]);
        _checkResult(result, 'ghostty_key_event_new');
        _handle = rt.readPtr(out);
      } finally {
        rt.freeOpaque(out);
      }
    }
  }

  _GhosttyWasmRuntime? _wasm;
  int _handle = 0;
  int _utf8StoragePtr = 0;
  int _utf8StorageLen = 0;
  bool _closed = false;

  GhosttyKeyAction _fallbackAction = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
  GhosttyKey _fallbackKey = GhosttyKey.GHOSTTY_KEY_UNIDENTIFIED;
  int _fallbackMods = 0;
  int _fallbackConsumedMods = 0;
  bool _fallbackComposing = false;
  String _fallbackUtf8Text = '';
  int _fallbackUnshiftedCodepoint = 0;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtKeyEvent is already closed.');
    }
  }

  GhosttyKeyAction get action {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return GhosttyKeyAction.fromValue(
        rt.callInt('ghostty_key_event_get_action', <Object>[_handle]),
      );
    }
    return _fallbackAction;
  }

  set action(GhosttyKeyAction value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_action', <Object>[
        _handle,
        value.value,
      ]);
      return;
    }
    _fallbackAction = value;
  }

  GhosttyKey get key {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return GhosttyKey.fromValue(
        rt.callInt('ghostty_key_event_get_key', <Object>[_handle]),
      );
    }
    return _fallbackKey;
  }

  set key(GhosttyKey value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_key', <Object>[_handle, value.value]);
      return;
    }
    _fallbackKey = value;
  }

  int get mods {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return rt.callInt('ghostty_key_event_get_mods', <Object>[_handle]);
    }
    return _fallbackMods;
  }

  set mods(int value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_mods', <Object>[_handle, value]);
      return;
    }
    _fallbackMods = value;
  }

  int get consumedMods {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return rt.callInt('ghostty_key_event_get_consumed_mods', <Object>[
        _handle,
      ]);
    }
    return _fallbackConsumedMods;
  }

  set consumedMods(int value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_consumed_mods', <Object>[
        _handle,
        value,
      ]);
      return;
    }
    _fallbackConsumedMods = value;
  }

  bool get composing {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return rt.callBool('ghostty_key_event_get_composing', <Object>[_handle]);
    }
    return _fallbackComposing;
  }

  set composing(bool value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_composing', <Object>[
        _handle,
        value ? 1 : 0,
      ]);
      return;
    }
    _fallbackComposing = value;
  }

  String get utf8Text {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      final lenPtr = rt.allocUsize();
      if (lenPtr == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_usize',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final textPtr = rt.callInt('ghostty_key_event_get_utf8', <Object>[
          _handle,
          lenPtr,
        ]);
        final len = rt.readUsize(lenPtr);
        if (textPtr == 0 || len == 0) {
          return '';
        }
        return utf8.decode(rt.u8View(textPtr, len), allowMalformed: true);
      } finally {
        rt.freeUsize(lenPtr);
      }
    }
    return _fallbackUtf8Text;
  }

  set utf8Text(String value) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      _freeUtf8Storage();
      if (value.isEmpty) {
        rt.callInt('ghostty_key_event_set_utf8', <Object>[_handle, 0, 0]);
        return;
      }
      final bytes = utf8.encode(value);
      final textPtr = rt.allocU8Array(bytes.length);
      if (textPtr == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_u8_array',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      rt.u8View(textPtr, bytes.length).setAll(0, bytes);
      _utf8StoragePtr = textPtr;
      _utf8StorageLen = bytes.length;
      rt.callInt('ghostty_key_event_set_utf8', <Object>[
        _handle,
        textPtr,
        bytes.length,
      ]);
      return;
    }
    _fallbackUtf8Text = value;
  }

  int get unshiftedCodepoint {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null) {
      return rt.callInt('ghostty_key_event_get_unshifted_codepoint', <Object>[
        _handle,
      ]);
    }
    return _fallbackUnshiftedCodepoint;
  }

  set unshiftedCodepoint(int value) {
    _ensureOpen();
    if (value < 0 || value > 0x10FFFF) {
      throw RangeError.range(value, 0, 0x10FFFF, 'unshiftedCodepoint');
    }
    final rt = _wasm;
    if (rt != null) {
      rt.callInt('ghostty_key_event_set_unshifted_codepoint', <Object>[
        _handle,
        value,
      ]);
      return;
    }
    _fallbackUnshiftedCodepoint = value;
  }

  void _freeUtf8Storage() {
    final rt = _wasm;
    if (rt != null && _utf8StoragePtr != 0) {
      rt.freeU8Array(_utf8StoragePtr, _utf8StorageLen);
      _utf8StoragePtr = 0;
      _utf8StorageLen = 0;
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _freeUtf8Storage();
    final rt = _wasm;
    if (rt != null && _handle != 0) {
      rt.callInt('ghostty_key_event_free', <Object>[_handle]);
      _handle = 0;
      _wasm = null;
    }
    _closed = true;
  }
}

final class VtKeyEncoder {
  VtKeyEncoder() {
    final rt = _runtime();
    if (rt != null) {
      _wasm = rt;
      final out = rt.allocOpaque();
      if (out == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_opaque',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final result = rt.callInt('ghostty_key_encoder_new', <Object>[0, out]);
        _checkResult(result, 'ghostty_key_encoder_new');
        _handle = rt.readPtr(out);
      } finally {
        rt.freeOpaque(out);
      }
    }
  }

  _GhosttyWasmRuntime? _wasm;
  int _handle = 0;
  bool _closed = false;

  bool _cursorKeyApplication = false;
  bool _keypadKeyApplication = false;
  bool _ignoreKeypadWithNumLock = true;
  bool _altEscPrefix = true;
  bool _modifyOtherKeysState2 = true;
  int _kittyFlags = GhosttyKittyFlags.disabled;
  GhosttyOptionAsAlt _macosOptionAsAlt =
      GhosttyOptionAsAlt.GHOSTTY_OPTION_AS_ALT_FALSE;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtKeyEncoder is already closed.');
    }
  }

  void _setBoolOptionWasm(GhosttyKeyEncoderOption option, bool value) {
    final rt = _wasm;
    if (rt == null) {
      return;
    }
    final ptr = rt.allocU8();
    if (ptr == 0) {
      throw GhosttyVtError(
        'ghostty_wasm_alloc_u8',
        GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
      );
    }
    try {
      rt.writeU8(ptr, value ? 1 : 0);
      rt.callInt('ghostty_key_encoder_setopt', <Object>[
        _handle,
        option.value,
        ptr,
      ]);
    } finally {
      rt.freeU8(ptr);
    }
  }

  set cursorKeyApplication(bool enabled) {
    _ensureOpen();
    _cursorKeyApplication = enabled;
    _setBoolOptionWasm(
      GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION,
      enabled,
    );
  }

  set keypadKeyApplication(bool enabled) {
    _ensureOpen();
    _keypadKeyApplication = enabled;
    _setBoolOptionWasm(
      GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION,
      enabled,
    );
  }

  set ignoreKeypadWithNumLock(bool enabled) {
    _ensureOpen();
    _ignoreKeypadWithNumLock = enabled;
    _setBoolOptionWasm(
      GhosttyKeyEncoderOption
          .GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK,
      enabled,
    );
  }

  set altEscPrefix(bool enabled) {
    _ensureOpen();
    _altEscPrefix = enabled;
    _setBoolOptionWasm(
      GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX,
      enabled,
    );
  }

  set modifyOtherKeysState2(bool enabled) {
    _ensureOpen();
    _modifyOtherKeysState2 = enabled;
    _setBoolOptionWasm(
      GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2,
      enabled,
    );
  }

  set kittyFlags(int flags) {
    _ensureOpen();
    _kittyFlags = flags;
    final rt = _wasm;
    if (rt == null) {
      return;
    }
    final ptr = rt.allocU8();
    if (ptr == 0) {
      throw GhosttyVtError(
        'ghostty_wasm_alloc_u8',
        GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
      );
    }
    try {
      rt.writeU8(ptr, flags & 0xFF);
      rt.callInt('ghostty_key_encoder_setopt', <Object>[
        _handle,
        GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS.value,
        ptr,
      ]);
    } finally {
      rt.freeU8(ptr);
    }
  }

  set macosOptionAsAlt(GhosttyOptionAsAlt value) {
    _ensureOpen();
    _macosOptionAsAlt = value;
    final rt = _wasm;
    if (rt == null) {
      return;
    }
    final ptr = rt.allocU8Array(4);
    if (ptr == 0) {
      throw GhosttyVtError(
        'ghostty_wasm_alloc_u8_array',
        GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
      );
    }
    try {
      rt.writeU32(ptr, value.value);
      rt.callInt('ghostty_key_encoder_setopt', <Object>[
        _handle,
        GhosttyKeyEncoderOption
            .GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT
            .value,
        ptr,
      ]);
    } finally {
      rt.freeU8Array(ptr, 4);
    }
  }

  Uint8List encode(VtKeyEvent event) {
    _ensureOpen();
    final rt = _wasm;
    if (rt != null && event._wasm == rt && event._handle != 0) {
      final outLenPtr = rt.allocUsize();
      if (outLenPtr == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_usize',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        final first = rt.callInt('ghostty_key_encoder_encode', <Object>[
          _handle,
          event._handle,
          0,
          0,
          outLenPtr,
        ]);
        final required = rt.readUsize(outLenPtr);
        if (first == GhosttyResult.GHOSTTY_SUCCESS.value && required == 0) {
          return Uint8List(0);
        }
        if (first != GhosttyResult.GHOSTTY_OUT_OF_MEMORY.value) {
          _checkResult(first, 'ghostty_key_encoder_encode(size_probe)');
        }
        if (required == 0) {
          return Uint8List(0);
        }

        final outBuf = rt.allocU8Array(required);
        if (outBuf == 0) {
          throw GhosttyVtError(
            'ghostty_wasm_alloc_u8_array',
            GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
          );
        }
        try {
          final second = rt.callInt('ghostty_key_encoder_encode', <Object>[
            _handle,
            event._handle,
            outBuf,
            required,
            outLenPtr,
          ]);
          _checkResult(second, 'ghostty_key_encoder_encode');
          final written = rt.readUsize(outLenPtr);
          return Uint8List.fromList(rt.u8View(outBuf, written));
        } finally {
          rt.freeU8Array(outBuf, required);
        }
      } finally {
        rt.freeUsize(outLenPtr);
      }
    }

    var bytes = _encodeLegacy(event);

    final wantsKitty = _kittyFlags != GhosttyKittyFlags.disabled;
    if (wantsKitty &&
        (event.mods != 0 ||
            event.action != GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS)) {
      final kittyCode = _kittyKeyCode(event);
      if (kittyCode != 0) {
        final mods = _kittyModifierValue(event.mods);
        final seq =
            '\x1b[$kittyCode;$mods'
            '${event.action == GhosttyKeyAction.GHOSTTY_KEY_ACTION_RELEASE ? ':3' : ''}u';
        bytes = Uint8List.fromList(utf8.encode(seq));
      }
    }

    final useAltPrefix =
        _altEscPrefix &&
        (event.mods & GhosttyModsMask.alt) != 0 &&
        bytes.isNotEmpty;
    if (useAltPrefix) {
      bytes = Uint8List.fromList(<int>[0x1B, ...bytes]);
    }

    // Preserve option to avoid "unused" lints for stored options.
    if (_keypadKeyApplication ||
        _ignoreKeypadWithNumLock ||
        _modifyOtherKeysState2 ||
        _macosOptionAsAlt != GhosttyOptionAsAlt.GHOSTTY_OPTION_AS_ALT_FALSE) {
      // No-op in web fallback.
    }

    return bytes;
  }

  String encodeToString(VtKeyEvent event) =>
      String.fromCharCodes(encode(event));

  Uint8List _encodeLegacy(VtKeyEvent event) {
    final ctrl = (event.mods & GhosttyModsMask.ctrl) != 0;

    if (ctrl) {
      final control = _controlCodeForLetter(event.key);
      if (control != null) {
        return Uint8List.fromList(<int>[control]);
      }
    }

    final special = _specialSequence(
      event.key,
      cursorApplication: _cursorKeyApplication,
    );
    if (special != null) {
      return Uint8List.fromList(special);
    }

    if (event.utf8Text.isNotEmpty) {
      return Uint8List.fromList(utf8.encode(event.utf8Text));
    }

    return Uint8List(0);
  }

  int? _controlCodeForLetter(GhosttyKey key) {
    final value = key.value;
    final a = GhosttyKey.GHOSTTY_KEY_A.value;
    final z = GhosttyKey.GHOSTTY_KEY_Z.value;
    if (value < a || value > z) {
      return null;
    }
    return (value - a) + 1;
  }

  int _kittyModifierValue(int mods) {
    var value = 1;
    if ((mods & GhosttyModsMask.shift) != 0) {
      value += 1;
    }
    if ((mods & GhosttyModsMask.alt) != 0) {
      value += 2;
    }
    if ((mods & GhosttyModsMask.ctrl) != 0) {
      value += 4;
    }
    if ((mods & GhosttyModsMask.superKey) != 0) {
      value += 8;
    }
    return value;
  }

  int _kittyKeyCode(VtKeyEvent event) {
    switch (event.key) {
      case GhosttyKey.GHOSTTY_KEY_ENTER:
        return 13;
      case GhosttyKey.GHOSTTY_KEY_TAB:
        return 9;
      case GhosttyKey.GHOSTTY_KEY_BACKSPACE:
        return 127;
      case GhosttyKey.GHOSTTY_KEY_ESCAPE:
        return 27;
      default:
        final value = event.key.value;
        final a = GhosttyKey.GHOSTTY_KEY_A.value;
        final z = GhosttyKey.GHOSTTY_KEY_Z.value;
        if (value >= a && value <= z) {
          return 'a'.codeUnitAt(0) + (value - a);
        }
        return event.unshiftedCodepoint;
    }
  }

  List<int>? _specialSequence(
    GhosttyKey key, {
    required bool cursorApplication,
  }) {
    switch (key) {
      case GhosttyKey.GHOSTTY_KEY_ENTER:
        return <int>[13];
      case GhosttyKey.GHOSTTY_KEY_TAB:
        return <int>[9];
      case GhosttyKey.GHOSTTY_KEY_BACKSPACE:
        return <int>[127];
      case GhosttyKey.GHOSTTY_KEY_ESCAPE:
        return <int>[27];
      case GhosttyKey.GHOSTTY_KEY_ARROW_UP:
        return utf8.encode(cursorApplication ? '\x1bOA' : '\x1b[A');
      case GhosttyKey.GHOSTTY_KEY_ARROW_DOWN:
        return utf8.encode(cursorApplication ? '\x1bOB' : '\x1b[B');
      case GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT:
        return utf8.encode(cursorApplication ? '\x1bOC' : '\x1b[C');
      case GhosttyKey.GHOSTTY_KEY_ARROW_LEFT:
        return utf8.encode(cursorApplication ? '\x1bOD' : '\x1b[D');
      case GhosttyKey.GHOSTTY_KEY_HOME:
        return utf8.encode(cursorApplication ? '\x1bOH' : '\x1b[H');
      case GhosttyKey.GHOSTTY_KEY_END:
        return utf8.encode(cursorApplication ? '\x1bOF' : '\x1b[F');
      case GhosttyKey.GHOSTTY_KEY_INSERT:
        return utf8.encode('\x1b[2~');
      case GhosttyKey.GHOSTTY_KEY_DELETE:
        return utf8.encode('\x1b[3~');
      case GhosttyKey.GHOSTTY_KEY_PAGE_UP:
        return utf8.encode('\x1b[5~');
      case GhosttyKey.GHOSTTY_KEY_PAGE_DOWN:
        return utf8.encode('\x1b[6~');
      case GhosttyKey.GHOSTTY_KEY_F1:
        return utf8.encode('\x1bOP');
      case GhosttyKey.GHOSTTY_KEY_F2:
        return utf8.encode('\x1bOQ');
      case GhosttyKey.GHOSTTY_KEY_F3:
        return utf8.encode('\x1bOR');
      case GhosttyKey.GHOSTTY_KEY_F4:
        return utf8.encode('\x1bOS');
      case GhosttyKey.GHOSTTY_KEY_F5:
        return utf8.encode('\x1b[15~');
      case GhosttyKey.GHOSTTY_KEY_F6:
        return utf8.encode('\x1b[17~');
      case GhosttyKey.GHOSTTY_KEY_F7:
        return utf8.encode('\x1b[18~');
      case GhosttyKey.GHOSTTY_KEY_F8:
        return utf8.encode('\x1b[19~');
      case GhosttyKey.GHOSTTY_KEY_F9:
        return utf8.encode('\x1b[20~');
      case GhosttyKey.GHOSTTY_KEY_F10:
        return utf8.encode('\x1b[21~');
      case GhosttyKey.GHOSTTY_KEY_F11:
        return utf8.encode('\x1b[23~');
      case GhosttyKey.GHOSTTY_KEY_F12:
        return utf8.encode('\x1b[24~');
      default:
        return null;
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    final rt = _wasm;
    if (rt != null && _handle != 0) {
      rt.callInt('ghostty_key_encoder_free', <Object>[_handle]);
      _handle = 0;
      _wasm = null;
    }
    _closed = true;
  }
}

final class GhosttyVt {
  const GhosttyVt._();

  static bool isPasteSafe(String text) {
    return isPasteSafeBytes(utf8.encode(text));
  }

  static bool isPasteSafeBytes(List<int> bytes) {
    final rt = _runtime();
    if (rt != null) {
      if (bytes.isEmpty) {
        return true;
      }
      final dataPtr = rt.allocU8Array(bytes.length);
      if (dataPtr == 0) {
        throw GhosttyVtError(
          'ghostty_wasm_alloc_u8_array',
          GhosttyResult.GHOSTTY_OUT_OF_MEMORY,
        );
      }
      try {
        rt.u8View(dataPtr, bytes.length).setAll(0, bytes);
        return rt.callBool('ghostty_paste_is_safe', <Object>[
          dataPtr,
          bytes.length,
        ]);
      } finally {
        rt.freeU8Array(dataPtr, bytes.length);
      }
    }

    // Fallback for web usage prior to wasm initialization.
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        return false;
      }
      if (i + 5 < bytes.length &&
          bytes[i] == 0x1B &&
          bytes[i + 1] == 0x5B &&
          bytes[i + 2] == 0x32 &&
          bytes[i + 3] == 0x30 &&
          bytes[i + 4] == 0x31 &&
          bytes[i + 5] == 0x7E) {
        return false;
      }
    }
    return true;
  }

  static VtOscParser newOscParser() => VtOscParser();
  static VtSgrParser newSgrParser() => VtSgrParser();
  static VtKeyEvent newKeyEvent() => VtKeyEvent();
  static VtKeyEncoder newKeyEncoder() => VtKeyEncoder();
}
