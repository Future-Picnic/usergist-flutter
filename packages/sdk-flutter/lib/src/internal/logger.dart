import 'package:flutter/foundation.dart';
import '../models/diagnostic.dart';

/// Internal, gated logger used by the SDK. Uses [debugPrint] under the
/// hood so output is elided in release builds by default.
///
/// Set [setDebug] to `true` to enable verbose traces.
class UserGistLogger {
  UserGistLogger._();

  /// Singleton instance.
  static final UserGistLogger instance = UserGistLogger._();

  bool _debug = false;
  void Function(SdkDiagnostic diagnostic)? _diagnosticHandler;

  /// Installs a production-safe error callback.
  void setDiagnosticHandler(void Function(SdkDiagnostic diagnostic)? handler) {
    _diagnosticHandler = handler;
  }

  void _diagnostic(String message) {
    try {
      _diagnosticHandler?.call(
        SdkDiagnostic(
          code: 'sdk_error',
          message: message.length <= 200 ? message : message.substring(0, 200),
          occurredAt: DateTime.now().toUtc(),
        ),
      );
    } on Object {
      // Host diagnostics must never cross the SDK boundary.
    }
  }

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
    _diagnostic(message);
    if (!kDebugMode && !_debug) return;
    debugPrint('[usergist][warn] $message');
  }

  /// Logs an error with optional stack-trace.
  void e(String message, [Object? error, StackTrace? stack]) {
    _diagnostic(message);
    if (!kDebugMode && !_debug) return;
    debugPrint('[usergist][error] $message${error != null ? ': $error' : ''}');
    if (stack != null && _debug) {
      debugPrint(stack.toString());
    }
  }
}

/// Shorthand accessor.
UserGistLogger get log => UserGistLogger.instance;
