import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  const defaultForeground = Color(0xFF9AD1C0);
  const defaultBackground = Color(0xFF0A0F14);
  final palette = GhosttyTerminalPalette.xterm.ansi;

  group('GhosttyTerminalResolvedStyle', () {
    test(
      'resolves explicit foreground and background from palette indices',
      () {
        final resolved = GhosttyTerminalResolvedStyle.fromNativeStyle(
          style: const VtStyle(
            foreground: VtStyleColor.palette(9),
            background: VtStyleColor.palette(11),
            underlineColor: VtStyleColor.palette(12),
            bold: true,
            italic: true,
            faint: false,
            blink: false,
            inverse: false,
            invisible: false,
            strikethrough: true,
            overline: true,
            underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_CURLY,
          ),
          palette: palette,
          defaultForeground: defaultForeground,
          defaultBackground: defaultBackground,
        );

        expect(resolved.foreground, equals(palette[9]));
        expect(resolved.background, equals(palette[11]));
        expect(resolved.underlineColor, equals(palette[12]));
        expect(resolved.hasExplicitForeground, isTrue);
        expect(resolved.hasExplicitBackground, isTrue);
        expect(resolved.hasExplicitUnderlineColor, isTrue);
        expect(resolved.bold, isTrue);
        expect(resolved.italic, isTrue);
        expect(resolved.overline, isTrue);
        expect(resolved.strikethrough, isTrue);
        expect(
          resolved.underline,
          GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_CURLY,
        );
        expect(resolved.invisible, isFalse);
      },
    );

    test('applies inverse swapping with explicit vs implicit style colors', () {
      final explicit = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.palette(1),
          background: VtStyleColor.palette(2),
          underlineColor: VtStyleColor.none(),
          bold: false,
          italic: false,
          faint: false,
          blink: false,
          inverse: true,
          invisible: false,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      final implicit = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.none(),
          background: VtStyleColor.none(),
          underlineColor: VtStyleColor.none(),
          bold: false,
          italic: false,
          faint: false,
          blink: false,
          inverse: true,
          invisible: false,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      expect(explicit.foreground, equals(palette[2]));
      expect(explicit.background, equals(palette[1]));
      expect(implicit.foreground, equals(defaultBackground));
      expect(implicit.background, equals(defaultForeground));
    });

    test('supports invisible and faint transforms consistently', () {
      final faint = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.rgb(VtRgbColor(255, 120, 40)),
          background: VtStyleColor.none(),
          underlineColor: VtStyleColor.none(),
          bold: false,
          italic: false,
          faint: true,
          blink: false,
          inverse: false,
          invisible: false,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );
      expect(
        faint.foreground,
        equals(const Color.fromRGBO(255, 120, 40, 0.72)),
      );

      final invisible = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.palette(1),
          background: VtStyleColor.none(),
          underlineColor: VtStyleColor.none(),
          bold: false,
          italic: false,
          faint: false,
          blink: false,
          inverse: false,
          invisible: true,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );
      expect(invisible.foreground, equals(defaultBackground));
      expect(invisible.background, equals(Colors.transparent));
    });

    test('formatter and native style resolution stay aligned', () {
      const formattedStyle = GhosttyTerminalStyle(
        foreground: GhosttyTerminalColor.palette(1),
        background: GhosttyTerminalColor.palette(2),
        underlineColor: GhosttyTerminalColor.palette(3),
        bold: true,
        italic: true,
        faint: true,
        blink: false,
        inverse: true,
        invisible: true,
        strikethrough: true,
        overline: true,
        underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DASHED,
        hyperlink: 'https://example.com',
      );
      const nativeStyle = VtStyle(
        foreground: VtStyleColor.palette(1),
        background: VtStyleColor.palette(2),
        underlineColor: VtStyleColor.palette(3),
        bold: true,
        italic: true,
        faint: true,
        blink: false,
        inverse: true,
        invisible: true,
        strikethrough: true,
        overline: true,
        underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DASHED,
      );

      final resolvedFormatted = GhosttyTerminalResolvedStyle.fromFormattedStyle(
        style: formattedStyle,
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );
      final resolvedNative = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: nativeStyle,
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      expect(resolvedFormatted.foreground, equals(resolvedNative.foreground));
      expect(resolvedFormatted.background, equals(resolvedNative.background));
      expect(
        resolvedFormatted.underlineColor,
        equals(resolvedNative.underlineColor),
      );
      expect(resolvedFormatted.bold, isTrue);
      expect(resolvedNative.bold, isTrue);
      expect(resolvedFormatted.italic, isTrue);
      expect(resolvedNative.italic, isTrue);
      expect(resolvedFormatted.overline, isTrue);
      expect(resolvedNative.overline, isTrue);
      expect(resolvedFormatted.strikethrough, isTrue);
      expect(resolvedNative.strikethrough, isTrue);
    });

    test(
      'resolves metadata background color as implicit background when style is not explicit',
      () {
        final style = GhosttyTerminalResolvedStyle.fromNativeStyle(
          style: const VtStyle(
            foreground: VtStyleColor.none(),
            background: VtStyleColor.none(),
            underlineColor: VtStyleColor.none(),
            bold: false,
            italic: false,
            faint: false,
            blink: false,
            inverse: false,
            invisible: false,
            strikethrough: false,
            overline: false,
            underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
          ),
          palette: palette,
          defaultForeground: defaultForeground,
          defaultBackground: defaultBackground,
        );

        final resolved = GhosttyTerminalResolvedStyle.resolveNativeStyleColors(
          style: style,
          defaultForeground: defaultForeground,
          defaultBackground: defaultBackground,
          metadataColor: const Color(0xFF445566),
        );

        expect(resolved.foreground, equals(defaultForeground));
        expect(resolved.background, equals(const Color(0xFF445566)));
      },
    );

    test('keeps explicit background when metadata color is provided', () {
      final style = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.palette(1),
          background: VtStyleColor.palette(2),
          underlineColor: VtStyleColor.none(),
          bold: false,
          italic: false,
          faint: false,
          blink: false,
          inverse: false,
          invisible: false,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      final resolved = GhosttyTerminalResolvedStyle.resolveNativeStyleColors(
        style: style,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
        metadataColor: const Color(0xFF445566),
      );

      expect(resolved.background, equals(palette[2]));
    });

    test('falls back when palette index is out of palette range', () {
      final resolved = GhosttyTerminalResolvedStyle.fromNativeStyle(
        style: const VtStyle(
          foreground: VtStyleColor.palette(255),
          background: VtStyleColor.palette(300),
          underlineColor: VtStyleColor.palette(300),
          bold: false,
          italic: false,
          faint: false,
          blink: false,
          inverse: false,
          invisible: false,
          strikethrough: false,
          overline: false,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      expect(resolved.foreground, equals(const Color(0xFFEEEEEE)));
      expect(resolved.background, equals(defaultBackground));
      expect(resolved.underlineColor, equals(defaultForeground));
    });

    test('resolves formatted styles with matching SGR logic', () {
      final resolved = GhosttyTerminalResolvedStyle.fromFormattedStyle(
        style: const GhosttyTerminalStyle(
          foreground: GhosttyTerminalColor.palette(2),
          background: GhosttyTerminalColor.palette(3),
          underlineColor: GhosttyTerminalColor.palette(4),
          bold: true,
          italic: true,
          faint: false,
          blink: false,
          inverse: false,
          invisible: false,
          strikethrough: true,
          overline: true,
          underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DASHED,
        ),
        palette: palette,
        defaultForeground: defaultForeground,
        defaultBackground: defaultBackground,
      );

      expect(resolved.foreground, equals(palette[2]));
      expect(resolved.background, equals(palette[3]));
      expect(resolved.underlineColor, equals(palette[4]));
      expect(resolved.hasExplicitForeground, isTrue);
      expect(resolved.hasExplicitBackground, isTrue);
      expect(resolved.hasExplicitUnderlineColor, isTrue);
      expect(
        resolved.underline,
        equals(GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DASHED),
      );
      expect(resolved.bold, isTrue);
      expect(resolved.italic, isTrue);
      expect(resolved.overline, isTrue);
      expect(resolved.strikethrough, isTrue);
    });

    test(
      'formatted style inverse and invisible resolve to explicit foreground/background flags',
      () {
        final resolved = GhosttyTerminalResolvedStyle.fromFormattedStyle(
          style: const GhosttyTerminalStyle(
            foreground: GhosttyTerminalColor.palette(1),
            background: GhosttyTerminalColor.palette(2),
            underline: GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
            inverse: true,
            invisible: true,
          ),
          palette: palette,
          defaultForeground: defaultForeground,
          defaultBackground: defaultBackground,
        );

        expect(resolved.background, equals(palette[1]));
        expect(resolved.foreground, equals(palette[1]));
      },
    );
  });
}
