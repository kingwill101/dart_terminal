import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

import 'terminal_surface_contract.dart';

/// Snapshot of styled terminal output suitable for custom painting.
@immutable
final class GhosttyTerminalSnapshot
    implements
        GhosttyTerminalInteractiveBuffer<
          GhosttyTerminalCellPosition,
          GhosttyTerminalSelection
        > {
  const GhosttyTerminalSnapshot({required this.lines, this.cursor});

  const GhosttyTerminalSnapshot.empty()
    : lines = const <GhosttyTerminalLine>[GhosttyTerminalLine.empty()],
      cursor = const GhosttyTerminalCursor(row: 0, col: 0);

  /// Parses VT-formatted terminal output into styled lines and cursor state.
  factory GhosttyTerminalSnapshot.fromFormattedVt(
    String text, {
    int maxLines = 2000,
  }) {
    return _GhosttyTerminalSnapshotParser(maxLines: maxLines).parse(text);
  }

  final List<GhosttyTerminalLine> lines;
  final GhosttyTerminalCursor? cursor;

  int get lineCount => lines.length;

  /// Extracts plain text for an inclusive cell selection.
  @override
  String textForSelection(
    GhosttyTerminalSelection selection, {
    GhosttyTerminalCopyOptions options = const GhosttyTerminalCopyOptions(),
  }) {
    final normalized = selection.normalized;
    if (lines.isEmpty) {
      return '';
    }

    final startRow = normalized.start.row.clamp(0, lines.length - 1);
    final endRow = normalized.end.row.clamp(0, lines.length - 1);
    final buffer = StringBuffer();
    for (var row = startRow; row <= endRow; row++) {
      final line = lines[row];
      final startCol = row == startRow ? normalized.start.col : 0;
      final endCol = row == endRow ? normalized.end.col : line.cellCount - 1;
      if (line.cellCount > 0) {
        final text = line.textForCellRange(startCol, endCol);
        buffer.write(options.trimTrailingSpaces ? text.trimRight() : text);
      }
      if (row != endRow) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// Returns a selection covering the full visible transcript.
  @override
  GhosttyTerminalSelection? selectAllSelection() {
    if (lines.isEmpty) {
      return null;
    }
    return lineSelectionBetweenRows(0, lines.length - 1);
  }

  /// Returns an inclusive full-row selection across visible rows.
  @override
  GhosttyTerminalSelection? lineSelectionBetweenRows(
    int baseRow,
    int extentRow,
  ) {
    if (lines.isEmpty) {
      return null;
    }

    final startRow = baseRow.clamp(0, lines.length - 1);
    final endRow = extentRow.clamp(0, lines.length - 1);
    final normalizedStart = math.min(startRow, endRow);
    final normalizedEnd = math.max(startRow, endRow);
    final endLine = lines[normalizedEnd];
    final endCol = math.max(0, endLine.cellCount - 1);
    return GhosttyTerminalSelection(
      base: GhosttyTerminalCellPosition(row: normalizedStart, col: 0),
      extent: GhosttyTerminalCellPosition(row: normalizedEnd, col: endCol),
    );
  }

  /// Returns the OSC 8 hyperlink at [position], if the cell is linked.
  @override
  String? hyperlinkAt(GhosttyTerminalCellPosition position) {
    if (lines.isEmpty || position.row < 0 || position.row >= lines.length) {
      return null;
    }
    return lines[position.row].hyperlinkAtCell(position.col);
  }

  /// Returns a word-like inclusive selection anchored at [position].
  @override
  GhosttyTerminalSelection? wordSelectionAt(
    GhosttyTerminalCellPosition position, {
    GhosttyTerminalWordBoundaryPolicy policy =
        const GhosttyTerminalWordBoundaryPolicy(),
  }) {
    if (lines.isEmpty || position.row < 0 || position.row >= lines.length) {
      return null;
    }
    return lines[position.row].wordSelectionAtCell(
      position.row,
      position.col,
      policy: policy,
    );
  }
}

/// Controls how selected terminal text is converted back into plain text.
@immutable
final class GhosttyTerminalCopyOptions {
  const GhosttyTerminalCopyOptions({
    this.trimTrailingSpaces = true,
    this.joinWrappedLines = false,
    this.wrappedLineJoiner = '',
  });

  /// Removes trailing spaces from each selected line before copying.
  final bool trimTrailingSpaces;

  /// Merges soft-wrapped terminal lines into a single copied line.
  final bool joinWrappedLines;

  /// Separator inserted when [joinWrappedLines] merges wrapped rows.
  final String wrappedLineJoiner;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalCopyOptions &&
        other.trimTrailingSpaces == trimTrailingSpaces &&
        other.joinWrappedLines == joinWrappedLines &&
        other.wrappedLineJoiner == wrappedLineJoiner;
  }

  @override
  int get hashCode =>
      Object.hash(trimTrailingSpaces, joinWrappedLines, wrappedLineJoiner);
}

/// Controls how terminal text is grouped for word selection.
@immutable
final class GhosttyTerminalWordBoundaryPolicy {
  const GhosttyTerminalWordBoundaryPolicy({
    this.extraWordCharacters = '._/~:@%#?&=+-',
    this.treatNonAsciiAsWord = true,
  });

  /// Additional ASCII characters that should be considered part of a word.
  final String extraWordCharacters;

  /// Whether non-ASCII code points should extend word selections.
  final bool treatNonAsciiAsWord;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalWordBoundaryPolicy &&
        other.extraWordCharacters == extraWordCharacters &&
        other.treatNonAsciiAsWord == treatNonAsciiAsWord;
  }

  @override
  int get hashCode => Object.hash(extraWordCharacters, treatNonAsciiAsWord);
}

