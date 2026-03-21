import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ghostty_vte_bindings_generated.dart' as bindings;

/// High-level helpers and wrappers on top of libghostty-vt FFI bindings.
///
/// Provides factory methods for OSC/SGR parsers, terminals, formatters,
/// key events, and key encoders, as well as paste-safety checks.
///
/// ```dart
/// // Create a terminal and formatter
/// final terminal = GhosttyVt.newTerminal(cols: 80, rows: 24);
/// final formatter = terminal.createFormatter(
///   const VtFormatterTerminalOptions(
///     emit: GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_PLAIN,
///     trim: true,
///   ),
/// );
/// terminal.write('Hello');
/// print(formatter.formatText());
/// formatter.close();
/// terminal.close();
///
/// // Check paste safety
/// if (GhosttyVt.isPasteSafe(clipboardText)) {
///   terminal.write(clipboardText);
/// }
///
/// // Create a key encoder
/// final encoder = GhosttyVt.newKeyEncoder();
/// final event = GhosttyVt.newKeyEvent();
/// // ... configure event ...
/// final bytes = encoder.encode(event);
/// event.close();
/// encoder.close();
/// ```
final class GhosttyVt {
  const GhosttyVt._();

  /// Returns whether [text] is safe to paste into a terminal.
  ///
  /// Checks for dangerous control characters that could execute
  /// unintended commands.
  ///
  /// ```dart
  /// final safe = GhosttyVt.isPasteSafe('ls -la');
  /// assert(safe == true);
  /// ```
  static bool isPasteSafe(String text) {
    final bytes = utf8.encode(text);
    return isPasteSafeBytes(bytes);
  }

  /// Returns whether raw UTF-8 bytes are safe to paste into a terminal.
  static bool isPasteSafeBytes(List<int> bytes) {
    final ptr = calloc<ffi.Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return bindings.ghostty_paste_is_safe(ptr.cast<ffi.Char>(), bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Creates a streaming OSC parser.
  static VtOscParser newOscParser() => VtOscParser();

  /// Creates an SGR parser.
  static VtSgrParser newSgrParser() => VtSgrParser();

  /// Creates a key event object.
  static VtKeyEvent newKeyEvent() => VtKeyEvent();

  /// Creates a key encoder object.
  static VtKeyEncoder newKeyEncoder() => VtKeyEncoder();

  /// Creates a terminal emulator instance.
  static VtTerminal newTerminal({
    required int cols,
    required int rows,
    int maxScrollback = 10_000,
  }) => VtTerminal(cols: cols, rows: rows, maxScrollback: maxScrollback);
}

/// Exception thrown for libghostty-vt operation failures.
///
/// Contains the failed [operation] name and the native [result] code.
final class GhosttyVtError implements Exception {
  GhosttyVtError(this.operation, this.result);

  final String operation;
  final bindings.GhosttyResult result;

  @override
  String toString() {
    return 'GhosttyVtError(operation: $operation, result: $result)';
  }
}

void _checkResult(bindings.GhosttyResult result, String operation) {
  if (result != bindings.GhosttyResult.GHOSTTY_SUCCESS) {
    throw GhosttyVtError(operation, result);
  }
}

int _checkPositiveUint16(int value, String name) {
  if (value < 1 || value > 0xFFFF) {
    throw RangeError.range(value, 1, 0xFFFF, name);
  }
  return value;
}

int _checkNonNegative(int value, String name) {
  if (value < 0) {
    throw RangeError.range(value, 0, null, name);
  }
  return value;
}

typedef _GhosttyAllocatorAllocNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Size len,
      ffi.Uint8 alignment,
      ffi.UintPtr retAddr,
    );

typedef _GhosttyAllocatorResizeNative =
    ffi.Bool Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Pointer<ffi.Void> memory,
      ffi.Size memoryLen,
      ffi.Uint8 alignment,
      ffi.Size newLen,
      ffi.UintPtr retAddr,
    );

typedef _GhosttyAllocatorRemapNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Pointer<ffi.Void> memory,
      ffi.Size memoryLen,
      ffi.Uint8 alignment,
      ffi.Size newLen,
      ffi.UintPtr retAddr,
    );

typedef _GhosttyAllocatorFreeNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Pointer<ffi.Void> memory,
      ffi.Size memoryLen,
      ffi.Uint8 alignment,
      ffi.UintPtr retAddr,
    );

/// Native allocator bridge for advanced libghostty-vt usage.
///
/// `VtAllocator.dartMalloc` uses Dart's `malloc`/`free` underneath and can be
/// passed to raw generated bindings that accept a `GhosttyAllocator*`.
///
/// Most callers should use the higher-level helpers on [VtTerminalFormatter]
/// instead of interacting with this directly.
final class VtAllocator {
  VtAllocator._(this.pointer);

  /// Allocator backed by Dart's `malloc`/`free`.
  static final VtAllocator dartMalloc = VtAllocator._(_create());

  /// Native allocator pointer suitable for generated bindings.
  final ffi.Pointer<bindings.GhosttyAllocator> pointer;

  static ffi.Pointer<bindings.GhosttyAllocator> _create() {
    final vtable = calloc<bindings.GhosttyAllocatorVtable>();
    final allocator = calloc<bindings.GhosttyAllocator>();

    vtable.ref
      ..alloc = ffi.Pointer.fromFunction<_GhosttyAllocatorAllocNative>(_alloc)
      ..resize = ffi.Pointer.fromFunction<_GhosttyAllocatorResizeNative>(
        _resize,
        false,
      )
      ..remap = ffi.Pointer.fromFunction<_GhosttyAllocatorRemapNative>(_remap)
      ..free = ffi.Pointer.fromFunction<_GhosttyAllocatorFreeNative>(_free);

    allocator.ref
      ..ctx = ffi.nullptr
      ..vtable = vtable;

    return allocator;
  }

