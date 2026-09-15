import 'models/identity_state.dart';
import 'dart:async';

import 'internal/core.dart';
import 'internal/presentation_gate.dart';
import 'internal/logger.dart';
import 'internal/requests/requests_api.dart';
import 'internal/transport/endpoints.dart';
import 'ui/requests_host.dart';
import 'models/consent.dart';
import 'models/diagnostic.dart';
import 'models/inapp_message.dart';
import 'models/request.dart';
import 'models/response_info.dart';
import 'models/survey.dart';
import 'models/theme.dart';
import 'ui/prompt_presenter.dart';
import 'ui/inapp_presenter.dart';
import 'ui/survey_presenter.dart';

/// Deployment environment enum. Maps to a default base URL.
enum UserGistEnvironment {
  /// Production.
  production,

  /// Staging / pre-prod.
  staging,

  /// Local / development.
  development;

  /// Default API base URL for this environment.
  String get defaultUrl => switch (this) {
        UserGistEnvironment.production => DefaultApiUrls.production,
        UserGistEnvironment.staging => DefaultApiUrls.staging,
        UserGistEnvironment.development => DefaultApiUrls.development,
      };
}

/// Public static entrypoint to the UserGist feedback SDK.
///
/// All methods wrap their implementation in a try/catch so the SDK
/// never throws across its public boundary.
class UserGist {
  UserGist._();

  /// Current SDK version (kept in sync with pubspec).
  static const String sdkVersion = '0.1.4';

  static UserGistCore? _core;
  static void Function(PushSubscriptionState)? _pushSubscriptionHandler;
  static void setPushSubscriptionStateHandler(
      void Function(PushSubscriptionState)? handler) {
    _pushSubscriptionHandler = handler;
    _core?.onPushSubscriptionState = handler;
    _core?.notifyPushSubscription();
  }

  static SubjectTokenProvider? _subjectTokenProvider;
  static void Function(IdentityState)? _identityStateHandler;
  static IdentityState get identityState =>
      _core?.identityState ??
      const IdentityState(status: 'anonymous', anonymousId: '');
  static void setSubjectTokenProvider(SubjectTokenProvider? provider) {
    _subjectTokenProvider = provider;
    _core?.subjectTokenProvider = provider;
  }

  static void setIdentityStateHandler(void Function(IdentityState)? handler) {
    _identityStateHandler = handler;
    _core?.onIdentityState = handler;
    try {
      handler?.call(identityState);
    } on Object catch (error, stack) {
      log.e("identity observer failed", error, stack);
    }
  }

  static Future<IdentifyResult> identifyAsync(String userId,
      {Map<String, Object?>? properties, required String subjectToken}) async {
    try {
      return await _core?.identify(userId, properties, subjectToken) ??
          IdentifyResult.rejected;
    } on Object catch (error, stack) {
      log.e('identify failed', error, stack);
      return IdentifyResult.rejected;
    }
  }

  static Future<IdentifyResult> setUserProperties(
      Map<String, Object?> properties,
      {List<String> unset = const <String>[]}) async {
    try {
      return await _core?.setUserProperties(properties, unset) ??
          IdentifyResult.rejected;
    } on Object catch (error, stack) {
      log.e('setUserProperties failed', error, stack);
      return IdentifyResult.rejected;
    }
  }

  static Completer<void>? _initializing;
  static Future<bool>? _resetWork;
  static bool _resetPending = false;
  static final PresentationGate internalPresentationGate = PresentationGate();

  /// Pause campaign UI without stopping analytics or closing an active route.
  static void pausePresentation() => internalPresentationGate.setPaused(true);

  /// Call after the loaded screen and startup navigation have completed.
  static void resumePresentation() => internalPresentationGate.setPaused(false);