/// Host-facing selection payload including extracted text.
@immutable
final class GhosttyTerminalSelectionContent<SelectionT> {
  const GhosttyTerminalSelectionContent({
    required this.selection,
    required this.text,
  });

  /// Selection object associated with [text].
  final SelectionT selection;

  /// Extracted plain text for [selection].
  final String text;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalSelectionContent<SelectionT> &&
        other.selection == selection &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(selection, text);
}

/// Terminal cell coordinate used for selections and hit-testing.
@immutable
final class GhosttyTerminalCellPosition
    implements Comparable<GhosttyTerminalCellPosition> {
  const GhosttyTerminalCellPosition({required this.row, required this.col});

  /// Zero-based row index in the visible terminal transcript.
  final int row;

  /// Zero-based column index within [row].
  final int col;

  @override
  int compareTo(GhosttyTerminalCellPosition other) {
    final rowCompare = row.compareTo(other.row);
    return rowCompare != 0 ? rowCompare : col.compareTo(other.col);
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalCellPosition &&
        other.row == row &&
        other.col == col;
  }

  @override
  int get hashCode => Object.hash(row, col);
}

/// Inclusive terminal text selection.
@immutable
final class GhosttyTerminalSelection {
  const GhosttyTerminalSelection({required this.base, required this.extent});

  /// Anchor cell where the selection gesture started.
  final GhosttyTerminalCellPosition base;

  /// Active edge of the selection, inclusive.
  final GhosttyTerminalCellPosition extent;

  /// Returns this selection ordered from top-left to bottom-right.
  GhosttyTerminalSelection get normalized {
    if (base.compareTo(extent) <= 0) {
      return this;
    }
    return GhosttyTerminalSelection(base: extent, extent: base);
  }

  /// Inclusive first cell of the normalized selection.
  GhosttyTerminalCellPosition get start => normalized.base;

  /// Inclusive last cell of the normalized selection.
  GhosttyTerminalCellPosition get end => normalized.extent;

  /// Whether the selection covers exactly one cell.
  bool get isCollapsed => base == extent;

  /// Returns whether the inclusive selection covers the given cell.
  bool contains(int row, int col) {
    final current = GhosttyTerminalCellPosition(row: row, col: col);
    final normalized = this.normalized;
    return current.compareTo(normalized.base) >= 0 &&
        current.compareTo(normalized.extent) <= 0;
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalSelection &&
        other.base == base &&
        other.extent == extent;
  }

  @override
  int get hashCode => Object.hash(base, extent);
}

/// Single styled line within a [GhosttyTerminalSnapshot].
@immutable
final class GhosttyTerminalLine {
  const GhosttyTerminalLine(this.runs);

  const GhosttyTerminalLine.empty() : runs = const <GhosttyTerminalRun>[];

