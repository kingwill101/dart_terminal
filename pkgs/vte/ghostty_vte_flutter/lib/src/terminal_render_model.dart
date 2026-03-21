import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

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
