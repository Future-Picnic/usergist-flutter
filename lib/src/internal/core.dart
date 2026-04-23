import 'dart:async';
import 'dart:io' show File;

import '../models/any_value.dart';
import '../models/consent.dart';
import '../models/context.dart';
import '../models/event.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import '../ui/prompt_presenter.dart';
import 'consent_store.dart';
import 'device_context.dart';
import 'event_queue.dart';
import 'identity.dart';
import 'json.dart';
import 'lifecycle/app_lifecycle.dart';
import 'logger.dart';
import 'storage.dart';
import 'transport/api_client.dart';
import 'transport/endpoints.dart';
import 'transport/retry_policy.dart';
import 'triggers/frequency_cap.dart';
import 'triggers/rules_cache.dart';
import 'triggers/segment_evaluator.dart';
import 'triggers/trigger_matcher.dart';

/// The actual implementation of the SDK. Owns all internal state and
/// is the singleton instance that [Ritmus] delegates to.
///
/// This class is deliberately library-internal (exported only through
/// `ritmus_feedback/src/...`). Do not import directly from apps.
class RitmusCore {
  /// Creates a core instance. Call [start] before using it.
  RitmusCore({
    required this.writeKey,
    required this.baseUrl,
    required this.sdkVersion,
    required this.flushInterval,
    required this.flushBatchSize,
    required this.maxQueueSize,
    required this.triggerSyncInterval,
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

  late final KeyValueStore _kv;

  /// Persistent identity store.
  late final IdentityStore identity;

  late final ConsentStore _consent;
  late final EventQueue _queue;
  late final RulesCache _rulesCache;
  late final FrequencyCapStore _freqCaps;
  late final TriggerMatcher _matcher;
  late final ApiClient _api;
  late final AppLifecycle _lifecycle;

  final StreamController<PromptShowRequest> _showCtrl =
      StreamController<PromptShowRequest>.broadcast();
  final StreamController<String> _shownCtrl =
      StreamController<String>.broadcast();
  final StreamController<PromptResponseInfo> _respCtrl =
      StreamController<PromptResponseInfo>.broadcast();

  final Map<String, DateTime> _shownAt = <String, DateTime>{};
  final Map<String, Map<int, int>> _eventCounts = <String, Map<int, int>>{};
  final Map<String, DateTime> _lastEventAt = <String, DateTime>{};

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
  bool _started = false;

  /// Caller-side theme overrides (updated by [setThemeOverrides]).
  PromptTheme? themeOverrides;

  /// Stream of prompt-show requests for the UI presenter.
  Stream<PromptShowRequest> get showRequests => _showCtrl.stream;

  /// Stream of prompt-shown notifications (public API).
  Stream<String> get onPromptShown => _shownCtrl.stream;

  /// Stream of response info (public API).
  Stream<PromptResponseInfo> get onResponse => _respCtrl.stream;

  /// Boots the core: hydrates state, boots timers, collects context.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _kv = SharedPrefsStore(writeKey: writeKey);
    identity = IdentityStore(_kv);
    _consent = ConsentStore(_kv);
    _freqCaps = FrequencyCapStore(_kv);
    await Future.wait<void>(<Future<void>>[
      identity.hydrate(),
      _consent.hydrate(),
      _freqCaps.hydrate(),
    ]);

    final dir = await ritmusSupportDir(writeKey);
    _queue = EventQueue(
      file: File('${dir.path}/queue.jsonl'),
      maxSize: maxQueueSize,
    );
    _rulesCache = RulesCache(file: File('${dir.path}/rules.json'));
    await Future.wait<void>(<Future<void>>[
      _queue.hydrate(),
      _rulesCache.hydrate(),
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
    _sessionId = _newSessionId();

    unawaited(_collectContext());

    _lifecycle = AppLifecycle(
      onResumed: () {
        unawaited(flush());
        unawaited(_syncTriggers());
      },
      onPaused: () {
        unawaited(flush());
      },
    );
    _lifecycle.attach();

    _flushTimer =
        Timer.periodic(flushInterval, (_) => unawaited(flush()));
    _triggerTimer = Timer.periodic(
      triggerSyncInterval,
      (_) => unawaited(_syncTriggers()),
    );
    unawaited(_syncTriggers());

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
  ) async {
    await identity.setExternalId(userId);
    final clean = sanitizeProperties(properties);
    if (clean.isNotEmpty) {
      await identity.setExternalProperties(safeEncode(clean));
    }
    if (!_consent.isFeedbackGranted) return;
    await _api.postJson(SdkEndpoints.identify, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'externalId': userId,
      if (clean.isNotEmpty) 'properties': clean,
    });
  }

  /// Tracks an event.
  void track(String name, Map<String, Object?>? properties) {
    final now = DateTime.now().toUtc();
    final clean = sanitizeProperties(properties);
    final event = IngestEvent(
      name: name,
      timestamp: now.toIso8601String(),
      anonymousId: identity.anonymousId,
      externalId: identity.externalId,
      properties: clean,
      sessionId: _sessionId,
      sdkVersion: sdkVersion,
      appVersion: _appVersion,
    );
    unawaited(_queue.append(event));
    _recordLocalEvent(name, now);
    _maybeFire(name, clean);
    unawaited(flush());
  }

  /// Sets consent and flushes if feedback consent was newly granted.
  Future<void> setConsent(Consent purposes) async {
    final wasGranted = _consent.isFeedbackGranted;
    await _consent.set(purposes);
    final granted = _consent.isFeedbackGranted;
    await _api.postJson(SdkEndpoints.consent, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'externalId': identity.externalId,
      'purposes': purposes.toJson(),
    });
    if (!wasGranted && granted) {
      await flush();
      await _syncTriggers();
    }
  }

  /// Registers a device token with the control plane. Consent-gated on push.
  Future<void> registerPushToken(
    String token,
    String platform,
    String environment,
  ) async {
    if (!_consent.isPushGranted) return;
    await _api.postJson(SdkEndpoints.pushRegisterToken, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'externalId': identity.externalId,
      'token': token,
      'platform': platform,
      'environment': environment,
      'language': null,
      'timezone': DateTime.now().timeZoneName,
      'sdkVersion': '0.1.0',
      'optIn': true,
    });
  }