  final List<GhosttyTerminalRun> runs;

  String get text => runs.map((run) => run.text).join();

  int get cellCount => runs.fold<int>(0, (sum, run) => sum + run.cells);

  String textForCellRange(int startCol, int endColInclusive) {
    if (runs.isEmpty || endColInclusive < startCol) {
      return '';
    }

    final normalizedStart = startCol < 0 ? 0 : startCol;
    final normalizedEnd = endColInclusive >= cellCount
        ? cellCount - 1
        : endColInclusive;
    if (normalizedEnd < normalizedStart) {
      return '';
    }

    final buffer = StringBuffer();
    var cellIndex = 0;
    for (final run in runs) {
      for (final character in _splitCharacters(run.text)) {
        if (cellIndex >= normalizedStart && cellIndex <= normalizedEnd) {
          buffer.write(character);
        }
        cellIndex++;
        if (cellIndex > normalizedEnd) {
          return buffer.toString();
        }
      }
    }
    return buffer.toString();
  }

  /// Returns the OSC 8 hyperlink at the given zero-based terminal column.
  String? hyperlinkAtCell(int col) {
    return _hyperlinkInfoAtCell(col)?.uri;
  }

  /// Returns an inclusive selection covering the word-like token at [col].
  GhosttyTerminalSelection? wordSelectionAtCell(
    int row,
    int col, {
    GhosttyTerminalWordBoundaryPolicy policy =
        const GhosttyTerminalWordBoundaryPolicy(),
  }) {
    if (runs.isEmpty || cellCount == 0) {
      return null;
    }

    final normalizedCol = col.clamp(0, cellCount - 1);
    final hyperlink = _hyperlinkInfoAtCell(normalizedCol);
    if (hyperlink != null) {
      return GhosttyTerminalSelection(
        base: GhosttyTerminalCellPosition(row: row, col: hyperlink.startCol),
        extent: GhosttyTerminalCellPosition(row: row, col: hyperlink.endCol),
      );
    }

    final cells = _lineCells();
    final classification = _classifyTerminalCharacter(
      cells[normalizedCol].text,
      policy: policy,
    );
    var start = normalizedCol;
    var end = normalizedCol;

    while (start > 0 &&
        _classifyTerminalCharacter(cells[start - 1].text, policy: policy) ==
            classification) {
      start--;
    }
    while (end + 1 < cells.length &&
        _classifyTerminalCharacter(cells[end + 1].text, policy: policy) ==
            classification) {
      end++;
    }

    return GhosttyTerminalSelection(
      base: GhosttyTerminalCellPosition(row: row, col: start),
      extent: GhosttyTerminalCellPosition(row: row, col: end),
    );
  }

  List<_GhosttyTerminalLineCell> _lineCells() {
    final cells = <_GhosttyTerminalLineCell>[];
    for (final run in runs) {
      for (final character in _splitCharacters(run.text)) {
        cells.add(_GhosttyTerminalLineCell(text: character, style: run.style));
      }
    }
    return cells;
  }

  _GhosttyTerminalHyperlink? _hyperlinkInfoAtCell(int col) {
    if (runs.isEmpty || cellCount == 0) {
      return null;
    }

    final normalized = col.clamp(0, cellCount - 1);
    final styled = _styledHyperlinkAtCell(normalized);
    if (styled != null) {
      return styled;
    }

    return _detectedHyperlinkAtCell(normalized);
  }

  _GhosttyTerminalHyperlink? _styledHyperlinkAtCell(int col) {
    var cellIndex = 0;
    for (final run in runs) {
      final runEnd = cellIndex + run.cells;
      if (col < runEnd) {
        final uri = run.style.hyperlink;
        if (uri == null) {
          return null;
        }

        var startCol = cellIndex;
        var endCol = runEnd - 1;
        while (startCol > 0 && _styledHyperlinkUriAtCell(startCol - 1) == uri) {
          startCol--;
        }
        while (endCol + 1 < cellCount &&
            _styledHyperlinkUriAtCell(endCol + 1) == uri) {
          endCol++;
        }
        return _GhosttyTerminalHyperlink(
          uri: uri,
          startCol: startCol,
          endCol: endCol,
        );
      }
      cellIndex = runEnd;
    }
    return null;
  }

