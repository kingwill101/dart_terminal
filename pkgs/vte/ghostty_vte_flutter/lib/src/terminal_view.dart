import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

import 'keyboard_input.dart';
import 'terminal_auto_scroll_session.dart';
import 'terminal_controller.dart';
import 'terminal_gesture_coordinator.dart';
import 'terminal_interactions.dart';
import 'terminal_pointer_flow.dart';
import 'terminal_snapshot.dart';
import 'terminal_selection_session.dart';

/// Painter-based terminal widget that renders lines from [GhosttyTerminalController].
///
/// The controller now keeps a real [VtTerminal] alive, and this widget sizes
/// that VT grid to the available layout while rendering styled VT formatter
/// snapshots with lightweight Flutter painting.
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
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontPackage,
    this.letterSpacing = 0,
    this.cellWidthScale = 1,
    this.padding = const EdgeInsets.all(12),
    this.palette = GhosttyTerminalPalette.xterm,
    this.cursorColor = const Color(0xFF9AD1C0),
    this.selectionColor = const Color(0x665DA9FF),
    this.hyperlinkColor = const Color(0xFF61AFEF),
    this.copyOptions = const GhosttyTerminalCopyOptions(),
    this.wordBoundaryPolicy = const GhosttyTerminalWordBoundaryPolicy(),
    this.selectionAutoScrollEdgeInset = 28,
    this.onSelectionChanged,
    this.onSelectionContentChanged,
    this.onCopySelection,
    this.onPasteRequest,
    this.onOpenHyperlink,
  });

  final GhosttyTerminalController controller;
  final bool autofocus;
  final FocusNode? focusNode;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color chromeColor;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final String? fontPackage;
  final double letterSpacing;
  final double cellWidthScale;
  final EdgeInsets padding;
  final GhosttyTerminalPalette palette;
  final Color cursorColor;
  final Color selectionColor;
  final Color hyperlinkColor;
  final GhosttyTerminalCopyOptions copyOptions;
  final GhosttyTerminalWordBoundaryPolicy wordBoundaryPolicy;
  final double selectionAutoScrollEdgeInset;
  final ValueChanged<GhosttyTerminalSelection?>? onSelectionChanged;
  final ValueChanged<
    GhosttyTerminalSelectionContent<GhosttyTerminalSelection>?
  >?
  onSelectionContentChanged;
  final Future<void> Function(String text)? onCopySelection;
  final Future<String?> Function()? onPasteRequest;
  final Future<void> Function(String uri)? onOpenHyperlink;

  @override
  State<GhosttyTerminalView> createState() => _GhosttyTerminalViewState();
}

