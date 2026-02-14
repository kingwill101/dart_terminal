import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ghostty_vte/ghostty_vte.dart';

/// [GhosttyTerminalController] for managing VT state and input handling.
export 'src/terminal_controller.dart';

/// [GhosttyTerminalView] widget for rendering terminal output in Flutter.
export 'src/terminal_view.dart';

/// Platform-resolved ghostty_vte API (`GhosttyVt`, `GhosttyVtWasm`, etc.).
///
/// Re-exported so consumers do not need a separate direct dependency on
/// `ghostty_vte`.
export 'package:ghostty_vte/ghostty_vte.dart';

/// Package-level setup and lightweight terminal widgets for Flutter.
///
/// The wasm runtime can be initialized via [initializeGhosttyVteWeb] on web
/// before constructing web terminal views.

/// Initializes the Ghostty wasm module on web from bundled Flutter assets.
Future<void> initializeGhosttyVteWeb({
  String assetPath = 'packages/ghostty_vte_flutter/assets/ghostty-vt.wasm',
}) async {
  if (!kIsWeb || GhosttyVtWasm.isInitialized) {
    return;
  }
  final data = await rootBundle.load(assetPath);
  await GhosttyVtWasm.initializeFromBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// Backwards-compatible starter widget.
///
/// Prefer [GhosttyTerminalView] + [GhosttyTerminalController] for a terminal
/// implementation.
class GhosttyTerminalWidget extends StatelessWidget {
  const GhosttyTerminalWidget({
    required this.sampleInput,
    this.isPasteSafe,
    super.key,
  });

  final String sampleInput;
  final bool Function(String text)? isPasteSafe;

  @override
  Widget build(BuildContext context) {
    final safe = (isPasteSafe ?? GhosttyVt.isPasteSafe)(sampleInput);
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF111111)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'ghostty_vte_flutter\n'
          'sample: $sampleInput\n'
          'paste safe: $safe',
          style: const TextStyle(
            color: Color(0xFFE6E6E6),
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