  String? _styledHyperlinkUriAtCell(int col) {
    var cellIndex = 0;
    for (final run in runs) {
      final runEnd = cellIndex + run.cells;
      if (col < runEnd) {
        return run.style.hyperlink;
      }
      cellIndex = runEnd;
    }
    return null;
  }

  _GhosttyTerminalHyperlink? _detectedHyperlinkAtCell(int col) {
    final cells = _lineCells();
    final text = cells.map((cell) => cell.text).join();
    for (final match in _terminalUrlPattern.allMatches(text)) {
      final raw = match.group(0);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      final trimmed = raw.replaceFirst(RegExp(r'[),.;:!?]+$'), '');
      if (trimmed.isEmpty) {
        continue;
      }

      final prefixCellCount = _splitCharacters(
        text.substring(0, match.start),
      ).length;
      final linkCellCount = _splitCharacters(trimmed).length;
      final startCol = prefixCellCount;
      final endCol = startCol + linkCellCount - 1;
      if (col >= startCol && col <= endCol) {
        return _GhosttyTerminalHyperlink(
          uri: trimmed,
          startCol: startCol,
          endCol: endCol,
        );
      }
    }

    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalLine && listEquals(other.runs, runs);
  }

  @override
  int get hashCode => Object.hashAll(runs);
}

final class _GhosttyTerminalLineCell {
  const _GhosttyTerminalLineCell({required this.text, required this.style});

  final String text;
  final GhosttyTerminalStyle style;
}

final class _GhosttyTerminalHyperlink {
  const _GhosttyTerminalHyperlink({
    required this.uri,
    required this.startCol,
    required this.endCol,
  });

  final String uri;
  final int startCol;
  final int endCol;
}

enum _GhosttyTerminalCellClass { whitespace, word, other }

final RegExp _terminalUrlPattern = RegExp(
  r'''(https?:\/\/[^\s<>"']+|mailto:[^\s<>"']+)''',
);

_GhosttyTerminalCellClass _classifyTerminalCharacter(
  String text, {
  required GhosttyTerminalWordBoundaryPolicy policy,
}) {
  if (text.trim().isEmpty) {
    return _GhosttyTerminalCellClass.whitespace;
  }
  if (_isWordLikeCharacter(text, policy: policy)) {
    return _GhosttyTerminalCellClass.word;
  }
  return _GhosttyTerminalCellClass.other;
}

bool _isWordLikeCharacter(
  String text, {
  required GhosttyTerminalWordBoundaryPolicy policy,
}) {
  final extra = policy.extraWordCharacters;
  for (final rune in text.runes) {
    if ((rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        extra.contains(String.fromCharCode(rune)) ||
        (policy.treatNonAsciiAsWord && rune > 0x7F)) {
      continue;
    }
    return false;
  }
  return true;
}

/// Consecutive terminal cells that share the same style.
@immutable
final class GhosttyTerminalRun {
  const GhosttyTerminalRun({
    required this.text,
    required this.cells,
    this.style = const GhosttyTerminalStyle(),
  });

  final String text;
  final int cells;
  final GhosttyTerminalStyle style;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalRun &&
        other.text == text &&
        other.cells == cells &&
        other.style == style;
  }

  @override
  int get hashCode => Object.hash(text, cells, style);
}

/// Cursor position within a styled terminal snapshot.
@immutable
final class GhosttyTerminalCursor {
  const GhosttyTerminalCursor({required this.row, required this.col});

  final int row;
  final int col;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalCursor &&
        other.row == row &&
        other.col == col;
  }

  @override
  int get hashCode => Object.hash(row, col);
}

/// Abstract terminal color reference resolved against a terminal palette.
@immutable
final class GhosttyTerminalColor {
  const GhosttyTerminalColor.palette(this.paletteIndex) : rgb = null;

  const GhosttyTerminalColor.rgb(int red, int green, int blue)
    : paletteIndex = null,
      rgb = (red << 16) | (green << 8) | blue;

  final int? paletteIndex;
  final int? rgb;

  int get red => (rgb! >> 16) & 0xFF;
  int get green => (rgb! >> 8) & 0xFF;
  int get blue => rgb! & 0xFF;

