import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/storage.dart';
import 'package:usergist_feedback/src/internal/survey_store.dart';
import 'package:usergist_feedback/src/models/survey.dart';

void main() {
  test('local survey progress survives restart and wins over stale server data',
      () async {
    final values = <String, String>{};
    final first = SurveyStore(_MemoryStore(values));
    await first.hydrate();
    await first.upsert(
      'survey-1',
      const SurveyAttemptSession(
        attemptId: 'attempt-1',
        startQuestionId: 'q1',
        progressSnapshot: <String, Object?>{'q1': 'server'},
        currentQuestionId: 'q1',
        resumed: false,
      ),
    );
    await first.update(
      'attempt-1',
      'q2',
      <String, Object?>{'q1': 'local'},
    );

    final restored = SurveyStore(_MemoryStore(values));
    await restored.hydrate();
    final merged = restored.merge(
      'survey-1',
      const SurveyAttemptSession(
        attemptId: 'attempt-1',
        startQuestionId: 'q1',
        progressSnapshot: <String, Object?>{'q1': 'stale'},
        currentQuestionId: 'q1',
        resumed: true,
      ),
    );

    expect(merged.currentQuestionId, 'q2');
    expect(merged.progressSnapshot['q1'], 'local');
  });
}

class _MemoryStore implements KeyValueStore {
  _MemoryStore(this.values);

  final Map<String, String> values;

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }
}
