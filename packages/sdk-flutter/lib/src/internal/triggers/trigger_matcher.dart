import '../../models/prompt.dart';
import '../logger.dart';
import 'frequency_cap.dart';
import 'rules_cache.dart';
import 'segment_evaluator.dart';

/// Resolves armed triggers for an incoming event. Returns the first
/// prompt that passes all gates (segment rules + frequency caps).
class TriggerMatcher {
  /// Creates a matcher.
  TriggerMatcher({
    required this.rulesCache,
    required this.frequencyCapStore,
  });

  /// Cache of currently armed triggers.
  final RulesCache rulesCache;

  /// Store of prompt-show history for frequency-cap evaluation.
  final FrequencyCapStore frequencyCapStore;

  /// Returns the first prompt that fires for [eventName], or `null`.
  ArmedTrigger? match({
    required String eventName,
    required UserState userState,
    DateTime? now,
  }) {
    final candidates = rulesCache.forEvent(eventName);
    if (candidates.isEmpty) return null;
    for (final trigger in candidates) {
      if (trigger.clientSideEligible == false) {
        log.d('server-authoritative trigger skipped: ${trigger.promptId}');
        continue;
      }
      final segOk = evaluateSerializedSegmentRules(
        trigger.segmentRules,
        userState,
      );
      if (!segOk) {
        log.d('segment mismatch for ${trigger.promptId}');
        continue;
      }
      final allowed = frequencyCapStore.allow(
        trigger.promptId,
        trigger.frequency,
        now: now,
      );
      if (!allowed) {
        log.d('frequency cap blocks ${trigger.promptId}');
        continue;
      }
      return trigger;
    }
    return null;
  }
}
