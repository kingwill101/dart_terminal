library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart' as gvf;
import 'package:ultraviolet/ultraviolet.dart' as uv;

import 'terminal_colors.dart';
import 'terminal_controller.dart';
import 'terminal_selection.dart';

/// Interactive terminal widget backed by UV cell rendering.
class GhosttyUvTerminalView extends StatefulWidget {
  const GhosttyUvTerminalView({
    required this.controller,
    super.key,
    this.autofocus = false,
    this.focusNode,
    this.palette = GhosttyUvTerminalPalette.xterm,
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontPackage,
    this.fontSize = 14,
    this.lineHeight = 1.25,
    this.letterSpacing = 0,
    this.cellWidthScale = 1,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.selectionColor,
    this.copyOptions = const GhosttyUvTerminalCopyOptions(),
    this.wordBoundaryPolicy = const GhosttyUvWordBoundaryPolicy(),
    this.selectionAutoScrollEdgeInset = 24,
    this.onSelectionChanged,
    this.onSelectionContentChanged,
    this.onCopySelection,
    this.onPasteRequest,
    this.onOpenHyperlink,
  });

  final GhosttyUvTerminalController controller;
  final bool autofocus;
  final FocusNode? focusNode;
  final GhosttyUvTerminalPalette palette;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final String? fontPackage;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double cellWidthScale;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Color? selectionColor;
  final GhosttyUvTerminalCopyOptions copyOptions;
  final GhosttyUvWordBoundaryPolicy wordBoundaryPolicy;
  final double selectionAutoScrollEdgeInset;
  final ValueChanged<GhosttyUvTerminalSelection?>? onSelectionChanged;
  final ValueChanged<GhosttyUvTerminalSelectionContent?>?
  onSelectionContentChanged;
  final Future<void> Function(String text)? onCopySelection;
  final Future<String?> Function()? onPasteRequest;
  final Future<void> Function(String uri)? onOpenHyperlink;

  @override
  State<GhosttyUvTerminalView> createState() => _GhosttyUvTerminalViewState();
}

