library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart'
    show GhosttyTerminalInteractiveBuffer;
import 'package:ultraviolet/ultraviolet.dart';

import 'terminal_selection.dart';

/// UV-backed terminal screen state with a lightweight VT parser.
final class GhosttyUvTerminalScreen
    implements
        GhosttyTerminalInteractiveBuffer<
          GhosttyUvTerminalCellPosition,
          GhosttyUvTerminalSelection
        > {
  GhosttyUvTerminalScreen({
    required int rows,
    required int cols,
    this.maxScrollback = 10_000,
  }) : _rows = rows,
       _cols = cols,
       _buffer = Buffer.create(cols, rows),
       _altBuffer = Buffer.create(cols, rows),
       _primaryWrappedRows = List<bool>.filled(rows, false, growable: true),
       _altWrappedRows = List<bool>.filled(rows, false, growable: true) {
    _scrollBottom = rows - 1;
  }

  final int maxScrollback;

  int _rows;
  int _cols;
  final Buffer _buffer;
  final Buffer _altBuffer;
  final List<Line> _scrollback = <Line>[];
  final List<bool> _scrollbackWrapped = <bool>[];
  final List<bool> _primaryWrappedRows;
  final List<bool> _altWrappedRows;
  bool _useAltBuffer = false;

  int _cursorX = 0;
  int _cursorY = 0;
  bool _cursorVisible = true;

  int _savedCursorX = 0;
  int _savedCursorY = 0;

  UvStyle _currentStyle = const UvStyle();
  Link _activeLink = const Link();

  int _scrollTop = 0;
  int _scrollBottom = 0;

  bool _cursorKeyApplication = false;
  bool _keypadKeyApplication = false;
  bool _bracketedPasteMode = false;
  bool _modifyOtherKeysState2 = false;
  int _kittyKeyboardFlags = 0;

  final _escBuffer = <int>[];
  final _utf8Buffer = <int>[];
  int _utf8ExpectedLength = 0;
  _ParseState _parseState = _ParseState.ground;

  late final Set<int> _tabStops = _initTabStops();

  Buffer get buffer => _useAltBuffer ? _altBuffer : _buffer;
  int get rows => _rows;
  int get cols => _cols;
  int get cursorX => _cursorX;
  int get cursorY => _cursorY;
  bool get cursorVisible => _cursorVisible;
  bool get isAltScreen => _useAltBuffer;
  UvStyle get currentStyle => _currentStyle;
  bool get cursorKeyApplication => _cursorKeyApplication;
  bool get keypadKeyApplication => _keypadKeyApplication;
  bool get bracketedPasteMode => _bracketedPasteMode;
  bool get modifyOtherKeysState2 => _modifyOtherKeysState2;
  int get kittyKeyboardFlags => _kittyKeyboardFlags;
  int get scrollbackLineCount => _scrollback.length;
  int get maxScrollOffset => _scrollback.length;
  int get totalLineCount => _scrollback.length + _rows;

  String get plainText => _joinLines(_allLines(), styled: false);
  String get styledText => _joinLines(_allLines(), styled: true);

  Cell? cellAt(int x, int y) => buffer.cellAt(x, y);

  void write(Uint8List data) {
    for (final byte in data) {
      _processByte(byte);
    }
  }

  void resize({required int rows, required int cols}) {
    _rows = rows;
    _cols = cols;
    _buffer.resize(cols, rows);
    _altBuffer.resize(cols, rows);
    _resizeWrappedRows(_primaryWrappedRows, rows);
    _resizeWrappedRows(_altWrappedRows, rows);
    _scrollBottom = rows - 1;
    _cursorX = _cursorX.clamp(0, cols - 1);
    _cursorY = _cursorY.clamp(0, rows - 1);
  }

  void clear() {
    buffer.clear();
    _clearWrappedRows(_activeWrappedRows);
    _cursorX = 0;
    _cursorY = 0;
  }

  void reset() {
    _buffer.clear();
    _altBuffer.clear();
    _scrollback.clear();
    _scrollbackWrapped.clear();
    _clearWrappedRows(_primaryWrappedRows);
    _clearWrappedRows(_altWrappedRows);
    _useAltBuffer = false;
    _cursorX = 0;
    _cursorY = 0;
    _cursorVisible = true;
    _savedCursorX = 0;
    _savedCursorY = 0;
    _currentStyle = const UvStyle();
    _activeLink = const Link();
    _scrollTop = 0;
    _scrollBottom = _rows - 1;
    _cursorKeyApplication = false;
    _keypadKeyApplication = false;
    _bracketedPasteMode = false;
    _modifyOtherKeysState2 = false;
    _kittyKeyboardFlags = 0;
    _escBuffer.clear();
    _utf8Buffer.clear();
    _utf8ExpectedLength = 0;
    _parseState = _ParseState.ground;
  }

  int normalizeScrollOffset(int requested) {
    return requested.clamp(0, maxScrollOffset);
  }

  int visibleWindowStart({int scrollOffset = 0}) {
    return math.max(
      0,
      _scrollback.length - normalizeScrollOffset(scrollOffset),
    );
  }

  int absoluteRowForVisibleRow(int visibleRow, {int scrollOffset = 0}) {
    return visibleWindowStart(scrollOffset: scrollOffset) + visibleRow;
  }

  Line? lineAtAbsoluteRow(int absoluteRow) {
    if (absoluteRow < 0 || absoluteRow >= totalLineCount) {
      return null;
    }
    if (absoluteRow < _scrollback.length) {
      return _scrollback[absoluteRow];
    }
    return buffer.line(absoluteRow - _scrollback.length);
  }

  Line? visibleLine(int visibleRow, {int scrollOffset = 0}) {
    return lineAtAbsoluteRow(
      absoluteRowForVisibleRow(visibleRow, scrollOffset: scrollOffset),
    );
  }

  int normalizeAbsoluteColumn(int absoluteRow, int column) {
    final line = lineAtAbsoluteRow(absoluteRow);
    if (line == null) {
      return column;
    }
    return _resolveCellOrigin(line, column.clamp(0, _cols - 1));
  }

  int normalizeVisibleColumn(
    int visibleRow,
    int column, {
    int scrollOffset = 0,
  }) {
    final absoluteRow = absoluteRowForVisibleRow(
      visibleRow,
      scrollOffset: scrollOffset,
    );
    return normalizeAbsoluteColumn(absoluteRow, column);
  }

  Link? linkAtVisiblePosition(
    int column,
    int visibleRow, {
    int scrollOffset = 0,
  }) {
    final absoluteRow = absoluteRowForVisibleRow(
      visibleRow,
      scrollOffset: scrollOffset,
    );
    return linkAtAbsolutePosition(absoluteRow, column);
  }

  Link? linkAtAbsolutePosition(int absoluteRow, int column) {
    final line = lineAtAbsoluteRow(absoluteRow);
    if (line == null) {
      return null;
    }
    final resolvedColumn = _resolveCellOrigin(line, column.clamp(0, _cols - 1));
    final cell = line.at(resolvedColumn);
    if (cell == null || cell.link.url.isEmpty) {
      return null;
    }
    return cell.link;
  }

  @override
  String? hyperlinkAt(GhosttyUvTerminalCellPosition position) {
    return linkAtAbsolutePosition(position.row, position.column)?.url;
  }

  GhosttyUvTerminalSelection? wordSelectionAtAbsolutePosition(
    int absoluteRow,
    int column, {
    GhosttyUvWordBoundaryPolicy wordBoundaryPolicy =
        const GhosttyUvWordBoundaryPolicy(),
  }) {
    final line = lineAtAbsoluteRow(absoluteRow);
    if (line == null || line.length == 0) {
      return null;
    }

    final normalizedColumn = normalizeAbsoluteColumn(absoluteRow, column);
    final hyperlink = linkAtAbsolutePosition(absoluteRow, normalizedColumn);
    if (hyperlink != null) {
      final start = _scanLinkedColumn(
        line,
        normalizedColumn,
        hyperlink.url,
        forward: false,
      );
      final end = _scanLinkedColumn(
        line,
        normalizedColumn,
        hyperlink.url,
        forward: true,
      );
      return GhosttyUvTerminalSelection(
        anchor: GhosttyUvTerminalCellPosition(row: absoluteRow, column: start),
        extent: GhosttyUvTerminalCellPosition(row: absoluteRow, column: end),
      );
    }

    final cellClass = _classifyTerminalCharacter(
      _cellTextAtColumn(line, normalizedColumn),
      wordBoundaryPolicy,
    );
    final start = _scanClassifiedColumn(
      line,
      normalizedColumn,
      cellClass,
      wordBoundaryPolicy,
      forward: false,
    );
    final end = _scanClassifiedColumn(
      line,
      normalizedColumn,
      cellClass,
      wordBoundaryPolicy,
      forward: true,
    );
    return GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: absoluteRow, column: start),
      extent: GhosttyUvTerminalCellPosition(row: absoluteRow, column: end),
    );
  }

  @override
  GhosttyUvTerminalSelection? wordSelectionAt(
    GhosttyUvTerminalCellPosition position,
  ) {
    return wordSelectionAtAbsolutePosition(position.row, position.column);
  }

  GhosttyUvTerminalSelection? lineSelectionBetweenAbsoluteRows(
    int startRow,
    int endRow,
  ) {
    if (totalLineCount <= 0) {
      return null;
    }

    final clampedStartRow = startRow.clamp(0, totalLineCount - 1);
    final clampedEndRow = endRow.clamp(0, totalLineCount - 1);
    final firstRow = math.min(clampedStartRow, clampedEndRow);
    final lastRow = math.max(clampedStartRow, clampedEndRow);
    final lastLine = lineAtAbsoluteRow(lastRow);
    final lastColumn = math.max(0, (lastLine?.length ?? _cols) - 1);
    return GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: firstRow, column: 0),
      extent: GhosttyUvTerminalCellPosition(row: lastRow, column: lastColumn),
    );
  }

  @override
  GhosttyUvTerminalSelection? selectAllSelection() {
    int? firstRow;
    int? lastRow;
    var lastColumn = 0;

    for (var row = 0; row < totalLineCount; row++) {
      final line = lineAtAbsoluteRow(row);
      if (line == null || !_lineHasVisibleContent(line)) {
        continue;
      }
      firstRow ??= row;
      lastRow = row;
      lastColumn = _lastVisibleColumn(line);
    }

    if (firstRow == null || lastRow == null) {
      return null;
    }

    return GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: firstRow, column: 0),
      extent: GhosttyUvTerminalCellPosition(row: lastRow, column: lastColumn),
    );
  }

  @override
  GhosttyUvTerminalSelection? lineSelectionBetweenRows(
    int startRow,
    int endRow,
  ) {
    return lineSelectionBetweenAbsoluteRows(startRow, endRow);
  }

  String visibleText({int scrollOffset = 0}) {
    final lines = List<Line>.generate(
      _rows,
      (index) =>
          visibleLine(index, scrollOffset: scrollOffset) ?? Line.filled(_cols),
      growable: false,
    );
    return _joinLines(lines, styled: false);
  }

  @override
  String textForSelection(
    GhosttyUvTerminalSelection selection, {
    GhosttyUvTerminalCopyOptions options = const GhosttyUvTerminalCopyOptions(),
  }) {
    final normalized = selection;
    final start = normalized.start;
    final end = normalized.end;
    final out = StringBuffer();

    for (var row = start.row; row <= end.row; row++) {
      final line = lineAtAbsoluteRow(row);
      if (line == null) {
        continue;
      }
      final startColumn = row == start.row ? start.column : 0;
      final endColumn = row == end.row ? end.column : line.length - 1;
      var lineText = _extractLineText(line, startColumn, endColumn);
      if (options.trimTrailingSpaces) {
        lineText = lineText.replaceFirst(RegExp(r' +$'), '');
      }
      out.write(lineText);
      if (row < end.row) {
        final joinsWrappedLine =
            options.joinWrappedLines && isLineWrappedAtAbsoluteRow(row);
        out.write(joinsWrappedLine ? options.wrappedLineJoiner : '\n');
      }
    }

    return out.toString();
  }

  bool isLineWrappedAtAbsoluteRow(int absoluteRow) {
    if (absoluteRow < 0 || absoluteRow >= totalLineCount) {
      return false;
    }
    if (absoluteRow < _scrollbackWrapped.length) {
      return _scrollbackWrapped[absoluteRow];
    }
    final bufferRow = absoluteRow - _scrollbackWrapped.length;
    final wrappedRows = _activeWrappedRows;
    if (bufferRow < 0 || bufferRow >= wrappedRows.length) {
      return false;
    }
    return wrappedRows[bufferRow];
  }

  Set<int> _initTabStops() {
    final stops = <int>{};
    for (var i = 0; i < _cols; i += 8) {
      stops.add(i);
    }
    return stops;
  }

  void _processByte(int byte) {
    switch (_parseState) {
      case _ParseState.ground:
        _processGround(byte);
      case _ParseState.escape:
        _processEscape(byte);
      case _ParseState.csi:
        _processCsi(byte);
      case _ParseState.osc:
        _processOsc(byte);
      case _ParseState.oscEsc:
        _processOscEsc(byte);
      case _ParseState.charset:
        _parseState = _ParseState.ground;
    }
  }

  void _processGround(int byte) {
    if (_utf8ExpectedLength > 0 || byte >= 0x80) {
      _processUtf8(byte);
      return;
    }

    switch (byte) {
      case 0x1B:
        _flushUtf8Malformed();
        _escBuffer.clear();
        _parseState = _ParseState.escape;
      case 0x07:
        break;
      case 0x08:
        if (_cursorX > 0) {
          _cursorX--;
        }
      case 0x09:
        _advanceToNextTabStop();
      case 0x0A:
      case 0x0B:
      case 0x0C:
        _lineFeed();
      case 0x0D:
        _cursorX = 0;
      case 0x0E:
      case 0x0F:
        break;
      default:
        if (byte >= 0x20) {
          _putText(String.fromCharCode(byte));
        }
    }
  }

  void _processUtf8(int byte) {
    if (_utf8ExpectedLength == 0) {
      _utf8ExpectedLength = _utf8SequenceLength(byte);
      if (_utf8ExpectedLength == 0) {
        _putText('\uFFFD');
        return;
      }
      _utf8Buffer
        ..clear()
        ..add(byte);
      if (_utf8ExpectedLength == 1) {
        _flushUtf8Buffer();
      }
      return;
    }

    if ((byte & 0xC0) != 0x80) {
      _flushUtf8Malformed();
      _processGround(byte);
      return;
    }

    _utf8Buffer.add(byte);
    if (_utf8Buffer.length >= _utf8ExpectedLength) {
      _flushUtf8Buffer();
    }
  }

  int _utf8SequenceLength(int byte) {
    if (byte < 0x80) {
      return 1;
    }
    if ((byte & 0xE0) == 0xC0) {
      return 2;
    }
    if ((byte & 0xF0) == 0xE0) {
      return 3;
    }
    if ((byte & 0xF8) == 0xF0) {
      return 4;
    }
    return 0;
  }

  void _flushUtf8Buffer() {
    final text = utf8.decode(_utf8Buffer, allowMalformed: true);
    _utf8Buffer.clear();
    _utf8ExpectedLength = 0;
    for (final grapheme in graphemes(text)) {
      _putText(grapheme);
    }
  }

  void _flushUtf8Malformed() {
    if (_utf8Buffer.isEmpty) {
      _utf8ExpectedLength = 0;
      return;
    }
    _utf8Buffer.clear();
    _utf8ExpectedLength = 0;
    _putText('\uFFFD');
  }

  void _processEscape(int byte) {
    switch (byte) {
      case 0x5B:
        _escBuffer.clear();
        _parseState = _ParseState.csi;
      case 0x5D:
        _escBuffer.clear();
        _parseState = _ParseState.osc;
      case 0x28:
      case 0x29:
      case 0x2A:
      case 0x2B:
        _parseState = _ParseState.charset;
      case 0x37:
        _savedCursorX = _cursorX;
        _savedCursorY = _cursorY;
        _parseState = _ParseState.ground;
      case 0x38:
        _cursorX = _savedCursorX.clamp(0, _cols - 1);
        _cursorY = _savedCursorY.clamp(0, _rows - 1);
        _parseState = _ParseState.ground;
      case 0x44:
        _lineFeed();
        _parseState = _ParseState.ground;
      case 0x45:
        _cursorX = 0;
        _lineFeed();
        _parseState = _ParseState.ground;
      case 0x4D:
        _reverseIndex();
        _parseState = _ParseState.ground;
      case 0x63:
        reset();
        _parseState = _ParseState.ground;
      default:
        _parseState = _ParseState.ground;
    }
  }

  void _processCsi(int byte) {
    if (byte >= 0x40 && byte <= 0x7E) {
      _executeCsi(byte);
      _parseState = _ParseState.ground;
    } else {
      _escBuffer.add(byte);
    }
  }

  void _processOsc(int byte) {
    if (byte == 0x07) {
      _handleOsc();
      _parseState = _ParseState.ground;
    } else if (byte == 0x1B) {
      _parseState = _ParseState.oscEsc;
    } else {
      _escBuffer.add(byte);
    }
  }

  void _processOscEsc(int byte) {
    if (byte == 0x5C) {
      _handleOsc();
      _parseState = _ParseState.ground;
      return;
    }
    _escBuffer.clear();
    _parseState = _ParseState.escape;
    _processEscape(byte);
  }

  void _handleOsc() {
    final payload = utf8.decode(_escBuffer, allowMalformed: true);
    _escBuffer.clear();

    if (payload.startsWith('8;')) {
      final split = payload.indexOf(';', 2);
      if (split == -1) {
        return;
      }
      final params = payload.substring(2, split);
      final uri = payload.substring(split + 1);
      _activeLink = uri.isEmpty ? const Link() : Link(url: uri, params: params);
    }
  }

  void _executeCsi(int finalByte) {
    final params = _parseCsiParams();
    final hasQuestion = _escBuffer.isNotEmpty && _escBuffer.first == 0x3F;
    final hasGreater = _escBuffer.isNotEmpty && _escBuffer.first == 0x3E;

    switch (finalByte) {
      case 0x41:
        _cursorY = (_cursorY - _param(params, 0, 1)).clamp(0, _rows - 1);
      case 0x42:
        _cursorY = (_cursorY + _param(params, 0, 1)).clamp(0, _rows - 1);
      case 0x43:
        _cursorX = (_cursorX + _param(params, 0, 1)).clamp(0, _cols - 1);
      case 0x44:
        _cursorX = (_cursorX - _param(params, 0, 1)).clamp(0, _cols - 1);
      case 0x45:
        _cursorY = (_cursorY + _param(params, 0, 1)).clamp(0, _rows - 1);
        _cursorX = 0;
      case 0x46:
        _cursorY = (_cursorY - _param(params, 0, 1)).clamp(0, _rows - 1);
        _cursorX = 0;
      case 0x47:
        _cursorX = (_param(params, 0, 1) - 1).clamp(0, _cols - 1);
      case 0x48:
      case 0x66:
        _cursorY = (_param(params, 0, 1) - 1).clamp(0, _rows - 1);
        _cursorX = (_param(params, 1, 1) - 1).clamp(0, _cols - 1);
      case 0x4A:
        _eraseInDisplay(_param(params, 0, 0));
      case 0x4B:
        _eraseInLine(_param(params, 0, 0));
      case 0x4C:
        _insertActiveLines(_cursorY, _param(params, 0, 1));
      case 0x4D:
        _deleteActiveLines(_cursorY, _param(params, 0, 1));
      case 0x50:
        buffer.deleteCell(
          _cursorX,
          _cursorY,
          _param(params, 0, 1),
          Cell.emptyCell(),
        );
      case 0x53:
        _scrollUp(_param(params, 0, 1));
      case 0x54:
        _scrollDown(_param(params, 0, 1));
      case 0x58:
        final count = _param(params, 0, 1);
        for (var i = 0; i < count && _cursorX + i < _cols; i++) {
          buffer.setCell(_cursorX + i, _cursorY, Cell.emptyCell());
        }
      case 0x40:
        buffer.insertCell(
          _cursorX,
          _cursorY,
          _param(params, 0, 1),
          Cell.emptyCell(),
        );
      case 0x64:
        _cursorY = (_param(params, 0, 1) - 1).clamp(0, _rows - 1);
      case 0x68:
        if (hasQuestion) {
          _handleDecMode(params, true);
        }
      case 0x6C:
        if (hasQuestion) {
          _handleDecMode(params, false);
        }
      case 0x6D:
        if (hasGreater) {
          _handleGreaterModes(params);
        } else {
          _handleSgr(params);
        }
      case 0x72:
        final top = _param(params, 0, 1);
        final bottom = _param(params, 1, _rows);
        _scrollTop = (top - 1).clamp(0, _rows - 1);
        _scrollBottom = (bottom - 1).clamp(0, _rows - 1);
        _cursorX = 0;
        _cursorY = 0;
      case 0x73:
        _savedCursorX = _cursorX;
        _savedCursorY = _cursorY;
      case 0x75:
        _cursorX = _savedCursorX.clamp(0, _cols - 1);
        _cursorY = _savedCursorY.clamp(0, _rows - 1);
      default:
        break;
    }
  }

  void _putText(String grapheme) {
    if (grapheme.isEmpty) {
      return;
    }
    if (_cursorX >= _cols) {
      _cursorX = 0;
      _lineFeed(wrappedFromCurrentLine: true);
    }

    final cell = Cell.newCell(WidthMethod.grapheme, grapheme)
      ..style = _currentStyle
      ..link = _activeLink;

    if (cell.width == 0) {
      if (_cursorX == 0) {
        return;
      }
      final previousX = _cursorX - 1;
      final previous = buffer.cellAt(previousX, _cursorY);
      if (previous == null) {
        return;
      }
      final combined = previous.clone()
        ..content = '${previous.content}$grapheme'
        ..width = WidthMethod.grapheme.stringWidth(
          '${previous.content}$grapheme',
        );
      buffer.setCell(previousX, _cursorY, combined);
      return;
    }

    buffer.setCell(_cursorX, _cursorY, cell);
    _cursorX += cell.width;
  }

  void _lineFeed({bool wrappedFromCurrentLine = false}) {
    _setWrappedRow(_cursorY, wrappedFromCurrentLine);
    if (_cursorY >= _scrollBottom) {
      _scrollUp(1);
    } else {
      _cursorY++;
    }
  }

  void _reverseIndex() {
    if (_cursorY <= _scrollTop) {
      _scrollDown(1);
    } else {
      _cursorY--;
    }
  }

  void _scrollUp(int count) {
    for (var i = 0; i < count; i++) {
      if (!_useAltBuffer && _scrollTop == 0) {
        _pushScrollbackLine(
          _cloneLine(buffer.line(_scrollTop)),
          wrapped: _wrappedRow(_scrollTop),
        );
      }
      _deleteActiveLines(_scrollTop, 1);
      _insertActiveLines(_scrollBottom, 1);
    }
  }

  void _scrollDown(int count) {
    for (var i = 0; i < count; i++) {
      _deleteActiveLines(_scrollBottom, 1);
      _insertActiveLines(_scrollTop, 1);
    }
  }

  void _advanceToNextTabStop() {
    for (var x = _cursorX + 1; x < _cols; x++) {
      if (_tabStops.contains(x)) {
        _cursorX = x;
        return;
      }
    }
    _cursorX = _cols - 1;
  }

  void _eraseInDisplay(int mode) {
    switch (mode) {
      case 0:
        _eraseInLine(0);
        for (var y = _cursorY + 1; y < _rows; y++) {
          _clearLine(y);
        }
      case 1:
        _eraseInLine(1);
        for (var y = 0; y < _cursorY; y++) {
          _clearLine(y);
        }
      case 2:
        buffer.clear();
        _clearWrappedRows(_activeWrappedRows);
      case 3:
        buffer.clear();
        _scrollback.clear();
        _scrollbackWrapped.clear();
        _clearWrappedRows(_activeWrappedRows);
    }
  }

  void _eraseInLine(int mode) {
    switch (mode) {
      case 0:
        for (var x = _cursorX; x < _cols; x++) {
          buffer.setCell(x, _cursorY, Cell.emptyCell());
        }
      case 1:
        for (var x = 0; x <= _cursorX; x++) {
          buffer.setCell(x, _cursorY, Cell.emptyCell());
        }
      case 2:
        _clearLine(_cursorY);
    }
  }

  void _clearLine(int y) {
    for (var x = 0; x < _cols; x++) {
      buffer.setCell(x, y, Cell.emptyCell());
    }
    _setWrappedRow(y, false);
  }

  void _handleDecMode(List<int> params, bool enable) {
    for (final mode in params) {
      switch (mode) {
        case 1:
          _cursorKeyApplication = enable;
        case 25:
          _cursorVisible = enable;
        case 47:
          _useAltBuffer = enable;
          if (enable) {
            _altBuffer.clear();
            _clearWrappedRows(_altWrappedRows);
          }
        case 66:
          _keypadKeyApplication = enable;
        case 1049:
          if (enable) {
            _useAltBuffer = true;
            _altBuffer.clear();
            _clearWrappedRows(_altWrappedRows);
            _savedCursorX = _cursorX;
            _savedCursorY = _cursorY;
            _cursorX = 0;
            _cursorY = 0;
          } else {
            _useAltBuffer = false;
            _cursorX = _savedCursorX.clamp(0, _cols - 1);
            _cursorY = _savedCursorY.clamp(0, _rows - 1);
          }
        case 2004:
          _bracketedPasteMode = enable;
        default:
          break;
      }
    }
  }

  void _handleGreaterModes(List<int> params) {
    if (params.length >= 2 && params.first == 4) {
      _modifyOtherKeysState2 = params[1] == 2;
    }
    if (params.length >= 2 && params.first == 1) {
      _kittyKeyboardFlags = params[1];
    }
  }

  void _handleSgr(List<int> params) {
    if (params.isEmpty) {
      _currentStyle = const UvStyle();
      return;
    }

    var index = 0;
    while (index < params.length) {
      final value = params[index];
      switch (value) {
        case 0:
          _currentStyle = const UvStyle();
        case 1:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.bold,
          );
        case 2:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.faint,
          );
        case 3:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.italic,
          );
        case 4:
          _currentStyle = _currentStyle.copyWith(
            underline: UnderlineStyle.single,
          );
        case 5:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.blink,
          );
        case 7:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.reverse,
          );
        case 8:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.conceal,
          );
        case 9:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs | Attr.strikethrough,
          );
        case 22:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~(Attr.bold | Attr.faint),
          );
        case 23:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~Attr.italic,
          );
        case 24:
          _currentStyle = _currentStyle.copyWith(
            underline: UnderlineStyle.none,
          );
        case 25:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~Attr.blink,
          );
        case 27:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~Attr.reverse,
          );
        case 28:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~Attr.conceal,
          );
        case 29:
          _currentStyle = _currentStyle.copyWith(
            attrs: _currentStyle.attrs & ~Attr.strikethrough,
          );
        case >= 30 && <= 37:
          _currentStyle = _currentStyle.copyWith(
            fg: UvColor.basic16(value - 30),
          );
        case 38:
          index = _parseExtendedColor(params, index, foreground: true);
          continue;
        case 39:
          _currentStyle = _currentStyle.copyWith(clearFg: true);
        case >= 40 && <= 47:
          _currentStyle = _currentStyle.copyWith(
            bg: UvColor.basic16(value - 40),
          );
        case 48:
          index = _parseExtendedColor(params, index, foreground: false);
          continue;
        case 49:
          _currentStyle = _currentStyle.copyWith(clearBg: true);
        case >= 90 && <= 97:
          _currentStyle = _currentStyle.copyWith(
            fg: UvColor.basic16(value - 90, bright: true),
          );
        case >= 100 && <= 107:
          _currentStyle = _currentStyle.copyWith(
            bg: UvColor.basic16(value - 100, bright: true),
          );
      }
      index++;
    }
  }

  int _parseExtendedColor(
    List<int> params,
    int index, {
    required bool foreground,
  }) {
    if (index + 1 >= params.length) {
      return index + 1;
    }
    final mode = params[index + 1];
    if (mode == 5 && index + 2 < params.length) {
      final color = UvColor.indexed256(params[index + 2]);
      _currentStyle = foreground
          ? _currentStyle.copyWith(fg: color)
          : _currentStyle.copyWith(bg: color);
      return index + 3;
    }
    if (mode == 2 && index + 4 < params.length) {
      final color = UvColor.rgb(
        params[index + 2],
        params[index + 3],
        params[index + 4],
      );
      _currentStyle = foreground
          ? _currentStyle.copyWith(fg: color)
          : _currentStyle.copyWith(bg: color);
      return index + 5;
    }
    return index + 1;
  }

  List<int> _parseCsiParams() {
    final raw = String.fromCharCodes(
      _escBuffer.where((byte) => byte >= 0x30 && byte <= 0x3F),
    );
    final cleaned = raw.startsWith('?') || raw.startsWith('>')
        ? raw.substring(1)
        : raw;
    if (cleaned.isEmpty) {
      return const <int>[];
    }
    return cleaned.split(';').map((value) => int.tryParse(value) ?? 0).toList();
  }

  int _resolveCellOrigin(Line line, int column) {
    final cell = line.at(column);
    if (cell != null && !cell.isZero) {
      return column;
    }
    for (var x = column - 1; x >= 0 && x >= column - 4; x--) {
      final candidate = line.at(x);
      if (candidate == null || candidate.isZero) {
        continue;
      }
      if (x + math.max(1, candidate.width) > column) {
        return x;
      }
    }
    return column;
  }

  String _cellTextAtColumn(Line line, int column) {
    if (column < 0 || column >= line.length) {
      return '';
    }
    final resolvedColumn = _resolveCellOrigin(line, column);
    final cell = line.at(resolvedColumn);
    if (cell == null || cell.isZero || cell.isEmpty) {
      return ' ';
    }
    return cell.content;
  }

  String? _hyperlinkUrlAtColumn(Line line, int column) {
    if (column < 0 || column >= line.length) {
      return null;
    }
    final resolvedColumn = _resolveCellOrigin(line, column);
    final cell = line.at(resolvedColumn);
    final url = cell?.link.url;
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  int _scanLinkedColumn(
    Line line,
    int startColumn,
    String url, {
    required bool forward,
  }) {
    var column = startColumn.clamp(0, line.length - 1);
    while (true) {
      final nextColumn = forward ? column + 1 : column - 1;
      if (nextColumn < 0 || nextColumn >= line.length) {
        return column;
      }
      if (_hyperlinkUrlAtColumn(line, nextColumn) != url) {
        return column;
      }
      column = nextColumn;
    }
  }

  bool _lineHasVisibleContent(Line line) {
    for (var column = 0; column < line.length; column++) {
      final cellText = _cellTextAtColumn(line, column);
      if (cellText.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  int _lastVisibleColumn(Line line) {
    for (var column = line.length - 1; column >= 0; column--) {
      final cellText = _cellTextAtColumn(line, column);
      if (cellText.trim().isNotEmpty) {
        return _resolveCellOrigin(line, column);
      }
    }
    return math.max(0, line.length - 1);
  }

  int _scanClassifiedColumn(
    Line line,
    int startColumn,
    _GhosttyUvCellClass cellClass,
    GhosttyUvWordBoundaryPolicy wordBoundaryPolicy, {
    required bool forward,
  }) {
    var column = startColumn.clamp(0, line.length - 1);
    while (true) {
      final nextColumn = forward ? column + 1 : column - 1;
      if (nextColumn < 0 || nextColumn >= line.length) {
        return column;
      }
      if (_classifyTerminalCharacter(
            _cellTextAtColumn(line, nextColumn),
            wordBoundaryPolicy,
          ) !=
          cellClass) {
        return column;
      }
      column = nextColumn;
    }
  }

  List<bool> get _activeWrappedRows =>
      _useAltBuffer ? _altWrappedRows : _primaryWrappedRows;

  void _resizeWrappedRows(List<bool> rows, int nextLength) {
    if (rows.length > nextLength) {
      rows.removeRange(nextLength, rows.length);
      return;
    }
    if (rows.length < nextLength) {
      rows.addAll(List<bool>.filled(nextLength - rows.length, false));
    }
  }

  void _clearWrappedRows(List<bool> rows) {
    for (var index = 0; index < rows.length; index++) {
      rows[index] = false;
    }
  }

  bool _wrappedRow(int row) {
    if (row < 0 || row >= _activeWrappedRows.length) {
      return false;
    }
    return _activeWrappedRows[row];
  }

  void _setWrappedRow(int row, bool wrapped) {
    if (row < 0 || row >= _activeWrappedRows.length) {
      return;
    }
    _activeWrappedRows[row] = wrapped;
  }

  void _insertActiveLines(int y, int count) {
    if (count <= 0 || y < 0 || y >= _rows) {
      return;
    }
    final wrappedRows = _activeWrappedRows;
    final cappedCount = math.min(count, _rows - y);
    buffer.insertLine(y, cappedCount, Cell.emptyCell());
    for (var row = _rows - 1; row >= y + cappedCount; row--) {
      wrappedRows[row] = wrappedRows[row - cappedCount];
    }
    for (var row = y; row < y + cappedCount; row++) {
      wrappedRows[row] = false;
    }
  }

  void _deleteActiveLines(int y, int count) {
    if (count <= 0 || y < 0 || y >= _rows) {
      return;
    }
    final wrappedRows = _activeWrappedRows;
    final cappedCount = math.min(count, _rows - y);
    buffer.deleteLine(y, cappedCount, Cell.emptyCell());
    for (var row = y; row < _rows - cappedCount; row++) {
      wrappedRows[row] = wrappedRows[row + cappedCount];
    }
    for (var row = _rows - cappedCount; row < _rows; row++) {
      wrappedRows[row] = false;
    }
  }

  void _pushScrollbackLine(Line line, {required bool wrapped}) {
    if (maxScrollback <= 0) {
      return;
    }
    if (_scrollback.length >= maxScrollback) {
      _scrollback.removeAt(0);
      _scrollbackWrapped.removeAt(0);
    }
    _scrollback.add(line);
    _scrollbackWrapped.add(wrapped);
  }

  Line _cloneLine(Line? line) {
    if (line == null) {
      return Line.filled(_cols);
    }
    return Line.fromCells(
      line.cells.map((cell) => cell.clone()).toList(growable: false),
    );
  }

  List<Line> _allLines() {
    return <Line>[
      ..._scrollback,
      for (var y = 0; y < _rows; y++) buffer.line(y) ?? Line.filled(_cols),
    ];
  }

  String _joinLines(List<Line> lines, {required bool styled}) {
    final out = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      out.write(styled ? lines[index].render() : lines[index].toString());
      if (index < lines.length - 1) {
        out.write('\n');
      }
    }
    return out.toString();
  }

  String _extractLineText(Line line, int startColumn, int endColumn) {
    if (line.length == 0) {
      return '';
    }

    final start = startColumn.clamp(0, line.length - 1);
    final end = endColumn.clamp(0, line.length - 1);
    if (end < start) {
      return '';
    }

    final out = StringBuffer();
    var column = start;
    while (column <= end) {
      final resolved = _resolveCellOrigin(line, column);
      final cell = line.at(resolved);
      if (cell == null || cell.isZero) {
        column++;
        continue;
      }
      final cellWidth = math.max(1, cell.width);
      final cellEnd = resolved + cellWidth - 1;
      if (cellEnd < start) {
        column = cellEnd + 1;
        continue;
      }
      if (cell.isEmpty) {
        final visibleStart = math.max(start, resolved);
        final visibleEnd = math.min(end, cellEnd);
        out.write(
          List<String>.filled(visibleEnd - visibleStart + 1, ' ').join(),
        );
      } else {
        out.write(cell.content);
      }
      column = cellEnd + 1;
    }
    return out.toString();
  }

  static int _param(List<int> params, int index, int fallback) {
    if (index >= params.length) {
      return fallback;
    }
    final value = params[index];
    return value == 0 ? fallback : value;
  }
}

enum _ParseState { ground, escape, csi, osc, oscEsc, charset }

enum _GhosttyUvCellClass { whitespace, word, other }

_GhosttyUvCellClass _classifyTerminalCharacter(
  String text,
  GhosttyUvWordBoundaryPolicy wordBoundaryPolicy,
) {
  if (text.trim().isEmpty) {
    return _GhosttyUvCellClass.whitespace;
  }
  if (_isWordLikeCharacter(text, wordBoundaryPolicy)) {
    return _GhosttyUvCellClass.word;
  }
  return _GhosttyUvCellClass.other;
}

bool _isWordLikeCharacter(
  String text,
  GhosttyUvWordBoundaryPolicy wordBoundaryPolicy,
) {
  final extra = wordBoundaryPolicy.extraWordCharacters;
  for (final rune in text.runes) {
    if ((rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        extra.contains(String.fromCharCode(rune)) ||
        (wordBoundaryPolicy.treatNonAsciiAsWord && rune > 0x7F)) {
      continue;
    }
    return false;
  }
  return true;
}
