/// Lightweight segment rules shipped with each armed trigger. The SDK
/// evaluates a subset locally for instant firing; the server re-verifies.
///
/// Mirrors `SerializedSegmentRules` from `sdk-core`.
class SerializedSegmentRules {
  /// Creates a set of segment rules.
  const SerializedSegmentRules({
    this.userProperties = const <UserPropertyRule>[],
    this.eventCounts = const <EventCountRule>[],
  });

  /// User-property predicates (implicit AND across entries).
  final List<UserPropertyRule> userProperties;

  /// Event-count predicates (implicit AND across entries).
  final List<EventCountRule> eventCounts;

  /// Parses from the JSON payload.
  factory SerializedSegmentRules.fromJson(Map<String, Object?> json) {
    final up = <UserPropertyRule>[];
    final ec = <EventCountRule>[];
    final rawUp = json['userProperties'];
    final rawEc = json['eventCounts'];
    if (rawUp is List<Object?>) {
      for (final r in rawUp) {
        if (r is Map<String, Object?>) {
          up.add(UserPropertyRule.fromJson(r));
        }
      }
    }
    if (rawEc is List<Object?>) {
      for (final r in rawEc) {
        if (r is Map<String, Object?>) {
          ec.add(EventCountRule.fromJson(r));
        }
      }
    }
    return SerializedSegmentRules(
      userProperties: List<UserPropertyRule>.unmodifiable(up),
      eventCounts: List<EventCountRule>.unmodifiable(ec),
    );
  }

  /// Returns `true` if there are no predicates at all.
  bool get isEmpty => userProperties.isEmpty && eventCounts.isEmpty;
}

/// Comparison operator for user-property rules.
enum UserPropertyOp {
  /// Equality.
  eq,

  /// Inequality.
  neq,

  /// Value must be in a provided list.
  inList,

  /// Numeric greater-than.
  gt,

  /// Numeric greater-than-or-equal.
  gte,

  /// Numeric less-than.
  lt,

  /// Numeric less-than-or-equal.
  lte;

  /// Parses from wire value.
  static UserPropertyOp fromWire(String value) {
    switch (value) {
      case 'eq':
        return UserPropertyOp.eq;
      case 'neq':
        return UserPropertyOp.neq;
      case 'in':
        return UserPropertyOp.inList;
      case 'gt':
        return UserPropertyOp.gt;
      case 'gte':
        return UserPropertyOp.gte;
      case 'lt':
        return UserPropertyOp.lt;
      case 'lte':
        return UserPropertyOp.lte;
    }
    throw FormatException('Unknown user-property op: $value');
  }
}

/// A single user-property predicate.
class UserPropertyRule {
  /// Creates a user-property rule.
  const UserPropertyRule({
    required this.key,
    required this.op,
    required this.value,
  });

  /// Property key.
  final String key;

  /// Comparison operator.
  final UserPropertyOp op;

  /// Value to compare against — either a scalar or a list of scalars
  /// (for [UserPropertyOp.inList]).
  final Object? value;

  /// Parses from JSON.
  factory UserPropertyRule.fromJson(Map<String, Object?> json) =>
      UserPropertyRule(
        key: json['key']! as String,
        op: UserPropertyOp.fromWire(json['op']! as String),
        value: json['value'],
      );
}

/// Comparison operator for event-count rules.
enum EventCountOp {
  /// Count equals.
  eq,

  /// Count at least.
  gte,

  /// Count at most.
  lte;

  /// Parses from wire value.
  static EventCountOp fromWire(String value) {
    switch (value) {
      case 'eq':
        return EventCountOp.eq;
      case 'gte':
        return EventCountOp.gte;
      case 'lte':
        return EventCountOp.lte;
    }
    throw FormatException('Unknown event-count op: $value');
  }
}

/// An event-count predicate: "user did event X at least N times in M days".
class EventCountRule {
  /// Creates an event-count rule.
  const EventCountRule({
    required this.eventName,
    required this.op,
    required this.count,
    required this.windowDays,
  });

  /// Event name to count.
  final String eventName;

  /// Comparison operator.
  final EventCountOp op;

  /// Count threshold.
  final int count;

  /// Sliding-window length in days.
  final int windowDays;

  /// Parses from JSON.
  factory EventCountRule.fromJson(Map<String, Object?> json) => EventCountRule(
        eventName: json['eventName']! as String,
        op: EventCountOp.fromWire(json['op']! as String),
        count: (json['count']! as num).toInt(),
        windowDays: (json['windowDays']! as num).toInt(),
      );
}
