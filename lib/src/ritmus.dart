import 'dart:async';

import 'internal/core.dart';
import 'internal/logger.dart';
import 'internal/transport/endpoints.dart';
import 'models/consent.dart';
import 'models/response_info.dart';
import 'models/theme.dart';
import 'ui/prompt_presenter.dart';

/// Deployment environment enum. Maps to a default base URL.
enum RitmusEnvironment {
  /// Production.
  production,

  /// Staging / pre-prod.
  staging,

  /// Local / development.
  development;

  /// Default API base URL for this environment.
  String get defaultUrl => switch (this) {
        RitmusEnvironment.production => DefaultApiUrls.production,
        RitmusEnvironment.staging => DefaultApiUrls.staging,
        RitmusEnvironment.development => DefaultApiUrls.development,
      };
}

/// Public static entrypoint to the Ritmus feedback SDK.
///
/// All methods wrap their implementation in a try/catch so the SDK
/// never throws across its public boundary.
class Ritmus {
  Ritmus._();

  /// Current SDK version (kept in sync with pubspec).
  static const String sdkVersion = '0.1.0';

  static RitmusCore? _core;

  /// Initializes the SDK. Safe to call multiple times — subsequent calls
  /// are ignored (the first configuration wins).
  static Future<void> init({
    required String writeKey,
    RitmusEnvironment environment = RitmusEnvironment.production,
    String? apiUrl,
    bool debug = false,
    Duration flushInterval = const Duration(seconds: 15),
    int flushBatchSize = 100,
    int maxQueueSize = 1000,
    Duration triggerSyncInterval = const Duration(minutes: 5),
  }) async {
    try {
      if (_core != null) {
        log.w('Ritmus.init called more than once — ignoring');
        return;
      }
      log.setDebug(debug);
      final core = RitmusCore(
        writeKey: writeKey,
        baseUrl: apiUrl ?? environment.defaultUrl,
        sdkVersion: sdkVersion,
        flushInterval: flushInterval,
        flushBatchSize: flushBatchSize,
        maxQueueSize: maxQueueSize,
        triggerSyncInterval: triggerSyncInterval,
      );
      await core.start();
      _core = core;
    } on Object catch (err, st) {
      log.e('Ritmus.init failed', err, st);
    }
  }

  /// Identifies the currently logged-in user with a stable id and
  /// optional properties.
  static Future<void> identify(
    String userId, {
    Map<String, Object?>? properties,
  }) async {
    try {
      final core = _core;
      if (core == null) return;
      await core.identify(userId, properties);
    } on Object catch (err, st) {
      log.e('identify failed', err, st);
    }
  }

  /// Records an event. Non-blocking from the caller's perspective.
  static void track(
    String eventName, {
    Map<String, Object?>? properties,
  }) {
    try {
      final core = _core;
      if (core == null) return;
      core.track(eventName, properties);
    } on Object catch (err, st) {
      log.e('track failed', err, st);
    }
  }

  /// Sets consent. Transport is blocked until feedback consent is
  /// granted.
  static Future<void> setConsent(Consent purposes) async {
    try {
      final core = _core;
      if (core == null) return;
      await core.setConsent(purposes);
    } on Object catch (err, st) {
      log.e('setConsent failed', err, st);
    }
  }

  /// Registers a device token with the control plane. Ignored if push
  /// consent has not been granted.
  static Future<void> registerPushToken(
    String token,
    String platform,
    String environment,
  ) async {
    try {
      final core = _core;
      if (core == null) return;
      await core.registerPushToken(token, platform, environment);
    } on Object catch (err, st) {
      log.e('registerPushToken failed', err, st);
    }
  }

  /// Invalidates a previously-registered device token.
  static Future<void> invalidatePushToken(String token) async {
    try {
      final core = _core;
      if (core == null) return;
      await core.invalidatePushToken(token);
    } on Object catch (err, st) {
      log.e('invalidatePushToken failed', err, st);
    }
  }

  /// Clears identity and local state (queue + caches + consent).
  static Future<void> reset() async {
    try {
      final core = _core;
      if (core == null) return;
      await core.reset();
    } on Object catch (err, st) {
      log.e('reset failed', err, st);
    }
  }

  /// Replaces the caller-side theme overrides.
  static void setThemeOverrides(PromptTheme theme) {
    try {
      final core = _core;
      if (core == null) return;
      core.setThemeOverrides(theme);
    } on Object catch (err, st) {
      log.e('setThemeOverrides failed', err, st);
    }
  }

  /// Flushes the event queue to the server (consent-gated).
  static Future<void> flush() async {
    try {
      final core = _core;
      if (core == null) return;
      await core.flush();
    } on Object catch (err, st) {
      log.e('flush failed', err, st);
    }
  }

  /// Enables or disables debug logging.
  // ignore: avoid_positional_boolean_parameters
  static void setDebug(bool enabled) {
    log.setDebug(enabled);
  }

  /// Current anonymous identifier (empty string before [init]).
  static String get anonymousId => _core?.identity.anonymousId ?? '';

  /// Broadcast stream of prompt ids as they are shown on-device.
  static Stream<String> get onPromptShown =>
      _core?.onPromptShown ?? const Stream<String>.empty();

  /// Broadcast stream of response info (submission or dismissal).
  static Stream<PromptResponseInfo> get onResponse =>
      _core?.onResponse ?? const Stream<PromptResponseInfo>.empty();

  // ----- internal accessors used by RitmusProvider -----

  /// Internal: stream of prompt-show requests routed to the UI layer.
  static Stream<PromptShowRequest> get internalShowStream =>
      _core?.showRequests ?? const Stream<PromptShowRequest>.empty();

  /// Internal: reports a user response from the presenter.
  static void internalReportResponse(PromptResponseInfo info) {
    _core?.reportResponse(info);
  }

  /// Internal: reports that the sheet has been shown.
  static void internalReportShown(String promptId) {
    _core?.reportShown(promptId);
  }

  /// Internal: current theme overrides.
  static PromptTheme? get internalThemeOverrides => _core?.themeOverrides;
}