  /// Initializes the SDK. Safe to call multiple times — subsequent calls
  /// are ignored (the first configuration wins).
  static Future<void> init({
    required String writeKey,
    UserGistEnvironment environment = UserGistEnvironment.production,
    String? apiUrl,
    bool debug = false,
    bool presentationPaused = false,
    Duration flushInterval = const Duration(seconds: 15),
    int flushBatchSize = 100,
    int maxQueueSize = 1000,
    Duration triggerSyncInterval = const Duration(minutes: 5),
  }) async {
    if (_core != null) return;
    final pending = _initializing;
    if (pending != null) return pending.future;
    final initialized = Completer<void>();
    _initializing = initialized;
    try {
      internalPresentationGate.setPaused(presentationPaused);
      log.setDebug(debug);
      late final UserGistCore core;
      core = UserGistCore(
        presentationGate: internalPresentationGate,
        writeKey: writeKey,
        baseUrl: apiUrl ?? environment.defaultUrl,
        sdkVersion: sdkVersion,
        flushInterval: flushInterval,
        flushBatchSize: flushBatchSize,
        maxQueueSize: maxQueueSize,
        triggerSyncInterval: triggerSyncInterval,
        onSurveyInvite: (summary) {
          final invite = surveyHandlers.onInvite;
          if (invite != null) {
            try {
              invite(summary);
            } on Object catch (error, stack) {
              core.releaseSurveyReservation(summary.id);
              log.e('survey invite handler failed', error, stack);
            }
          } else {
            unawaited(
              core
                  .openSurvey(summary.id, source: summary.source)
                  .catchError((Object error, StackTrace stack) {
                core.releaseSurveyReservation(summary.id);
                log.e('triggered survey open failed', error, stack);
              }),
            );
          }
        },
      );
      core.onPushSubscriptionState = _pushSubscriptionHandler;
      core.subjectTokenProvider = _subjectTokenProvider;
      core.onIdentityState = _identityStateHandler;
      await core.start(deferNetworkDelivery: true);
      _core = core;
      if (!_resetPending) core.startNetworkDelivery();
    } on Object catch (err, st) {
      internalPresentationGate.invalidate();
      log.e('UserGist.init failed', err, st);
    } finally {
      _initializing = null;
      initialized.complete();
    }
  }

