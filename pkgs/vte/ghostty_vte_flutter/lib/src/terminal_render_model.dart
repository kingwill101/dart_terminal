import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ghostty_vte/ghostty_vte.dart';
import 'terminal_snapshot.dart';

/// Resolved cell style derived from Ghostty render-state data.
@immutable
final class GhosttyTerminalResolvedStyle {
  const GhosttyTerminalResolvedStyle({
    required this.foreground,
    required this.background,
    required this.underlineColor,
    required this.bold,
    required this.italic,
    required this.blink,
    required this.overline,
    required this.strikethrough,
    required this.underline,
    required this.inverse,
    required this.invisible,
    required this.faint,
    this.hasExplicitUnderlineColor = false,
    this.hasExplicitForeground = false,
    this.hasExplicitBackground = false,
  });

  final Color foreground;
  final Color background;
  final Color underlineColor;
  final bool bold;
  final bool italic;
  final bool blink;
  final bool overline;
  final bool strikethrough;
  final GhosttySgrUnderline underline;
  final bool inverse;
  final bool invisible;
  final bool faint;
  final bool hasExplicitUnderlineColor;
  final bool hasExplicitForeground;
  final bool hasExplicitBackground;

  factory GhosttyTerminalResolvedStyle.fromFormattedStyle({
    required GhosttyTerminalStyle style,
    required List<Color> palette,
    required Color defaultForeground,
    required Color defaultBackground,
  }) {
    Color resolveStyleColor({
      required GhosttyTerminalColor? color,
      required Color fallback,
      required List<Color> palette,
    }) {
      if (color == null) {
        return fallback;
      }
      final rgb = color.rgb;
      if (rgb != null) {
        return Color.fromARGB(
          0xFF,
          (rgb >> 16) & 0xFF,
          (rgb >> 8) & 0xFF,
          rgb & 0xFF,
        );
      }
      final index = color.paletteIndex;
      if (index == null) {
        return fallback;
      }
      if (index >= 0 && index < palette.length) {
        return palette[index];
      }
      return GhosttyTerminalPalette.xterm.resolve(
        GhosttyTerminalColor.palette(index),
        fallback: fallback,
      );
    }

    final hasExplicitForeground = style.foreground != null;
    final hasExplicitBackground = style.background != null;
    final hasExplicitUnderlineColor = style.underlineColor != null;
    const transparent = Color(0x00000000);

    var foreground = hasExplicitForeground
        ? resolveStyleColor(
            color: style.foreground,
            fallback: defaultForeground,
            palette: palette,
          )
        : transparent;
    var background = hasExplicitBackground
        ? resolveStyleColor(
            color: style.background,
            fallback: defaultBackground,
            palette: palette,
          )
        : transparent;
    if (style.inverse) {
      final swappedForeground = background;
      background = hasExplicitForeground
          ? foreground
          : (foreground == transparent ? defaultForeground : foreground);
      foreground = hasExplicitBackground
          ? swappedForeground
          : (swappedForeground == transparent
                ? defaultBackground
                : swappedForeground);
    }
    if (style.invisible) {
      foreground = background == transparent ? defaultBackground : background;
    }
    if (style.faint) {
      foreground = foreground.withValues(alpha: 0.72);
    }
    if (foreground == transparent) {
      foreground = defaultForeground;
    }

    return GhosttyTerminalResolvedStyle(
      foreground: foreground,
      background: background,
      underlineColor: resolveStyleColor(
        color: style.underlineColor,
        fallback: hasExplicitUnderlineColor ? defaultForeground : transparent,
        palette: palette,
      ),
      bold: style.bold,
      italic: style.italic,
      blink: style.blink,
      overline: style.overline,
      strikethrough: style.strikethrough,
      underline:
          style.underline ?? GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE,
      inverse: style.inverse,
      invisible: style.invisible,
      faint: style.faint,
      hasExplicitUnderlineColor: hasExplicitUnderlineColor,
      hasExplicitForeground: hasExplicitForeground,
      hasExplicitBackground: hasExplicitBackground,
    );
  }