  static ffi.Pointer<ffi.Void> _alloc(
    ffi.Pointer<ffi.Void> ctx,
    int len,
    int alignment,
    int retAddr,
  ) {
    if (len <= 0) {
      return ffi.nullptr;
    }
    try {
      return malloc
          .allocate<ffi.Uint8>(len, alignment: alignment)
          .cast<ffi.Void>();
    } catch (_) {
      return ffi.nullptr;
    }
  }

  static bool _resize(
    ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.Void> memory,
    int memoryLen,
    int alignment,
    int newLen,
    int retAddr,
  ) {
    return false;
  }

  static ffi.Pointer<ffi.Void> _remap(
    ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.Void> memory,
    int memoryLen,
    int alignment,
    int newLen,
    int retAddr,
  ) {
    final remapped = _alloc(ctx, newLen, alignment, retAddr);
    if (remapped == ffi.nullptr) {
      return ffi.nullptr;
    }

    if (memory != ffi.nullptr && memoryLen > 0) {
      final copyLen = memoryLen < newLen ? memoryLen : newLen;
      remapped
          .cast<ffi.Uint8>()
          .asTypedList(copyLen)
          .setAll(0, memory.cast<ffi.Uint8>().asTypedList(copyLen));
      _free(ctx, memory, memoryLen, alignment, retAddr);
    }

    return remapped;
  }

  static void _free(
    ffi.Pointer<ffi.Void> ctx,
    ffi.Pointer<ffi.Void> memory,
    int memoryLen,
    int alignment,
    int retAddr,
  ) {
    if (memory == ffi.nullptr) {
      return;
    }
    malloc.free(memory);
  }

  /// Copies [len] bytes from [ptr] into Dart-managed memory and frees [ptr].
  Uint8List copyBytesAndFree(ffi.Pointer<ffi.Uint8> ptr, int len) {
    if (ptr == ffi.nullptr || len == 0) {
      if (ptr != ffi.nullptr) {
        freePointer(ptr.cast());
      }
      return Uint8List(0);
    }

    final bytes = Uint8List.fromList(ptr.asTypedList(len));
    freePointer(ptr.cast());
    return bytes;
  }

  /// Frees a pointer allocated by this allocator.
  void freePointer(ffi.Pointer<ffi.Void> ptr) {
    if (ptr == ffi.nullptr) {
      return;
    }
    malloc.free(ptr);
  }
}

/// Bit masks for keyboard modifiers.
///
/// Combine with bitwise OR to represent multiple modifiers.
///
/// ```dart
/// final mods = GhosttyModsMask.ctrl | GhosttyModsMask.shift;
/// event.mods = mods;
/// ```
final class GhosttyModsMask {
  const GhosttyModsMask._();

  static const int shift = bindings.GHOSTTY_MODS_SHIFT;
  static const int ctrl = bindings.GHOSTTY_MODS_CTRL;
  static const int alt = bindings.GHOSTTY_MODS_ALT;
  static const int superKey = bindings.GHOSTTY_MODS_SUPER;
  static const int capsLock = bindings.GHOSTTY_MODS_CAPS_LOCK;
  static const int numLock = bindings.GHOSTTY_MODS_NUM_LOCK;
  static const int shiftSide = bindings.GHOSTTY_MODS_SHIFT_SIDE;
  static const int ctrlSide = bindings.GHOSTTY_MODS_CTRL_SIDE;
  static const int altSide = bindings.GHOSTTY_MODS_ALT_SIDE;
  static const int superSide = bindings.GHOSTTY_MODS_SUPER_SIDE;
}

/// Bit flags for the Kitty keyboard protocol.
///
/// Set on [VtKeyEncoder.kittyFlags] to control encoding behavior.
///
/// ```dart
/// encoder.kittyFlags = GhosttyKittyFlags.disambiguate
///     | GhosttyKittyFlags.reportEvents;
/// ```
final class GhosttyKittyFlags {
  const GhosttyKittyFlags._();

  static const int disabled = bindings.GHOSTTY_KITTY_KEY_DISABLED;
  static const int disambiguate = bindings.GHOSTTY_KITTY_KEY_DISAMBIGUATE;
  static const int reportEvents = bindings.GHOSTTY_KITTY_KEY_REPORT_EVENTS;
  static const int reportAlternates =
      bindings.GHOSTTY_KITTY_KEY_REPORT_ALTERNATES;
  static const int reportAll = bindings.GHOSTTY_KITTY_KEY_REPORT_ALL;
  static const int reportAssociated =
      bindings.GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED;
  static const int all = bindings.GHOSTTY_KITTY_KEY_ALL;
}

/// Named ANSI color indices.
final class GhosttyNamedColor {
  const GhosttyNamedColor._();

  static const int black = bindings.GHOSTTY_COLOR_NAMED_BLACK;
  static const int red = bindings.GHOSTTY_COLOR_NAMED_RED;
  static const int green = bindings.GHOSTTY_COLOR_NAMED_GREEN;
  static const int yellow = bindings.GHOSTTY_COLOR_NAMED_YELLOW;
  static const int blue = bindings.GHOSTTY_COLOR_NAMED_BLUE;
  static const int magenta = bindings.GHOSTTY_COLOR_NAMED_MAGENTA;
  static const int cyan = bindings.GHOSTTY_COLOR_NAMED_CYAN;
  static const int white = bindings.GHOSTTY_COLOR_NAMED_WHITE;
  static const int brightBlack = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_BLACK;
  static const int brightRed = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_RED;
  static const int brightGreen = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_GREEN;
  static const int brightYellow = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_YELLOW;
  static const int brightBlue = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_BLUE;
  static const int brightMagenta = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_MAGENTA;
  static const int brightCyan = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_CYAN;
  static const int brightWhite = bindings.GHOSTTY_COLOR_NAMED_BRIGHT_WHITE;
}