  Future<void> invalidatePushToken(String token) async {
    await _api.postJson(SdkEndpoints.pushInvalidateToken, <String, Object?>{
      'anonymousId': identity.anonymousId,
      'token': token,
    });
  }

  /// Clears all local state.
  Future<void> reset() async {
    await _queue.clear();
    await _rulesCache.clear();
    await _freqCaps.clear();
    await _consent.clear();
    await identity.reset();
    _shownAt.clear();
    _eventCounts.clear();
    _lastEventAt.clear();
    _sessionId = _newSessionId();
  }

  /// Flushes the event queue to the server. Consent-gated.
  Future<void> flush() async {
    if (!_consent.isFeedbackGranted) return;
    final inflight = _inflightFlush;
    if (inflight != null) return inflight;
    final completer = Completer<void>();
    _inflightFlush = completer.future;
    try {
      while (!_queue.isEmpty) {
        final batch = _queue.peek(flushBatchSize);
        if (batch.isEmpty) break;
        final payload = <String, Object?>{
          'events':
              batch.map((e) => e.toJson()).toList(growable: false),
          'context': _context().toJson(),
        };
        final res = await _api.postJson(SdkEndpoints.ingest, payload);
        if (!res.success) {
          log.w('ingest failed (${res.status}): ${res.error}');
          break;
        }
        await _queue.drop(batch.length);
      }
    } finally {
      _inflightFlush = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Reports that a prompt was presented on-device.
  void reportShown(String promptId) {
    final now = DateTime.now().toUtc();
    _shownAt[promptId] = now;
    unawaited(_freqCaps.record(promptId, when: now));
    _shownCtrl.add(promptId);
    track(r'$prompt_shown', <String, Object?>{'promptId': promptId});
  }

  /// Reports a user response back from the UI presenter.
  void reportResponse(PromptResponseInfo info) {
    _respCtrl.add(info);
    final payload = <String, Object?>{
      'promptId': info.promptId,
      'anonymousId': identity.anonymousId,
      'externalId': identity.externalId,
      'answers':
          info.answers.map((a) => a.toJson()).toList(growable: false),
      'dismissed': info.dismissed,
      'latencyMs': info.latencyMs,
    };
    unawaited(_api.postJson(SdkEndpoints.responses, payload));
    track(r'$feedback_response', <String, Object?>{
      'promptId': info.promptId,
      'dismissed': info.dismissed,
      'latencyMs': info.latencyMs,
    });
  }

  /// Tears down timers, subscriptions, and HTTP resources.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _triggerTimer?.cancel();
    _lifecycle.detach();
    await _showCtrl.close();
    await _shownCtrl.close();
    await _respCtrl.close();
    _api.dispose();
  }

  IngestContext _context() => IngestContext(
        anonymousId: identity.anonymousId,
        externalId: identity.externalId,
        sdkVersion: sdkVersion,
        appVersion: _appVersion,
        locale: _locale,
        timezone: _timezone,
        osName: _osName,
        osVersion: _osVersion,
        deviceModel: _deviceModel,
      );

  void _recordLocalEvent(String name, DateTime at) {
    _lastEventAt[name] = at;
    final buckets = _eventCounts.putIfAbsent(name, () => <int, int>{});
    for (final window in const <int>[1, 7, 30, 90]) {
      buckets[window] = (buckets[window] ?? 0) + 1;
    }
  }

  void _maybeFire(String eventName, Map<String, Object?> props) {
    if (!_consent.isFeedbackGranted) return;
    if (eventName.startsWith(r'$')) return;
    final userState = UserState(
      properties: props,
      eventCounts: _eventCounts,
      lastEventAt: _lastEventAt.map(
        (k, v) => MapEntry<String, DateTime?>(k, v),
      ),
    );
    final trigger = _matcher.match(
      eventName: eventName,
      userState: userState,
    );
    if (trigger == null) return;
    _showCtrl.add(PromptShowRequest(prompt: trigger.prompt));
  }

  Future<void> _syncTriggers() async {
    if (!_consent.isFeedbackGranted) return;
    final res = await _api.getJson(
      SdkEndpoints.armedTriggers,
      query: <String, String>{
        'anonymousId': identity.anonymousId,
        if (identity.externalId != null) 'externalId': identity.externalId!,
      },
    );
    if (!res.success || res.data == null) return;
    final raw = res.data!['triggers'];
    if (raw is! List<Object?>) return;
    final next = <Map<String, Object?>>[];
    for (final t in raw) {
      if (t is Map<String, Object?>) next.add(t);
    }
    await _rulesCache.replace(next);
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
}
