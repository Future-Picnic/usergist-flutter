import 'package:flutter/widgets.dart';

/// Thin wrapper around [WidgetsBindingObserver] that forwards
/// [AppLifecycleState] changes to callbacks supplied at construction.
class AppLifecycle with WidgetsBindingObserver {
  /// Creates an observer.
  AppLifecycle({this.onResumed, this.onPaused, this.onDetached});

  /// Called on [AppLifecycleState.resumed].
  final VoidCallback? onResumed;

  /// Called on [AppLifecycleState.paused].
  final VoidCallback? onPaused;

  /// Called on [AppLifecycleState.detached].
  final VoidCallback? onDetached;

  bool _attached = false;

  /// Registers the observer with the Flutter binding. Safe to call
  /// before the binding exists (no-op in that case).
  void attach() {
    if (_attached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } on Object {
      // Binding not yet initialized (e.g. unit tests).
    }
  }

  /// Removes the observer from the binding.
  void detach() {
    if (!_attached) return;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } on Object {
      // Ignore.
    }
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResumed?.call();
      case AppLifecycleState.paused:
        onPaused?.call();
      case AppLifecycleState.detached:
        onDetached?.call();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
