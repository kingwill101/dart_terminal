/// Flutter bindings for controlling [portable_pty] sessions from widgets and services.
///
/// This package provides [FlutterPtyController], a thin [ChangeNotifier]
/// wrapper around `portable_pty`'s [PortablePtyController].
///
/// ```dart
/// import 'package:portable_pty_flutter/portable_pty_flutter.dart';
///
/// final controller = FlutterPtyController(defaultShell: '/bin/bash');
/// await controller.start();
/// controller.write('ls -la\n');
/// // ... read output, display in widgets ...
/// controller.dispose();
/// ```
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