  bool get isPalette => paletteIndex != null;

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalColor &&
        other.paletteIndex == paletteIndex &&
        other.rgb == rgb;
  }

  @override
  int get hashCode => Object.hash(paletteIndex, rgb);
}

/// Terminal text styling extracted from VT formatter output.
@immutable
final class GhosttyTerminalStyle {
  const GhosttyTerminalStyle({
    this.bold = false,
    this.faint = false,
    this.italic = false,
    this.underline,
    this.underlineColor,
    this.overline = false,
    this.blink = false,
    this.inverse = false,
    this.invisible = false,
    this.strikethrough = false,
    this.foreground,
    this.background,
    this.hyperlink,
  });

  final bool bold;
  final bool faint;
  final bool italic;
  final GhosttySgrUnderline? underline;
  final GhosttyTerminalColor? underlineColor;
  final bool overline;
  final bool blink;
  final bool inverse;
  final bool invisible;
  final bool strikethrough;
  final GhosttyTerminalColor? foreground;
  final GhosttyTerminalColor? background;
  final String? hyperlink;

  GhosttyTerminalStyle copyWith({
    bool? bold,
    bool? faint,
    bool? italic,
    GhosttySgrUnderline? underline,
    bool clearUnderline = false,
    GhosttyTerminalColor? underlineColor,
    bool clearUnderlineColor = false,
    bool? overline,
    bool? blink,
    bool? inverse,
    bool? invisible,
    bool? strikethrough,
    GhosttyTerminalColor? foreground,
    bool clearForeground = false,
    GhosttyTerminalColor? background,
    bool clearBackground = false,
    String? hyperlink,
    bool clearHyperlink = false,
  }) {
    return GhosttyTerminalStyle(
      bold: bold ?? this.bold,
      faint: faint ?? this.faint,
      italic: italic ?? this.italic,
      underline: clearUnderline ? null : (underline ?? this.underline),
      underlineColor: clearUnderlineColor
          ? null
          : (underlineColor ?? this.underlineColor),
      overline: overline ?? this.overline,
      blink: blink ?? this.blink,
      inverse: inverse ?? this.inverse,
      invisible: invisible ?? this.invisible,
      strikethrough: strikethrough ?? this.strikethrough,
      foreground: clearForeground ? null : (foreground ?? this.foreground),
      background: clearBackground ? null : (background ?? this.background),
      hyperlink: clearHyperlink ? null : (hyperlink ?? this.hyperlink),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalStyle &&
        other.bold == bold &&
        other.faint == faint &&
        other.italic == italic &&
        other.underline == underline &&
        other.underlineColor == underlineColor &&
        other.overline == overline &&
        other.blink == blink &&
        other.inverse == inverse &&
        other.invisible == invisible &&
        other.strikethrough == strikethrough &&
        other.foreground == foreground &&
        other.background == background &&
        other.hyperlink == hyperlink;
  }

  @override
  int get hashCode => Object.hash(
    bold,
    faint,
    italic,
    underline,
    underlineColor,
    overline,
    blink,
    inverse,
    invisible,
    strikethrough,
    foreground,
    background,
    hyperlink,
  );
}

/// ANSI palette and 256-color resolver used by [GhosttyTerminalView].
@immutable
final class GhosttyTerminalPalette {
  const GhosttyTerminalPalette({required this.ansi});

  /// XTerm-compatible default terminal colors.
  static const GhosttyTerminalPalette xterm = GhosttyTerminalPalette(
    ansi: <Color>[
      Color(0xFF1D2430),
      Color(0xFFF7768E),
      Color(0xFF9ECE6A),
      Color(0xFFE0AF68),
      Color(0xFF7AA2F7),
      Color(0xFFBB9AF7),
      Color(0xFF7DCFFF),
      Color(0xFFC0CAF5),
      Color(0xFF414868),
      Color(0xFFFF899D),
      Color(0xFFB9F27C),
      Color(0xFFF0C47A),
      Color(0xFF8DB6FF),
      Color(0xFFCBA6FF),
      Color(0xFF94E2FF),
      Color(0xFFE6EDF3),
    ],
  );

  final List<Color> ansi;