/// RGB color value with 8-bit [r], [g], [b] channels.
///
/// ```dart
/// const red = VtRgbColor(255, 0, 0);
/// print('Red: ${red.r}, Green: ${red.g}, Blue: ${red.b}');
/// ```
final class VtRgbColor {
  const VtRgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  factory VtRgbColor.fromNative(bindings.GhosttyColorRgb native) {
    final r = calloc<ffi.Uint8>();
    final g = calloc<ffi.Uint8>();
    final b = calloc<ffi.Uint8>();
    try {
      bindings.ghostty_color_rgb_get(native, r, g, b);
      return VtRgbColor(r.value, g.value, b.value);
    } finally {
      calloc.free(r);
      calloc.free(g);
      calloc.free(b);
    }
  }

  @override
  String toString() => 'VtRgbColor(r: $r, g: $g, b: $b)';
}

/// Scroll viewport behavior for [VtTerminal.scrollViewport].
final class VtTerminalScrollViewport {
  const VtTerminalScrollViewport._(this._tag, {this.delta = 0});

  /// Scroll to the top of the scrollback.
  const VtTerminalScrollViewport.top()
    : this._(
        bindings.GhosttyTerminalScrollViewportTag.GHOSTTY_SCROLL_VIEWPORT_TOP,
      );

  /// Scroll to the bottom of the active screen.
  const VtTerminalScrollViewport.bottom()
    : this._(
        bindings
            .GhosttyTerminalScrollViewportTag
            .GHOSTTY_SCROLL_VIEWPORT_BOTTOM,
      );

  /// Scroll by [delta] rows. Negative values move up.
  const VtTerminalScrollViewport.delta(int delta)
    : this._(
        bindings.GhosttyTerminalScrollViewportTag.GHOSTTY_SCROLL_VIEWPORT_DELTA,
        delta: delta,
      );

  final bindings.GhosttyTerminalScrollViewportTag _tag;
  final int delta;
}

/// Extra screen state to include in styled formatter output.
final class VtFormatterScreenExtra {
  const VtFormatterScreenExtra({
    this.cursor = false,
    this.style = false,
    this.hyperlink = false,
    this.protection = false,
    this.kittyKeyboard = false,
    this.charsets = false,
  });

  final bool cursor;
  final bool style;
  final bool hyperlink;
  final bool protection;
  final bool kittyKeyboard;
  final bool charsets;
}

/// Extra terminal state to include in styled formatter output.
final class VtFormatterTerminalExtra {
  const VtFormatterTerminalExtra({
    this.palette = false,
    this.modes = false,
    this.scrollingRegion = false,
    this.tabstops = false,
    this.pwd = false,
    this.keyboard = false,
    this.screen = const VtFormatterScreenExtra(),
  });

  final bool palette;
  final bool modes;
  final bool scrollingRegion;
  final bool tabstops;
  final bool pwd;
  final bool keyboard;
  final VtFormatterScreenExtra screen;
}

/// Options for [VtTerminal.createFormatter].
final class VtFormatterTerminalOptions {
  const VtFormatterTerminalOptions({
    this.emit = bindings.GhosttyFormatterFormat.GHOSTTY_FORMATTER_FORMAT_PLAIN,
    this.unwrap = false,
    this.trim = true,
    this.extra = const VtFormatterTerminalExtra(),
  });

  final bindings.GhosttyFormatterFormat emit;
  final bool unwrap;
  final bool trim;
  final VtFormatterTerminalExtra extra;
}

/// Stateful VT terminal emulator instance.
final class VtTerminal {
  VtTerminal({required int cols, required int rows, int maxScrollback = 10_000})
    : _cols = _checkPositiveUint16(cols, 'cols'),
      _rows = _checkPositiveUint16(rows, 'rows'),
      _maxScrollback = _checkNonNegative(maxScrollback, 'maxScrollback'),
      _handle = _newTerminal(
        cols: cols,
        rows: rows,
        maxScrollback: maxScrollback,
      );

  final bindings.GhosttyTerminal _handle;
  final Set<VtTerminalFormatter> _formatters = <VtTerminalFormatter>{};
  bool _closed = false;
  int _cols;
  int _rows;
  final int _maxScrollback;

  static bindings.GhosttyTerminal _newTerminal({
    required int cols,
    required int rows,
    required int maxScrollback,
  }) {
    final optionsPtr = calloc<bindings.GhosttyTerminalOptions>();
    final out = calloc<bindings.GhosttyTerminal>();
    try {
      optionsPtr.ref
        ..cols = _checkPositiveUint16(cols, 'cols')
        ..rows = _checkPositiveUint16(rows, 'rows')
        ..max_scrollback = _checkNonNegative(maxScrollback, 'maxScrollback');
      final result = bindings.ghostty_terminal_new(
        ffi.nullptr,
        out,
        optionsPtr.ref,
      );
      _checkResult(result, 'ghostty_terminal_new');
      return out.value;
    } finally {
      calloc.free(out);
      calloc.free(optionsPtr);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtTerminal is already closed.');
    }
  }

  void _detachFormatter(VtTerminalFormatter formatter) {
    _formatters.remove(formatter);
  }

  int get cols {
    _ensureOpen();
    return _cols;
  }

  int get rows {
    _ensureOpen();
    return _rows;
  }

  int get maxScrollback {
    _ensureOpen();
    return _maxScrollback;
  }

