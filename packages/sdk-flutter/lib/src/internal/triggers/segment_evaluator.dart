import '../../models/segment.dart';

/// The user state snapshot used by the local segment evaluator.
class UserState {
  /// Creates a [UserState] snapshot.
  const UserState({
    this.properties = const <String, Object?>{},
    this.eventCounts = const <String, Map<int, int>>{},
    this.lastEventAt = const <String, DateTime?>{},
  });

  /// Property key -> scalar value.
  final Map<String, Object?> properties;

  /// eventName -> (windowDays -> count) map.
  final Map<String, Map<int, int>> eventCounts;

  /// eventName -> most-recent timestamp.
  final Map<String, DateTime?> lastEventAt;
}

/// Evaluates [rules] against [user]. A `null` ruleset returns `true`.
///
/// Port of `evaluateSerializedSegmentRules` from sdk-core.
bool evaluateSerializedSegmentRules(
  SerializedSegmentRules? rules,
  UserState user,
) {
  if (rules == null) return true;
  for (final rule in rules.userProperties) {
    if (!_evaluateUserProperty(rule, user)) return false;
  }
  for (final rule in rules.eventCounts) {
    if (!_evaluateEventCount(rule, user)) return false;
  }
  return true;
}

bool _evaluateUserProperty(UserPropertyRule rule, UserState user) {
  final actual = user.properties[rule.key];
  switch (rule.op) {
    case UserPropertyOp.eq:
      return actual == rule.value;
    case UserPropertyOp.neq:
      return actual != rule.value;
    case UserPropertyOp.inList:
      if (rule.value is! List) return false;
      if (actual == null) return false;
      return (rule.value! as List<Object?>).contains(actual);
    case UserPropertyOp.gt:
      return _numericCompare(actual, rule.value, (a, b) => a > b);
    case UserPropertyOp.gte:
      return _numericCompare(actual, rule.value, (a, b) => a >= b);
    case UserPropertyOp.lt:
      return _numericCompare(actual, rule.value, (a, b) => a < b);
    case UserPropertyOp.lte:
      return _numericCompare(actual, rule.value, (a, b) => a <= b);
  }
}

bool _numericCompare(
  Object? actual,
  Object? expected,
  bool Function(num a, num b) cmp,
) {
  if (actual is num && expected is num) return cmp(actual, expected);
  return false;
}

bool _evaluateEventCount(EventCountRule rule, UserState user) {
  final bucket = user.eventCounts[rule.eventName];
  final count = bucket?[rule.windowDays] ?? 0;
  switch (rule.op) {
    case EventCountOp.eq:
      return count == rule.count;
    case EventCountOp.gte:
      return count >= rule.count;
    case EventCountOp.lte:
      return count <= rule.count;
  }
}
