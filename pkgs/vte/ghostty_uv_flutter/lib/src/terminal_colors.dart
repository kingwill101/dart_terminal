library;

import 'dart:ui' show Color;

import 'package:ultraviolet/ultraviolet.dart';

/// Terminal palette and color conversion helpers for UV-backed rendering.
final class GhosttyUvTerminalPalette {
  const GhosttyUvTerminalPalette({
    required this.basic16,
    required this.defaultForeground,
    required this.defaultBackground,
    required this.cursorColor,
    required this.selectionColor,
  });

  final List<Color> basic16;
  final Color defaultForeground;
  final Color defaultBackground;
  final Color cursorColor;
  final Color selectionColor;

  static const xterm = GhosttyUvTerminalPalette(
    basic16: <Color>[
      Color(0xFF000000),
      Color(0xFFCD0000),
      Color(0xFF00CD00),
      Color(0xFFCDCD00),
      Color(0xFF0000EE),
      Color(0xFFCD00CD),
      Color(0xFF00CDCD),
      Color(0xFFE5E5E5),
      Color(0xFF7F7F7F),
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFFFFFF00),
      Color(0xFF5C5CFF),
      Color(0xFFFF00FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFFFF),
    ],
    defaultForeground: Color(0xFFE6EDF3),
    defaultBackground: Color(0xFF0A0F14),
    cursorColor: Color(0xFF9AD1C0),
    selectionColor: Color(0x665DA9FF),
  );

  Color resolve(UvColor? color, Color fallback) {
    return switch (color) {
      null => fallback,
      UvRgb c => Color.fromARGB(c.a, c.r, c.g, c.b),
      UvBasic16 c => basic16[c.index + (c.bright ? 8 : 0)],
      UvIndexed256 c => _indexed256ToColor(c.index),
    };
  }

  Color _indexed256ToColor(int index) {
    if (index < 16) {
      return basic16[index];
    }
    if (index < 232) {
      final value = index - 16;
      const cubeSteps = <int>[0, 95, 135, 175, 215, 255];
      final r = cubeSteps[value ~/ 36];
      final g = cubeSteps[(value % 36) ~/ 6];
      final b = cubeSteps[value % 6];
      return Color.fromARGB(255, r, g, b);
    }
    final gray = 8 + (index - 232) * 10;
    return Color.fromARGB(255, gray, gray, gray);
  }
}