  /// Writes raw VT-encoded bytes into the terminal stream.
  void writeBytes(List<int> bytes) {
    _ensureOpen();
    if (bytes.isEmpty) {
      return;
    }
    final ptr = calloc<ffi.Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      bindings.ghostty_terminal_vt_write(_handle, ptr, bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Writes text bytes into the terminal stream.
  void write(String text, {Encoding encoding = utf8}) {
    writeBytes(encoding.encode(text));
  }

  /// Performs a full terminal reset while preserving dimensions.
  void reset() {
    _ensureOpen();
    bindings.ghostty_terminal_reset(_handle);
  }

  /// Resizes the terminal to the given cell dimensions.
  void resize({required int cols, required int rows}) {
    _ensureOpen();
    final checkedCols = _checkPositiveUint16(cols, 'cols');
    final checkedRows = _checkPositiveUint16(rows, 'rows');
    final result = bindings.ghostty_terminal_resize(
      _handle,
      checkedCols,
      checkedRows,
    );
    _checkResult(result, 'ghostty_terminal_resize');
    _cols = checkedCols;
    _rows = checkedRows;
  }

  /// Scrolls the visible viewport within the terminal scrollback.
  void scrollViewport(VtTerminalScrollViewport behavior) {
    _ensureOpen();
    final behaviorPtr = calloc<bindings.GhosttyTerminalScrollViewport>();
    try {
      behaviorPtr.ref.tagAsInt = behavior._tag.value;
      if (behavior._tag ==
          bindings
              .GhosttyTerminalScrollViewportTag
              .GHOSTTY_SCROLL_VIEWPORT_DELTA) {
        behaviorPtr.ref.value.delta = behavior.delta;
      }
      bindings.ghostty_terminal_scroll_viewport(_handle, behaviorPtr.ref);
    } finally {
      calloc.free(behaviorPtr);
    }
  }

  /// Scrolls to the top of the terminal scrollback.
  void scrollToTop() {
    scrollViewport(const VtTerminalScrollViewport.top());
  }

  /// Scrolls back to the active bottom of the terminal.
  void scrollToBottom() {
    scrollViewport(const VtTerminalScrollViewport.bottom());
  }

  /// Scrolls by [delta] rows. Negative values move up.
  void scrollBy(int delta) {
    scrollViewport(VtTerminalScrollViewport.delta(delta));
  }

  /// Creates a formatter that reflects the terminal state on each call.
  VtTerminalFormatter createFormatter([
    VtFormatterTerminalOptions options = const VtFormatterTerminalOptions(),
  ]) {
    _ensureOpen();
    final formatter = VtTerminalFormatter._(this, options);
    _formatters.add(formatter);
    return formatter;
  }

  /// Releases terminal resources.
  void close() {
    if (_closed) {
      return;
    }
    for (final formatter in List<VtTerminalFormatter>.from(_formatters)) {
      formatter.close();
    }
    bindings.ghostty_terminal_free(_handle);
    _closed = true;
  }
}

/// Reusable formatter for a [VtTerminal].
final class VtTerminalFormatter {
  VtTerminalFormatter._(VtTerminal terminal, VtFormatterTerminalOptions options)
    : _terminal = terminal,
      _handle = _newFormatter(terminal, options);

  final VtTerminal _terminal;
  final bindings.GhosttyFormatter _handle;
  bool _closed = false;

  static bindings.GhosttyFormatter _newFormatter(
    VtTerminal terminal,
    VtFormatterTerminalOptions options,
  ) {
    final out = calloc<bindings.GhosttyFormatter>();
    final nativeOptions = calloc<bindings.GhosttyFormatterTerminalOptions>();
    try {
      final screen = options.extra.screen;
      nativeOptions.ref
        ..size = ffi.sizeOf<bindings.GhosttyFormatterTerminalOptions>()
        ..emitAsInt = options.emit.value
        ..unwrap = options.unwrap
        ..trim = options.trim
        ..extra.size = ffi.sizeOf<bindings.GhosttyFormatterTerminalExtra>()
        ..extra.palette = options.extra.palette
        ..extra.modes = options.extra.modes
        ..extra.scrolling_region = options.extra.scrollingRegion
        ..extra.tabstops = options.extra.tabstops
        ..extra.pwd = options.extra.pwd
        ..extra.keyboard = options.extra.keyboard
        ..extra.screen.size = ffi.sizeOf<bindings.GhosttyFormatterScreenExtra>()
        ..extra.screen.cursor = screen.cursor
        ..extra.screen.style = screen.style
        ..extra.screen.hyperlink = screen.hyperlink
        ..extra.screen.protection = screen.protection
        ..extra.screen.kitty_keyboard = screen.kittyKeyboard
        ..extra.screen.charsets = screen.charsets;

      final result = bindings.ghostty_formatter_terminal_new(
        ffi.nullptr,
        out,
        terminal._handle,
        nativeOptions.ref,
      );
      _checkResult(result, 'ghostty_formatter_terminal_new');
      return out.value;
    } finally {
      calloc.free(nativeOptions);
      calloc.free(out);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtTerminalFormatter is already closed.');
    }
  }

  int _requiredSize() {
    final outWritten = calloc<ffi.Size>();
    try {
      final result = bindings.ghostty_formatter_format_buf(
        _handle,
        ffi.nullptr,
        0,
        outWritten,
      );
      if (result == bindings.GhosttyResult.GHOSTTY_SUCCESS) {
        return outWritten.value;
      }
      if (result != bindings.GhosttyResult.GHOSTTY_OUT_OF_SPACE) {
        _checkResult(result, 'ghostty_formatter_format_buf(size_probe)');
      }
      return outWritten.value;
    } finally {
      calloc.free(outWritten);
    }
  }

  /// Formats the terminal into a byte buffer.
  Uint8List formatBytes() {
    _ensureOpen();
    _terminal._ensureOpen();

    var required = _requiredSize();
    if (required == 0) {
      return Uint8List(0);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final buffer = calloc<ffi.Uint8>(required);
      final outWritten = calloc<ffi.Size>();
      try {
        final result = bindings.ghostty_formatter_format_buf(
          _handle,
          buffer,
          required,
          outWritten,
        );
        if (result == bindings.GhosttyResult.GHOSTTY_SUCCESS) {
          return Uint8List.fromList(buffer.asTypedList(outWritten.value));
        }
        if (result != bindings.GhosttyResult.GHOSTTY_OUT_OF_SPACE) {
          _checkResult(result, 'ghostty_formatter_format_buf');
        }
        required = outWritten.value;
        if (required == 0) {
          return Uint8List(0);
        }
      } finally {
        calloc.free(outWritten);
        calloc.free(buffer);
      }
    }

    throw StateError(
      'VtTerminalFormatter output changed while formatting. Retry the call.',
    );
  }

  /// Formats the terminal using `ghostty_formatter_format_alloc`.
  ///
  /// This path uses a Dart-owned allocator so the returned buffer can be
  /// safely released from Dart after copying it into a [Uint8List].
  Uint8List formatBytesAllocated() {
    return formatBytesAllocatedWith(VtAllocator.dartMalloc);
  }

  /// Formats the terminal using `ghostty_formatter_format_alloc` and [allocator].
  Uint8List formatBytesAllocatedWith(VtAllocator allocator) {
    _ensureOpen();
    _terminal._ensureOpen();

    final outPtr = calloc<ffi.Pointer<ffi.Uint8>>();
    final outLen = calloc<ffi.Size>();
    try {
      final result = bindings.ghostty_formatter_format_alloc(
        _handle,
        allocator.pointer,
        outPtr,
        outLen,
      );
      _checkResult(result, 'ghostty_formatter_format_alloc');

      return allocator.copyBytesAndFree(outPtr.value, outLen.value);
    } finally {
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  /// Formats the terminal and decodes the bytes into a Dart string.
  String formatText({Encoding encoding = utf8}) {
    final bytes = formatBytes();
    if (encoding == utf8) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return encoding.decode(bytes);
  }

  /// Formats via [formatBytesAllocated] and decodes the result.
  String formatTextAllocated({Encoding encoding = utf8}) {
    return formatTextAllocatedWith(VtAllocator.dartMalloc, encoding: encoding);
  }

  /// Formats via [formatBytesAllocatedWith] and decodes the result.
  String formatTextAllocatedWith(
    VtAllocator allocator, {
    Encoding encoding = utf8,
  }) {
    final bytes = formatBytesAllocatedWith(allocator);
    if (encoding == utf8) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return encoding.decode(bytes);
  }

  /// Releases formatter resources.
  void close() {
    if (_closed) {
      return;
    }
    bindings.ghostty_formatter_free(_handle);
    _terminal._detachFormatter(this);
    _closed = true;
  }
}

/// Streaming OSC (Operating System Command) parser.
///
/// Feeds terminal bytes through the parser to extract OSC sequences
/// such as window title changes.
///
/// ```dart
/// final parser = VtOscParser();
/// // Feed an OSC 2 (set window title) sequence byte by byte
/// parser.addText('\x1b]2;My Title\x07');
/// // ... or feed individual bytes with addByte()
///
/// final command = parser.end();
/// print(command.windowTitle); // 'My Title'
/// parser.close();
/// ```
final class VtOscParser {
  VtOscParser() : _handle = _newOscParser();

  final bindings.GhosttyOscParser _handle;
  bool _closed = false;

  static bindings.GhosttyOscParser _newOscParser() {
    final out = calloc<bindings.GhosttyOscParser>();
    try {
      final result = bindings.ghostty_osc_new(ffi.nullptr, out);
      _checkResult(result, 'ghostty_osc_new');
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtOscParser is already closed.');
    }
  }

  /// Resets parser state.
  void reset() {
    _ensureOpen();
    bindings.ghostty_osc_reset(_handle);
  }

  /// Feeds one byte into the OSC parser.
  void addByte(int byte) {
    _ensureOpen();
    if (byte < 0 || byte > 255) {
      throw RangeError.range(byte, 0, 255, 'byte');
    }
    bindings.ghostty_osc_next(_handle, byte);
  }

  /// Feeds multiple bytes into the OSC parser.
  void addBytes(Iterable<int> bytes) {
    for (final byte in bytes) {
      addByte(byte);
    }
  }

  /// Feeds text bytes (UTF-8 by default) into the OSC parser.
  void addText(String text, {Encoding encoding = utf8}) {
    addBytes(encoding.encode(text));
  }

  /// Finalizes parsing and returns a stable command snapshot.
  ///
  /// Returns a [VtOscCommand] with type [GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID]
  /// if the fed bytes did not form a valid OSC sequence.
  VtOscCommand end({int terminator = 0x07}) {
    _ensureOpen();
    if (terminator < 0 || terminator > 255) {
      throw RangeError.range(terminator, 0, 255, 'terminator');
    }

    final command = bindings.ghostty_osc_end(_handle, terminator);

    // Guard: if the native call returned a null pointer, treat as invalid.
    if (command == ffi.nullptr) {
      return const VtOscCommand(
        type: bindings.GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID,
      );
    }

    final type = bindings.ghostty_osc_command_type(command);

    // Guard: don't attempt to extract data from invalid/unrecognised commands
    // — the native library may segfault if asked for data on a command that
    // doesn't carry it.
    if (type == bindings.GhosttyOscCommandType.GHOSTTY_OSC_COMMAND_INVALID) {
      return VtOscCommand(type: type);
    }

    String? windowTitle;

    // Only query the window-title data field for command types that carry it.
    if (type ==
            bindings
                .GhosttyOscCommandType
                .GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_TITLE ||
        type ==
            bindings
                .GhosttyOscCommandType
                .GHOSTTY_OSC_COMMAND_CHANGE_WINDOW_ICON) {
      final out = calloc<ffi.Pointer<ffi.Char>>();
      try {
        final hasTitle = bindings.ghostty_osc_command_data(
          command,
          bindings
              .GhosttyOscCommandData
              .GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR,
          out.cast(),
        );
        final ptr = out.value;
        if (hasTitle && ptr != ffi.nullptr) {
          windowTitle = ptr.cast<Utf8>().toDartString();
        }
      } finally {
        calloc.free(out);
      }
    }

    return VtOscCommand(type: type, windowTitle: windowTitle);
  }

  /// Releases parser resources.
  void close() {
    if (_closed) {
      return;
    }
    bindings.ghostty_osc_free(_handle);
    _closed = true;
  }
}

/// Parsed OSC command snapshot.
///
/// Contains the command [type] and optional data such as [windowTitle]
/// extracted during parsing.
final class VtOscCommand {
  const VtOscCommand({required this.type, this.windowTitle});

  final bindings.GhosttyOscCommandType type;

  /// Window title when available for title-changing OSC commands.
  final String? windowTitle;
}

/// Parsed data for unknown SGR attributes.
final class VtSgrUnknownData {
  const VtSgrUnknownData({required this.full, required this.partial});

  final List<int> full;
  final List<int> partial;
}

/// High-level view of an SGR attribute.
final class VtSgrAttributeData {
  const VtSgrAttributeData._({
    required this.tag,
    this.unknown,
    this.underline,
    this.rgb,
    this.paletteIndex,
  });

  final bindings.GhosttySgrAttributeTag tag;
  final VtSgrUnknownData? unknown;
  final bindings.GhosttySgrUnderline? underline;
  final VtRgbColor? rgb;
  final int? paletteIndex;

  static VtSgrAttributeData fromPointer(
    ffi.Pointer<bindings.GhosttySgrAttribute> nativePtr,
  ) {
    final tag = bindings.ghostty_sgr_attribute_tag(nativePtr.ref);
    final value = bindings.ghostty_sgr_attribute_value(nativePtr).ref;
    switch (tag) {
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNKNOWN:
        final unknown = value.unknown;
        final fullOut = calloc<ffi.Pointer<ffi.Uint16>>();
        final partialOut = calloc<ffi.Pointer<ffi.Uint16>>();
        late final List<int> full;
        late final List<int> partial;
        try {
          final fullLen = bindings.ghostty_sgr_unknown_full(unknown, fullOut);
          final fullPtr = fullOut.value;
          full = fullLen == 0 || fullPtr == ffi.nullptr
              ? const <int>[]
              : List<int>.unmodifiable(fullPtr.asTypedList(fullLen));

          final partialLen = bindings.ghostty_sgr_unknown_partial(
            unknown,
            partialOut,
          );
          final partialPtr = partialOut.value;
          partial = partialLen == 0 || partialPtr == ffi.nullptr
              ? const <int>[]
              : List<int>.unmodifiable(partialPtr.asTypedList(partialLen));
        } finally {
          calloc.free(fullOut);
          calloc.free(partialOut);
        }
        return VtSgrAttributeData._(
          tag: tag,
          unknown: VtSgrUnknownData(full: full, partial: partial),
        );
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE:
        return VtSgrAttributeData._(tag: tag, underline: value.underline);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR:
        return VtSgrAttributeData._(
          tag: tag,
          rgb: VtRgbColor.fromNative(value.underline_color),
        );
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_FG:
        return VtSgrAttributeData._(
          tag: tag,
          rgb: VtRgbColor.fromNative(value.direct_color_fg),
        );
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_DIRECT_COLOR_BG:
        return VtSgrAttributeData._(
          tag: tag,
          rgb: VtRgbColor.fromNative(value.direct_color_bg),
        );
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_UNDERLINE_COLOR_256:
        return VtSgrAttributeData._(
          tag: tag,
          paletteIndex: value.underline_color_256,
        );
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_8:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.bg_8);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_8:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.fg_8);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_BG_8:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.bright_bg_8);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BRIGHT_FG_8:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.bright_fg_8);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_BG_256:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.bg_256);
      case bindings.GhosttySgrAttributeTag.GHOSTTY_SGR_ATTR_FG_256:
        return VtSgrAttributeData._(tag: tag, paletteIndex: value.fg_256);
      default:
        return VtSgrAttributeData._(tag: tag);
    }
  }
}