  factory GhosttyTerminalResolvedStyle.fromNativeStyle({
    required VtStyle style,
    required List<Color> palette,
    required Color defaultForeground,
    required Color defaultBackground,
  }) {
    Color resolveStyleColor(
      VtStyleColor color, {
      required Color fallback,
      required List<Color> palette,
    }) {
      if (!color.isSet) {
        return fallback;
      }
      final rgb = color.rgb;
      if (rgb != null) {
        return Color.fromARGB(0xFF, rgb.r, rgb.g, rgb.b);
      }
      final index = color.paletteIndex;
      if (index == null) {
        return fallback;
      }
      if (index >= 0 && index < palette.length) {
        return palette[index];
      }
      return GhosttyTerminalPalette.xterm.resolve(
        GhosttyTerminalColor.palette(index),
        fallback: fallback,
      );
    }

    final hasExplicitForeground = style.foreground.isSet;
    final hasExplicitBackground = style.background.isSet;
    final hasExplicitUnderlineColor = style.underlineColor.isSet;
    const transparent = Color(0x00000000);

    var foreground = hasExplicitForeground
        ? resolveStyleColor(
            style.foreground,
            fallback: defaultForeground,
            palette: palette,
          )
        : transparent;
    var background = hasExplicitBackground
        ? resolveStyleColor(
            style.background,
            fallback: defaultBackground,
            palette: palette,
          )
        : transparent;

    if (style.inverse) {
      final swappedForeground = background;
      background = hasExplicitForeground
          ? foreground
          : (foreground == transparent ? defaultForeground : foreground);
      foreground = hasExplicitBackground
          ? swappedForeground
          : (swappedForeground == transparent
                ? defaultBackground
                : swappedForeground);
    }
    if (style.invisible) {
      foreground = background == transparent ? defaultBackground : background;
    }
    if (style.faint) {
      foreground = foreground.withValues(alpha: 0.72);
    }
    if (foreground == transparent) {
      foreground = defaultForeground;
    }

    return GhosttyTerminalResolvedStyle(
      foreground: foreground,
      background: background,
      underlineColor: resolveStyleColor(
        style.underlineColor,
        fallback: hasExplicitUnderlineColor ? defaultForeground : transparent,
        palette: palette,
      ),
      hasExplicitUnderlineColor: hasExplicitUnderlineColor,
      hasExplicitForeground: hasExplicitForeground,
      hasExplicitBackground: hasExplicitBackground,
      inverse: style.inverse,
      invisible: style.invisible,
      faint: style.faint,
      blink: style.blink,
      bold: style.bold,
      italic: style.italic,
      overline: style.overline,
      strikethrough: style.strikethrough,
      underline: style.underline,
    );
  }

  static ({Color foreground, Color background}) resolveNativeStyleColors({
    required GhosttyTerminalResolvedStyle style,
    required Color defaultForeground,
    required Color defaultBackground,
    Color? metadataColor,
  }) {
    final resolvedBackground =
        metadataColor == null || style.hasExplicitBackground
        ? style.background
        : metadataColor;
    return (foreground: style.foreground, background: resolvedBackground);
  }
}

/// Cell-level metadata derived from the raw Ghostty cell snapshot.
@immutable
final class GhosttyTerminalRenderCellMetadata {
  const GhosttyTerminalRenderCellMetadata({
    required this.codepoint,
    required this.contentTag,
    required this.styleId,
    required this.colorPaletteIndex,
    required this.colorRgb,
    required this.wide,
    required this.hasBackgroundColor,
    this.backgroundColor,
  });

  final int codepoint;
  final GhosttyCellContentTag contentTag;
  final int styleId;
  final int? colorPaletteIndex;
  final Color? colorRgb;
  final GhosttyCellWide wide;
  final bool hasBackgroundColor;
  final Color? backgroundColor;
}

/// Visible cell snapshot derived from Ghostty render-state rows.
@immutable
final class GhosttyTerminalRenderCell {
  const GhosttyTerminalRenderCell({
    required this.text,
    required this.width,
    required this.hasText,
    required this.hasStyling,
    required this.hasHyperlink,
    required this.isProtected,
    required this.semanticContent,
    required this.metadata,
    required this.style,
  });

  final String text;
  final int width;
  final bool hasText;
  final bool hasStyling;
  final bool hasHyperlink;
  final bool isProtected;
  final GhosttyCellSemanticContent semanticContent;
  final GhosttyTerminalRenderCellMetadata metadata;
  final GhosttyTerminalResolvedStyle style;
}

/// Visible row snapshot derived from Ghostty render-state rows.
@immutable
final class GhosttyTerminalRenderRow {
  const GhosttyTerminalRenderRow({
    required this.dirty,
    required this.wrap,
    required this.wrapContinuation,
    required this.hasGrapheme,
    required this.styled,
    required this.hasHyperlink,
    required this.semanticPrompt,
    required this.kittyVirtualPlaceholder,
    required this.cells,
  });

  final bool dirty;
  final bool wrap;
  final bool wrapContinuation;
  final bool hasGrapheme;
  final bool styled;
  final bool hasHyperlink;
  final GhosttyRowSemanticPrompt semanticPrompt;
  final bool kittyVirtualPlaceholder;
  final List<GhosttyTerminalRenderCell> cells;
}

/// Cursor viewport state derived from Ghostty render-state data.
@immutable
final class GhosttyTerminalRenderCursor {
  const GhosttyTerminalRenderCursor({
    required this.visualStyle,
    required this.visible,
    required this.blinking,
    required this.passwordInput,
    required this.hasViewportPosition,
    this.row,
    this.col,
    this.onWideTail = false,
    this.color,
  });

  final GhosttyRenderStateCursorVisualStyle visualStyle;
  final bool visible;
  final bool blinking;
  final bool passwordInput;
  final bool hasViewportPosition;
  final int? row;
  final int? col;
  final bool onWideTail;
  final Color? color;
}

/// High-fidelity visible render-state snapshot from Ghostty.
@immutable
final class GhosttyTerminalRenderSnapshot {
  const GhosttyTerminalRenderSnapshot({
    required this.cols,
    required this.rows,
    required this.dirty,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.cursor,
    required this.rowsData,
  });

  final int cols;
  final int rows;
  final GhosttyRenderStateDirty dirty;
  final Color backgroundColor;
  final Color foregroundColor;
  final GhosttyTerminalRenderCursor cursor;
  final List<GhosttyTerminalRenderRow> rowsData;

  bool get hasViewportData => rowsData.isNotEmpty;
}
