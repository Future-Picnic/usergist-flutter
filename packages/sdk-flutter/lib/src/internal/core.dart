import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import '../models/any_value.dart';
import '../push/push.dart';
import '../models/consent.dart';
import '../models/context.dart';
import '../models/event.dart';
import '../models/inapp_message.dart';
import '../models/prompt.dart';
import '../models/response_info.dart';
import '../models/survey.dart';
import '../models/theme.dart';
import '../ui/prompt_presenter.dart';
import '../ui/inapp_presenter.dart';
import '../ui/survey_presenter.dart';
import 'consent_store.dart';
import 'device_context.dart';
import 'event_queue.dart';
import 'identity.dart';
import 'instruction_dedupe.dart';
import 'json.dart';
import 'lifecycle/app_lifecycle.dart';
import 'logger.dart';
import 'mutation_queue.dart';
import 'requests/requests_api.dart';
import 'requests/requests_cache.dart';
import 'secure_store.dart';
import 'storage.dart';
import 'survey_store.dart';
import 'transport/api_client.dart';
import 'transport/endpoints.dart';
import 'transport/retry_policy.dart';
import 'uid.dart';
import 'triggers/frequency_cap.dart';
import 'triggers/campaign_rules_cache.dart';
import 'triggers/rules_cache.dart';
import 'triggers/segment_evaluator.dart';
import 'triggers/trigger_matcher.dart';

/// The actual implementation of the SDK. Owns all internal state and
/// is the singleton instance that [UserGist] delegates to.
///
/// This class is deliberately library-internal (exported only through
/// `usergist_feedback/src/...`). Do not import directly from apps.
class UserGistCore {
  /// Creates a core instance. Call [start] before using it.
  UserGistCore({
    required this.writeKey,
    required this.baseUrl,
    required this.sdkVersion,
    required this.flushInterval,
    required this.flushBatchSize,
    required this.maxQueueSize,
    required this.triggerSyncInterval,
    this.onSurveyInvite,
  });

  /// Write key for this app.
  final String writeKey;

  /// Resolved base URL.
  final String baseUrl;

  /// SDK version (forwarded from the public API).
  final String sdkVersion;

  /// Timer period for background flushes.
  final Duration flushInterval;

  /// Max events per flush.
  final int flushBatchSize;

  /// Maximum queued-event count.
  final int maxQueueSize;

  /// Timer period for trigger syncs.
  final Duration triggerSyncInterval;

  /// Delivers server-issued survey offers to the public handler surface.
  final void Function(SurveySummary summary)? onSurveyInvite;

  late final SharedPrefsStore _kv;
  late final SecureKeyValueStore _secureStore;

  /// Persistent identity store.
  late final IdentityStore identity;

  late final ConsentStore _consent;
  late final EventQueue _queue;
  late final MutationQueue _mutations;
  late final LocalInstructionDedupe _localInstructionDedupe;
  late final SurveyStore _surveyStore;
  late final RulesCache _rulesCache;
  late final CampaignRulesCache _campaignRules;
  late final FrequencyCapStore _freqCaps;
  late final TriggerMatcher _matcher;
  late final ApiClient _api;
  late final AppLifecycle _lifecycle;

  /// In-memory cache for optimistic vote/follow mutations.
  final RequestsCache requestsCache = RequestsCache();

  /// HTTP helper for the Feature Requests pillar. Initialised in `start()`.
  RequestsApi get requestsApi => RequestsApi(_api);

  final StreamController<PromptShowRequest> _showCtrl =
      StreamController<PromptShowRequest>.broadcast();
  final StreamController<String> _shownCtrl =
      StreamController<String>.broadcast();
  final StreamController<PromptResponseInfo> _respCtrl =
      StreamController<PromptResponseInfo>.broadcast();
  final StreamController<InAppShowRequest> _inAppCtrl =
      StreamController<InAppShowRequest>.broadcast();
  final StreamController<SurveyShowRequest> _surveyCtrl =
      StreamController<SurveyShowRequest>.broadcast();
  final StreamController<void> _resetCtrl = StreamController<void>.broadcast();