/// SGR (Select Graphic Rendition) parameter parser.
///
/// Parses CSI SGR parameter values into structured attribute data.
///
/// ```dart
/// final parser = VtSgrParser();
/// final attrs = parser.parseParams([1, 31]); // bold + red foreground
/// for (final attr in attrs) {
///   print(attr.tag);
/// }
/// parser.close();
/// ```
final class VtSgrParser {
  VtSgrParser()
    : _handle = _newSgrParser(),
      _attrPtr = calloc<bindings.GhosttySgrAttribute>();

  final bindings.GhosttySgrParser _handle;
  final ffi.Pointer<bindings.GhosttySgrAttribute> _attrPtr;
  bool _closed = false;

  static bindings.GhosttySgrParser _newSgrParser() {
    final out = calloc<bindings.GhosttySgrParser>();
    try {
      final result = bindings.ghostty_sgr_new(ffi.nullptr, out);
      _checkResult(result, 'ghostty_sgr_new');
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtSgrParser is already closed.');
    }
  }

  /// Resets iteration state.
  void reset() {
    _ensureOpen();
    bindings.ghostty_sgr_reset(_handle);
  }

  /// Sets SGR parameter values and optional separators.
  ///
  /// If [separators] is set, it must match [params] length and should contain
  /// separator bytes such as `;` and `:`.
  void setParams(List<int> params, {String? separators}) {
    _ensureOpen();
    if (separators != null && separators.length != params.length) {
      throw ArgumentError.value(
        separators,
        'separators',
        'Must have same length as params.',
      );
    }

    final paramsPtr = calloc<ffi.Uint16>(params.length);
    ffi.Pointer<ffi.Char> separatorsPtr = ffi.nullptr;
    ffi.Pointer<ffi.Char>? allocatedSeparators;
    try {
      for (var i = 0; i < params.length; i++) {
        final value = params[i];
        if (value < 0 || value > 0xFFFF) {
          throw RangeError.range(value, 0, 0xFFFF, 'params[$i]');
        }
        paramsPtr[i] = value;
      }

      if (separators != null) {
        allocatedSeparators = calloc<ffi.Char>(separators.length);
        for (var i = 0; i < separators.length; i++) {
          final value = separators.codeUnitAt(i);
          if (value > 0xFF) {
            throw RangeError.range(value, 0, 0xFF, 'separators[$i]');
          }
          allocatedSeparators[i] = value;
        }
        separatorsPtr = allocatedSeparators;
      }

      final result = bindings.ghostty_sgr_set_params(
        _handle,
        paramsPtr,
        separatorsPtr,
        params.length,
      );
      _checkResult(result, 'ghostty_sgr_set_params');
    } finally {
      calloc.free(paramsPtr);
      if (allocatedSeparators != null) {
        calloc.free(allocatedSeparators);
      }
    }
  }

