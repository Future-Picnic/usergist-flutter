import 'package:flutter/foundation.dart';

/// Internal, gated logger used by the SDK. Uses [debugPrint] under the
/// hood so output is elided in release builds by default.
///
/// Set [setDebug] to `true` to enable verbose traces.
class UserGistLogger {
  UserGistLogger._();

  /// Singleton instance.
  static final UserGistLogger instance = UserGistLogger._();

  bool _debug = false;

  /// Enables or disables verbose logging.
  // ignore: avoid_positional_boolean_parameters
  void setDebug(bool enabled) {
    _debug = enabled;
  }

  /// Returns whether debug logging is currently enabled.
  bool get isDebug => _debug;

  /// Logs a debug line.
  void d(String message) {
    if (!_debug && !kDebugMode) return;
    if (!_debug) return;
    debugPrint('[usergist] $message');
  }

  /// Logs an info line. Only emitted when debug is enabled.
  void i(String message) {
    if (!_debug) return;
    debugPrint('[usergist] $message');
  }

  /// Logs a warning. Always emitted in debug mode.
  void w(String message) {
    if (!kDebugMode && !_debug) return;
    debugPrint('[usergist][warn] $message');
  }

  /// Logs an error with optional stack-trace.
  void e(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode && !_debug) return;
    debugPrint('[usergist][error] $message${error != null ? ': $error' : ''}');
    if (stack != null && _debug) {
      debugPrint(stack.toString());
    }
  }
}

/// Shorthand accessor.
UserGistLogger get log => UserGistLogger.instance;
