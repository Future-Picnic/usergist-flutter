import 'dart:io';

import '../../models/inapp_message.dart';
import '../../models/survey.dart';
import '../json.dart';
import '../logger.dart';

/// Durable hot-path cache for client-side surveys and in-app messages.
class CampaignRulesCache {
  CampaignRulesCache({
    required File surveysFile,
    required File inAppFile,
  })  : _surveysFile = surveysFile,
        _inAppFile = inAppFile;

  final File _surveysFile;
  final File _inAppFile;
  Map<String, List<ArmedSurvey>> _surveysByEvent =
      const <String, List<ArmedSurvey>>{};
  Map<String, ArmedSurvey> _surveysById = const <String, ArmedSurvey>{};
  Map<String, List<ArmedInAppMessage>> _inAppByEvent =
      const <String, List<ArmedInAppMessage>>{};

  List<ArmedSurvey> surveysFor(String eventName) =>
      _surveysByEvent[eventName] ?? const <ArmedSurvey>[];

  ArmedSurvey? survey(String campaignId) => _surveysById[campaignId];

  List<ArmedInAppMessage> inAppFor(String eventName) =>
      _inAppByEvent[eventName] ?? const <ArmedInAppMessage>[];

  Future<void> hydrate() async {
    await Future.wait<void>(<Future<void>>[
      _hydrateSurveys(),
      _hydrateInApp(),
    ]);
  }

  Future<void> replaceSurveys(List<Map<String, Object?>> raw) async {
    _indexSurveys(raw);
    await _persist(_surveysFile, raw);
  }

  Future<void> replaceInApp(List<Map<String, Object?>> raw) async {
    _indexInApp(raw);
    await _persist(_inAppFile, raw);
  }

  Future<void> clear() async {
    _indexSurveys(const <Map<String, Object?>>[]);
    _indexInApp(const <Map<String, Object?>>[]);
    await Future.wait<void>(<Future<void>>[
      _persist(_surveysFile, const <Map<String, Object?>>[]),
      _persist(_inAppFile, const <Map<String, Object?>>[]),
    ]);
  }

  Future<void> _hydrateSurveys() async {
    final raw = await _read(_surveysFile);
    _indexSurveys(raw);
  }

  Future<void> _hydrateInApp() async {
    final raw = await _read(_inAppFile);
    _indexInApp(raw);
  }

  void _indexSurveys(List<Map<String, Object?>> raw) {
    final byEvent = <String, List<ArmedSurvey>>{};
    final byId = <String, ArmedSurvey>{};
    for (final item in raw) {
      try {
        final armed = ArmedSurvey.fromJson(item);
        if (armed.campaignId.isEmpty || armed.eventName.isEmpty) continue;
        byEvent.putIfAbsent(armed.eventName, () => <ArmedSurvey>[]).add(armed);
        byId[armed.campaignId] = armed;
      } on Object catch (error) {
        log.w('drop malformed armed survey: $error');
      }
    }
    _surveysByEvent = byEvent;
    _surveysById = byId;
  }

  void _indexInApp(List<Map<String, Object?>> raw) {
    final byEvent = <String, List<ArmedInAppMessage>>{};
    for (final item in raw) {
      try {
        final message = ArmedInAppMessage.fromJson(item);
        if (message.messageId.isEmpty || message.eventName.isEmpty) continue;
        byEvent
            .putIfAbsent(message.eventName, () => <ArmedInAppMessage>[])
            .add(message);
      } on Object catch (error) {
        log.w('drop malformed armed in-app message: $error');
      }
    }
    _inAppByEvent = byEvent;
  }

  Future<List<Map<String, Object?>>> _read(File file) async {
    try {
      if (!await file.exists()) return const <Map<String, Object?>>[];
      final decoded = safeDecodeList(await file.readAsString());
      return decoded.whereType<Map<String, Object?>>().toList(growable: false);
    } on Object catch (error, stack) {
      log.e('campaign cache hydrate failed', error, stack);
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> _persist(File file, List<Map<String, Object?>> raw) async {
    try {
      await file.writeAsString(safeEncode(raw), flush: true);
    } on Object catch (error, stack) {
      log.e('campaign cache persist failed', error, stack);
    }
  }
}
