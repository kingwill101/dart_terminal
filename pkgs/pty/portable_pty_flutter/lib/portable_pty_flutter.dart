/// Flutter bindings for controlling [portable_pty] sessions from widgets and services.
///
/// Re-exporting the platform-agnostic PTY API allows callers to configure custom
/// transport implementations without adding a second direct dependency.
library;

/// Platform-resolved [PortablePty] class, [PortablePtyTransport] contract,
/// [PortablePtyController], and [PtyListenable] mixin.
///
/// Re-exported so consumers of this Flutter package do not need a separate
/// direct dependency on `portable_pty`.
export 'package:portable_pty/portable_pty.dart';

/// [FlutterPtyController] — thin [ChangeNotifier] wrapper around
/// [PortablePtyController] for use with Flutter widget tree listeners.
export 'src/flutter_pty_controller.dart';
