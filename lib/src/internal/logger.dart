import 'package:flutter/foundation.dart';

/// Internal, gated logger used by the SDK. Uses [debugPrint] under the
/// hood so output is elided in release builds by default.
///
/// Set [setDebug] to `true` to enable verbose traces.
class RitmusLogger {
  RitmusLogger._();

  /// Singleton instance.
  static final RitmusLogger instance = RitmusLogger._();

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
    debugPrint('[ritmus] $message');
  }

  /// Logs an info line. Only emitted when debug is enabled.
  void i(String message) {
    if (!_debug) return;
    debugPrint('[ritmus] $message');
  }

  /// Logs a warning. Always emitted in debug mode.
  void w(String message) {
    if (!kDebugMode && !_debug) return;
    debugPrint('[ritmus][warn] $message');
  }

  /// Logs an error with optional stack-trace.
  void e(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode && !_debug) return;
    debugPrint('[ritmus][error] $message${error != null ? ': $error' : ''}');
    if (stack != null && _debug) {
      debugPrint(stack.toString());
    }
  }
}

/// Shorthand accessor.
RitmusLogger get log => RitmusLogger.instance;
