import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/mutation_queue.dart';

void main() {
  test('mutation queue persists, deduplicates, prioritizes, and gates removal',
      () async {
    final memory = <String, String>{};
    MutationQueue makeQueue() => MutationQueue.withPersistence(
          read: (key) async => memory[key],
          writeStrict: (key, value) async {
            memory[key] = value;
            return true;
          },
        );

    final queue = makeQueue();
    await queue.hydrate();
    final feedbackId = await queue.enqueue(
      MutationKind.feedbackResponse,
      MutationPurpose.feedback,
      <String, Object?>{'promptId': 'p-1'},
      dedupeKey: 'response:p-1',
    );
    final duplicate = await queue.enqueue(
      MutationKind.feedbackResponse,
      MutationPurpose.feedback,
      <String, Object?>{'promptId': 'p-1'},
      dedupeKey: 'response:p-1',
    );
    final identifyId = await queue.enqueue(
      MutationKind.identify,
      MutationPurpose.essential,
      <String, Object?>{'externalId': 'u-1'},
    );

    expect(duplicate, feedbackId);
    expect(queue.length, 2);
    expect(queue.first?.id, identifyId);

    final restored = makeQueue();
    await restored.hydrate();
    expect(restored.length, 2);
    await restored.removePurpose(MutationPurpose.feedback);
    expect(restored.contains(feedbackId), isFalse);
    expect(restored.contains(identifyId), isTrue);
  });

  test('mutation queue restores memory when persistence fails', () async {
    var shouldFail = false;
    final queue = MutationQueue.withPersistence(
      read: (_) async => null,
      writeStrict: (_, __) async => !shouldFail,
    );
    await queue.hydrate();
    final id = await queue.enqueue(
      MutationKind.identify,
      MutationPurpose.essential,
      <String, Object?>{'externalId': 'u-1'},
    );

    shouldFail = true;
    await expectLater(queue.remove(id), throwsStateError);

    expect(queue.contains(id), isTrue);
    expect(queue.length, 1);
  });
}
