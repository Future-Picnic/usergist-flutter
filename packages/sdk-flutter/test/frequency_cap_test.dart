import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/storage.dart';
import 'package:usergist_feedback/src/internal/triggers/frequency_cap.dart';
import 'package:usergist_feedback/src/models/prompt.dart';

class _InMemoryStore implements KeyValueStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> readString(String key) async => _data[key];

  @override
  Future<void> writeString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }
}

void main() {
  test('allow before any record', () async {
    final store = FrequencyCapStore(_InMemoryStore());
    await store.hydrate();
    expect(
      store.allow(
        'p1',
        const FrequencyCaps(perPromptDays: 7, perUserDays: 1),
      ),
      isTrue,
    );
  });

  test('per-prompt cap blocks within window', () async {
    final store = FrequencyCapStore(_InMemoryStore());
    await store.hydrate();
    final now = DateTime.utc(2025, 1, 10);
    await store.record('p1', when: now);
    expect(
      store.allow(
        'p1',
        const FrequencyCaps(perPromptDays: 7),
        now: now.add(const Duration(days: 3)),
      ),
      isFalse,
    );
    expect(
      store.allow(
        'p1',
        const FrequencyCaps(perPromptDays: 7),
        now: now.add(const Duration(days: 8)),
      ),
      isTrue,
    );
  });

  test('per-user cap blocks across different prompts', () async {
    final store = FrequencyCapStore(_InMemoryStore());
    await store.hydrate();
    final now = DateTime.utc(2025, 1, 10);
    await store.record('p1', when: now);
    expect(
      store.allow(
        'p2',
        const FrequencyCaps(perUserDays: 2),
        now: now.add(const Duration(days: 1)),
      ),
      isFalse,
    );
    expect(
      store.allow(
        'p2',
        const FrequencyCaps(perUserDays: 2),
        now: now.add(const Duration(days: 3)),
      ),
      isTrue,
    );
  });

  test('persists across hydrations', () async {
    final backing = _InMemoryStore();
    final a = FrequencyCapStore(backing);
    await a.hydrate();
    final now = DateTime.utc(2025, 1, 10);
    await a.record('p1', when: now);
    final b = FrequencyCapStore(backing);
    await b.hydrate();
    expect(
      b.allow(
        'p1',
        const FrequencyCaps(perPromptDays: 7),
        now: now.add(const Duration(days: 1)),
      ),
      isFalse,
    );
  });
}