  Color resolve(GhosttyTerminalColor? color, {required Color fallback}) {
    if (color == null) {
      return fallback;
    }
    if (!color.isPalette) {
      return Color(0xFF000000 | color.rgb!);
    }

    final index = color.paletteIndex!;
    if (index >= 0 && index < ansi.length) {
      return ansi[index];
    }
    if (index >= 16 && index <= 231) {
      final cubeIndex = index - 16;
      const levels = <int>[0, 95, 135, 175, 215, 255];
      final red = levels[(cubeIndex ~/ 36) % 6];
      final green = levels[(cubeIndex ~/ 6) % 6];
      final blue = levels[cubeIndex % 6];
      return Color.fromARGB(0xFF, red, green, blue);
    }
    if (index >= 232 && index <= 255) {
      final value = 8 + (index - 232) * 10;
      return Color.fromARGB(0xFF, value, value, value);
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) {
    return other is GhosttyTerminalPalette && listEquals(other.ansi, ansi);
  }

  @override
  int get hashCode => Object.hashAll(ansi);
}

Iterable<String> _splitCharacters(String text) sync* {
  for (var index = 0; index < text.length;) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
      final next = text.codeUnitAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        yield text.substring(index, index + 2);
        index += 2;
        continue;
      }
    }
    yield text.substring(index, index + 1);
    index++;
  }
}

final class _GhosttyTerminalSnapshotParser {
  _GhosttyTerminalSnapshotParser({required this.maxLines});

  final int maxLines;
  final VtSgrParser _sgrParser = VtSgrParser();

  final List<List<_GhosttyTerminalCell?>> _lines =
      <List<_GhosttyTerminalCell?>>[<_GhosttyTerminalCell?>[]];

  GhosttyTerminalStyle _style = const GhosttyTerminalStyle();
  int _row = 0;
  int _col = 0;
  GhosttyTerminalCursor? _cursor;

  GhosttyTerminalSnapshot parse(String text) {
    try {
      for (var index = 0; index < text.length;) {
        final unit = text.codeUnitAt(index);
        if (unit == 0x1B) {
          index = _consumeEscape(text, index);
          continue;
        }
        if (unit == 0x0D) {
          _col = 0;
          _cursor = GhosttyTerminalCursor(row: _row, col: _col);
          index++;
          continue;
        }
        if (unit == 0x0A) {
          _row++;
          _ensureLine(_row);
          _cursor = GhosttyTerminalCursor(row: _row, col: _col);
          index++;
          continue;
        }
        if (unit == 0x08) {
          if (_col > 0) {
            _col--;
          }
          _cursor = GhosttyTerminalCursor(row: _row, col: _col);
          index++;
          continue;
        }
        if (unit == 0x09) {
          final spaces = 8 - (_col % 8);
          for (var i = 0; i < spaces; i++) {
            _writeCell(' ');
          }
          index++;
          continue;
        }

        final character = _readCharacter(text, index);
        _writeCell(character);
        index += character.length;
      }

      final lines = _compactLines();
      if (lines.isEmpty) {
        return const GhosttyTerminalSnapshot.empty();
      }
      return GhosttyTerminalSnapshot(lines: lines, cursor: _cursor);
    } finally {
      _sgrParser.close();
    }
  }

  int _consumeEscape(String text, int index) {
    if (index + 1 >= text.length) {
      return text.length;
    }
    final next = text.codeUnitAt(index + 1);
    if (next == 0x5B) {
      return _consumeCsi(text, index + 2);
    }
    if (next == 0x5D) {
      return _consumeOsc(text, index + 2);
    }
    if (next == 0x50 || next == 0x58 || next == 0x5E || next == 0x5F) {
      return _consumeEscTerminatedString(text, index + 2);
    }
    return _consumeEscSequence(text, index + 1);
  }

  int _consumeEscSequence(String text, int index) {
    var cursor = index;
    while (cursor < text.length) {
      final unit = text.codeUnitAt(cursor);
      if (unit >= 0x30 && unit <= 0x7E) {
        return cursor + 1;
      }
      cursor++;
    }
    return text.length;
  }

  int _consumeEscTerminatedString(String text, int index) {
    var cursor = index;
    while (cursor < text.length) {
      final unit = text.codeUnitAt(cursor);
      if (unit == 0x07) {
        return cursor + 1;
      }
      if (unit == 0x1B &&
          cursor + 1 < text.length &&
          text.codeUnitAt(cursor + 1) == 0x5C) {
        return cursor + 2;
      }
      cursor++;
    }
    return text.length;
  }