  /// Returns the next parsed attribute, or `null` if exhausted.
  VtSgrAttributeData? next() {
    _ensureOpen();
    final hasNext = bindings.ghostty_sgr_next(_handle, _attrPtr);
    if (!hasNext) {
      return null;
    }
    return VtSgrAttributeData.fromPointer(_attrPtr);
  }

  /// Parses all currently configured attributes.
  List<VtSgrAttributeData> parseAll() {
    final out = <VtSgrAttributeData>[];
    while (true) {
      final nextAttr = next();
      if (nextAttr == null) {
        break;
      }
      out.add(nextAttr);
    }
    return out;
  }

  /// Parses [params] and returns all attributes in one call.
  List<VtSgrAttributeData> parseParams(List<int> params, {String? separators}) {
    setParams(params, separators: separators);
    return parseAll();
  }

  /// Releases parser resources.
  void close() {
    if (_closed) {
      return;
    }
    bindings.ghostty_sgr_free(_handle);
    calloc.free(_attrPtr);
    _closed = true;
  }
}

/// Mutable key event used with [VtKeyEncoder].
///
/// Configure the event's [action], [key], [mods], and [utf8Text] properties,
/// then pass it to [VtKeyEncoder.encode] to produce terminal escape bytes.
///
/// ```dart
/// final event = VtKeyEvent();
/// event
///   ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
///   ..key = GhosttyKey.GHOSTTY_KEY_ENTER
///   ..mods = 0;
/// // ... encode with VtKeyEncoder ...
/// event.close();
/// ```
final class VtKeyEvent {
  VtKeyEvent() : _handle = _newKeyEvent();

