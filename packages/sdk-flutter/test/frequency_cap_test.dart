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
  for (final scope in ['prompt', 'user']) {
    test('$scope exact expiry survives hydration', () async {
      final backing = _InMemoryStore();
      final first = FrequencyCapStore(backing);
      final shownAt = DateTime.utc(2026, 11, 12, 9, 37, 12, 345);
      await first.record('original', when: shownAt);
      final restored = FrequencyCapStore(backing);
      await restored.hydrate();
      final caps = scope == 'prompt'
          ? const FrequencyCaps(perPromptDays: 2)
          : const FrequencyCaps(perUserDays: 2);
      final id = scope == 'prompt' ? 'original' : 'different';
      final expiry = shownAt.add(const Duration(days: 2));
      expect(
          restored.allow(id, caps,
              now: expiry.subtract(const Duration(microseconds: 1))),
          isFalse);
      expect(restored.allow(id, caps, now: expiry), isTrue);
      expect(
          restored.allow(id, caps,
              now: expiry.add(const Duration(microseconds: 1))),
          isTrue);
    });
  }

  test('zero and omitted limits allow; longest active tier wins', () async {
    final store = FrequencyCapStore(_InMemoryStore());
    final shownAt = DateTime.utc(2026, 11, 12);
    await store.record('original', when: shownAt);
    expect(
        store.allow('original', const FrequencyCaps(), now: shownAt), isTrue);
    expect(
        store.allow(
            'original', const FrequencyCaps(perPromptDays: 0, perUserDays: 0),
            now: shownAt),
        isTrue);
    const caps = FrequencyCaps(perPromptDays: 3, perUserDays: 1);
    expect(
        store.allow('original', caps,
            now: shownAt.add(const Duration(days: 1))),
        isFalse);
    expect(
        store.allow('different', caps,
            now: shownAt.add(const Duration(days: 1))),
        isTrue);
    expect(
        store.allow('original', caps,
            now: shownAt.add(const Duration(days: 3))),
        isTrue);
  });

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