  int _consumeCsi(String text, int index) {
    final buffer = StringBuffer();
    var cursor = index;
    while (cursor < text.length) {
      final unit = text.codeUnitAt(cursor);
      if (unit >= 0x40 && unit <= 0x7E) {
        _applyCsi(buffer.toString(), String.fromCharCode(unit));
        return cursor + 1;
      }
      buffer.writeCharCode(unit);
      cursor++;
    }
    return text.length;
  }

  int _consumeOsc(String text, int index) {
    final buffer = StringBuffer();
    var cursor = index;
    while (cursor < text.length) {
      final unit = text.codeUnitAt(cursor);
      if (unit == 0x07) {
        _applyOsc(buffer.toString());
        return cursor + 1;
      }
      if (unit == 0x1B &&
          cursor + 1 < text.length &&
          text.codeUnitAt(cursor + 1) == 0x5C) {
        _applyOsc(buffer.toString());
        return cursor + 2;
      }
      buffer.writeCharCode(unit);
      cursor++;
    }
    return text.length;
  }

  void _applyCsi(String params, String finalByte) {
    switch (finalByte) {
      case 'm':
        _applySgr(params);
        break;
      case 'H':
      case 'f':
        final values = _parseIntParams(params);
        final row = values.isEmpty ? 1 : values.first;
        final col = values.length < 2 ? 1 : values[1];
        final nextRow = row <= 0 ? 0 : row - 1;
        final nextCol = col <= 0 ? 0 : col - 1;
        _row = nextRow;
        _col = nextCol;
        _ensureLine(_row);
        _cursor = GhosttyTerminalCursor(row: _row, col: _col);
        break;
      case 'G':
        final values = _parseIntParams(params);
        _col = values.isEmpty ? 0 : (values.first - 1).clamp(0, 0x7FFFFFFF);
        _cursor = GhosttyTerminalCursor(row: _row, col: _col);
        break;
      default:
        break;
    }
  }

  void _applyOsc(String payload) {
    final separator = payload.indexOf(';');
    if (separator <= 0) {
      return;
    }
    final command = payload.substring(0, separator);
    final data = payload.substring(separator + 1);
    if (command != '8') {
      return;
    }
    final secondSeparator = data.indexOf(';');
    if (secondSeparator < 0) {
      return;
    }
    final uri = data.substring(secondSeparator + 1);
    _style = uri.isEmpty
        ? _style.copyWith(clearHyperlink: true)
        : _style.copyWith(hyperlink: uri);
  }