  final bindings.GhosttyKeyEvent _handle;
  bool _closed = false;
  ffi.Pointer<ffi.Uint8>? _utf8Storage;

  static bindings.GhosttyKeyEvent _newKeyEvent() {
    final out = calloc<bindings.GhosttyKeyEvent>();
    try {
      final result = bindings.ghostty_key_event_new(ffi.nullptr, out);
      _checkResult(result, 'ghostty_key_event_new');
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtKeyEvent is already closed.');
    }
  }

  bindings.GhosttyKeyAction get action {
    _ensureOpen();
    return bindings.ghostty_key_event_get_action(_handle);
  }

  set action(bindings.GhosttyKeyAction value) {
    _ensureOpen();
    bindings.ghostty_key_event_set_action(_handle, value);
  }

  bindings.GhosttyKey get key {
    _ensureOpen();
    return bindings.ghostty_key_event_get_key(_handle);
  }

  set key(bindings.GhosttyKey value) {
    _ensureOpen();
    bindings.ghostty_key_event_set_key(_handle, value);
  }

  int get mods {
    _ensureOpen();
    return bindings.ghostty_key_event_get_mods(_handle);
  }

  set mods(int value) {
    _ensureOpen();
    bindings.ghostty_key_event_set_mods(_handle, value);
  }

  int get consumedMods {
    _ensureOpen();
    return bindings.ghostty_key_event_get_consumed_mods(_handle);
  }

  set consumedMods(int value) {
    _ensureOpen();
    bindings.ghostty_key_event_set_consumed_mods(_handle, value);
  }

  bool get composing {
    _ensureOpen();
    return bindings.ghostty_key_event_get_composing(_handle);
  }

  set composing(bool value) {
    _ensureOpen();
    bindings.ghostty_key_event_set_composing(_handle, value);
  }

  String get utf8Text {
    _ensureOpen();
    final lenPtr = calloc<ffi.Size>();
    try {
      final ptr = bindings.ghostty_key_event_get_utf8(_handle, lenPtr);
      final len = lenPtr.value;
      if (ptr == ffi.nullptr || len == 0) {
        return '';
      }
      final bytes = ptr.cast<ffi.Uint8>().asTypedList(len);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      calloc.free(lenPtr);
    }
  }

  set utf8Text(String value) {
    _ensureOpen();
    _freeUtf8Storage();

    if (value.isEmpty) {
      bindings.ghostty_key_event_set_utf8(_handle, ffi.nullptr, 0);
      return;
    }

    final bytes = utf8.encode(value);
    final ptr = calloc<ffi.Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    _utf8Storage = ptr;
    bindings.ghostty_key_event_set_utf8(
      _handle,
      ptr.cast<ffi.Char>(),
      bytes.length,
    );
  }

  int get unshiftedCodepoint {
    _ensureOpen();
    return bindings.ghostty_key_event_get_unshifted_codepoint(_handle);
  }

  set unshiftedCodepoint(int value) {
    _ensureOpen();
    if (value < 0 || value > 0x10FFFF) {
      throw RangeError.range(value, 0, 0x10FFFF, 'unshiftedCodepoint');
    }
    bindings.ghostty_key_event_set_unshifted_codepoint(_handle, value);
  }

  void _freeUtf8Storage() {
    final storage = _utf8Storage;
    if (storage != null) {
      calloc.free(storage);
      _utf8Storage = null;
    }
  }

  /// Releases key event resources.
  void close() {
    if (_closed) {
      return;
    }
    _freeUtf8Storage();
    bindings.ghostty_key_event_free(_handle);
    _closed = true;
  }
}

