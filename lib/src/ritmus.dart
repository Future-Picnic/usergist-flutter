import 'dart:async';

import 'internal/core.dart';
import 'internal/logger.dart';
import 'internal/transport/endpoints.dart';
import 'models/consent.dart';
import 'models/request.dart';
import 'models/response_info.dart';
import 'models/survey.dart';
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

  // ---------------- Surveys ----------------

  /// Host-app survey lifecycle handlers. Set before calling [openSurvey].
  static SurveyHandlers surveyHandlers = const SurveyHandlers();

  /// Returns the list of surveys currently open to this user. v1 surface:
  /// consent-gated scaffold — the full native multi-step renderer is a
  /// follow-up release. Returns an empty list today.
  static Future<List<SurveySummary>> getAvailableSurveys() async {
    try {
      final core = _core;
      if (core == null) return const <SurveySummary>[];
      if (core.consent.allowsSurvey != true) return const <SurveySummary>[];
      // v2: GET /v1/sdk/surveys/available once the renderer ships.
      return const <SurveySummary>[];
    } on Object catch (err, st) {
      log.e('getAvailableSurveys failed', err, st);
      return const <SurveySummary>[];
    }
  }

  /// Requests that the host app render the specified survey. The SDK
  /// notifies the host via [SurveyHandlers.onShow].
  static void openSurvey(String surveyId, {String? language}) {
    try {
      final core = _core;
      if (core == null) return;
      if (core.consent.allowsSurvey != true) return;
      surveyHandlers.onShow?.call(surveyId);
    } on Object catch (err, st) {
      log.e('openSurvey failed', err, st);
    }
  }

  /// Handles a Ritmus survey share link. Returns true when the URI is a
  /// recognized Ritmus survey link.
  static bool handleSurveyDeepLink(Uri uri) {
    try {
      final segments = uri.pathSegments;
      final pathToken = (segments.length >= 2 && segments[0] == 's') ? segments[1] : null;
      final queryToken = uri.queryParameters['survey'];
      final token = pathToken ?? queryToken;
      if (token == null || token.isEmpty) return false;
      log.d('survey.deep-link token=${token.substring(0, token.length.clamp(0, 8))}…');
      return true;
    } on Object catch (err, st) {
      log.e('handleSurveyDeepLink failed', err, st);
      return false;
    }
  }

  // ---------------- Feature Requests (5th pillar) ----------------
  // STATUS: API surface declared; HTTP + UI tracked in PARITY.md as the
  // Flutter-stub for this pillar.

  static RequestsHandlers requestsHandlers = const RequestsHandlers();

  /// Open the SDK-provided requests board UI. Host apps that want a
  /// fully custom UX can ignore this and call [getRequests] directly.
  /// The launcher requires a `BuildContext`; pass one via
  /// [openRequestsBoardIn] from within your widget tree.
  static void openRequestsBoard() {
    // No-op without a BuildContext; the typed launcher below is preferred.
  }

  /// Open the detail view for a specific request. Same caveat as
  /// [openRequestsBoard] — prefer [openRequestDetailIn] from a widget.
  static void openRequestDetail(String requestId) {
    // ignore: unused_local_variable
    final _ = requestId;
  }

  /// Submit a new request. Validates client-side per spec §7.
  static Future<FeatureRequest> submitRequest({
    required String title,
    required String description,
  }) async {
    if (title.isEmpty || title.length > 120) {
      throw ArgumentError('title required, max 120 chars');
    }
    if (description.isEmpty || description.length > 1500) {
      throw ArgumentError('description required, max 1500 chars');
    }
    final core = _core;
    if (core == null) throw StateError('Ritmus.start() has not run');
    final result = await core.requestsApi.submit(
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
      title: title,
      description: description,
    );
    if (result == null) throw StateError('submit failed');
    core.requestsCache.upsert(result);
    requestsHandlers.onSubmit?.call(result);
    return result;
  }

  /// Fetch a page of requests.
  static Future<GetRequestsResult> getRequests({
    GetRequestsOptions options = const GetRequestsOptions(),
  }) async {
    final core = _core;
    if (core == null) return const GetRequestsResult(items: [], nextCursor: null);
    return core.requestsApi.list(
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
      options: options,
    );
  }

  /// Fetch a single request by id.
  static Future<FeatureRequest?> getRequest(String requestId) async {
    final core = _core;
    if (core == null) return null;
    final r = await core.requestsApi.getOne(
      requestId: requestId,
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
    );
    if (r != null) core.requestsCache.upsert(r);
    return r;
  }

  /// Toggle upvote — idempotent, optimistic at the cache layer.
  static Future<RequestVote> voteOnRequest(
    String requestId, {
    required bool vote,
  }) async {
    final core = _core;
    if (core == null) throw StateError('Ritmus.start() has not run');
    final rollback = core.requestsCache.applyOptimisticVote(requestId, vote);
    final outcome = await core.requestsApi.vote(
      requestId: requestId,
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
      vote: vote,
    );
    if (outcome == null) {
      rollback();
      throw StateError('vote failed');
    }
    core.requestsCache.commitVote(requestId, outcome);
    requestsHandlers.onVote?.call(outcome);
    return outcome;
  }

  /// Toggle follow.
  static Future<RequestFollow> followRequest(
    String requestId, {
    required bool follow,
  }) async {
    final core = _core;
    if (core == null) throw StateError('Ritmus.start() has not run');
    final rollback = core.requestsCache.applyOptimisticFollow(requestId, follow);
    final outcome = await core.requestsApi.follow(
      requestId: requestId,
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
      follow: follow,
    );
    if (outcome == null) {
      rollback();
      throw StateError('follow failed');
    }
    core.requestsCache.commitFollow(requestId, outcome);
    requestsHandlers.onFollow?.call(outcome);
    return outcome;
  }

  /// Register host-app callbacks.
  static void setRequestsHandlers(RequestsHandlers handlers) {
    requestsHandlers = handlers;
  }
}
