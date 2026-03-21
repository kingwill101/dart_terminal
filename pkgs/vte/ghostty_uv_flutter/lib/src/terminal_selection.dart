library;

import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart' as gvf;

typedef GhosttyUvTerminalCopyOptions = gvf.GhosttyTerminalCopyOptions;
typedef GhosttyUvWordBoundaryPolicy = gvf.GhosttyTerminalWordBoundaryPolicy;

/// Absolute cell position in the combined terminal transcript.
final class GhosttyUvTerminalCellPosition
    implements Comparable<GhosttyUvTerminalCellPosition> {
  const GhosttyUvTerminalCellPosition({
    required this.row,
    required this.column,
  });

  final int row;
  final int column;

  @override
  int compareTo(GhosttyUvTerminalCellPosition other) {
    final rowOrder = row.compareTo(other.row);
    if (rowOrder != 0) {
      return rowOrder;
    }
    return column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyUvTerminalCellPosition &&
        other.row == row &&
        other.column == column;
  }

  @override
  int get hashCode => Object.hash(row, column);
}

/// Inclusive text selection over the combined terminal transcript.
final class GhosttyUvTerminalSelection {
  const GhosttyUvTerminalSelection({
    required this.anchor,
    required this.extent,
  });

  final GhosttyUvTerminalCellPosition anchor;
  final GhosttyUvTerminalCellPosition extent;

  GhosttyUvTerminalCellPosition get start {
    return anchor.compareTo(extent) <= 0 ? anchor : extent;
  }

  GhosttyUvTerminalCellPosition get end {
    return anchor.compareTo(extent) <= 0 ? extent : anchor;
  }

  bool get isCollapsed => anchor == extent;

  bool contains(int row, int column) {
    final startPos = start;
    final endPos = end;
    if (row < startPos.row || row > endPos.row) {
      return false;
    }
    if (startPos.row == endPos.row) {
      return column >= startPos.column && column <= endPos.column;
    }
    if (row == startPos.row) {
      return column >= startPos.column;
    }
    if (row == endPos.row) {
      return column <= endPos.column;
    }
    return true;
  }

  bool intersectsSpan(int row, int startColumn, int endColumn) {
    final startPos = start;
    final endPos = end;
    if (row < startPos.row || row > endPos.row) {
      return false;
    }

    final spanStart = startColumn <= endColumn ? startColumn : endColumn;
    final spanEnd = startColumn <= endColumn ? endColumn : startColumn;

    if (startPos.row == endPos.row) {
      return row == startPos.row &&
          startPos.column <= spanEnd &&
          endPos.column >= spanStart;
    }
    if (row == startPos.row) {
      return spanEnd >= startPos.column;
    }
    if (row == endPos.row) {
      return spanStart <= endPos.column;
    }
    return true;
  }
}

typedef GhosttyUvTerminalSelectionContent =
    gvf.GhosttyTerminalSelectionContent<GhosttyUvTerminalSelection>;