/// Terminal key encoder.
///
/// Converts [VtKeyEvent] objects into the byte sequences expected by
/// terminal applications, supporting legacy, xterm, and Kitty keyboard
/// protocol modes.
///
/// ```dart
/// final encoder = VtKeyEncoder();
/// encoder.kittyFlags = GhosttyKittyFlags.disambiguate;
///
/// final event = VtKeyEvent();
/// event
///   ..action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS
///   ..key = GhosttyKey.GHOSTTY_KEY_A
///   ..utf8Text = 'a';
///
/// final bytes = encoder.encode(event);
/// terminal.writeBytes(bytes);
///
/// event.close();
/// encoder.close();
/// ```
final class VtKeyEncoder {
  VtKeyEncoder() : _handle = _newKeyEncoder();

  final bindings.GhosttyKeyEncoder _handle;
  bool _closed = false;

  static bindings.GhosttyKeyEncoder _newKeyEncoder() {
    final out = calloc<bindings.GhosttyKeyEncoder>();
    try {
      final result = bindings.ghostty_key_encoder_new(ffi.nullptr, out);
      _checkResult(result, 'ghostty_key_encoder_new');
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('VtKeyEncoder is already closed.');
    }
  }

  void _setBoolOption(bindings.GhosttyKeyEncoderOption option, bool value) {
    final ptr = calloc<ffi.Bool>()..value = value;
    try {
      bindings.ghostty_key_encoder_setopt(_handle, option, ptr.cast());
    } finally {
      calloc.free(ptr);
    }
  }

  /// DEC mode 1: cursor key application mode.
  set cursorKeyApplication(bool enabled) {
    _ensureOpen();
    _setBoolOption(
      bindings
          .GhosttyKeyEncoderOption
          .GHOSTTY_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION,
      enabled,
    );
  }

  /// DEC mode 66: keypad key application mode.
  set keypadKeyApplication(bool enabled) {
    _ensureOpen();
    _setBoolOption(
      bindings
          .GhosttyKeyEncoderOption
          .GHOSTTY_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION,
      enabled,
    );
  }

  /// DEC mode 1035: ignore keypad with numlock.
  set ignoreKeypadWithNumLock(bool enabled) {
    _ensureOpen();
    _setBoolOption(
      bindings
          .GhosttyKeyEncoderOption
          .GHOSTTY_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK,
      enabled,
    );
  }

  /// DEC mode 1036: alt sends escape prefix.
  set altEscPrefix(bool enabled) {
    _ensureOpen();
    _setBoolOption(
      bindings.GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_ALT_ESC_PREFIX,
      enabled,
    );
  }

  /// xterm modifyOtherKeys mode 2.
  set modifyOtherKeysState2(bool enabled) {
    _ensureOpen();
    _setBoolOption(
      bindings
          .GhosttyKeyEncoderOption
          .GHOSTTY_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2,
      enabled,
    );
  }

  /// Kitty keyboard protocol flags.
  set kittyFlags(int flags) {
    _ensureOpen();
    if (flags < 0 || flags > 0xFF) {
      throw RangeError.range(flags, 0, 0xFF, 'kittyFlags');
    }
    final ptr = calloc<ffi.Uint8>()..value = flags;
    try {
      bindings.ghostty_key_encoder_setopt(
        _handle,
        bindings.GhosttyKeyEncoderOption.GHOSTTY_KEY_ENCODER_OPT_KITTY_FLAGS,
        ptr.cast(),
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// macOS option-as-alt behavior.
  set macosOptionAsAlt(bindings.GhosttyOptionAsAlt value) {
    _ensureOpen();
    final ptr = calloc<ffi.UnsignedInt>()..value = value.value;
    try {
      bindings.ghostty_key_encoder_setopt(
        _handle,
        bindings
            .GhosttyKeyEncoderOption
            .GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
        ptr.cast(),
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// Copies key encoder options from a terminal instance.
  ///
  /// This mirrors terminal modes such as cursor-key application mode and
  /// keyboard protocol settings onto the encoder.
  void setOptionsFromTerminal(VtTerminal terminal) {
    _ensureOpen();
    terminal._ensureOpen();
    bindings.ghostty_key_encoder_setopt_from_terminal(
      _handle,
      terminal._handle,
    );
  }

  /// Encodes a key event into terminal bytes.
  Uint8List encode(VtKeyEvent event) {
    _ensureOpen();
    event._ensureOpen();

    final outLen = calloc<ffi.Size>();
    try {
      final first = bindings.ghostty_key_encoder_encode(
        _handle,
        event._handle,
        ffi.nullptr,
        0,
        outLen,
      );
      if (first == bindings.GhosttyResult.GHOSTTY_SUCCESS &&
          outLen.value == 0) {
        return Uint8List(0);
      }
      if (first != bindings.GhosttyResult.GHOSTTY_OUT_OF_MEMORY) {
        _checkResult(first, 'ghostty_key_encoder_encode(size_probe)');
      }

      final required = outLen.value;
      if (required == 0) {
        return Uint8List(0);
      }

      final buffer = calloc<ffi.Char>(required);
      try {
        final secondOutLen = calloc<ffi.Size>();
        try {
          final second = bindings.ghostty_key_encoder_encode(
            _handle,
            event._handle,
            buffer,
            required,
            secondOutLen,
          );
          _checkResult(second, 'ghostty_key_encoder_encode');
          final written = secondOutLen.value;
          return Uint8List.fromList(
            buffer.cast<ffi.Uint8>().asTypedList(written),
          );
        } finally {
          calloc.free(secondOutLen);
        }
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(outLen);
    }
  }

  /// Encodes a key event to a single Dart string of byte code units.
  String encodeToString(VtKeyEvent event) {
    return String.fromCharCodes(encode(event));
  }

  /// Releases key encoder resources.
  void close() {
    if (_closed) {
      return;
    }
    bindings.ghostty_key_encoder_free(_handle);
    _closed = true;
  }
}
