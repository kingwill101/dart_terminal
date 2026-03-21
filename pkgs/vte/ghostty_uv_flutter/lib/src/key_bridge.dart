library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ghostty_vte/ghostty_vte.dart';
import 'package:ultraviolet/ultraviolet.dart';

import 'terminal_screen.dart';

const _uvToGhosttyKey = <int, GhosttyKey>{
  0x61: GhosttyKey.GHOSTTY_KEY_A,
  0x62: GhosttyKey.GHOSTTY_KEY_B,
  0x63: GhosttyKey.GHOSTTY_KEY_C,
  0x64: GhosttyKey.GHOSTTY_KEY_D,
  0x65: GhosttyKey.GHOSTTY_KEY_E,
  0x66: GhosttyKey.GHOSTTY_KEY_F,
  0x67: GhosttyKey.GHOSTTY_KEY_G,
  0x68: GhosttyKey.GHOSTTY_KEY_H,
  0x69: GhosttyKey.GHOSTTY_KEY_I,
  0x6a: GhosttyKey.GHOSTTY_KEY_J,
  0x6b: GhosttyKey.GHOSTTY_KEY_K,
  0x6c: GhosttyKey.GHOSTTY_KEY_L,
  0x6d: GhosttyKey.GHOSTTY_KEY_M,
  0x6e: GhosttyKey.GHOSTTY_KEY_N,
  0x6f: GhosttyKey.GHOSTTY_KEY_O,
  0x70: GhosttyKey.GHOSTTY_KEY_P,
  0x71: GhosttyKey.GHOSTTY_KEY_Q,
  0x72: GhosttyKey.GHOSTTY_KEY_R,
  0x73: GhosttyKey.GHOSTTY_KEY_S,
  0x74: GhosttyKey.GHOSTTY_KEY_T,
  0x75: GhosttyKey.GHOSTTY_KEY_U,
  0x76: GhosttyKey.GHOSTTY_KEY_V,
  0x77: GhosttyKey.GHOSTTY_KEY_W,
  0x78: GhosttyKey.GHOSTTY_KEY_X,
  0x79: GhosttyKey.GHOSTTY_KEY_Y,
  0x7a: GhosttyKey.GHOSTTY_KEY_Z,
  0x30: GhosttyKey.GHOSTTY_KEY_DIGIT_0,
  0x31: GhosttyKey.GHOSTTY_KEY_DIGIT_1,
  0x32: GhosttyKey.GHOSTTY_KEY_DIGIT_2,
  0x33: GhosttyKey.GHOSTTY_KEY_DIGIT_3,
  0x34: GhosttyKey.GHOSTTY_KEY_DIGIT_4,
  0x35: GhosttyKey.GHOSTTY_KEY_DIGIT_5,
  0x36: GhosttyKey.GHOSTTY_KEY_DIGIT_6,
  0x37: GhosttyKey.GHOSTTY_KEY_DIGIT_7,
  0x38: GhosttyKey.GHOSTTY_KEY_DIGIT_8,
  0x39: GhosttyKey.GHOSTTY_KEY_DIGIT_9,
  0x2d: GhosttyKey.GHOSTTY_KEY_MINUS,
  0x3d: GhosttyKey.GHOSTTY_KEY_EQUAL,
  0x5b: GhosttyKey.GHOSTTY_KEY_BRACKET_LEFT,
  0x5d: GhosttyKey.GHOSTTY_KEY_BRACKET_RIGHT,
  0x5c: GhosttyKey.GHOSTTY_KEY_BACKSLASH,
  0x3b: GhosttyKey.GHOSTTY_KEY_SEMICOLON,
  0x27: GhosttyKey.GHOSTTY_KEY_QUOTE,
  0x60: GhosttyKey.GHOSTTY_KEY_BACKQUOTE,
  0x2c: GhosttyKey.GHOSTTY_KEY_COMMA,
  0x2e: GhosttyKey.GHOSTTY_KEY_PERIOD,
  0x2f: GhosttyKey.GHOSTTY_KEY_SLASH,
  keySpace: GhosttyKey.GHOSTTY_KEY_SPACE,
  keyEnter: GhosttyKey.GHOSTTY_KEY_ENTER,
  keyTab: GhosttyKey.GHOSTTY_KEY_TAB,
  keyBackspace: GhosttyKey.GHOSTTY_KEY_BACKSPACE,
  keyEscape: GhosttyKey.GHOSTTY_KEY_ESCAPE,
  keyUp: GhosttyKey.GHOSTTY_KEY_ARROW_UP,
  keyDown: GhosttyKey.GHOSTTY_KEY_ARROW_DOWN,
  keyLeft: GhosttyKey.GHOSTTY_KEY_ARROW_LEFT,
  keyRight: GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT,
  keyHome: GhosttyKey.GHOSTTY_KEY_HOME,
  keyEnd: GhosttyKey.GHOSTTY_KEY_END,
  keyPgUp: GhosttyKey.GHOSTTY_KEY_PAGE_UP,
  keyPgDown: GhosttyKey.GHOSTTY_KEY_PAGE_DOWN,
  keyInsert: GhosttyKey.GHOSTTY_KEY_INSERT,
  keyDelete: GhosttyKey.GHOSTTY_KEY_DELETE,
  keyF1: GhosttyKey.GHOSTTY_KEY_F1,
  keyF2: GhosttyKey.GHOSTTY_KEY_F2,
  keyF3: GhosttyKey.GHOSTTY_KEY_F3,
  keyF4: GhosttyKey.GHOSTTY_KEY_F4,
  keyF5: GhosttyKey.GHOSTTY_KEY_F5,
  keyF6: GhosttyKey.GHOSTTY_KEY_F6,
  keyF7: GhosttyKey.GHOSTTY_KEY_F7,
  keyF8: GhosttyKey.GHOSTTY_KEY_F8,
  keyF9: GhosttyKey.GHOSTTY_KEY_F9,
  keyF10: GhosttyKey.GHOSTTY_KEY_F10,
  keyF11: GhosttyKey.GHOSTTY_KEY_F11,
  keyF12: GhosttyKey.GHOSTTY_KEY_F12,
  keyKpEnter: GhosttyKey.GHOSTTY_KEY_NUMPAD_ENTER,
  keyKp0: GhosttyKey.GHOSTTY_KEY_NUMPAD_0,
  keyKp1: GhosttyKey.GHOSTTY_KEY_NUMPAD_1,
  keyKp2: GhosttyKey.GHOSTTY_KEY_NUMPAD_2,
  keyKp3: GhosttyKey.GHOSTTY_KEY_NUMPAD_3,
  keyKp4: GhosttyKey.GHOSTTY_KEY_NUMPAD_4,
  keyKp5: GhosttyKey.GHOSTTY_KEY_NUMPAD_5,
  keyKp6: GhosttyKey.GHOSTTY_KEY_NUMPAD_6,
  keyKp7: GhosttyKey.GHOSTTY_KEY_NUMPAD_7,
  keyKp8: GhosttyKey.GHOSTTY_KEY_NUMPAD_8,
  keyKp9: GhosttyKey.GHOSTTY_KEY_NUMPAD_9,
  keyKpPlus: GhosttyKey.GHOSTTY_KEY_NUMPAD_ADD,
  keyKpMinus: GhosttyKey.GHOSTTY_KEY_NUMPAD_SUBTRACT,
  keyKpMultiply: GhosttyKey.GHOSTTY_KEY_NUMPAD_MULTIPLY,
  keyKpDivide: GhosttyKey.GHOSTTY_KEY_NUMPAD_DIVIDE,
  keyKpDecimal: GhosttyKey.GHOSTTY_KEY_NUMPAD_DECIMAL,
  keyKpEqual: GhosttyKey.GHOSTTY_KEY_NUMPAD_EQUAL,
};