  /// Identifies the currently logged-in user with a stable id and
  /// optional properties.
  static Future<void> identify(
    String userId, {
    Map<String, Object?>? properties,
    required String subjectToken,
  }) async {
    try {
      final core = _core;
      if (core == null) return;
      await core.identify(userId, properties, subjectToken);
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

  /// Sets consent. Transport is blocked until at least one purpose is granted.
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

  /// Rebinds the last successfully registered token to an identified user.
  static Future<void> rebindPushToken(String externalId) async {
    try {
      await _core?.rebindPushToken(externalId);
    } on Object catch (err, st) {
      log.e('rebindPushToken failed', err, st);
    }
  }

  /// Sends a delivered/displayed/dismissed push receipt beacon.
  static Future<void> pushBeacon(
    String kind,
    String deliveryId, {
    String? actionButton,
  }) async {
    try {
      await _core?.pushBeacon(
        kind,
        deliveryId,
        actionButton: actionButton,
      );
    } on Object catch (err, st) {
      log.e('pushBeacon failed', err, st);
    }
  }

  /// Acknowledges a silent reachability ping.
  static Future<void> pushAckSilent(String pingId) async {
    try {
      await _core?.pushAckSilent(pingId);
    } on Object catch (err, st) {
      log.e('pushAckSilent failed', err, st);
    }
  }

  /// Records an application-open reachability beacon.
  static Future<void> pushAppOpen() async {
    try {
      await _core?.pushAppOpen();
    } on Object catch (err, st) {
      log.e('pushAppOpen failed', err, st);
    }
  }

  /// Fetches the remote push-channel registry.
  static Future<List<Map<String, Object?>>> pushFetchChannels() async {
    try {
      return await _core?.pushFetchChannels() ?? const <Map<String, Object?>>[];
    } on Object catch (err, st) {
      log.e('pushFetchChannels failed', err, st);
      return const <Map<String, Object?>>[];
    }
  }

  /// Updates a user-owned channel subscription.
  static Future<void> pushSetChannelSubscription(
    String channelId,
    bool subscribed,
  ) async {
    try {
      await _core?.pushSetChannelSubscription(channelId, subscribed);
    } on Object catch (err, st) {
      log.e('pushSetChannelSubscription failed', err, st);
    }
  }

  /// False leaves SDK work paused; fix secure storage and retry before login.
  static Future<bool> resetAsync() =>
      _resetWork ??= _performReset().whenComplete(() {
        _resetWork = null;
      });

  static Future<bool> _performReset() async {
    _resetPending = true;
    final initializing = _initializing;
    try {
      await initializing?.future;
      // Failed initialization cannot certify that stored identity was cleared.
      if (initializing != null && _core == null) return false;
      await _core?.reset();
      _resetPending = false;
      return true;
    } on Object catch (error, stack) {
      log.e('reset failed', error, stack);
      return false;
    }
  }

  /// Clears identity and local state (queue + caches + consent).
  static Future<void> reset() async {
    await resetAsync();
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

  /// Receives bounded, non-throwing SDK diagnostics in production.
  static void setDiagnosticHandler(
    void Function(SdkDiagnostic diagnostic)? handler,
  ) {
    log.setDiagnosticHandler(handler);
  }

  /// Current anonymous identifier (empty string before [init]).
  static String get anonymousId => _core?.identity.anonymousId ?? '';

  /// Stable identified-user ID accepted by the server, or null while the
  /// installation is anonymous.
  static String? get externalId => _core?.identity.externalId;

  /// Broadcast stream of prompt ids as they are shown on-device.
  static Stream<String> get onPromptShown =>
      _core?.onPromptShown ?? const Stream<String>.empty();

  /// Broadcast stream of response info (submission or dismissal).
  static Stream<PromptResponseInfo> get onResponse =>
      _core?.onResponse ?? const Stream<PromptResponseInfo>.empty();

  // ----- internal accessors used by UserGistProvider -----

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

  /// Internal: releases a reserved prompt after presentation fails.
  static void internalReportPromptPresentationFailed(String promptId) {
    _core?.releasePromptReservation(promptId);
  }

  /// Internal: current theme overrides.
  static PromptTheme? get internalThemeOverrides => _core?.themeOverrides;

  /// Internal: authenticated in-app messages routed to the UI provider.
  static Stream<InAppShowRequest> get internalInAppShowStream =>
      _core?.inAppShowRequests ?? const Stream<InAppShowRequest>.empty();

  /// Internal: fetched survey attempts routed to the native provider.
  static Stream<SurveyShowRequest> get internalSurveyShowStream =>
      _core?.surveyShowRequests ?? const Stream<SurveyShowRequest>.empty();

  /// Internal: tells the mounted provider to close SDK-owned routes on reset.
  static Stream<void> get internalResetStream =>
      _core?.resetRequests ?? const Stream<void>.empty();

  /// Internal: reports that an in-app message reached the screen.
  static void internalReportInAppShown(String messageId) {
    _core?.reportInAppShown(messageId);
    inAppHandlers.onShow?.call(messageId);
  }

  /// Internal: reports user or timer dismissal.
  static void internalReportInAppDismissed(String messageId, String reason) {
    _core?.reportInAppDismissed(messageId, reason);
    inAppHandlers.onDismiss?.call(messageId, reason);
  }

  /// Internal: reports a CTA click and its action metadata.
  static void internalReportInAppCta(
    String messageId,
    InAppCta cta,
    int index,
  ) {
    _core?.reportInAppCta(messageId, cta, index);
    final click = InAppCtaClick(
      messageId: messageId,
      action: cta.action,
      target: cta.target,
      label: cta.label,
      index: index,
      actionJson: cta.actionJson,
    );
    try {
      inAppHandlers.onCtaClick?.call(click);
    } on Object {
      // Host callbacks cannot interrupt action dispatch or modal cleanup.
    }
    if (cta.action == 'json' && cta.actionJson != null) {
      try {
        inAppHandlers.onJsonAction?.call(cta.actionJson!, click);
      } on Object {
        // Host action executors must not throw across the SDK boundary.
      }
    }
  }

  /// Internal: persists the SDK-owned survey presenter's current answers.
  static Future<void> internalSaveSurveyProgress(
    String attemptId,
    String? currentQuestionId,
    Map<String, Object?> answers,
  ) async {
    await _core?.saveSurveyProgress(attemptId, currentQuestionId, answers);
  }

  /// Internal: submits an SDK-owned survey attempt exactly once.
  static Future<bool> internalCompleteSurvey(
    String attemptId,
    Map<String, Object?> answers,
  ) async =>
      await _core?.completeSurvey(attemptId, answers) ?? false;

  /// Internal: marks a started survey attempt as abandoned.
  static Future<bool> internalAbandonSurvey(String attemptId) async =>
      await _core?.abandonSurvey(attemptId) ?? false;

  /// Internal: reports successful survey presentation to the runtime.
  static void internalReportSurveyShown(String surveyId) {
    _core?.reportSurveyShown(surveyId);
    surveyHandlers.onShow?.call(surveyId);
  }

  /// Internal: releases a reserved survey after presentation fails.
  static void internalReportSurveyPresentationFailed(String surveyId) {
    _core?.releaseSurveyReservation(surveyId);
  }

  /// Internal: forwards a completed survey lifecycle event to the host.
  static void internalReportSurveyComplete(String surveyId, String attemptId) {
    surveyHandlers.onComplete?.call(surveyId, attemptId);
  }

  /// Internal: forwards an abandoned survey lifecycle event to the host.
  static void internalReportSurveyAbandon(String surveyId, String attemptId) {
    surveyHandlers.onAbandon?.call(surveyId, attemptId);
  }

  // ---------------- Surveys ----------------

  /// Host-app survey lifecycle handlers. Set before calling [openSurvey].
  static SurveyHandlers surveyHandlers = const SurveyHandlers();

  /// Replaces the lifecycle callbacks for SDK-rendered surveys.
  static void setSurveyHandlers(SurveyHandlers handlers) {
    surveyHandlers = handlers;
  }

  /// Optional lifecycle handlers for SDK-rendered in-app messages.
  static InAppHandlers inAppHandlers = const InAppHandlers();

  /// Replaces the current in-app lifecycle handler set.
  static void setInAppHandlers(InAppHandlers handlers) {
    inAppHandlers = handlers;
  }

  /// Returns the list of surveys currently open to this user.
  static Future<List<SurveySummary>> getAvailableSurveys() async {
    try {
      final core = _core;
      if (core == null) return const <SurveySummary>[];
      if (core.consent.allowsSurvey != true) return const <SurveySummary>[];
      return await core.getAvailableSurveys();
    } on Object catch (err, st) {
      log.e('getAvailableSurveys failed', err, st);
      return const <SurveySummary>[];
    }
  }

  /// Fetches and presents a specific survey using the native renderer.
  static Future<void> openSurvey(String surveyId, {String? language}) async {
    try {
      final core = _core;
      if (core == null) return;
      if (core.consent.allowsSurvey != true) return;
      await core.openSurvey(surveyId, language: language);
    } on Object catch (err, st) {
      _core?.releaseSurveyReservation(surveyId);
      log.e('openSurvey failed', err, st);
    }
  }

  /// Handles a UserGist survey share link. Returns true when the URI is a
  /// recognized UserGist survey link.
  static bool handleSurveyDeepLink(Uri uri) {
    try {
      final segments = uri.pathSegments;
      final pathToken =
          (segments.length >= 2 && segments[0] == 's') ? segments[1] : null;
      final queryToken = uri.queryParameters['survey'];
      final token = pathToken ?? queryToken;
      if (token == null || token.isEmpty) return false;
      final core = _core;
      if (core == null || core.consent.allowsSurvey != true) return false;
      unawaited(
        core
            .resolveSurveyLink(token)
            .catchError((Object error, StackTrace stack) {
          log.e('resolveSurveyLink failed', error, stack);
        }),
      );
      return true;
    } on Object catch (err, st) {
      log.e('handleSurveyDeepLink failed', err, st);
      return false;
    }
  }

  // ---------------- Feature Requests (5th pillar) ----------------
  // HTTP transport, optimistic state, search, and SDK-owned UI are wired.

  /// Host-app lifecycle handlers for the SDK-owned feature-request surface.
  static RequestsHandlers requestsHandlers = const RequestsHandlers();

  /// Open the SDK-provided requests board UI. Drop-in: as long as the
  /// host app has mounted `UserGistProvider` below its Navigator (or supplied
  /// its navigator key), no further wiring is required.
  static void openRequestsBoard() {
    RequestsNav.board();
  }

  /// Open the detail view for a specific request.
  static void openRequestDetail(String requestId) {
    RequestsNav.detail(requestId);
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
    if (core == null) throw StateError('UserGist.start() has not run');
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
    if (core == null) {
      return const GetRequestsResult(items: [], nextCursor: null);
    }
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
    if (core == null) throw StateError('UserGist.start() has not run');
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
    if (core == null) throw StateError('UserGist.start() has not run');
    final rollback =
        core.requestsCache.applyOptimisticFollow(requestId, follow);
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

  /// Fetch comments for a request, ordered oldest-first.
  static Future<List<FlutterRequestComment>> getComments(
    String requestId,
  ) async {
    final core = _core;
    if (core == null) return const [];
    return core.requestsApi.comments(
      requestId: requestId,
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
    );
  }

  /// Post a comment on a request.
  static Future<FlutterRequestComment?> postComment(
    String requestId,
    String body,
  ) async {
    if (body.trim().isEmpty || body.length > 1000) {
      throw ArgumentError('comment body required, max 1000 chars');
    }
    final core = _core;
    if (core == null) throw StateError('UserGist.start() has not run');
    return core.requestsApi.postComment(
      requestId: requestId,
      anonymousId: core.identity.anonymousId,
      externalId: core.identity.externalId,
      body: body,
    );
  }

  /// Edit one of the viewer's own comments.
  static Future<FlutterRequestComment?> editComment(
    String requestId,
    String commentId,
    String body,
  ) async {
    if (body.trim().isEmpty || body.length > 1000) {
      throw ArgumentError('comment body required, max 1000 chars');
    }
    final core = _core;
    if (core == null) throw StateError('UserGist.start() has not run');
    return core.requestsApi.editComment(
      requestId: requestId,
      commentId: commentId,
      anonymousId: core.identity.anonymousId,
      body: body,
    );
  }

  /// Delete one of the viewer's own comments.
  static Future<bool> deleteComment(
    String requestId,
    String commentId,
  ) async {
    final core = _core;
    if (core == null) return false;
    return core.requestsApi.deleteComment(
      requestId: requestId,
      commentId: commentId,
      anonymousId: core.identity.anonymousId,
    );
  }

  /// Fetch per-app branding (entry label, accent color, etc.). The
  /// SDK UI uses this; host apps rarely need to call it directly.
  static Future<FlutterRequestBranding?> getRequestBranding() async {
    final core = _core;
    if (core == null) return null;
    return core.requestsApi.getBranding();
  }

  /// Register host-app callbacks.
  static void setRequestsHandlers(RequestsHandlers handlers) {
    requestsHandlers = handlers;
  }
}
