/// Lightweight listener mechanism for [PortablePtyController].
///
/// This replaces Flutter's `ChangeNotifier` so the controller can be used
/// from pure Dart (CLI, server, tests) without a Flutter dependency.
mixin PtyListenable {
  final List<void Function()> _listeners = <void Function()>[];
  bool _disposed = false;

  /// Register a callback that fires whenever state changes.
  void addListener(void Function() listener) {
    if (_disposed) return;
    _listeners.add(listener);
  }

  /// Remove a previously registered listener.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Notify all registered listeners of a state change.
  void notifyListeners() {
    if (_disposed) return;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  /// Whether this object has been disposed.
  bool get isDisposed => _disposed;

  /// Release resources and prevent further notifications.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