const _numpadText = <int, String>{
  keyKp0: '0',
  keyKp1: '1',
  keyKp2: '2',
  keyKp3: '3',
  keyKp4: '4',
  keyKp5: '5',
  keyKp6: '6',
  keyKp7: '7',
  keyKp8: '8',
  keyKp9: '9',
  keyKpPlus: '+',
  keyKpMinus: '-',
  keyKpMultiply: '*',
  keyKpDivide: '/',
  keyKpDecimal: '.',
  keyKpEqual: '=',
};

const _shiftedAsciiAliases = <int, int>{
  0x21: 0x31,
  0x40: 0x32,
  0x23: 0x33,
  0x24: 0x34,
  0x25: 0x35,
  0x5E: 0x36,
  0x26: 0x37,
  0x2A: 0x38,
  0x28: 0x39,
  0x29: 0x30,
  0x5F: 0x2D,
  0x2B: 0x3D,
  0x7B: 0x5B,
  0x7D: 0x5D,
  0x7C: 0x5C,
  0x3A: 0x3B,
  0x22: 0x27,
  0x7E: 0x60,
  0x3C: 0x2C,
  0x3E: 0x2E,
  0x3F: 0x2F,
};

/// Bridges UV key events to the Ghostty VT key encoder.
final class GhosttyUvKeyBridge {
  GhosttyUvKeyBridge() : _encoder = GhosttyVt.newKeyEncoder();

