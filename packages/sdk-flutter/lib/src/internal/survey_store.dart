import 'dart:convert';

import '../models/survey.dart';
import 'storage.dart';

/// Versioned local attempt snapshots used to resume while progress transport
/// is offline. The server still owns attempt creation and attempt IDs.
class SurveyStore {
  SurveyStore(this._store);

  static const String _key = 'surveys.attempts';
  final KeyValueStore _store;
  final Map<String, _StoredSurveyAttempt> _attempts =
      <String, _StoredSurveyAttempt>{};

  Future<void> hydrate() async {
    final raw = await _store.readString(_key);
    if (raw == null) return;
    try {
      final root = jsonDecode(raw);
      if (root is! Map<String, Object?> || root['version'] != 1) return;
      final attempts = root['attempts'];
      if (attempts is! List<Object?>) return;
      _attempts
        ..clear()
        ..addEntries(
          attempts
              .whereType<Map<String, Object?>>()
              .map(_StoredSurveyAttempt.fromJson)
              .map((attempt) => MapEntry(attempt.surveyId, attempt)),
        );
    } on Object {
      _attempts.clear();
    }
  }

  SurveyAttemptSession merge(
    String surveyId,
    SurveyAttemptSession server,
  ) {
    final local = _attempts[surveyId];
    if (local == null || local.attemptId != server.attemptId) return server;
    return SurveyAttemptSession(
      attemptId: server.attemptId,
      startQuestionId: server.startQuestionId,
      progressSnapshot: <String, Object?>{
        ...server.progressSnapshot,
        ...local.progressSnapshot,
      },
      currentQuestionId: local.currentQuestionId ?? server.currentQuestionId,
      resumed: true,
    );
  }

  Future<void> upsert(
    String surveyId,
    SurveyAttemptSession attempt,
  ) async {
    _attempts[surveyId] = _StoredSurveyAttempt(
      surveyId: surveyId,
      attemptId: attempt.attemptId,
      currentQuestionId: attempt.currentQuestionId ?? attempt.startQuestionId,
      progressSnapshot: Map<String, Object?>.from(attempt.progressSnapshot),
    );
    await _persist();
  }

  Future<void> update(
    String attemptId,
    String? currentQuestionId,
    Map<String, Object?> snapshot,
  ) async {
    MapEntry<String, _StoredSurveyAttempt>? match;
    for (final entry in _attempts.entries) {
      if (entry.value.attemptId == attemptId) {
        match = entry;
        break;
      }
    }
    if (match == null) return;
    _attempts[match.key] = _StoredSurveyAttempt(
      surveyId: match.value.surveyId,
      attemptId: attemptId,
      currentQuestionId: currentQuestionId,
      progressSnapshot: Map<String, Object?>.from(snapshot),
    );
    await _persist();
  }

  Future<void> removeAttempt(String attemptId) async {
    _attempts.removeWhere((_, attempt) => attempt.attemptId == attemptId);
    await _persist();
  }

  Future<void> clear() async {
    _attempts.clear();
    await _store.remove(_key);
  }

  Future<void> _persist() => _store.writeString(
        _key,
        jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': _attempts.values
              .map((attempt) => attempt.toJson())
              .toList(growable: false),
        }),
      );
}

class _StoredSurveyAttempt {
  const _StoredSurveyAttempt({
    required this.surveyId,
    required this.attemptId,
    required this.currentQuestionId,
    required this.progressSnapshot,
  });

  final String surveyId;
  final String attemptId;
  final String? currentQuestionId;
  final Map<String, Object?> progressSnapshot;

  factory _StoredSurveyAttempt.fromJson(Map<String, Object?> json) =>
      _StoredSurveyAttempt(
        surveyId: json['surveyId'] as String? ?? '',
        attemptId: json['attemptId'] as String? ?? '',
        currentQuestionId: json['currentQuestionId'] as String?,
        progressSnapshot: Map<String, Object?>.from(
          json['progressSnapshot'] as Map<String, Object?>? ??
              const <String, Object?>{},
        ),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'surveyId': surveyId,
        'attemptId': attemptId,
        'currentQuestionId': currentQuestionId,
        'progressSnapshot': progressSnapshot,
      };
}