  final Map<String, DateTime> _shownAt = <String, DateTime>{};
  final Map<String, Map<int, int>> _eventCounts = <String, Map<int, int>>{};
  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};
  final Map<String, List<DateTime>> _eventHistory = <String, List<DateTime>>{};
  final Map<String, DateTime> _surveyCooldownByCampaign = <String, DateTime>{};
  final Set<String> _pendingPromptCapIds = <String>{};
  final Set<String> _pendingSurveyCapIds = <String>{};
  bool _appOpenPending = false;
  int _resetGeneration = 0;
  bool _resetInProgress = false;
  Map<String, Object?> _identityProperties = <String, Object?>{};

  String? _appVersion;
  String? _locale;
  String? _timezone;
  String? _osName;
  String? _osVersion;
  String? _deviceModel;
  String? _sessionId;

  Timer? _flushTimer;
  Timer? _triggerTimer;
  Future<void>? _inflightFlush;
  Future<void>? _sessionFuture;
  Future<void>? _instructionFuture;
  Future<Set<String>>? _mutationFuture;
  String? _subjectToken;
  String? _lastPushToken;
  bool _started = false;

  static const String _subjectTokenKey = 'session.subjectToken';
  static const String _instructionCursorKey = 'instructions.cursor';
  static const String _seenInstructionsKey = 'instructions.seen';
  static const String _eventHistoryKey = 'userState.eventHistory';

  /// Caller-side theme overrides (updated by [setThemeOverrides]).
  PromptTheme? themeOverrides;

  /// Stream of prompt-show requests for the UI presenter.
  Stream<PromptShowRequest> get showRequests => _showCtrl.stream;

  /// Stream of prompt-shown notifications (public API).
  Stream<String> get onPromptShown => _shownCtrl.stream;

  /// Stream of response info (public API).
  Stream<PromptResponseInfo> get onResponse => _respCtrl.stream;

  /// Stream of authenticated in-app display instructions for the UI layer.
  Stream<InAppShowRequest> get inAppShowRequests => _inAppCtrl.stream;

  /// Stream of fetched surveys with an authorized server attempt.
  Stream<SurveyShowRequest> get surveyShowRequests => _surveyCtrl.stream;

  /// Signals providers to dismiss every SDK-owned surface during reset.
  Stream<void> get resetRequests => _resetCtrl.stream;

  /// Public read accessor for current consent state.
  Consent get consent => _consent.current;

  /// Boots the core: hydrates state, boots timers, collects context.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _kv = SharedPrefsStore(writeKey: writeKey);
    _secureStore = SecureKeyValueStore(writeKey: writeKey, legacy: _kv);
    // Secrets (identity + consent) live in the encrypted store; bulk
    // frequency-cap state stays in plaintext prefs (not secret, large).
    identity = IdentityStore(_secureStore);
    _consent = ConsentStore(_secureStore);
    _mutations = MutationQueue(_secureStore);
    _localInstructionDedupe = LocalInstructionDedupe(_kv);
    _surveyStore = SurveyStore(_kv);
    _freqCaps = FrequencyCapStore(_kv);
    await Future.wait<void>(<Future<void>>[
      identity.hydrate(),
      _consent.hydrate(),
      _mutations.hydrate(),
      _localInstructionDedupe.hydrate(),
      _surveyStore.hydrate(),
      _freqCaps.hydrate(),
    ]);
    final storedIdentityProperties = await identity.readExternalProperties();
    if (storedIdentityProperties != null) {
      _identityProperties = safeDecodeMap(storedIdentityProperties);
    }
    _restoreEventHistory(await _kv.readString(_eventHistoryKey));

    final dir = await usergistSupportDir(writeKey);
    _queue = EventQueue(
      file: File('${dir.path}/queue.jsonl'),
      maxSize: maxQueueSize,
    );
    _rulesCache = RulesCache(file: File('${dir.path}/rules.json'));
    _campaignRules = CampaignRulesCache(
      surveysFile: File('${dir.path}/survey_rules.json'),
      inAppFile: File('${dir.path}/inapp_rules.json'),
    );
    await Future.wait<void>(<Future<void>>[
      _queue.hydrate(),
      _rulesCache.hydrate(),
      _campaignRules.hydrate(),
    ]);

    _matcher = TriggerMatcher(
      rulesCache: _rulesCache,
      frequencyCapStore: _freqCaps,
    );
    _api = ApiClient(
      baseUrl: baseUrl,
      writeKey: writeKey,
      sdkVersion: sdkVersion,
      retryPolicy: RetryPolicy(),
    );
    try {
      await _ensureSubjectSession();
      await _flushMutations();
    } on Object catch (error, stack) {
      log.e(
        'subject session warmup failed; background retry scheduled',
        error,
        stack,
      );
    }
    _sessionId = _newSessionId();

    _runAsync(_collectContext(), 'device context collection');

    _lifecycle = AppLifecycle(
      onResumed: () {
        _runAsync(flush(), 'foreground flush');
        _runAsync(
          _syncTriggers().whenComplete(_requestAppOpen),
          'foreground trigger sync',
        );
        _runAsync(pollInstructions(), 'foreground instruction poll');
      },
      onPaused: () {
        _runAsync(flush(), 'background flush');
      },
    );
    _lifecycle.attach();

    _flushTimer = Timer.periodic(
      flushInterval,
      (_) => _runAsync(flush(), 'periodic flush'),
    );
    _triggerTimer = Timer.periodic(
      triggerSyncInterval,
      (_) => _runAsync(_syncTriggers(), 'periodic trigger sync'),
    );
    _runAsync(
      _syncTriggers().whenComplete(_requestAppOpen),
      'initial trigger sync',
    );
    _runAsync(pollInstructions(), 'initial instruction poll');

    log.d('SDK started (baseUrl=$baseUrl, anonId=${identity.anonymousId})');
  }

  /// Replaces the caller-side theme overrides.
  void setThemeOverrides(PromptTheme theme) {
    themeOverrides = theme;
  }

  /// Identifies the user.
  Future<void> identify(
    String userId,
    Map<String, Object?>? properties,
    String subjectToken,
  ) async {
    if (userId.isEmpty) {
      throw ArgumentError('identify requires a non-empty userId');
    }
    if (!subjectToken.startsWith('st_')) {
      throw ArgumentError('identify requires a server-minted subject token');
    }
    final clean = sanitizeProperties(properties);
    final mutationId = await _mutations.enqueue(
      MutationKind.identify,
      MutationPurpose.essential,
      <String, Object?>{
        'subjectToken': subjectToken,
        'anonymousId': identity.anonymousId,
        'externalId': userId,
        if (_consent.isAnalyticsGranted && clean.isNotEmpty)
          'properties': clean,
      },
      dedupeKey: 'identify:$userId',
    );
    await _flushMutations();
    if (_mutations.contains(mutationId)) {
      throw StateError('identify is stored locally and pending retry');
    }
  }

  /// Tracks an event.
  void track(
    String name,
    Map<String, Object?>? properties, {
    EventPurpose purpose = EventPurpose.analytics,
  }) {
    if (name.isEmpty) {
      throw ArgumentError('track requires a non-empty event name');
    }
    final now = DateTime.now().toUtc();
    final clean = sanitizeProperties(properties);
    final event = IngestEvent(
      eventId: newUuid(),
      purpose: purpose,
      name: name,
      timestamp: now.toIso8601String(),
      anonymousId: identity.anonymousId,
      externalId: identity.externalId,
      properties: clean,
      sessionId: _sessionId,
      sdkVersion: sdkVersion,
      appVersion: _appVersion,
    );
    _runAsync(_queue.append(event), 'event persistence');
    _recordLocalEvent(name, now);
    _maybeFire(name, clean, event.eventId);
    _runAsync(flush(), 'event flush');
  }

  /// Sets consent and flushes if feedback consent was newly granted.
  Future<void> setConsent(Consent purposes) async {
    final previous = _consent.current;
    await _consent.set(purposes);
    final current = _consent.current;
    await _api.postJson(SdkEndpoints.consent, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'externalId': identity.externalId,
      'purposes': _consent.current.toResolvedJson(),
      'version': _consent.version,
      'effectiveAt': _consent.updatedAt.toIso8601String(),
    });
    if (purposes.analytics == false) {
      await _queue.removePurpose(EventPurpose.analytics);
    }
    if (purposes.feedback == false) {
      await _queue.removePurpose(EventPurpose.feedback);
      await _mutations.removePurpose(MutationPurpose.feedback);
      _pendingPromptCapIds.clear();
    }
    if (purposes.survey == false) {
      await _mutations.removePurpose(MutationPurpose.survey);
      _pendingSurveyCapIds.clear();
    }
    if ((previous.analytics != true && current.analytics == true) ||
        (previous.feedback != true && current.feedback == true)) {
      await flush();
    }
    if ((previous.feedback != true && current.feedback == true) ||
        (previous.survey != true && current.survey == true)) {
      await _syncTriggers();
      _emitPendingAppOpenIfReady();
    }
  }

  /// Registers a device token with the control plane. Consent-gated on push.
  Future<void> registerPushToken(
    String token,
    String platform,
    String environment,
  ) async {
    if (!_consent.isPushGranted) return;
    final result = await _api.postJson(
      SdkEndpoints.pushRegisterToken,
      <String, Object?>{
        'anonymousId': identity.anonymousId,
        'externalId': identity.externalId,
        'token': token,
        'platform': platform,
        'environment': environment,
        'language': null,
        'timezone': DateTime.now().timeZoneName,
        'sdkVersion': sdkVersion,
        'optIn': true,
      },
    );
    if (result.success) _lastPushToken = token;
  }

  Future<void> invalidatePushToken(String token) async {
    final result = await _api.postJson(
      SdkEndpoints.pushInvalidateToken,
      <String, Object?>{
        'anonymousId': identity.anonymousId,
        'token': token,
      },
    );
    if (result.success && _lastPushToken == token) _lastPushToken = null;
  }

  /// Rebinds a registered token after a successful identified-subject swap.
  Future<void> rebindPushToken(String externalId) async {
    final token = _lastPushToken;
    if (token == null || token.isEmpty || externalId.isEmpty) return;
    await _api.postJson(SdkEndpoints.pushRebind, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'externalId': externalId,
      'token': token,
    });
  }

  Future<void> pushBeacon(
    String kind,
    String deliveryId, {
    String? actionButton,
  }) async {
    final path = switch (kind) {
      'delivered' => SdkEndpoints.pushDelivered,
      'displayed' => SdkEndpoints.pushDisplayed,
      'dismissed' => SdkEndpoints.pushDismissed,
      _ => null,
    };
    if (path == null || deliveryId.isEmpty) return;
    await _api.postJson(path, <String, Object?>{
      'deliveryId': deliveryId,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      if (actionButton != null) 'actionButton': actionButton,
    });
  }

  Future<void> pushAckSilent(String pingId) async {
    if (pingId.isEmpty) return;
    await _api.postJson(SdkEndpoints.pushSilentAck, <String, Object?>{
      'pingId': pingId,
      'anonymousId': identity.anonymousId,
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> pushAppOpen() async {
    if (_lastPushToken == null) return;
    await _api.postJson(SdkEndpoints.pushAppOpen, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> pushFetchChannels() async {
    final result = await _api.getJson(SdkEndpoints.pushChannels);
    final channels = result.data?['channels'];
    if (!result.success || channels is! List<Object?>) {
      return const <Map<String, Object?>>[];
    }
    return channels.whereType<Map<String, Object?>>().toList(growable: false);
  }

  Future<void> pushSetChannelSubscription(
    String channelId,
    bool subscribed,
  ) async {
    if (channelId.isEmpty) return;
    await _api.postJson(
      SdkEndpoints.pushChannelSubscription,
      <String, Object?>{
        'anonymousId': identity.anonymousId,
        'channelId': channelId,
        'subscribed': subscribed,
      },
    );
  }

  /// Fetches survey offers authorized for the current anonymous/identified
  /// subject.
  Future<List<SurveySummary>> getAvailableSurveys() async {
    if (!_consent.current.allowsSurvey) return const <SurveySummary>[];
    final result = await _api.getJson(
      SdkEndpoints.availableSurveys,
      query: <String, String>{
        'anonymousId': identity.anonymousId,
        if (identity.externalId != null) 'externalId': identity.externalId!,
      },
    );
    if (!result.success) return const <SurveySummary>[];
    final raw = result.data?['surveys'];
    if (raw is! List<Object?>) return const <SurveySummary>[];
    return raw
        .whereType<Map<String, Object?>>()
        .map(SurveySummary.fromJson)
        .toList(growable: false);
  }

  /// Resolves a share token and emits the resulting survey offer.
  Future<void> resolveSurveyLink(String token) async {
    if (!_consent.current.allowsSurvey) return;
    final result = await _api.postJson(
      SdkEndpoints.resolveSurveyLink,
      <String, Object?>{
        'token': token,
        'anonymousId': identity.anonymousId,
        'externalId': identity.externalId,
      },
    );
    if (!result.success) return;
    if (result.data?['consentRequired'] == true) return;
    final surveyId = result.data?['surveyId'];
    if (surveyId is! String) return;
    onSurveyInvite?.call(
      SurveySummary(
        id: surveyId,
        name: result.data?['name'] as String? ?? '',
        mode: 'link_only',
        source: 'link',
      ),
    );
  }

  /// Fetches a survey, creates or resumes its server-owned attempt, then
  /// hands both to the native renderer.
  Future<void> openSurvey(
    String surveyId, {
    String? language,
    String source = 'on_demand',
  }) async {
    if (!_consent.current.allowsSurvey || surveyId.isEmpty) return;
    final cachedSurvey = _campaignRules.survey(surveyId)?.survey;
    SurveyCampaignWithFlow survey;
    if (cachedSurvey != null) {
      survey = cachedSurvey;
    } else {
      final surveyResult = await _api.getJson(
        SdkEndpoints.survey(surveyId),
        query: <String, String>{
          'anonymousId': identity.anonymousId,
          if (identity.externalId != null) 'externalId': identity.externalId!,
          if (language != null && language.isNotEmpty) 'language': language,
        },
      );
      if (!surveyResult.success || surveyResult.data == null) {
        throw StateError('survey fetch failed (${surveyResult.status})');
      }
      survey = SurveyCampaignWithFlow.fromJson(surveyResult.data!);
    }
    if (survey.id.isEmpty || survey.flow.questions.isEmpty) {
      throw const FormatException('survey payload is incomplete');
    }
    final acceptedSource = const <String>{
      'triggered',
      'scheduled',
      'link',
      'on_demand',
      'test',
    }.contains(source)
        ? source
        : 'on_demand';
    final attemptResult = await _api.postJson(
      SdkEndpoints.surveyAttempts(surveyId),
      <String, Object?>{
        'anonymousId': identity.anonymousId,
        'externalId': identity.externalId,
        'source': acceptedSource,
        if (language != null && language.isNotEmpty) 'language': language,
        'resume': true,
        'sdkVersion': sdkVersion,
        'appVersion': _appVersion,
        'platform': 'flutter',
      },
    );
    if (!attemptResult.success || attemptResult.data == null) {
      throw StateError('survey attempt failed (${attemptResult.status})');
    }
    final serverAttempt = SurveyAttemptSession.fromJson(attemptResult.data!);
    final attempt = _surveyStore.merge(surveyId, serverAttempt);
    if (attempt.attemptId.isEmpty) {
      throw const FormatException('survey attempt id is missing');
    }
    await _surveyStore.upsert(surveyId, attempt);
    _surveyCtrl.add(
      SurveyShowRequest(
        survey: survey,
        attempt: attempt,
        source: acceptedSource,
      ),
    );
  }

  Future<void> saveSurveyProgress(
    String attemptId,
    String? currentQuestionId,
    Map<String, Object?> answers,
  ) async {
    await _surveyStore.update(attemptId, currentQuestionId, answers);
    final result = await _api.patchJson(
      SdkEndpoints.surveyProgress(attemptId),
      <String, Object?>{
        'currentQuestionId': currentQuestionId,
        'progressSnapshot': answers,
      },
    );
    if (!result.success) {
      log.w('survey progress deferred (${result.status})');
    }
  }

  Future<bool> completeSurvey(
    String attemptId,
    Map<String, Object?> answers,
  ) async {
    if (_resetInProgress) return false;
    final deliveryGeneration = _resetGeneration;
    final mutationId = await _mutations.enqueue(
      MutationKind.surveyComplete,
      MutationPurpose.survey,
      <String, Object?>{
        'attemptId': attemptId,
        'body': <String, Object?>{
          'finalAnswers': answers.entries
              .map(
                (entry) => <String, Object?>{
                  'questionId': entry.key,
                  'value': entry.value,
                },
              )
              .toList(growable: false),
        },
      },
      dedupeKey: 'survey-complete:$attemptId',
    );
    final rejected = await _flushMutations();
    // Once encrypted persistence accepts the completion, the survey is done
    // from the user's perspective. A queued mutation is retried by lifecycle
    // sync and must not force the user to submit the same answers again.
    final accepted = !_resetInProgress &&
        _resetGeneration == deliveryGeneration &&
        !rejected.contains(mutationId);
    if (accepted) await _surveyStore.removeAttempt(attemptId);
    return accepted;
  }

  Future<bool> abandonSurvey(String attemptId) async {
    await _mutations.enqueue(
      MutationKind.surveyAbandon,
      MutationPurpose.survey,
      <String, Object?>{'attemptId': attemptId},
      dedupeKey: 'survey-abandon:$attemptId',
    );
    await _flushMutations();
    // Abandon closes the modal once the transition is durably recorded;
    // delivery may continue from the encrypted queue while offline.
    await _surveyStore.removeAttempt(attemptId);
    return true;
  }

  /// Clears all local state.
  Future<void> reset() async {
    if (_resetInProgress) return;
    _resetInProgress = true;
    _resetGeneration += 1;
    _resetCtrl.add(null);
    try {
      final session = _sessionFuture;
      final mutations = _mutationFuture;
      final inflight = <Future<Object?>>[
        if (session != null) session.then<Object?>((_) => null),
        if (mutations != null) mutations.then<Object?>((_) => null),
      ];
      if (inflight.isNotEmpty) {
        await Future.wait<Object?>(
          inflight.map(
            (future) => future.catchError((Object _, StackTrace __) => null),
          ),
        );
      }
      if (identical(_sessionFuture, session)) _sessionFuture = null;
      if (identical(_mutationFuture, mutations)) _mutationFuture = null;
      await _api.postJson(
        SdkEndpoints.sessionRevoke,
        const <String, Object?>{},
      );
      await _queue.clear();
      await _mutations.clear();
      await _rulesCache.clear();
      await _campaignRules.clear();
      await _surveyStore.clear();
      await _freqCaps.clear();
      await _consent.clear();
      await identity.reset();
      await _secureStore.remove(_subjectTokenKey);
      await _kv.remove(_instructionCursorKey);
      await _kv.remove(_seenInstructionsKey);
      await _kv.remove(_eventHistoryKey);
      await _localInstructionDedupe.clear();
      _subjectToken = null;
      _lastPushToken = null;
      _api.setSubjectToken(null);
      _shownAt.clear();
      _eventCounts.clear();
      _lastEventAt.clear();
      _eventHistory.clear();
      _surveyCooldownByCampaign.clear();
      _pendingPromptCapIds.clear();
      _pendingSurveyCapIds.clear();
      _appOpenPending = false;
      _identityProperties.clear();
      _sessionId = _newSessionId();
      await _ensureSubjectSession(allowDuringReset: true);
    } finally {
      _resetInProgress = false;
    }
  }

  /// Flushes the event queue to the server. Consent-gated.
  Future<void> flush() async {
    try {
      await _ensureSubjectSession();
    } on Object catch (error, stack) {
      log.e('subject session retry failed', error, stack);
      return;
    }
    // Essential mutations (notably identify) must keep retrying even when the
    // host has denied both event purposes. They are queued independently from
    // analytics/feedback events and are required to keep subject state sound.
    await _flushMutations();
    if (!_consent.isAnalyticsGranted && !_consent.isFeedbackGranted) {
      await pollInstructions();
      return;
    }
    final inflight = _inflightFlush;
    if (inflight != null) return inflight;
    final completer = Completer<void>();
    _inflightFlush = completer.future;
    try {
      while (!_queue.isEmpty) {
        final allowed = _queue.peek(_queue.length).where((event) {
          return event.purpose == EventPurpose.analytics
              ? _consent.isAnalyticsGranted
              : _consent.isFeedbackGranted;
        }).toList(growable: false);
        if (allowed.isEmpty) break;
        final first = allowed.first;
        final batch = allowed
            .where(
              (event) =>
                  event.anonymousId == first.anonymousId &&
                  event.externalId == first.externalId,
            )
            .take(flushBatchSize)
            .toList(growable: false);
        if (batch.isEmpty) break;
        final payload = <String, Object?>{
          'events': batch.map((e) => e.toWireJson()).toList(growable: false),
          'context': _contextFor(first).toJson(),
        };
        final res = await _api.postJson(SdkEndpoints.ingest, payload);
        if (!res.success) {
          final permanent = res.status != null &&
              res.status! >= 400 &&
              res.status! < 500 &&
              res.status != 429;
          if (permanent) {
            if (batch.length == 1) {
              await _queue.remove(<String>[first.eventId]);
              log.w('quarantined permanently rejected event ${first.eventId}');
              continue;
            }
            final single = await _api.postJson(
              SdkEndpoints.ingest,
              <String, Object?>{
                'events': <Object?>[first.toWireJson()],
                'context': _contextFor(first).toJson(),
              },
            );
            if (single.success ||
                (single.status != null &&
                    single.status! >= 400 &&
                    single.status! < 500 &&
                    single.status != 429)) {
              await _queue.remove(<String>[first.eventId]);
              if (!single.success) {
                log.w(
                  'quarantined permanently rejected event ${first.eventId}',
                );
              }
              continue;
            }
          }
          log.w('ingest failed (${res.status}): ${res.error}');
          break;
        }
        await _queue.remove(batch.map((event) => event.eventId));
      }
    } finally {
      _inflightFlush = null;
      if (!completer.isCompleted) completer.complete();
    }
    await pollInstructions();
    await _flushMutations();
  }

  /// Pulls, durably records, dispatches, then acknowledges server-to-SDK
  /// instructions. Concurrent lifecycle/flush callers share one poll.
  Future<void> pollInstructions() {
    final existing = _instructionFuture;
    if (existing != null) return existing;
    final future = _performInstructionPoll();
    _instructionFuture = future;
    return future.whenComplete(() {
      if (identical(_instructionFuture, future)) _instructionFuture = null;
    });
  }

  Future<void> _performInstructionPoll() async {
    try {
      await _ensureSubjectSession();
      final after = int.tryParse(
            await _kv.readString(_instructionCursorKey) ?? '',
          ) ??
          0;
      final seenRaw = await _kv.readString(_seenInstructionsKey);
      final seen = <int>{};
      if (seenRaw != null) {
        final decoded = jsonDecode(seenRaw);
        if (decoded is List<Object?>) {
          seen.addAll(decoded.whereType<num>().map((value) => value.toInt()));
        }
      }
      final result = await _api.getJson(
        SdkEndpoints.instructions,
        query: <String, String>{'after': '$after', 'limit': '100',
          'protocolVersion': '2', 'platform': Platform.isIOS ? 'ios' : 'android',
          'anonymousId': identity.anonymousId, 'sdkVersion': sdkVersion},
      );
      if (!result.success) return;
      final raw = result.data?['instructions'];
      if (raw is! List<Object?> || raw.isEmpty) return;
      final handled = <int>[];
      for (final value in raw) {
        if (value is! Map<String, Object?>) continue;
        final id = (value['id'] as num?)?.toInt();
        final type = value['type'] as String?;
        final payload = value['payload'];
        if (id == null || id <= 0 || type == null) continue;
        handled.add(id);
        if (seen.contains(id)) continue;
        if (payload is Map<String, Object?>) {
          _dispatchInstruction(type, payload);
        }
        seen.add(id);
        final kept = seen.toList(growable: false);
        final bounded =
            kept.length <= 200 ? kept : kept.sublist(kept.length - 200);
        if (!await _kv.writeStringStrict(
          _seenInstructionsKey,
          jsonEncode(bounded),
        )) {
          throw StateError('failed to persist instruction dedupe state');
        }
      }
      if (handled.isEmpty) return;
      final cursor = handled.fold<int>(after, (max, id) => id > max ? id : max);
      if (!await _kv.writeStringStrict(_instructionCursorKey, '$cursor')) {
        throw StateError('failed to persist instruction cursor');
      }
      await _api.postJson(
        SdkEndpoints.instructionsAck,
        <String, Object?>{'ids': handled},
      );
    } on Object catch (err, st) {
      log.e('instruction poll failed', err, st);
    }
  }

  void _dispatchInstruction(String type, Map<String, Object?> payload) {
    if (type == 'prompt.show') {
      if (!_consent.isFeedbackGranted) return;
      final prompt = payload['prompt'];
      if (prompt is! Map<String, Object?>) return;
      try {
        final promptId = payload['promptId'];
        final triggerEventId = payload['triggerEventId'];
        if (promptId is String &&
            triggerEventId is String &&
            _localInstructionDedupe.consume(
              _instructionKey('prompt.show', promptId, triggerEventId),
            )) {
          return;
        }
        _showCtrl.add(
          PromptShowRequest(prompt: ClientPrompt.fromJson(prompt)),
        );
      } on Object catch (err, st) {
        log.e('invalid prompt.show instruction', err, st);
      }
      return;
    }
    if (type == 'survey.offer') {
      if (!_consent.current.allowsSurvey) return;
      final surveyId = payload['surveyId'];
      final name = payload['name'];
      if (surveyId is! String || name is! String) return;
      final triggerEventId = payload['triggerEventId'];
      if (triggerEventId is String &&
          _localInstructionDedupe.consume(
            _instructionKey('survey.offer', surveyId, triggerEventId),
          )) {
        return;
      }
      onSurveyInvite?.call(
        SurveySummary(
          id: surveyId,
          name: name,
          mode: 'triggered',
          source: payload['source'] as String? ?? 'triggered',
        ),
      );
      return;
    }
    if (type == 'inapp.show') {
      if (!_consent.isFeedbackGranted) return;
      final rawMessage = payload['message'];
      if (rawMessage is! Map<String, Object?>) return;
      try {
        final message = ArmedInAppMessage.fromJson(rawMessage);
        if (message.messageId.isEmpty || message.title.isEmpty) return;
        final triggerEventId = payload['triggerEventId'];
        if (triggerEventId is String &&
            _localInstructionDedupe.consume(
              _instructionKey(
                'inapp.show',
                message.messageId,
                triggerEventId,
              ),
            )) {
          return;
        }
        _inAppCtrl.add(InAppShowRequest(message: message));
      } on Object catch (err, st) {
        log.e('invalid inapp.show instruction', err, st);
      }
      return;
    }
    if (type.startsWith('request.')) {
      Push.instance.dispatchSdkEvent(
        '\$${type.replaceAll('.', '_')}',
        Map<String, Object?>.from(payload),
      );
    }
  }

  /// Records a successful on-device in-app impression.
  void reportInAppShown(String messageId) {
    track(
      r'$inapp_shown',
      <String, Object?>{'message_id': messageId},
      purpose: EventPurpose.feedback,
    );
  }

  /// Records an explicit or timer-driven in-app dismissal.
  void reportInAppDismissed(String messageId, String reason) {
    track(
      reason == 'auto' ? r'$inapp_auto_dismissed' : r'$inapp_dismissed',
      <String, Object?>{'message_id': messageId},
      purpose: EventPurpose.feedback,
    );
  }

  /// Records a CTA click and emits its configured custom event when present.
  void reportInAppCta(String messageId, InAppCta cta, int index) {
    track(
      r'$inapp_cta_clicked',
      <String, Object?>{
        'message_id': messageId,
        'cta_index': index,
        'cta_action': cta.action,
        'cta_label': cta.label,
      },
      purpose: EventPurpose.feedback,
    );
    final target = cta.target;
    if (cta.action == 'custom_event' && target != null && target.isNotEmpty) {
      track(
        target,
        <String, Object?>{
          'message_id': messageId,
          'cta_index': index,
          'cta_label': cta.label,
        },
        purpose: EventPurpose.feedback,
      );
    }
  }

  /// Reports that a prompt was presented on-device.
  void reportShown(String promptId) {
    final now = DateTime.now().toUtc();
    _shownAt[promptId] = now;
    _shownCtrl.add(promptId);
    if (_pendingPromptCapIds.contains(promptId)) {
      unawaited(
        _freqCaps.record(promptId, when: now).then((_) {
          _pendingPromptCapIds.remove(promptId);
        }).catchError((Object error, StackTrace stack) {
          log.e('prompt frequency-cap persistence failed', error, stack);
        }),
      );
    }
    track(
      r'$feedback_prompt_shown',
      <String, Object?>{'promptId': promptId},
      purpose: EventPurpose.feedback,
    );
  }

  /// Reports a user response back from the UI presenter.
  void reportResponse(PromptResponseInfo info) {
    _respCtrl.add(info);
    final payload = <String, Object?>{
      'idempotencyKey': newUuid(),
      'promptId': info.promptId,
      'anonymousId': identity.anonymousId,
      'externalId': identity.externalId,
      'answers': info.answers.map((a) => a.toJson()).toList(growable: false),
      'dismissed': info.dismissed,
      'latencyMs': info.latencyMs,
    };
    unawaited(
      _mutations
          .enqueue(
            MutationKind.feedbackResponse,
            MutationPurpose.feedback,
            payload,
          )
          .then((_) => _flushMutations())
          .catchError((Object error, StackTrace stack) {
        log.e('feedback response persistence failed', error, stack);
        return <String>{};
      }),
    );
    track(
      r'$feedback_response',
      <String, Object?>{
        'promptId': info.promptId,
        'dismissed': info.dismissed,
        'latencyMs': info.latencyMs,
      },
      purpose: EventPurpose.feedback,
    );
  }

  /// Tears down timers, subscriptions, and HTTP resources.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _triggerTimer?.cancel();
    _lifecycle.detach();
    await _showCtrl.close();
    await _shownCtrl.close();
    await _respCtrl.close();
    await _inAppCtrl.close();
    await _surveyCtrl.close();
    await _resetCtrl.close();
    _api.dispose();
  }

  Future<void> _ensureSubjectSession({bool allowDuringReset = false}) {
    if (_resetInProgress && !allowDuringReset) {
      return Future<void>.error(StateError('UserGist reset in progress'));
    }
    if (_subjectToken != null) return Future<void>.value();
    final existing = _sessionFuture;
    if (existing != null) return existing;
    final generation = _resetGeneration;
    final future = _openSubjectSession(generation, allowDuringReset);
    _sessionFuture = future;
    return future.whenComplete(() {
      if (identical(_sessionFuture, future)) _sessionFuture = null;
    });
  }

  Future<void> _openSubjectSession(
    int generation,
    bool allowDuringReset,
  ) async {
    final persisted = await _secureStore.readString(_subjectTokenKey);
    _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
    _api.setSubjectToken(persisted);
    var result = await _api.postJson(
      SdkEndpoints.session,
      <String, Object?>{'anonymousId': identity.anonymousId},
      requiresSubject: false,
      idempotent: false,
    );
    _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
    final mayRotate =
        result.status == 401 || result.status == 403 || result.status == 409;
    if (!result.success && mayRotate) {
      // A known anonymous id cannot be claimed twice. If its credential is
      // expired/revoked, rotate the installation identity before retrying.
      if (persisted != null) await _secureStore.remove(_subjectTokenKey);
      _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
      _api.setSubjectToken(null);
      await identity.reset();
      _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
      result = await _api.postJson(
        SdkEndpoints.session,
        <String, Object?>{'anonymousId': identity.anonymousId},
        requiresSubject: false,
        idempotent: false,
      );
      _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
    }
    final token = result.data?['subjectToken'];
    if (!result.success || token is! String || !token.startsWith('st_')) {
      _api.setSubjectToken(null);
      throw StateError('unable to establish UserGist subject session');
    }
    if (!await _secureStore.writeStringStrict(_subjectTokenKey, token)) {
      _api.setSubjectToken(null);
      throw StateError('unable to persist UserGist subject session');
    }
    _ensureCurrentGeneration(generation, allowDuringReset: allowDuringReset);
    _subjectToken = token;
    _api.setSubjectToken(token);
  }

  Future<Set<String>> _flushMutations() {
    if (_resetInProgress) return Future<Set<String>>.value(<String>{});
    final existing = _mutationFuture;
    if (existing != null) return existing;
    final future = _performMutationFlush();
    _mutationFuture = future;
    return future.whenComplete(() {
      if (identical(_mutationFuture, future)) _mutationFuture = null;
    });
  }

  Future<Set<String>> _performMutationFlush() async {
    final generation = _resetGeneration;
    final rejected = <String>{};
    while (_mutations.length > 0) {
      if (_resetInProgress || _resetGeneration != generation) return rejected;
      final mutation = _mutations.first;
      if (mutation == null) break;
      if (mutation.purpose == MutationPurpose.feedback &&
          !_consent.isFeedbackGranted) {
        break;
      }
      if (mutation.purpose == MutationPurpose.survey &&
          !_consent.current.allowsSurvey) {
        break;
      }
      ApiResult<Map<String, Object?>> result;
      if (mutation.kind == MutationKind.identify) {
        final token = mutation.payload['subjectToken'];
        final anonymousId = mutation.payload['anonymousId'];
        final externalId = mutation.payload['externalId'];
        if (token is! String ||
            !token.startsWith('st_') ||
            anonymousId is! String ||
            externalId is! String) {
          await _mutations.remove(mutation.id);
          continue;
        }
        result = await _api.postJson(
          SdkEndpoints.identify,
          <String, Object?>{
            'anonymousId': anonymousId,
            'externalId': externalId,
            if (mutation.payload['properties'] is Map<String, Object?>)
              'properties': mutation.payload['properties'],
          },
          subjectTokenOverride: token,
        );
        if (_resetInProgress || _resetGeneration != generation) return rejected;
        if (result.success) {
          final persisted = await _secureStore.writeStringStrict(
            _subjectTokenKey,
            token,
          );
          if (!persisted) {
            break;
          }
          if (_resetInProgress || _resetGeneration != generation) {
            return rejected;
          }
          _subjectToken = token;
          _api.setSubjectToken(token);
          await identity.setExternalId(externalId);
          final properties = mutation.payload['properties'];
          if (properties is Map<String, Object?> && properties.isNotEmpty) {
            await identity.setExternalProperties(safeEncode(properties));
            _identityProperties = <String, Object?>{
              ..._identityProperties,
              ...properties,
            };
          }
          await rebindPushToken(externalId);
          if (_consent.isAnalyticsGranted) {
            track(
              '\$identify',
              properties is Map<String, Object?>
                  ? properties
                  : const <String, Object?>{},
            );
          }
        }
      } else if (mutation.kind == MutationKind.feedbackResponse) {
        result = await _api.postJson(SdkEndpoints.responses, mutation.payload);
      } else if (mutation.kind == MutationKind.surveyComplete) {
        final attemptId = mutation.payload['attemptId'];
        final body = mutation.payload['body'];
        if (attemptId is! String || body is! Map<String, Object?>) {
          await _mutations.remove(mutation.id);
          continue;
        }
        result = await _api.postJson(
          SdkEndpoints.surveyComplete(attemptId),
          body,
        );
      } else {
        final attemptId = mutation.payload['attemptId'];
        if (attemptId is! String) {
          await _mutations.remove(mutation.id);
          continue;
        }
        result = await _api.postJson(
          SdkEndpoints.surveyAbandon(attemptId),
          const <String, Object?>{},
        );
      }
      if (_resetInProgress || _resetGeneration != generation) return rejected;
      if (result.success) {
        await _mutations.remove(mutation.id);
        continue;
      }
      final permanent = result.status != null &&
          result.status! >= 400 &&
          result.status! < 500 &&
          result.status != 429;
      if (permanent) {
        await _mutations.remove(mutation.id);
        rejected.add(mutation.id);
        log.w(
          'quarantined permanently rejected ${mutation.kind.name} mutation',
        );
        continue;
      }
      break;
    }
    return rejected;
  }

  IngestContext _contextFor(IngestEvent event) => IngestContext(
        anonymousId: event.anonymousId,
        externalId: event.externalId,
        sdkVersion: sdkVersion,
        appVersion: _appVersion,
        locale: _locale,
        timezone: _timezone,
        osName: _osName,
        osVersion: _osVersion,
        deviceModel: _deviceModel,
      );

  void _recordLocalEvent(String name, DateTime at) {
    final history = _eventHistory.putIfAbsent(name, () => <DateTime>[]);
    history.add(at);
    if (history.length > _maxHistoryPerEvent) {
      history.removeRange(0, history.length - _maxHistoryPerEvent);
    }
    _rebuildEventState(at);
    _runAsync(_persistEventHistory(), 'user-state persistence');
  }

  void _restoreEventHistory(String? raw) {
    if (raw == null || raw.isEmpty) return;
    final decoded = safeDecodeMap(raw)['history'];
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      final values = entry.value;
      if (values is! List<Object?>) continue;
      final parsedAll = values
          .whereType<String>()
          .map(DateTime.tryParse)
          .whereType<DateTime>()
          .toList(growable: true);
      final parsed = parsedAll.length <= _maxHistoryPerEvent
          ? parsedAll
          : parsedAll.sublist(parsedAll.length - _maxHistoryPerEvent);
      if (parsed.isNotEmpty) _eventHistory[entry.key.toString()] = parsed;
    }
    _rebuildEventState(DateTime.now().toUtc());
  }

  void _rebuildEventState(DateTime now) {
    _eventCounts.clear();
    _lastEventAt.clear();
    for (final entry in _eventHistory.entries) {
      if (entry.value.isEmpty) continue;
      _lastEventAt[entry.key] = entry.value.last;
      _eventCounts[entry.key] = <int, int>{
        for (final days in _trackedWindowsDays)
          days: entry.value
              .where(
                (stamp) =>
                    now.difference(stamp).inMilliseconds <=
                    Duration(days: days).inMilliseconds,
              )
              .length,
      };
    }
  }

  Future<void> _persistEventHistory() => _kv.writeString(
        _eventHistoryKey,
        safeEncode(<String, Object?>{
          'version': 1,
          'history': _eventHistory.map<String, Object?>(
            (name, stamps) => MapEntry<String, Object?>(
              name,
              stamps.map((stamp) => stamp.toIso8601String()).toList(),
            ),
          ),
        }),
      );

  void _requestAppOpen() {
    if (!_consent.isFeedbackGranted) {
      _appOpenPending = true;
      return;
    }
    _appOpenPending = false;
    track(r'$app_open', null, purpose: EventPurpose.feedback);
  }

  void _emitPendingAppOpenIfReady() {
    if (!_appOpenPending || !_consent.isFeedbackGranted) return;
    _appOpenPending = false;
    track(r'$app_open', null, purpose: EventPurpose.feedback);
  }

  void _maybeFire(
    String eventName,
    Map<String, Object?> _,
    String eventId,
  ) {
    final userState = UserState(
      properties: _identityProperties,
      eventCounts: _eventCounts,
      lastEventAt: _lastEventAt.map(
        MapEntry<String, DateTime?>.new,
      ),
    );
    if (_consent.isFeedbackGranted) {
      final trigger = _matcher.match(
        eventName: eventName,
        userState: userState,
      );
      if (trigger != null && _pendingPromptCapIds.add(trigger.promptId)) {
        _rememberLocalInstruction(
          _instructionKey('prompt.show', trigger.promptId, eventId),
        );
        _showCtrl.add(PromptShowRequest(prompt: trigger.prompt));
      }
    }

    if (_consent.current.allowsSurvey) {
      for (final armed in _campaignRules.surveysFor(eventName)) {
        if (armed.clientSideEligible == false) continue;
        if (!evaluateSerializedSegmentRules(armed.segmentRules, userState)) {
          continue;
        }
        final cap = FrequencyCaps(
          perPromptDays: armed.frequencyCap.perCampaignDays,
          perUserDays: armed.frequencyCap.perPillarDays,
        );
        final capKey = 'survey:${armed.campaignId}';
        if (!_freqCaps.allow(capKey, cap)) continue;
        final cooldown = armed.cooldownSeconds ?? 0;
        final now = DateTime.now().toUtc();
        final last = _surveyCooldownByCampaign[armed.campaignId];
        if (last != null &&
            cooldown > 0 &&
            now.difference(last) < Duration(seconds: cooldown)) {
          continue;
        }
        if (!_pendingSurveyCapIds.add(armed.campaignId)) continue;
        _rememberLocalInstruction(
          _instructionKey('survey.offer', armed.campaignId, eventId),
        );
        onSurveyInvite?.call(
          SurveySummary(
            id: armed.campaignId,
            name: armed.survey.name,
            mode: 'triggered',
            source: 'triggered',
          ),
        );
        break;
      }
    }

    if (_consent.isFeedbackGranted) {
      for (final message in _campaignRules.inAppFor(eventName)) {
        if (message.clientSideEligible == false) continue;
        _rememberLocalInstruction(
          _instructionKey('inapp.show', message.messageId, eventId),
        );
        _inAppCtrl.add(InAppShowRequest(message: message));
        break;
      }
    }
  }

  String _instructionKey(String type, String refId, String eventId) =>
      '$type:$refId:event:$eventId';

  /// Commits local campaign caps after the survey route renders.
  void reportSurveyShown(String surveyId) {
    if (!_pendingSurveyCapIds.contains(surveyId)) return;
    final now = DateTime.now().toUtc();
    unawaited(
      _freqCaps.record('survey:$surveyId', when: now).then((_) {
        _pendingSurveyCapIds.remove(surveyId);
        _surveyCooldownByCampaign[surveyId] = now;
      }).catchError((Object error, StackTrace stack) {
        log.e('survey frequency-cap persistence failed', error, stack);
      }),
    );
  }

  /// Releases a campaign reservation when its route could not be presented.
  void releaseSurveyReservation(String surveyId) {
    _pendingSurveyCapIds.remove(surveyId);
  }

  /// Releases a prompt reservation when its sheet could not be presented.
  void releasePromptReservation(String promptId) {
    _pendingPromptCapIds.remove(promptId);
  }

  void _ensureCurrentGeneration(
    int generation, {
    bool allowDuringReset = false,
  }) {
    if (_resetGeneration != generation ||
        (_resetInProgress && !allowDuringReset)) {
      throw StateError('UserGist operation superseded by reset');
    }
  }

  void _runAsync(Future<void> future, String operation) {
    unawaited(
      future.catchError((Object error, StackTrace stack) {
        log.e('$operation failed', error, stack);
      }),
    );
  }

  void _rememberLocalInstruction(String key) {
    _localInstructionDedupe.remember(key);
  }

  Future<void> _syncTriggers() async {
    if (!_consent.isFeedbackGranted && !_consent.current.allowsSurvey) return;
    final query = <String, String>{
      'anonymousId': identity.anonymousId,
      if (identity.externalId != null) 'externalId': identity.externalId!,
    };
    if (_consent.isFeedbackGranted) {
      final promptResult = await _api.getJson(
        SdkEndpoints.armedTriggers,
        query: query,
      );
      final promptRaw = promptResult.data?['triggers'];
      if (promptResult.success && promptRaw is List<Object?>) {
        await _rulesCache.replace(
          promptRaw.whereType<Map<String, Object?>>().toList(growable: false),
        );
      }

      final inAppResult = await _api.getJson(
        SdkEndpoints.armedInAppMessages,
        query: query,
      );
      final inAppRaw = inAppResult.data?['messages'];
      if (inAppResult.success && inAppRaw is List<Object?>) {
        await _campaignRules.replaceInApp(
          inAppRaw.whereType<Map<String, Object?>>().toList(growable: false),
        );
      }
    }
    if (_consent.current.allowsSurvey) {
      final surveyResult = await _api.getJson(
        SdkEndpoints.armedSurveys,
        query: query,
      );
      final surveyRaw = surveyResult.data?['surveys'];
      if (surveyResult.success && surveyRaw is List<Object?>) {
        await _campaignRules.replaceSurveys(
          surveyRaw.whereType<Map<String, Object?>>().toList(growable: false),
        );
      }
    }
  }

  Future<void> _collectContext() async {
    final snap = await collectDeviceContext();
    _appVersion = snap.appVersion;
    _locale = snap.locale;
    _timezone = snap.timezone;
    _osName = snap.osName;
    _osVersion = snap.osVersion;
    _deviceModel = snap.deviceModel;
  }

  String _newSessionId() =>
      '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-'
      '${identity.anonymousId.substring(0, 8)}';

  static const List<int> _trackedWindowsDays = <int>[
    1,
    3,
    7,
    14,
    30,
    60,
    90,
    180,
    365,
  ];
  static const int _maxHistoryPerEvent = 200;
}
