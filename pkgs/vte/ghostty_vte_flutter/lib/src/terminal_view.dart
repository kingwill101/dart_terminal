import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

import 'terminal_controller.dart';

/// Painter-based terminal widget that renders lines from [GhosttyTerminalController].
///
/// This intentionally avoids a heavy terminal emulation dependency and keeps
/// rendering deterministic for lightweight terminal UIs.
class GhosttyTerminalView extends StatefulWidget {
  const GhosttyTerminalView({
    required this.controller,
    super.key,
    this.autofocus = false,
    this.focusNode,
    this.backgroundColor = const Color(0xFF0A0F14),
    this.foregroundColor = const Color(0xFFE6EDF3),
    this.chromeColor = const Color(0xFF121A24),
    this.fontSize = 14,
    this.lineHeight = 1.35,
    this.padding = const EdgeInsets.all(12),
  });

  final GhosttyTerminalController controller;
  final bool autofocus;
  final FocusNode? focusNode;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color chromeColor;
  final double fontSize;
  final double lineHeight;
  final EdgeInsets padding;

  @override
  State<GhosttyTerminalView> createState() => _GhosttyTerminalViewState();
}

class _GhosttyTerminalViewState extends State<GhosttyTerminalView> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GhosttyTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = _mapLogicalKey(event.logicalKey);
    final mods = _currentMods();
    final character = event.character ?? '';
    final codepoint = character.isNotEmpty ? character.runes.first : 0;

    if (key != null) {
      final sent = widget.controller.sendKey(
        key: key,
        action: event is KeyRepeatEvent
            ? GhosttyKeyAction.GHOSTTY_KEY_ACTION_REPEAT
            : GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
        mods: mods,
        utf8Text: character,
        unshiftedCodepoint: codepoint,
      );
      return sent ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (character.isNotEmpty) {
      final sent = widget.controller.write(character);
      return sent ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  int _currentMods() {
    final keyboard = HardwareKeyboard.instance;
    var mods = 0;
    if (keyboard.isShiftPressed) {
      mods |= GhosttyModsMask.shift;
    }
    if (keyboard.isControlPressed) {
      mods |= GhosttyModsMask.ctrl;
    }
    if (keyboard.isAltPressed) {
      mods |= GhosttyModsMask.alt;
    }
    if (keyboard.isMetaPressed) {
      mods |= GhosttyModsMask.superKey;
    }
    return mods;
  }

  GhosttyKey? _mapLogicalKey(LogicalKeyboardKey key) {
    return _logicalKeyMap[key];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _GhosttyTerminalPainter(
              revision: widget.controller.revision,
              title: widget.controller.title,
              lines: widget.controller.lines,
              running: widget.controller.isRunning,
              focused: _focusNode.hasFocus,
              backgroundColor: widget.backgroundColor,
              foregroundColor: widget.foregroundColor,
              chromeColor: widget.chromeColor,
              fontSize: widget.fontSize,
              lineHeight: widget.lineHeight,
              padding: widget.padding,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _GhosttyTerminalPainter extends CustomPainter {
  const _GhosttyTerminalPainter({
    required this.revision,
    required this.title,
    required this.lines,
    required this.running,
    required this.focused,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.chromeColor,
    required this.fontSize,
    required this.lineHeight,
    required this.padding,
  });

  final int revision;
  final String title;
  final List<String> lines;
  final bool running;
  final bool focused;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color chromeColor;
  final double fontSize;
  final double lineHeight;
  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    canvas.drawRect(fullRect, Paint()..color = backgroundColor);

    const headerHeight = 28.0;
    final headerRect = Rect.fromLTWH(0, 0, size.width, headerHeight);
    canvas.drawRect(headerRect, Paint()..color = chromeColor);

    final dotColor = running
        ? const Color(0xFF2BD576)
        : const Color(0xFFD65C5C);
    canvas.drawCircle(const Offset(12, 14), 4, Paint()..color = dotColor);

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: foregroundColor.withValues(alpha: 0.95),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.width - 24);
    titlePainter.paint(canvas, const Offset(22, 7));

    final contentTop = headerHeight + padding.top;
    final contentHeight = size.height - contentTop - padding.bottom;
    if (contentHeight <= 0) {
      return;
    }

    final linePx = fontSize * lineHeight;
    final maxVisible = (contentHeight / linePx).floor().clamp(0, 1000000);
    final start = lines.length > maxVisible ? lines.length - maxVisible : 0;
    final visible = lines.sublist(start);

    final textStyle = TextStyle(
      color: foregroundColor,
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: lineHeight,
    );
    var y = contentTop;
    for (final line in visible) {
      if (y > size.height) {
        break;
      }
      final painter = TextPainter(
        text: TextSpan(text: line, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: size.width - padding.horizontal);
      painter.paint(canvas, Offset(padding.left, y));
      y += linePx;
    }

    if (focused) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF5DA9FF);
      canvas.drawRect(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GhosttyTerminalPainter oldDelegate) {
    return revision != oldDelegate.revision ||
        title != oldDelegate.title ||
        running != oldDelegate.running ||
        focused != oldDelegate.focused ||
        backgroundColor != oldDelegate.backgroundColor ||
        foregroundColor != oldDelegate.foregroundColor ||
        chromeColor != oldDelegate.chromeColor ||
        fontSize != oldDelegate.fontSize ||
        lineHeight != oldDelegate.lineHeight ||
        padding != oldDelegate.padding;
  }
}

final Map<LogicalKeyboardKey, GhosttyKey> _logicalKeyMap =
    <LogicalKeyboardKey, GhosttyKey>{
      LogicalKeyboardKey.enter: GhosttyKey.GHOSTTY_KEY_ENTER,
      LogicalKeyboardKey.tab: GhosttyKey.GHOSTTY_KEY_TAB,
      LogicalKeyboardKey.backspace: GhosttyKey.GHOSTTY_KEY_BACKSPACE,
      LogicalKeyboardKey.escape: GhosttyKey.GHOSTTY_KEY_ESCAPE,
      LogicalKeyboardKey.space: GhosttyKey.GHOSTTY_KEY_SPACE,
      LogicalKeyboardKey.arrowUp: GhosttyKey.GHOSTTY_KEY_ARROW_UP,
      LogicalKeyboardKey.arrowDown: GhosttyKey.GHOSTTY_KEY_ARROW_DOWN,
      LogicalKeyboardKey.arrowLeft: GhosttyKey.GHOSTTY_KEY_ARROW_LEFT,
      LogicalKeyboardKey.arrowRight: GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT,
      LogicalKeyboardKey.delete: GhosttyKey.GHOSTTY_KEY_DELETE,
      LogicalKeyboardKey.insert: GhosttyKey.GHOSTTY_KEY_INSERT,
      LogicalKeyboardKey.home: GhosttyKey.GHOSTTY_KEY_HOME,
      LogicalKeyboardKey.end: GhosttyKey.GHOSTTY_KEY_END,
      LogicalKeyboardKey.pageUp: GhosttyKey.GHOSTTY_KEY_PAGE_UP,
      LogicalKeyboardKey.pageDown: GhosttyKey.GHOSTTY_KEY_PAGE_DOWN,
      LogicalKeyboardKey.keyA: GhosttyKey.GHOSTTY_KEY_A,
      LogicalKeyboardKey.keyB: GhosttyKey.GHOSTTY_KEY_B,
      LogicalKeyboardKey.keyC: GhosttyKey.GHOSTTY_KEY_C,
      LogicalKeyboardKey.keyD: GhosttyKey.GHOSTTY_KEY_D,
      LogicalKeyboardKey.keyE: GhosttyKey.GHOSTTY_KEY_E,
      LogicalKeyboardKey.keyF: GhosttyKey.GHOSTTY_KEY_F,
      LogicalKeyboardKey.keyG: GhosttyKey.GHOSTTY_KEY_G,
      LogicalKeyboardKey.keyH: GhosttyKey.GHOSTTY_KEY_H,
      LogicalKeyboardKey.keyI: GhosttyKey.GHOSTTY_KEY_I,
      LogicalKeyboardKey.keyJ: GhosttyKey.GHOSTTY_KEY_J,
      LogicalKeyboardKey.keyK: GhosttyKey.GHOSTTY_KEY_K,
      LogicalKeyboardKey.keyL: GhosttyKey.GHOSTTY_KEY_L,
      LogicalKeyboardKey.keyM: GhosttyKey.GHOSTTY_KEY_M,
      LogicalKeyboardKey.keyN: GhosttyKey.GHOSTTY_KEY_N,
      LogicalKeyboardKey.keyO: GhosttyKey.GHOSTTY_KEY_O,
      LogicalKeyboardKey.keyP: GhosttyKey.GHOSTTY_KEY_P,
      LogicalKeyboardKey.keyQ: GhosttyKey.GHOSTTY_KEY_Q,
      LogicalKeyboardKey.keyR: GhosttyKey.GHOSTTY_KEY_R,
      LogicalKeyboardKey.keyS: GhosttyKey.GHOSTTY_KEY_S,
      LogicalKeyboardKey.keyT: GhosttyKey.GHOSTTY_KEY_T,
      LogicalKeyboardKey.keyU: GhosttyKey.GHOSTTY_KEY_U,
      LogicalKeyboardKey.keyV: GhosttyKey.GHOSTTY_KEY_V,
      LogicalKeyboardKey.keyW: GhosttyKey.GHOSTTY_KEY_W,
      LogicalKeyboardKey.keyX: GhosttyKey.GHOSTTY_KEY_X,
      LogicalKeyboardKey.keyY: GhosttyKey.GHOSTTY_KEY_Y,
      LogicalKeyboardKey.keyZ: GhosttyKey.GHOSTTY_KEY_Z,
      LogicalKeyboardKey.digit0: GhosttyKey.GHOSTTY_KEY_DIGIT_0,
      LogicalKeyboardKey.digit1: GhosttyKey.GHOSTTY_KEY_DIGIT_1,
      LogicalKeyboardKey.digit2: GhosttyKey.GHOSTTY_KEY_DIGIT_2,
      LogicalKeyboardKey.digit3: GhosttyKey.GHOSTTY_KEY_DIGIT_3,
      LogicalKeyboardKey.digit4: GhosttyKey.GHOSTTY_KEY_DIGIT_4,
      LogicalKeyboardKey.digit5: GhosttyKey.GHOSTTY_KEY_DIGIT_5,
      LogicalKeyboardKey.digit6: GhosttyKey.GHOSTTY_KEY_DIGIT_6,
      LogicalKeyboardKey.digit7: GhosttyKey.GHOSTTY_KEY_DIGIT_7,
      LogicalKeyboardKey.digit8: GhosttyKey.GHOSTTY_KEY_DIGIT_8,
      LogicalKeyboardKey.digit9: GhosttyKey.GHOSTTY_KEY_DIGIT_9,
      LogicalKeyboardKey.minus: GhosttyKey.GHOSTTY_KEY_MINUS,
      LogicalKeyboardKey.equal: GhosttyKey.GHOSTTY_KEY_EQUAL,
      LogicalKeyboardKey.bracketLeft: GhosttyKey.GHOSTTY_KEY_BRACKET_LEFT,
      LogicalKeyboardKey.bracketRight: GhosttyKey.GHOSTTY_KEY_BRACKET_RIGHT,
      LogicalKeyboardKey.backslash: GhosttyKey.GHOSTTY_KEY_BACKSLASH,
      LogicalKeyboardKey.semicolon: GhosttyKey.GHOSTTY_KEY_SEMICOLON,
      LogicalKeyboardKey.quote: GhosttyKey.GHOSTTY_KEY_QUOTE,
      LogicalKeyboardKey.comma: GhosttyKey.GHOSTTY_KEY_COMMA,
      LogicalKeyboardKey.period: GhosttyKey.GHOSTTY_KEY_PERIOD,
      LogicalKeyboardKey.slash: GhosttyKey.GHOSTTY_KEY_SLASH,
      LogicalKeyboardKey.backquote: GhosttyKey.GHOSTTY_KEY_BACKQUOTE,
      LogicalKeyboardKey.f1: GhosttyKey.GHOSTTY_KEY_F1,
      LogicalKeyboardKey.f2: GhosttyKey.GHOSTTY_KEY_F2,
      LogicalKeyboardKey.f3: GhosttyKey.GHOSTTY_KEY_F3,
      LogicalKeyboardKey.f4: GhosttyKey.GHOSTTY_KEY_F4,
      LogicalKeyboardKey.f5: GhosttyKey.GHOSTTY_KEY_F5,
      LogicalKeyboardKey.f6: GhosttyKey.GHOSTTY_KEY_F6,
      LogicalKeyboardKey.f7: GhosttyKey.GHOSTTY_KEY_F7,
      LogicalKeyboardKey.f8: GhosttyKey.GHOSTTY_KEY_F8,
      LogicalKeyboardKey.f9: GhosttyKey.GHOSTTY_KEY_F9,
      LogicalKeyboardKey.f10: GhosttyKey.GHOSTTY_KEY_F10,
      LogicalKeyboardKey.f11: GhosttyKey.GHOSTTY_KEY_F11,
      LogicalKeyboardKey.f12: GhosttyKey.GHOSTTY_KEY_F12,
    };

Uint8List decodeHexBytes(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return Uint8List(0);
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  final out = Uint8List(parts.length);
  for (var i = 0; i < parts.length; i++) {
    out[i] = int.parse(parts[i], radix: 16);
  }
  return out;
}