  void _applySgr(String params) {
    final values = _parseIntParams(params, fallbackZero: true);
    final attrs = _sgrParser.parseParams(values);
    for (final attr in attrs) {
      switch (attr.tag) {
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BOLD:
          _style = _style.copyWith(bold: true, faint: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BOLD:
          _style = _style.copyWith(bold: false, faint: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_ITALIC:
          _style = _style.copyWith(italic: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_ITALIC:
          _style = _style.copyWith(italic: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FAINT:
          _style = _style.copyWith(faint: true, bold: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE:
          final underline = attr.underline;
          _style =
              underline == null ||
                  underline == GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE
              ? _style.copyWith(clearUnderline: true)
              : _style.copyWith(underline: underline);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR:
          final rgb = attr.rgb;
          if (rgb != null) {
            _style = _style.copyWith(
              underlineColor: GhosttyTerminalColor.rgb(rgb.r, rgb.g, rgb.b),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              underlineColor: GhosttyTerminalColor.palette(index),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_UNDERLINE_COLOR:
          _style = _style.copyWith(clearUnderlineColor: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_OVERLINE:
          _style = _style.copyWith(overline: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_OVERLINE:
          _style = _style.copyWith(overline: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BLINK:
          _style = _style.copyWith(blink: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BLINK:
          _style = _style.copyWith(blink: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_INVERSE:
          _style = _style.copyWith(inverse: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_INVERSE:
          _style = _style.copyWith(inverse: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_INVISIBLE:
          _style = _style.copyWith(invisible: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_INVISIBLE:
          _style = _style.copyWith(invisible: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_STRIKETHROUGH:
          _style = _style.copyWith(strikethrough: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_STRIKETHROUGH:
          _style = _style.copyWith(strikethrough: false);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG:
          final rgb = attr.rgb;
          if (rgb != null) {
            _style = _style.copyWith(
              foreground: GhosttyTerminalColor.rgb(rgb.r, rgb.g, rgb.b),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG:
          final rgb = attr.rgb;
          if (rgb != null) {
            _style = _style.copyWith(
              background: GhosttyTerminalColor.rgb(rgb.r, rgb.g, rgb.b),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_8:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              background: GhosttyTerminalColor.palette(index),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_8:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              foreground: GhosttyTerminalColor.palette(index),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_FG:
          _style = _style.copyWith(clearForeground: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_RESET_BG:
          _style = _style.copyWith(clearBackground: true);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_BG_8:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              background: GhosttyTerminalColor.palette(index + 8),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_FG_8:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              foreground: GhosttyTerminalColor.palette(index + 8),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_256:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              background: GhosttyTerminalColor.palette(index),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_256:
          final index = attr.paletteIndex;
          if (index != null) {
            _style = _style.copyWith(
              foreground: GhosttyTerminalColor.palette(index),
            );
          }
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNSET:
          _style = GhosttyTerminalStyle(hyperlink: _style.hyperlink);
          break;
        case GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN:
          break;
      }
    }
  }

  List<int> _parseIntParams(String params, {bool fallbackZero = false}) {
    if (params.isEmpty) {
      return fallbackZero ? <int>[0] : const <int>[];
    }
    return params
        .split(';')
        .map((part) => part.isEmpty ? 0 : int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  String _readCharacter(String text, int index) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
      final next = text.codeUnitAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return text.substring(index, index + 2);
      }
    }
    return text.substring(index, index + 1);
  }

  void _writeCell(String text) {
    _ensureLine(_row);
    final line = _lines[_row];
    while (line.length < _col) {
      line.add(null);
    }
    if (line.length == _col) {
      line.add(_GhosttyTerminalCell(text: text, style: _style));
    } else {
      line[_col] = _GhosttyTerminalCell(text: text, style: _style);
    }
    _col++;
    _cursor = GhosttyTerminalCursor(row: _row, col: _col);
  }

  void _ensureLine(int row) {
    while (_lines.length <= row) {
      _lines.add(<_GhosttyTerminalCell?>[]);
    }
  }

  List<GhosttyTerminalLine> _compactLines() {
    final compacted = <GhosttyTerminalLine>[];
    for (final line in _lines) {
      if (line.isEmpty) {
        compacted.add(const GhosttyTerminalLine.empty());
        continue;
      }

      final runs = <GhosttyTerminalRun>[];
      final textBuffer = StringBuffer();
      var style = const GhosttyTerminalStyle();
      var cells = 0;
      var hasRun = false;

      void flush() {
        if (!hasRun) {
          return;
        }
        runs.add(
          GhosttyTerminalRun(
            text: textBuffer.toString(),
            cells: cells,
            style: style,
          ),
        );
        textBuffer.clear();
        cells = 0;
        hasRun = false;
      }

      for (final cell in line) {
        final resolved =
            cell ??
            const _GhosttyTerminalCell(
              text: ' ',
              style: GhosttyTerminalStyle(),
            );
        if (!hasRun || resolved.style != style) {
          flush();
          style = resolved.style;
          hasRun = true;
        }
        textBuffer.write(resolved.text);
        cells++;
      }
      flush();
      compacted.add(
        runs.isEmpty
            ? const GhosttyTerminalLine.empty()
            : GhosttyTerminalLine(runs),
      );
    }

    if (compacted.length > maxLines) {
      final drop = compacted.length - maxLines;
      final lines = compacted.sublist(drop);
      final cursor = _cursor;
      if (cursor != null) {
        final shiftedRow = cursor.row - drop;
        _cursor = shiftedRow < 0
            ? null
            : GhosttyTerminalCursor(row: shiftedRow, col: cursor.col);
      }
      return lines;
    }

    return compacted;
  }
}

@immutable
final class _GhosttyTerminalCell {
  const _GhosttyTerminalCell({required this.text, required this.style});

  final String text;
  final GhosttyTerminalStyle style;
}
