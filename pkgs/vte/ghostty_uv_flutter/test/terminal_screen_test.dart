import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_uv_flutter/ghostty_uv_flutter.dart';
import 'package:ultraviolet/ultraviolet.dart';

void main() {
  test('screen handles overwrite after backspace', () {
    final screen = GhosttyUvTerminalScreen(rows: 4, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('abc\bd')));

    expect(screen.visibleText().trimRight(), 'abd');
  });

  test('screen tracks cursor key application mode', () {
    final screen = GhosttyUvTerminalScreen(rows: 4, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('\u001B[?1h')));
    expect(screen.cursorKeyApplication, isTrue);

    screen.write(Uint8List.fromList(utf8.encode('\u001B[?1l')));
    expect(screen.cursorKeyApplication, isFalse);
  });

  test('screen tracks bracketed paste mode', () {
    final screen = GhosttyUvTerminalScreen(rows: 4, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('\u001B[?2004h')));
    expect(screen.bracketedPasteMode, isTrue);

    screen.write(Uint8List.fromList(utf8.encode('\u001B[?2004l')));
    expect(screen.bracketedPasteMode, isFalse);
  });

  test('screen keeps unicode grapheme width from ultraviolet', () {
    final screen = GhosttyUvTerminalScreen(rows: 4, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('A🙂界')));

    expect(screen.cellAt(0, 0)?.content, 'A');
    expect(screen.cellAt(1, 0)?.content, '🙂');
    expect(screen.cellAt(1, 0)?.width, WidthMethod.grapheme.stringWidth('🙂'));
    expect(screen.cellAt(3, 0)?.content, '界');
  });

  test('screen applies sgr colors to cells', () {
    final screen = GhosttyUvTerminalScreen(rows: 4, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('\u001B[31mR')));

    final cell = screen.cellAt(0, 0);
    expect(cell, isNotNull);
    expect(cell!.style.fg, const UvBasic16(1));
  });

  test('screen records scrollback and exposes visible text', () {
    final screen = GhosttyUvTerminalScreen(rows: 2, cols: 12, maxScrollback: 8);

    screen.write(Uint8List.fromList(utf8.encode('one\r\ntwo\r\nthree')));

    expect(screen.scrollbackLineCount, 1);
    expect(screen.visibleText(), 'two\nthree');
    expect(screen.visibleText(scrollOffset: 1), 'one\ntwo');
  });

  test('screen extracts text for a selection', () {
    final screen = GhosttyUvTerminalScreen(rows: 3, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('hello\r\nworld')));

    const selection = GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: 0, column: 1),
      extent: GhosttyUvTerminalCellPosition(row: 1, column: 2),
    );

    expect(screen.textForSelection(selection), 'ello\nwor');
  });

  test('screen copy options can preserve trailing spaces', () {
    final screen = GhosttyUvTerminalScreen(rows: 2, cols: 5);

    screen.write(Uint8List.fromList(utf8.encode('ab')));

    const selection = GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: 0, column: 0),
      extent: GhosttyUvTerminalCellPosition(row: 0, column: 4),
    );

    expect(screen.textForSelection(selection), 'ab');
    expect(
      screen.textForSelection(
        selection,
        options: const GhosttyUvTerminalCopyOptions(trimTrailingSpaces: false),
      ),
      'ab   ',
    );
  });

  test('screen copy options can join wrapped lines', () {
    final screen = GhosttyUvTerminalScreen(rows: 3, cols: 5);

    screen.write(Uint8List.fromList(utf8.encode('hello world')));

    const selection = GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: 0, column: 0),
      extent: GhosttyUvTerminalCellPosition(row: 1, column: 4),
    );

    expect(screen.textForSelection(selection), 'hello\n worl');
    expect(
      screen.textForSelection(
        selection,
        options: const GhosttyUvTerminalCopyOptions(joinWrappedLines: true),
      ),
      'hello worl',
    );
  });

  test('screen copy options can customize wrapped-line join text', () {
    final screen = GhosttyUvTerminalScreen(rows: 3, cols: 5);

    screen.write(Uint8List.fromList(utf8.encode('hello world')));

    const selection = GhosttyUvTerminalSelection(
      anchor: GhosttyUvTerminalCellPosition(row: 0, column: 0),
      extent: GhosttyUvTerminalCellPosition(row: 1, column: 4),
    );

    expect(
      screen.textForSelection(
        selection,
        options: const GhosttyUvTerminalCopyOptions(
          joinWrappedLines: true,
          wrappedLineJoiner: ' ',
        ),
      ),
      'hello  worl',
    );
  });

  test('screen selects a word-like token at an absolute position', () {
    final screen = GhosttyUvTerminalScreen(rows: 2, cols: 20);

    screen.write(Uint8List.fromList(utf8.encode('hello world')));

    final selection = screen.wordSelectionAtAbsolutePosition(0, 7);

    expect(selection, isNotNull);
    expect(screen.textForSelection(selection!), 'world');
  });

  test('screen word selection honors custom boundary policy', () {
    final screen = GhosttyUvTerminalScreen(rows: 2, cols: 20);

    screen.write(Uint8List.fromList(utf8.encode('hello-world')));

    final selection = screen.wordSelectionAtAbsolutePosition(
      0,
      2,
      wordBoundaryPolicy: const GhosttyUvWordBoundaryPolicy(
        extraWordCharacters: '',
      ),
    );

    expect(selection, isNotNull);
    expect(screen.textForSelection(selection!), 'hello');
  });

  test('screen selects a linked span at an absolute position', () {
    final screen = GhosttyUvTerminalScreen(rows: 2, cols: 24);

    screen.write(
      Uint8List.fromList(
        utf8.encode(
          '\u001B]8;;https://ghostty.org\u0007ghostty\u001B]8;;\u0007',
        ),
      ),
    );

    final selection = screen.wordSelectionAtAbsolutePosition(0, 2);

    expect(selection, isNotNull);
    expect(screen.textForSelection(selection!), 'ghostty');
  });

  test('screen selects full lines across a row range', () {
    final screen = GhosttyUvTerminalScreen(rows: 3, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('one\r\ntwo\r\nthree')));

    final selection = screen.lineSelectionBetweenAbsoluteRows(0, 1);

    expect(selection, isNotNull);
    expect(screen.textForSelection(selection!), 'one\ntwo');
  });

  test('screen can select all visible transcript content', () {
    final screen = GhosttyUvTerminalScreen(rows: 3, cols: 12);

    screen.write(Uint8List.fromList(utf8.encode('one\r\ntwo\r\nthree')));

    final selection = screen.selectAllSelection();

    expect(selection, isNotNull);
    expect(screen.textForSelection(selection!), 'one\ntwo\nthree');
  });
}