class _GhosttyUvTerminalViewState extends State<GhosttyUvTerminalView> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  int _lastRows = -1;
  int _lastCols = -1;
  int _scrollOffsetLines = 0;
  Offset? _pendingDoubleTapLocalPosition;
  final gvf.GhosttyTerminalSelectionSession<GhosttyUvTerminalSelection>
  _selectionSession =
      gvf.GhosttyTerminalSelectionSession<GhosttyUvTerminalSelection>();
  final gvf.GhosttyTerminalAutoScrollSession<_TerminalMetrics>
  _autoScrollSession = gvf.GhosttyTerminalAutoScrollSession<_TerminalMetrics>();
  late final gvf.GhosttyTerminalGestureCoordinator<
    GhosttyUvTerminalCellPosition,
    GhosttyUvTerminalSelection
  >
  _gestureCoordinator =
      gvf.GhosttyTerminalGestureCoordinator<
        GhosttyUvTerminalCellPosition,
        GhosttyUvTerminalSelection
      >(_selectionSession);

  GhosttyUvTerminalSelection? get _selection => _selectionSession.selection;
  String? get _hoveredHyperlink => _selectionSession.hoveredHyperlink;
  int? get _lineSelectionAnchorRow => _selectionSession.lineSelectionAnchorRow;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant GhosttyUvTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastRows = -1;
      _lastCols = -1;
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
      gvf.ghosttyTerminalNotifySelectionContent<GhosttyUvTerminalSelection>(
        selection: _selection,
        resolveText: _selectionTextFor,
        onSelectionContentChanged: widget.onSelectionContentChanged,
      );
    }
  }

  @override
  void dispose() {
    _stopSelectionAutoScroll(clearDragState: true);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final modifiers = gvf.GhosttyTerminalModifierState.fromHardwareKeyboard();

    if (gvf.ghosttyTerminalMatchesClearSelectionShortcut(
          event.logicalKey,
          modifiers: modifiers,
        ) &&
        _selection != null) {
      _setSelection(null);
      return KeyEventResult.handled;
    }

    if (gvf.ghosttyTerminalMatchesCopyShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      final selectedText = _selectionText();
      if (selectedText.isNotEmpty) {
        unawaited(_copySelection(selectedText));
        return KeyEventResult.handled;
      }
    }

    if (gvf.ghosttyTerminalMatchesPasteShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    if (gvf.ghosttyTerminalMatchesHalfPageScrollShortcut(
      event.logicalKey,
      modifiers: modifiers,
      upward: true,
    )) {
      _applyScrollDelta((widget.controller.rows / 2).ceil());
      return KeyEventResult.handled;
    }
    if (gvf.ghosttyTerminalMatchesHalfPageScrollShortcut(
      event.logicalKey,
      modifiers: modifiers,
      upward: false,
    )) {
      _applyScrollDelta(-(widget.controller.rows / 2).ceil());
      return KeyEventResult.handled;
    }

    if (gvf.ghosttyTerminalMatchesSelectAllShortcut(
      event.logicalKey,
      modifiers: modifiers,
      platform: defaultTargetPlatform,
    )) {
      final selection = widget.controller.screen.selectAllSelection();
      if (selection != null) {
        _setSelection(selection);
        return KeyEventResult.handled;
      }
    }

    final key = _mapFlutterKey(event, modifiers);
    if (key == null) {
      return KeyEventResult.ignored;
    }

    if (_scrollOffsetLines != 0) {
      setState(() {
        _scrollOffsetLines = 0;
      });
    }

    return widget.controller.sendKey(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  uv.Key? _mapFlutterKey(
    KeyEvent event,
    gvf.GhosttyTerminalModifierState modifiers,
  ) {
    final logicalKey = event.logicalKey;
    final code = _mapLogicalKey(logicalKey);
    final character = gvf.ghosttyTerminalPrintableText(
      event,
      modifiers: modifiers,
    );
    final uvMods = _mapModifierStateToUv(modifiers);

    if (code == null) {
      if (character.isEmpty) {
        return null;
      }
      final codePoint = character.runes.first;
      return uv.Key(code: codePoint, text: character, mod: uvMods);
    }

    final useText =
        character.isNotEmpty &&
        !_namedKeys.contains(logicalKey) &&
        !modifiers.controlPressed &&
        !modifiers.metaPressed &&
        !modifiers.altPressed;

    return uv.Key(code: code, text: useText ? character : '', mod: uvMods);
  }

  int _mapModifierStateToUv(gvf.GhosttyTerminalModifierState modifiers) {
    var mods = 0;
    if (modifiers.shiftPressed) {
      mods |= uv.KeyMod.shift;
    }
    if (modifiers.controlPressed) {
      mods |= uv.KeyMod.ctrl;
    }
    if (modifiers.altPressed) {
      mods |= uv.KeyMod.alt;
    }
    if (modifiers.metaPressed) {
      mods |= uv.KeyMod.meta;
    }
    return mods;
  }

  Future<void> _copySelection(String text) async {
    await gvf.ghosttyTerminalCopyText(
      text,
      onCopySelection: widget.onCopySelection,
    );
  }

  Future<void> _pasteClipboard() async {
    final text = await gvf.ghosttyTerminalReadPasteText(
      onPasteRequest: widget.onPasteRequest,
    );
    if (text == null || text.isEmpty) {
      return;
    }
    if (_scrollOffsetLines != 0 && mounted) {
      setState(() {
        _scrollOffsetLines = 0;
      });
    }
    widget.controller.paste(text);
  }

  String _selectionText() {
    final selection = _selection;
    if (selection == null) {
      return '';
    }
    return _selectionTextFor(selection);
  }

  String _selectionTextFor(GhosttyUvTerminalSelection selection) {
    return widget.controller.screen.textForSelection(
      selection,
      options: widget.copyOptions,
    );
  }

  void _setSelection(
    GhosttyUvTerminalSelection? selection, {
    int? scrollOffsetLines,
  }) {
    final nextScrollOffset = scrollOffsetLines ?? _scrollOffsetLines;
    final previousSelection = _selection;
    if (!_selectionSession.updateSelection(selection) &&
        _scrollOffsetLines == nextScrollOffset) {
      return;
    }

    final selectionChanged = previousSelection != _selection;
    setState(() {
      _scrollOffsetLines = nextScrollOffset;
    });
    if (selectionChanged) {
      gvf.ghosttyTerminalNotifySelectionChange<GhosttyUvTerminalSelection>(
        previousSelection: previousSelection,
        nextSelection: _selection,
        resolveText: _selectionTextFor,
        onSelectionChanged: widget.onSelectionChanged,
        onSelectionContentChanged: widget.onSelectionContentChanged,
      );
    }
  }

  void _applyScrollDelta(int lines) {
    final screen = widget.controller.screen;
    final next = (_scrollOffsetLines + lines).clamp(0, screen.maxScrollOffset);
    if (next == _scrollOffsetLines) {
      return;
    }
    setState(() {
      _scrollOffsetLines = next;
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final metrics = _autoScrollSession.metrics;
    if (metrics == null) {
      return;
    }
    final lines = (event.scrollDelta.dy / metrics.cellHeight).round();
    if (lines == 0) {
      return;
    }
    _applyScrollDelta(lines);
  }

  void _beginSelection(Offset localPosition) {
    _focusNode.requestFocus();
    final position = _positionForLocalOffset(
      localPosition,
      clampToViewport: true,
    );
    final selection = _gestureCoordinator.beginSelection(
      position: position,
      collapsedSelection: (position) =>
          GhosttyUvTerminalSelection(anchor: position, extent: position),
    );
    if (selection == null) {
      return;
    }
    _setSelection(selection);
    _updateSelectionAutoScroll(localPosition);
  }

  void _handlePanStart(DragStartDetails details) {
    _focusNode.requestFocus();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    _updateSelectionAutoScroll(details.localPosition);
    final position = _positionForLocalOffset(
      details.localPosition,
      clampToViewport: true,
    );
    final nextSelection = _gestureCoordinator.updateSelection(
      currentSelection: _selection,
      position: position,
      extendSelection: (currentSelection, position) =>
          GhosttyUvTerminalSelection(
            anchor: currentSelection.anchor,
            extent: position,
          ),
      extendLineSelection: (anchorRow, position) => widget.controller.screen
          .lineSelectionBetweenAbsoluteRows(anchorRow, position.row),
    );
    if (nextSelection == null) {
      return;
    }
    if (_selection?.extent == position) {
      return;
    }
    _setSelection(nextSelection);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _stopSelectionAutoScroll();
    _focusNode.requestFocus();
    final position = _positionForLocalOffset(
      details.localPosition,
      clampToViewport: true,
    );
    final selection = _gestureCoordinator.beginLineSelection(
      position: position,
      rowOfPosition: (position) => position.row,
      resolveLineSelection: (position) => widget.controller.screen
          .lineSelectionBetweenAbsoluteRows(position.row, position.row),
    );
    if (selection == null) {
      return;
    }
    _setSelection(selection);
    _updateSelectionAutoScroll(details.localPosition);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final anchorRow = _lineSelectionAnchorRow;
    if (anchorRow == null) {
      return;
    }
    _updateSelectionAutoScroll(details.localPosition);
    final position = _positionForLocalOffset(
      details.localPosition,
      clampToViewport: true,
    );
    if (position == null) {
      return;
    }
    final selection = widget.controller.screen.lineSelectionBetweenAbsoluteRows(
      anchorRow,
      position.row,
    );
    if (selection == null) {
      return;
    }
    _setSelection(selection);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _stopSelectionAutoScroll(clearDragState: true);
  }

  void _handlePanEnd(DragEndDetails details) {
    _stopSelectionAutoScroll(clearDragState: true);
  }

  void _handlePanCancel() {
    _stopSelectionAutoScroll(clearDragState: true);
  }

  void _updateSelectionAutoScroll(Offset localPosition) {
    _autoScrollSession.updateDragPosition(localPosition);
    final size = _autoScrollSession.layoutSize;
    if (size == null) {
      _stopSelectionAutoScroll();
      return;
    }

    final topEdge = widget.padding.top + widget.selectionAutoScrollEdgeInset;
    final bottomEdge =
        size.height -
        widget.padding.bottom -
        widget.selectionAutoScrollEdgeInset;

    var direction = 0;
    if (localPosition.dy < topEdge) {
      direction = 1;
    } else if (localPosition.dy > bottomEdge) {
      direction = -1;
    }

    if (direction == 0) {
      _stopSelectionAutoScroll();
      return;
    }

    _autoScrollSession.updateDirection(direction);
    _autoScrollSession.ensureTimer(
      const Duration(milliseconds: 32),
      _tickSelectionAutoScroll,
    );
  }

  void _tickSelectionAutoScroll() {
    final selection = _selection;
    final dragPosition = _autoScrollSession.dragPosition;
    final size = _autoScrollSession.layoutSize;
    final metrics = _autoScrollSession.metrics;
    if (selection == null ||
        dragPosition == null ||
        size == null ||
        metrics == null) {
      _stopSelectionAutoScroll();
      return;
    }

    final contentTop = widget.padding.top;
    final contentBottom = size.height - widget.padding.bottom;
    final overflow = _autoScrollSession.direction > 0
        ? math.max(0, contentTop - dragPosition.dy)
        : math.max(0, dragPosition.dy - contentBottom);
    final lineDelta = math.min(
      4,
      math.max(1, (overflow / metrics.cellHeight).ceil()),
    );
    final nextScrollOffset =
        (_scrollOffsetLines + (_autoScrollSession.direction * lineDelta)).clamp(
          0,
          widget.controller.screen.maxScrollOffset,
        );
    final position = _positionForLocalOffset(
      dragPosition,
      clampToViewport: true,
      scrollOffsetOverride: nextScrollOffset,
    );
    if (position == null) {
      _stopSelectionAutoScroll();
      return;
    }
    final lineSelectionAnchorRow = _lineSelectionAnchorRow;
    final nextSelection = lineSelectionAnchorRow == null
        ? GhosttyUvTerminalSelection(anchor: selection.anchor, extent: position)
        : widget.controller.screen.lineSelectionBetweenAbsoluteRows(
            lineSelectionAnchorRow,
            position.row,
          );
    if (nextSelection == null) {
      _stopSelectionAutoScroll();
      return;
    }
    if (nextScrollOffset == _scrollOffsetLines && selection == nextSelection) {
      _stopSelectionAutoScroll();
      return;
    }
    _setSelection(nextSelection, scrollOffsetLines: nextScrollOffset);
  }

  void _stopSelectionAutoScroll({bool clearDragState = false}) {
    _autoScrollSession.stop();
    if (clearDragState) {
      _selectionSession.clearLineSelectionAnchorRow();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _stopSelectionAutoScroll(clearDragState: true);
    _focusNode.requestFocus();
    final position = _positionForLocalOffset(details.localPosition);
    final resolution = gvf
        .ghosttyTerminalResolveTap<
          GhosttyUvTerminalCellPosition,
          GhosttyUvTerminalSelection
        >(
          session: _selectionSession,
          selection: _selection,
          position: position,
          resolveUri: (position) => widget.controller.screen
              .linkAtAbsolutePosition(position.row, position.column)
              ?.url,
        );
    if (resolution.hyperlink case final hyperlink?) {
      unawaited(
        gvf.ghosttyTerminalOpenHyperlink(
          hyperlink,
          onOpenHyperlink: widget.onOpenHyperlink,
        ),
      );
      return;
    }
    if (resolution.clearSelection) {
      _setSelection(null);
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _selectionSession.armIgnoreNextTapClear();
    _pendingDoubleTapLocalPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    _stopSelectionAutoScroll(clearDragState: true);
    _focusNode.requestFocus();
    final localPosition = _pendingDoubleTapLocalPosition;
    _pendingDoubleTapLocalPosition = null;
    final position = localPosition == null
        ? null
        : _positionForLocalOffset(localPosition);
    final selection = _gestureCoordinator.completeWordSelection(
      position: position,
      resolveWordSelection: (position) =>
          widget.controller.screen.wordSelectionAtAbsolutePosition(
            position.row,
            position.column,
            wordBoundaryPolicy: widget.wordBoundaryPolicy,
          ),
    );
    if (selection == null) {
      return;
    }
    _setSelection(selection);
  }

  void _handleHover(PointerHoverEvent event) {
    final position = _positionForLocalOffset(event.localPosition);
    if (!gvf.ghosttyTerminalUpdateHoveredLink<
      GhosttyUvTerminalCellPosition,
      GhosttyUvTerminalSelection
    >(
      session: _selectionSession,
      position: position,
      resolveUri: (position) => widget.controller.screen
          .linkAtAbsolutePosition(position.row, position.column)
          ?.url,
    )) {
      return;
    }
    setState(() {});
  }

  void _handleExit(PointerExitEvent _) {
    if (!gvf.ghosttyTerminalClearHoveredLink<GhosttyUvTerminalSelection>(
      session: _selectionSession,
    )) {
      return;
    }
    setState(() {});
  }

  GhosttyUvTerminalCellPosition? _positionForLocalOffset(
    Offset localPosition, {
    bool clampToViewport = false,
    int? scrollOffsetOverride,
  }) {
    final metrics = _autoScrollSession.metrics;
    final size = _autoScrollSession.layoutSize;
    if (metrics == null || size == null) {
      return null;
    }

    final maxWidth = size.width - widget.padding.horizontal;
    final maxHeight = size.height - widget.padding.vertical;
    if (maxWidth <= 0 || maxHeight <= 0) {
      return null;
    }

    var x = localPosition.dx - widget.padding.left;
    var y = localPosition.dy - widget.padding.top;
    if (clampToViewport) {
      x = x.clamp(0, maxWidth - 0.001);
      y = y.clamp(0, maxHeight - 0.001);
    } else if (x < 0 || y < 0 || x >= maxWidth || y >= maxHeight) {
      return null;
    }

    final visibleColumn = (x / metrics.cellWidth).floor().clamp(
      0,
      widget.controller.cols - 1,
    );
    final visibleRow = (y / metrics.cellHeight).floor().clamp(
      0,
      widget.controller.rows - 1,
    );
    final scrollOffset = scrollOffsetOverride ?? _scrollOffsetLines;
    final absoluteRow = widget.controller.screen.absoluteRowForVisibleRow(
      visibleRow,
      scrollOffset: scrollOffset,
    );
    final absoluteColumn = widget.controller.screen.normalizeVisibleColumn(
      visibleRow,
      visibleColumn,
      scrollOffset: scrollOffset,
    );

    return GhosttyUvTerminalCellPosition(
      row: absoluteRow,
      column: absoluteColumn,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_scrollOffsetLines > widget.controller.screen.maxScrollOffset) {
      _scrollOffsetLines = widget.controller.screen.maxScrollOffset;
    }

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Focus(
          autofocus: widget.autofocus,
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: MouseRegion(
            cursor: _hoveredHyperlink != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.text,
            onHover: _handleHover,
            onExit: _handleExit,
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _focusNode.requestFocus,
                onTapUp: _handleTapUp,
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: _handleDoubleTap,
                onLongPressStart: _handleLongPressStart,
                onLongPressMoveUpdate: _handleLongPressMoveUpdate,
                onLongPressEnd: _handleLongPressEnd,
                onPanDown: (details) => _beginSelection(details.localPosition),
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                onPanCancel: _handlePanCancel,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = _measureMetrics(context);
                    _autoScrollSession.updateLayout(
                      layoutSize: constraints.biggest,
                      metrics: metrics,
                    );
                    _scheduleResize(constraints.biggest, metrics);

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.palette.defaultBackground,
                        borderRadius: widget.borderRadius,
                        border: Border.all(color: const Color(0xFF1E2A34)),
                      ),
                      child: ClipRRect(
                        borderRadius: widget.borderRadius,
                        child: CustomPaint(
                          painter: _GhosttyUvTerminalPainter(
                            controller: widget.controller,
                            palette: widget.palette,
                            metrics: metrics,
                            textStyle: _textStyle(context),
                            padding: widget.padding,
                            scrollOffsetLines: _scrollOffsetLines,
                            selection: _selection,
                            selectionColor:
                                widget.selectionColor ??
                                widget.palette.selectionColor,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _textStyle(BuildContext context) {
    return DefaultTextStyle.of(context).style.copyWith(
      fontFamily: widget.fontFamily,
      fontFamilyFallback: widget.fontFamilyFallback,
      package: widget.fontPackage,
      fontSize: widget.fontSize,
      height: widget.lineHeight,
      letterSpacing: widget.letterSpacing,
      color: widget.palette.defaultForeground,
    );
  }

  _TerminalMetrics _measureMetrics(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'W', style: _textStyle(context)),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = math.max(1.0, painter.width * widget.cellWidthScale);
    final height = math.max(1.0, painter.height);
    painter.dispose();
    return _TerminalMetrics(cellWidth: width, cellHeight: height);
  }

  void _scheduleResize(Size size, _TerminalMetrics metrics) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final usableWidth = math.max(0, size.width - widget.padding.horizontal);
    final usableHeight = math.max(0, size.height - widget.padding.vertical);
    final cols = math.max(1, (usableWidth / metrics.cellWidth).floor());
    final rows = math.max(1, (usableHeight / metrics.cellHeight).floor());
    if (cols == _lastCols && rows == _lastRows) {
      return;
    }
    _lastCols = cols;
    _lastRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.controller.resize(rows: rows, cols: cols);
    });
  }
}

final class _TerminalMetrics {
  const _TerminalMetrics({required this.cellWidth, required this.cellHeight});

  final double cellWidth;
  final double cellHeight;
}

final class _GhosttyUvTerminalPainter extends CustomPainter {
  const _GhosttyUvTerminalPainter({
    required this.controller,
    required this.palette,
    required this.metrics,
    required this.textStyle,
    required this.padding,
    required this.scrollOffsetLines,
    required this.selection,
    required this.selectionColor,
  });

  final GhosttyUvTerminalController controller;
  final GhosttyUvTerminalPalette palette;
  final _TerminalMetrics metrics;
  final TextStyle textStyle;
  final EdgeInsets padding;
  final int scrollOffsetLines;
  final GhosttyUvTerminalSelection? selection;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = controller.screen;
    final bgPaint = Paint()..color = palette.defaultBackground;
    canvas.drawRect(Offset.zero & size, bgPaint);
    canvas.save();
    canvas.translate(padding.left, padding.top);

    for (var visibleRow = 0; visibleRow < screen.rows; visibleRow++) {
      final absoluteRow = screen.absoluteRowForVisibleRow(
        visibleRow,
        scrollOffset: scrollOffsetLines,
      );
      final line = screen.visibleLine(
        visibleRow,
        scrollOffset: scrollOffsetLines,
      );
      if (line == null) {
        continue;
      }

      for (var x = 0; x < screen.cols; x++) {
        final cell = line.at(x);
        if (cell == null || cell.isZero) {
          continue;
        }

        final style = cell.style;
        final reverse = (style.attrs & uv.Attr.reverse) != 0;
        var foreground = palette.resolve(style.fg, palette.defaultForeground);
        var background = palette.resolve(style.bg, palette.defaultBackground);
        if (cell.link.url.isNotEmpty) {
          foreground = palette.resolve(style.fg, const Color(0xFF61AFEF));
        }
        if (reverse) {
          final swap = foreground;
          foreground = background;
          background = swap;
        }
        if ((style.attrs & uv.Attr.faint) != 0) {
          foreground = foreground.withAlpha(160);
        }

        final cellWidth = math.max(1, cell.width);
        final rect = Rect.fromLTWH(
          x * metrics.cellWidth,
          visibleRow * metrics.cellHeight,
          metrics.cellWidth * cellWidth,
          metrics.cellHeight,
        );
        canvas.drawRect(rect, Paint()..color = background);

        final currentSelection = selection;
        if (currentSelection != null &&
            currentSelection.intersectsSpan(
              absoluteRow,
              x,
              x + cellWidth - 1,
            )) {
          canvas.drawRect(rect, Paint()..color = selectionColor);
        }

        if (cell.content.isEmpty || cell.content == ' ') {
          continue;
        }
        if ((style.attrs & uv.Attr.conceal) != 0) {
          continue;
        }

        final paragraphStyle = ui.ParagraphStyle(
          textDirection: TextDirection.ltr,
          maxLines: 1,
        );
        final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
          ..pushStyle(
            textStyle
                .copyWith(
                  color: foreground,
                  fontWeight: (style.attrs & uv.Attr.bold) != 0
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontStyle: (style.attrs & uv.Attr.italic) != 0
                      ? FontStyle.italic
                      : FontStyle.normal,
                  decoration: _textDecoration(cell),
                  decorationColor: style.underlineColor != null
                      ? palette.resolve(style.underlineColor, foreground)
                      : foreground,
                )
                .getTextStyle(),
          )
          ..addText(cell.content);
        final paragraph = paragraphBuilder.build()
          ..layout(ui.ParagraphConstraints(width: rect.width));
        final dy = rect.top + (metrics.cellHeight - paragraph.height) / 2;
        canvas.drawParagraph(paragraph, Offset(rect.left, dy));
      }
    }

    if (scrollOffsetLines == 0 && screen.cursorVisible) {
      final cursorRect = Rect.fromLTWH(
        screen.cursorX * metrics.cellWidth,
        screen.cursorY * metrics.cellHeight,
        metrics.cellWidth,
        metrics.cellHeight,
      );
      canvas.drawRect(
        cursorRect,
        Paint()..color = palette.cursorColor.withAlpha(179),
      );
    }

    canvas.restore();
  }

  TextDecoration? _textDecoration(uv.Cell cell) {
    final style = cell.style;
    final underline = style.underline != uv.UnderlineStyle.none;
    final strike = (style.attrs & uv.Attr.strikethrough) != 0;
    if (underline && strike) {
      return TextDecoration.combine(const <TextDecoration>[
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    }
    if (underline || cell.link.url.isNotEmpty) {
      return TextDecoration.underline;
    }
    if (strike) {
      return TextDecoration.lineThrough;
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _GhosttyUvTerminalPainter oldDelegate) {
    return oldDelegate.controller.revision != controller.revision ||
        oldDelegate.metrics != metrics ||
        oldDelegate.palette != palette ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.padding != padding ||
        oldDelegate.scrollOffsetLines != scrollOffsetLines ||
        oldDelegate.selection != selection ||
        oldDelegate.selectionColor != selectionColor;
  }
}

final _namedKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.delete,
  LogicalKeyboardKey.insert,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.end,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

int? _mapLogicalKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.enter) return uv.keyEnter;
  if (key == LogicalKeyboardKey.backspace) return uv.keyBackspace;
  if (key == LogicalKeyboardKey.tab) return uv.keyTab;
  if (key == LogicalKeyboardKey.escape) return uv.keyEscape;
  if (key == LogicalKeyboardKey.space) return uv.keySpace;
  if (key == LogicalKeyboardKey.delete) return uv.keyDelete;
  if (key == LogicalKeyboardKey.insert) return uv.keyInsert;
  if (key == LogicalKeyboardKey.arrowUp) return uv.keyUp;
  if (key == LogicalKeyboardKey.arrowDown) return uv.keyDown;
  if (key == LogicalKeyboardKey.arrowLeft) return uv.keyLeft;
  if (key == LogicalKeyboardKey.arrowRight) return uv.keyRight;
  if (key == LogicalKeyboardKey.home) return uv.keyHome;
  if (key == LogicalKeyboardKey.end) return uv.keyEnd;
  if (key == LogicalKeyboardKey.pageUp) return uv.keyPgUp;
  if (key == LogicalKeyboardKey.pageDown) return uv.keyPgDown;
  if (key == LogicalKeyboardKey.f1) return uv.keyF1;
  if (key == LogicalKeyboardKey.f2) return uv.keyF2;
  if (key == LogicalKeyboardKey.f3) return uv.keyF3;
  if (key == LogicalKeyboardKey.f4) return uv.keyF4;
  if (key == LogicalKeyboardKey.f5) return uv.keyF5;
  if (key == LogicalKeyboardKey.f6) return uv.keyF6;
  if (key == LogicalKeyboardKey.f7) return uv.keyF7;
  if (key == LogicalKeyboardKey.f8) return uv.keyF8;
  if (key == LogicalKeyboardKey.f9) return uv.keyF9;
  if (key == LogicalKeyboardKey.f10) return uv.keyF10;
  if (key == LogicalKeyboardKey.f11) return uv.keyF11;
  if (key == LogicalKeyboardKey.f12) return uv.keyF12;

  final id = key.keyId;
  if (id >= 0x20 && id <= 0x7E) {
    return id;
  }
  return null;
}