  final VtKeyEncoder _encoder;
  bool _closed = false;

  void syncFromScreen(GhosttyUvTerminalScreen screen) {
    _checkOpen();
    _encoder.cursorKeyApplication = screen.cursorKeyApplication;
    _encoder.keypadKeyApplication = screen.keypadKeyApplication;
    _encoder.modifyOtherKeysState2 = screen.modifyOtherKeysState2;
    _encoder.kittyFlags = screen.kittyKeyboardFlags;
  }

  Uint8List encode(Key key) {
    _checkOpen();

    final mapped = _mapKey(key.code);
    if (mapped == null) {
      if (key.text.isNotEmpty && _canEmitTextDirectly(key.mod)) {
        return Uint8List.fromList(utf8.encode(key.text));
      }
      return Uint8List(0);
    }

    final event = GhosttyVt.newKeyEvent();
    try {
      event
        ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
        ..key = mapped
        ..mods = _mapModifiers(key.mod);

      if (key.text.isNotEmpty) {
        event.utf8Text = key.text;
      } else if (_numpadText.containsKey(key.code)) {
        event.utf8Text = _numpadText[key.code]!;
      } else if (key.code >= 0x20 && key.code <= 0x10FFFF) {
        event.utf8Text = String.fromCharCode(key.code);
      }

      return _encoder.encode(event);
    } finally {
      event.close();
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _encoder.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('GhosttyUvKeyBridge is closed.');
    }
  }

  GhosttyKey? _mapKey(int code) {
    final mapped = _uvToGhosttyKey[code];
    if (mapped != null) {
      return mapped;
    }
    final shiftedAlias = _shiftedAsciiAliases[code];
    if (shiftedAlias != null) {
      return _uvToGhosttyKey[shiftedAlias];
    }
    if (code >= 0x41 && code <= 0x5A) {
      return _uvToGhosttyKey[code + 0x20];
    }
    return null;
  }

  bool _canEmitTextDirectly(int mod) {
    return !KeyMod.contains(mod, KeyMod.ctrl) &&
        !KeyMod.contains(mod, KeyMod.alt) &&
        !KeyMod.contains(mod, KeyMod.meta);
  }

  int _mapModifiers(int mod) {
    var result = 0;
    if (KeyMod.contains(mod, KeyMod.shift)) {
      result |= GhosttyModsMask.shift;
    }
    if (KeyMod.contains(mod, KeyMod.alt)) {
      result |= GhosttyModsMask.alt;
    }
    if (KeyMod.contains(mod, KeyMod.ctrl)) {
      result |= GhosttyModsMask.ctrl;
    }
    if (KeyMod.contains(mod, KeyMod.meta)) {
      result |= GhosttyModsMask.superKey;
    }
    if (KeyMod.contains(mod, KeyMod.capsLock)) {
      result |= GhosttyModsMask.capsLock;
    }
    if (KeyMod.contains(mod, KeyMod.numLock)) {
      result |= GhosttyModsMask.numLock;
    }
    return result;
  }
}