class _GhosttyTerminalViewState extends State<GhosttyTerminalView> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  int _scrollOffsetLines = 0;
  int _lastReportedCols = -1;
  int _lastReportedRows = -1;
  final GhosttyTerminalSelectionSession<GhosttyTerminalSelection>
  _selectionSession =
      GhosttyTerminalSelectionSession<GhosttyTerminalSelection>();
  final GhosttyTerminalAutoScrollSession<_TerminalMetrics> _autoScrollSession =
      GhosttyTerminalAutoScrollSession<_TerminalMetrics>();
  late final GhosttyTerminalGestureCoordinator<
    GhosttyTerminalCellPosition,
    GhosttyTerminalSelection
  >
  _gestureCoordinator =
      GhosttyTerminalGestureCoordinator<
        GhosttyTerminalCellPosition,
        GhosttyTerminalSelection
      >(_selectionSession);

  GhosttyTerminalSelection? get _selection => _selectionSession.selection;
  String? get _hoveredHyperlink => _selectionSession.hoveredHyperlink;
  int? get _lineSelectionAnchorRow => _selectionSession.lineSelectionAnchorRow;

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
      _lastReportedCols = -1;
      _lastReportedRows = -1;
      _scrollOffsetLines = 0;
      _selectionSession.reset();
      _autoScrollSession.reset();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
    }
    if (oldWidget.copyOptions != widget.copyOptions && _selection != null) {
      ghosttyTerminalNotifySelectionContent<GhosttyTerminalSelection>(
        selection: _selection,
        resolveText: (selection) => widget.controller.snapshot.textForSelection(
          selection,
          options: widget.copyOptions,
        ),
        onSelectionContentChanged: widget.onSelectionContentChanged,
      );
    }
  }

  @override
  void dispose() {
    _stopAutoScroll();
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
    if (_selection != null) {
      ghosttyTerminalNotifySelectionContent<GhosttyTerminalSelection>(
        selection: _selection,
        resolveText: (selection) => widget.controller.snapshot.textForSelection(
          selection,
          options: widget.copyOptions,
        ),
        onSelectionContentChanged: widget.onSelectionContentChanged,
      );
    }
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final modifiers = GhosttyTerminalModifierState.fromHardwareKeyboard();

    if (ghosttyTerminalMatchesCopyShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      final text = _selectionText();
      if (text.isNotEmpty) {
        unawaited(_copySelection(text));
        return KeyEventResult.handled;
      }
    }
    if (ghosttyTerminalMatchesClearSelectionShortcut(
          event.logicalKey,
          modifiers: modifiers,
        ) &&
        _selection != null) {
      _setSelection(null);
      return KeyEventResult.handled;
    }
    if (ghosttyTerminalMatchesSelectAllShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      final selection = widget.controller.snapshot.selectAllSelection();
      if (selection != null) {
        _setSelection(selection);
        return KeyEventResult.handled;
      }
    }
    if (ghosttyTerminalMatchesPasteShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    final key = ghosttyTerminalLogicalKey(event.logicalKey);
    final mods = modifiers.ghosttyMask;
    final character = ghosttyTerminalPrintableText(event, modifiers: modifiers);

    if (key != null) {
      if (_selection != null) {
        if (_selectionSession.updateSelection(null)) {
          setState(() {});
        }
      }
      // Special keys are encoded from the key enum/modifier state alone.
      // Forwarding printable text metadata here breaks keys like backspace.
      final sent = widget.controller.sendKey(
        key: key,
        action: event is KeyRepeatEvent
            ? GhosttyKeyAction.GHOSTTY_KEY_ACTION_REPEAT
            : GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS,
        mods: mods,
        utf8Text: '',
        unshiftedCodepoint: 0,
      );
      return sent ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (character.isNotEmpty) {
      if (_selection != null) {
        if (_selectionSession.updateSelection(null)) {
          setState(() {});
        }
      }
      final sent = widget.controller.write(character);
      return sent ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _copySelection(String text) async {
    await ghosttyTerminalCopyText(
      text,
      onCopySelection: widget.onCopySelection,
    );
  }

  Future<void> _pasteClipboard() async {
    final text = await ghosttyTerminalReadPasteText(
      onPasteRequest: widget.onPasteRequest,
    );
    if (text == null || text.isEmpty) {
      return;
    }
    widget.controller.write(text, sanitizePaste: true);
  }

  String _selectionText() {
    final selection = _selection;
    if (selection == null) {
      return '';
    }
    return widget.controller.snapshot.textForSelection(
      selection,
      options: widget.copyOptions,
    );
  }

  void _setSelection(GhosttyTerminalSelection? selection) {
    final previousSelection = _selection;
    if (!_selectionSession.updateSelection(selection)) {
      return;
    }
    setState(() {});
    ghosttyTerminalNotifySelectionChange<GhosttyTerminalSelection>(
      previousSelection: previousSelection,
      nextSelection: _selection,
      resolveText: (nextSelection) => widget.controller.snapshot
          .textForSelection(nextSelection, options: widget.copyOptions),
      onSelectionChanged: widget.onSelectionChanged,
      onSelectionContentChanged: widget.onSelectionContentChanged,
    );
  }

  _TerminalMetrics _measureMetrics() {
    final painter = TextPainter(
      text: TextSpan(
        text: 'W',
        style: _terminalTextStyle(
          fontSize: widget.fontSize,
          lineHeight: widget.lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _TerminalMetrics(
      charWidth: math.max(1, painter.width * widget.cellWidthScale),
      linePixels: math.max(1, widget.fontSize * widget.lineHeight),
    );
  }

  TextStyle _terminalTextStyle({
    required double fontSize,
    required double lineHeight,
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    TextDecorationStyle? decorationStyle,
    Color? decorationColor,
  }) {
    return TextStyle(
      color: color,
      fontFamily: widget.fontFamily ?? 'monospace',
      fontFamilyFallback: widget.fontFamilyFallback,
      package: widget.fontPackage,
      fontSize: fontSize,
      height: lineHeight,
      letterSpacing: widget.letterSpacing,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationStyle: decorationStyle,
      decorationColor: decorationColor,
    );
  }

  void _syncGrid(Size size, _TerminalMetrics metrics) {
    const headerHeight = 28.0;
    final contentWidth = size.width - widget.padding.horizontal;
    final contentHeight = size.height - headerHeight - widget.padding.vertical;
    if (contentWidth <= 0 || contentHeight <= 0) {
      return;
    }

    final cols = math.max(1, (contentWidth / metrics.charWidth).floor());
    final rows = math.max(1, (contentHeight / metrics.linePixels).floor());
    if (cols == _lastReportedCols && rows == _lastReportedRows) {
      return;
    }

    _lastReportedCols = cols;
    _lastReportedRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.controller.resize(cols: cols, rows: rows);
    });
  }

  void _handlePointerSignal(
    PointerSignalEvent event,
    Size size,
    _TerminalMetrics metrics,
  ) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final deltaLines = (event.scrollDelta.dy / metrics.linePixels).round();
    if (deltaLines == 0) {
      return;
    }

    setState(() {
      _scrollOffsetLines = (_scrollOffsetLines - deltaLines).clamp(
        0,
        _maxScrollOffset(size, metrics),
      );
    });
  }

  int _maxScrollOffset(Size size, _TerminalMetrics metrics) {
    final viewport = _viewportFor(size, metrics);
    return math.max(
      0,
      widget.controller.snapshot.lines.length - viewport.maxVisible,
    );
  }

  _TerminalViewport _viewportFor(Size size, _TerminalMetrics metrics) {
    const headerHeight = 28.0;
    final contentTop = headerHeight + widget.padding.top;
    final contentHeight = size.height - contentTop - widget.padding.bottom;
    final maxVisible = contentHeight <= 0
        ? 1
        : math.max(1, (contentHeight / metrics.linePixels).floor());
    final lineCount = widget.controller.snapshot.lines.length;
    final maxOffset = math.max(0, lineCount - maxVisible);
    final offset = _scrollOffsetLines.clamp(0, maxOffset);
    final end = math.max(0, lineCount - offset);
    final start = math.max(0, end - maxVisible);
    return _TerminalViewport(
      startLine: start,
      contentTop: contentTop,
      contentHeight: math.max(0, contentHeight),
      maxVisible: maxVisible,
    );
  }

  GhosttyTerminalCellPosition? _positionForOffset(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics, {
    bool clampToViewport = false,
  }) {
    final viewport = _viewportFor(size, metrics);
    if (widget.controller.snapshot.lines.isEmpty) {
      return null;
    }

    final minX = widget.padding.left;
    final maxX = size.width - widget.padding.right;
    final minY = viewport.contentTop;
    final maxY = viewport.contentTop + viewport.contentHeight;
    if (!clampToViewport &&
        (localPosition.dx < minX ||
            localPosition.dx > maxX ||
            localPosition.dy < minY ||
            localPosition.dy > maxY)) {
      return null;
    }

    final resolvedX = clampToViewport
        ? localPosition.dx.clamp(minX, maxX)
        : localPosition.dx;
    final resolvedY = clampToViewport
        ? localPosition.dy.clamp(minY, maxY)
        : localPosition.dy;
    final lineIndex = ((resolvedY - viewport.contentTop) / metrics.linePixels)
        .floor();
    final row = (viewport.startLine + lineIndex).clamp(
      0,
      widget.controller.snapshot.lines.length - 1,
    );
    final lines = widget.controller.snapshot.lines;
    final col = ((resolvedX - widget.padding.left) / metrics.charWidth).floor();
    final maxCol = math.max(0, lines[row].cellCount - 1);
    return GhosttyTerminalCellPosition(row: row, col: col.clamp(0, maxCol));
  }

  void _stopAutoScroll({bool clearLineSelectionAnchor = true}) {
    _autoScrollSession.stop();
    if (clearLineSelectionAnchor) {
      _selectionSession.clearLineSelectionAnchorRow();
    }
  }

  void _syncAutoScroll(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics,
  ) {
    _autoScrollSession
      ..updateDragPosition(localPosition)
      ..updateLayout(layoutSize: size, metrics: metrics);

    final viewport = _viewportFor(size, metrics);
    final edgeThreshold = widget.selectionAutoScrollEdgeInset;
    final topEdge = viewport.contentTop + edgeThreshold;
    final bottomEdge =
        viewport.contentTop + viewport.contentHeight - edgeThreshold;
    final shouldScrollUp = localPosition.dy < topEdge;
    final shouldScrollDown = localPosition.dy > bottomEdge;
    if (!shouldScrollUp && !shouldScrollDown) {
      _stopAutoScroll(clearLineSelectionAnchor: false);
      return;
    }

    _autoScrollSession.ensureTimer(
      const Duration(milliseconds: 50),
      _performAutoScrollTick,
    );
  }

  void _performAutoScrollTick() {
    final size = _autoScrollSession.layoutSize;
    final metrics = _autoScrollSession.metrics;
    final localPosition = _autoScrollSession.dragPosition;
    if (!mounted || size == null || metrics == null || localPosition == null) {
      _stopAutoScroll();
      return;
    }

    final viewport = _viewportFor(size, metrics);
    final edgeThreshold = widget.selectionAutoScrollEdgeInset;
    final topEdge = viewport.contentTop + edgeThreshold;
    final bottomEdge =
        viewport.contentTop + viewport.contentHeight - edgeThreshold;
    final direction = localPosition.dy < topEdge
        ? 1
        : (localPosition.dy > bottomEdge ? -1 : 0);
    if (direction == 0) {
      _stopAutoScroll(clearLineSelectionAnchor: false);
      return;
    }

    final nextOffset = (_scrollOffsetLines + direction).clamp(
      0,
      _maxScrollOffset(size, metrics),
    );
    final position = _positionForOffset(
      Offset(
        localPosition.dx,
        direction < 0
            ? viewport.contentTop + 1
            : viewport.contentTop + viewport.contentHeight - 1,
      ),
      size,
      metrics,
      clampToViewport: true,
    );
    if (position == null) {
      _stopAutoScroll();
      return;
    }

    final current = _selection;
    if (current == null) {
      _stopAutoScroll();
      return;
    }

    final lineSelectionAnchorRow = _lineSelectionAnchorRow;
    final nextSelection = lineSelectionAnchorRow == null
        ? GhosttyTerminalSelection(base: current.base, extent: position)
        : widget.controller.snapshot.lineSelectionBetweenRows(
            lineSelectionAnchorRow,
            position.row,
          );
    final previousSelection = _selection;
    setState(() {
      _scrollOffsetLines = nextOffset;
    });
    _selectionSession.updateSelection(nextSelection);
    ghosttyTerminalNotifySelectionChange<GhosttyTerminalSelection>(
      previousSelection: previousSelection,
      nextSelection: _selection,
      resolveText: (selection) => widget.controller.snapshot.textForSelection(
        selection,
        options: widget.copyOptions,
      ),
      onSelectionChanged: widget.onSelectionChanged,
      onSelectionContentChanged: widget.onSelectionContentChanged,
    );
  }

  void _updateHoveredHyperlink(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics,
  ) {
    final position = _positionForOffset(localPosition, size, metrics);
    if (!ghosttyTerminalUpdateHoveredLink<
      GhosttyTerminalCellPosition,
      GhosttyTerminalSelection
    >(
      session: _selectionSession,
      position: position,
      resolveUri: widget.controller.snapshot.hyperlinkAt,
    )) {
      return;
    }
    setState(() {});
  }

  Future<void> _openHyperlink(String uri) async {
    await ghosttyTerminalOpenHyperlink(
      uri,
      onOpenHyperlink: widget.onOpenHyperlink,
    );
  }

  void _handleTapUp(Offset localPosition, Size size, _TerminalMetrics metrics) {
    FocusScope.of(context).requestFocus(_focusNode);
    final position = _positionForOffset(localPosition, size, metrics);
    final resolution =
        ghosttyTerminalResolveTap<
          GhosttyTerminalCellPosition,
          GhosttyTerminalSelection
        >(
          session: _selectionSession,
          selection: _selection,
          position: position,
          resolveUri: widget.controller.snapshot.hyperlinkAt,
        );
    if (resolution.hyperlink case final hyperlink?) {
      unawaited(_openHyperlink(hyperlink));
      return;
    }
    if (resolution.clearSelection) {
      _setSelection(null);
    }
  }

  void _beginSelection(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics,
  ) {
    final position = _positionForOffset(localPosition, size, metrics);
    final selection = _gestureCoordinator.beginSelection(
      position: position,
      collapsedSelection: (position) =>
          GhosttyTerminalSelection(base: position, extent: position),
    );
    if (selection == null) {
      return;
    }
    _stopAutoScroll();
    FocusScope.of(context).requestFocus(_focusNode);
    _setSelection(selection);
  }

  void _updateSelection(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics,
  ) {
    final position = _positionForOffset(
      localPosition,
      size,
      metrics,
      clampToViewport: true,
    );
    final nextSelection = _gestureCoordinator.updateSelection(
      currentSelection: _selection,
      position: position,
      extendSelection: (currentSelection, position) => GhosttyTerminalSelection(
        base: currentSelection.base,
        extent: position,
      ),
      extendLineSelection: (anchorRow, position) => widget.controller.snapshot
          .lineSelectionBetweenRows(anchorRow, position.row),
    );
    if (nextSelection == null) {
      return;
    }
    _setSelection(nextSelection);
    _syncAutoScroll(localPosition, size, metrics);
  }

  void _selectWord(Offset localPosition, Size size, _TerminalMetrics metrics) {
    final position = _positionForOffset(localPosition, size, metrics);
    final selection = _gestureCoordinator.selectWord(
      position: position,
      resolveWordSelection: (position) => widget.controller.snapshot
          .wordSelectionAt(position, policy: widget.wordBoundaryPolicy),
    );
    if (selection == null) {
      return;
    }
    _stopAutoScroll();
    FocusScope.of(context).requestFocus(_focusNode);
    _setSelection(selection);
  }

  void _beginLineSelection(
    Offset localPosition,
    Size size,
    _TerminalMetrics metrics,
  ) {
    final position = _positionForOffset(localPosition, size, metrics);
    final selection = _gestureCoordinator.beginLineSelection(
      position: position,
      rowOfPosition: (position) => position.row,
      resolveLineSelection: (position) => widget.controller.snapshot
          .lineSelectionBetweenRows(position.row, position.row),
    );
    if (selection == null) {
      return;
    }
    _setSelection(selection);
    _syncAutoScroll(localPosition, size, metrics);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _measureMetrics();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _autoScrollSession.updateLayout(layoutSize: size, metrics: metrics);
        _syncGrid(size, metrics);
        final viewport = _viewportFor(size, metrics);

        return Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _handleKey,
          child: MouseRegion(
            cursor: _hoveredHyperlink == null
                ? SystemMouseCursors.text
                : SystemMouseCursors.click,
            onExit: (_) {
              if (ghosttyTerminalClearHoveredLink<GhosttyTerminalSelection>(
                session: _selectionSession,
              )) {
                setState(() {});
              }
            },
            onHover: (event) =>
                _updateHoveredHyperlink(event.localPosition, size, metrics),
            child: Listener(
              onPointerSignal: (event) =>
                  _handlePointerSignal(event, size, metrics),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _handleTapUp(details.localPosition, size, metrics),
                onDoubleTapDown: (details) =>
                    _selectWord(details.localPosition, size, metrics),
                onLongPressStart: (details) =>
                    _beginLineSelection(details.localPosition, size, metrics),
                onLongPressMoveUpdate: (details) =>
                    _updateSelection(details.localPosition, size, metrics),
                onLongPressEnd: (_) => _stopAutoScroll(),
                onPanDown: (details) =>
                    _beginSelection(details.localPosition, size, metrics),
                onPanUpdate: (details) =>
                    _updateSelection(details.localPosition, size, metrics),
                onPanEnd: (_) => _stopAutoScroll(),
                onPanCancel: _stopAutoScroll,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _GhosttyTerminalPainter(
                      revision: widget.controller.revision,
                      title: widget.controller.title,
                      snapshot: widget.controller.snapshot,
                      running: widget.controller.isRunning,
                      focused: _focusNode.hasFocus,
                      cols: widget.controller.cols,
                      rows: widget.controller.rows,
                      scrollOffsetLines: _scrollOffsetLines,
                      visibleStartLine: viewport.startLine,
                      charWidth: metrics.charWidth,
                      linePixels: metrics.linePixels,
                      backgroundColor: widget.backgroundColor,
                      foregroundColor: widget.foregroundColor,
                      chromeColor: widget.chromeColor,
                      cursorColor: widget.cursorColor,
                      selectionColor: widget.selectionColor,
                      hyperlinkColor: widget.hyperlinkColor,
                      palette: widget.palette,
                      fontSize: widget.fontSize,
                      fontFamily: widget.fontFamily ?? 'monospace',
                      fontFamilyFallback: widget.fontFamilyFallback,
                      fontPackage: widget.fontPackage,
                      letterSpacing: widget.letterSpacing,
                      padding: widget.padding,
                      selection: _selection,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GhosttyTerminalPainter extends CustomPainter {
  const _GhosttyTerminalPainter({
    required this.revision,
    required this.title,
    required this.snapshot,
    required this.running,
    required this.focused,
    required this.cols,
    required this.rows,
    required this.scrollOffsetLines,
    required this.visibleStartLine,
    required this.charWidth,
    required this.linePixels,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.chromeColor,
    required this.cursorColor,
    required this.selectionColor,
    required this.hyperlinkColor,
    required this.palette,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.fontPackage,
    required this.letterSpacing,
    required this.padding,
    required this.selection,
  });

  final int revision;
  final String title;
  final GhosttyTerminalSnapshot snapshot;
  final bool running;
  final bool focused;
  final int cols;
  final int rows;
  final int scrollOffsetLines;
  final int visibleStartLine;
  final double charWidth;
  final double linePixels;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color chromeColor;
  final Color cursorColor;
  final Color selectionColor;
  final Color hyperlinkColor;
  final GhosttyTerminalPalette palette;
  final double fontSize;
  final String fontFamily;
  final List<String>? fontFamilyFallback;
  final String? fontPackage;
  final double letterSpacing;
  final EdgeInsets padding;
  final GhosttyTerminalSelection? selection;

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
    )..layout(maxWidth: size.width - 140);
    titlePainter.paint(canvas, const Offset(22, 7));

    final status =
        '${cols}x$rows${scrollOffsetLines > 0 ? '  +$scrollOffsetLines' : ''}';
    final statusPainter = TextPainter(
      text: TextSpan(
        text: status,
        style: TextStyle(
          color: foregroundColor.withValues(alpha: 0.68),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 100);
    statusPainter.paint(
      canvas,
      Offset(size.width - statusPainter.width - 12, 8),
    );

    final contentTop = headerHeight + padding.top;
    final contentHeight = size.height - contentTop - padding.bottom;
    if (contentHeight <= 0) {
      return;
    }

    final maxVisible = math.max(1, (contentHeight / linePixels).floor());
    final maxOffset = math.max(0, snapshot.lines.length - maxVisible);
    final offset = scrollOffsetLines.clamp(0, maxOffset);
    final end = math.max(0, snapshot.lines.length - offset);
    final start = math.max(0, end - maxVisible);
    final visible = snapshot.lines.sublist(start, end);
    final contentRect = Rect.fromLTWH(
      padding.left,
      contentTop,
      size.width - padding.horizontal,
      contentHeight,
    );

    canvas.save();
    canvas.clipRect(contentRect);
    var y = contentTop;
    for (var visibleIndex = 0; visibleIndex < visible.length; visibleIndex++) {
      final line = visible[visibleIndex];
      if (y > size.height) {
        break;
      }

      final row = start + visibleIndex;
      var x = padding.left;
      for (final run in line.runs) {
        final style = _ResolvedTerminalStyle.fromRun(
          run.style,
          palette: palette,
          defaultForeground: foregroundColor,
          defaultBackground: backgroundColor,
          hyperlinkColor: hyperlinkColor,
        );
        final width = run.cells * charWidth;
        if (style.background.a > 0) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, width, linePixels),
            Paint()..color = style.background,
          );
        }
        x += width;
      }

      _paintSelection(canvas, line: line, row: row, y: y);

      x = padding.left;
      for (final run in line.runs) {
        final style = _ResolvedTerminalStyle.fromRun(
          run.style,
          palette: palette,
          defaultForeground: foregroundColor,
          defaultBackground: backgroundColor,
          hyperlinkColor: hyperlinkColor,
        );
        final textStyle = style.toTextStyle(
          fontSize: fontSize,
          lineHeight: linePixels / fontSize,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontPackage: fontPackage,
          letterSpacing: letterSpacing,
        );
        var textX = x;
        final graphemes = _splitTerminalCells(run.text).toList(growable: false);
        final cellWidths = _measureTerminalCellWidths(run.text, run.cells);
        for (var index = 0; index < graphemes.length; index++) {
          final character = graphemes[index];
          final widthCells = cellWidths[index];
          final width = widthCells * charWidth;
          final painter = TextPainter(
            text: TextSpan(text: character, style: textStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout(minWidth: width, maxWidth: width);
          painter.paint(canvas, Offset(textX, y));
          textX += width;
        }
        x += run.cells * charWidth;
      }

      y += linePixels;
    }

    final cursor = snapshot.cursor;
    if (cursor != null) {
      final cursorLine = cursor.row - start;
      if (cursorLine >= 0 && cursorLine < visible.length) {
        final cursorRect = Rect.fromLTWH(
          padding.left + (cursor.col * charWidth),
          contentTop + (cursorLine * linePixels),
          charWidth,
          linePixels,
        );
        if (focused) {
          canvas.drawRect(
            cursorRect,
            Paint()..color = cursorColor.withValues(alpha: 0.78),
          );
        }
        canvas.drawRect(
          cursorRect.deflate(0.5),
          Paint()
            ..color = cursorColor.withValues(alpha: focused ? 1 : 0.88)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.restore();

    if (focused) {
      final focusPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF2A83FF);
      canvas.drawRect(fullRect.deflate(0.5), focusPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GhosttyTerminalPainter oldDelegate) {
    return revision != oldDelegate.revision ||
        title != oldDelegate.title ||
        running != oldDelegate.running ||
        focused != oldDelegate.focused ||
        cols != oldDelegate.cols ||
        rows != oldDelegate.rows ||
        scrollOffsetLines != oldDelegate.scrollOffsetLines ||
        visibleStartLine != oldDelegate.visibleStartLine ||
        charWidth != oldDelegate.charWidth ||
        linePixels != oldDelegate.linePixels ||
        fontSize != oldDelegate.fontSize ||
        fontFamily != oldDelegate.fontFamily ||
        !listEquals(fontFamilyFallback, oldDelegate.fontFamilyFallback) ||
        fontPackage != oldDelegate.fontPackage ||
        letterSpacing != oldDelegate.letterSpacing ||
        padding != oldDelegate.padding ||
        backgroundColor != oldDelegate.backgroundColor ||
        foregroundColor != oldDelegate.foregroundColor ||
        chromeColor != oldDelegate.chromeColor ||
        cursorColor != oldDelegate.cursorColor ||
        selectionColor != oldDelegate.selectionColor ||
        hyperlinkColor != oldDelegate.hyperlinkColor ||
        palette != oldDelegate.palette ||
        selection != oldDelegate.selection ||
        !listEquals(snapshot.lines, oldDelegate.snapshot.lines) ||
        snapshot.cursor != oldDelegate.snapshot.cursor;
  }

  void _paintSelection(
    Canvas canvas, {
    required GhosttyTerminalLine line,
    required int row,
    required double y,
  }) {
    final selection = this.selection;
    if (selection == null || line.cellCount == 0) {
      return;
    }
    final normalized = selection.normalized;
    if (row < normalized.start.row || row > normalized.end.row) {
      return;
    }

    final startCol = row == normalized.start.row ? normalized.start.col : 0;
    final endCol = row == normalized.end.row
        ? normalized.end.col
        : line.cellCount - 1;
    if (endCol < startCol) {
      return;
    }
    final left = padding.left + (startCol * charWidth);
    final width = (endCol - startCol + 1) * charWidth;
    canvas.drawRect(
      Rect.fromLTWH(left, y, width, linePixels),
      Paint()..color = selectionColor,
    );
  }
}

class _TerminalMetrics {
  const _TerminalMetrics({required this.charWidth, required this.linePixels});

  final double charWidth;
  final double linePixels;
}

class _TerminalViewport {
  const _TerminalViewport({
    required this.startLine,
    required this.contentTop,
    required this.contentHeight,
    required this.maxVisible,
  });

  final int startLine;
  final double contentTop;
  final double contentHeight;
  final int maxVisible;
}

final class _ResolvedTerminalStyle {
  const _ResolvedTerminalStyle({
    required this.foreground,
    required this.background,
    required this.decoration,
    required this.decorationStyle,
    required this.decorationColor,
    required this.fontWeight,
    required this.fontStyle,
  });

  factory _ResolvedTerminalStyle.fromRun(
    GhosttyTerminalStyle style, {
    required GhosttyTerminalPalette palette,
    required Color defaultForeground,
    required Color defaultBackground,
    required Color hyperlinkColor,
  }) {
    final baseForeground = palette.resolve(
      style.foreground,
      fallback: defaultForeground,
    );
    final baseBackground = style.background == null
        ? Colors.transparent
        : palette.resolve(style.background, fallback: defaultBackground);
    var foreground = baseForeground;
    var background = baseBackground;

    if (style.inverse) {
      foreground = baseBackground == Colors.transparent
          ? defaultBackground
          : baseBackground;
      background = style.foreground == null
          ? defaultForeground
          : baseForeground;
    }

    if (style.invisible) {
      foreground = background == Colors.transparent
          ? defaultBackground
          : background;
    }
    if (style.faint) {
      foreground = foreground.withValues(alpha: 0.72);
    }
    if (style.hyperlink != null && style.foreground == null) {
      foreground = hyperlinkColor;
    }

    final decorations = <TextDecoration>[];
    final underline = style.underline;
    if (underline != null &&
        underline != GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE) {
      decorations.add(TextDecoration.underline);
    }
    if (style.hyperlink != null &&
        (underline == null ||
            underline == GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_NONE)) {
      decorations.add(TextDecoration.underline);
    }
    if (style.overline) {
      decorations.add(TextDecoration.overline);
    }
    if (style.strikethrough) {
      decorations.add(TextDecoration.lineThrough);
    }

    return _ResolvedTerminalStyle(
      foreground: foreground,
      background: background,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      decorationStyle: switch (underline) {
        GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DOUBLE =>
          TextDecorationStyle.double,
        GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_CURLY =>
          TextDecorationStyle.wavy,
        GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DOTTED =>
          TextDecorationStyle.dotted,
        GhosttySgrUnderline.GHOSTTY_SGR_UNDERLINE_DASHED =>
          TextDecorationStyle.dashed,
        _ => TextDecorationStyle.solid,
      },
      decorationColor: palette.resolve(
        style.underlineColor,
        fallback: foreground,
      ),
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    );
  }

  final Color foreground;
  final Color background;
  final TextDecoration decoration;
  final TextDecorationStyle decorationStyle;
  final Color decorationColor;
  final FontWeight fontWeight;
  final FontStyle fontStyle;

  TextStyle toTextStyle({
    required double fontSize,
    required double lineHeight,
    required String fontFamily,
    required List<String>? fontFamilyFallback,
    required String? fontPackage,
    required double letterSpacing,
  }) {
    return TextStyle(
      color: foreground,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      package: fontPackage,
      fontSize: fontSize,
      height: lineHeight,
      letterSpacing: letterSpacing,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationStyle: decorationStyle,
      decorationColor: decorationColor,
    );
  }
}

Iterable<String> _splitTerminalCells(String text) sync* {
  if (text.isEmpty) {
    return;
  }
  yield* text.characters;
}

List<int> _measureTerminalCellWidths(String text, int totalCells) {
  final graphemes = _splitTerminalCells(text).toList(growable: false);
  if (graphemes.isEmpty) {
    return const <int>[];
  }

  if (totalCells <= 0) {
    return List<int>.filled(graphemes.length, 1, growable: false);
  }

  final widths = List<int>.filled(graphemes.length, 1, growable: false);
  var delta = totalCells - widths.fold(0, (sum, value) => sum + value);
  if (delta > 0) {
    final growOrder = <int>[for (var i = 0; i < widths.length; i++) i];
    var cursor = 0;
    while (delta > 0 && growOrder.isNotEmpty) {
      final index = growOrder[cursor % growOrder.length];
      widths[index]++;
      delta--;
      cursor++;
    }
  } else if (delta < 0) {
    final shrinkOrder = <int>[
      for (var i = widths.length - 1; i >= 0; i--)
        if (widths[i] > 1) i,
      for (var i = widths.length - 1; i >= 0; i--)
        if (widths[i] == 1) i,
    ];
    var cursor = 0;
    while (delta < 0 && shrinkOrder.isNotEmpty) {
      final index = shrinkOrder[cursor % shrinkOrder.length];
      if (widths[index] > 1) {
        widths[index]--;
        delta++;
      }
      cursor++;
      if (cursor > shrinkOrder.length * 4) {
        break;
      }
    }
  }

  return widths;
}
