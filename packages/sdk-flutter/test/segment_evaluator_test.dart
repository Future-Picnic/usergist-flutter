import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/triggers/segment_evaluator.dart';
import 'package:usergist_feedback/src/models/segment.dart';

void main() {
  test('null rules always match', () {
    expect(
      evaluateSerializedSegmentRules(null, const UserState()),
      isTrue,
    );
  });

  test('empty rules always match', () {
    expect(
      evaluateSerializedSegmentRules(
        const SerializedSegmentRules(),
        const UserState(),
      ),
      isTrue,
    );
  });

  test('user_property eq matches', () {
    const rules = SerializedSegmentRules(
      userProperties: <UserPropertyRule>[
        UserPropertyRule(
          key: 'plan',
          op: UserPropertyOp.eq,
          value: 'pro',
        ),
      ],
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(properties: <String, Object?>{'plan': 'pro'}),
      ),
      isTrue,
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(properties: <String, Object?>{'plan': 'free'}),
      ),
      isFalse,
    );
  });

  test('user_property in list matches', () {
    const rules = SerializedSegmentRules(
      userProperties: <UserPropertyRule>[
        UserPropertyRule(
          key: 'country',
          op: UserPropertyOp.inList,
          value: <Object?>['DE', 'FR'],
        ),
      ],
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(properties: <String, Object?>{'country': 'DE'}),
      ),
      isTrue,
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(properties: <String, Object?>{'country': 'US'}),
      ),
      isFalse,
    );
  });

  test('user_property numeric comparisons', () {
    for (final spec in <List<Object>>[
      <Object>[UserPropertyOp.gt, 9, 10, true],
      <Object>[UserPropertyOp.gte, 10, 10, true],
      <Object>[UserPropertyOp.lt, 11, 10, true],
      <Object>[UserPropertyOp.lte, 10, 10, true],
      <Object>[UserPropertyOp.gt, 11, 10, false],
    ]) {
      final op = spec[0] as UserPropertyOp;
      final value = spec[1];
      final actual = spec[2];
      final expected = spec[3] as bool;
      final rules = SerializedSegmentRules(
        userProperties: <UserPropertyRule>[
          UserPropertyRule(key: 'x', op: op, value: value),
        ],
      );
      final state = UserState(
        properties: <String, Object?>{'x': actual},
      );
      expect(
        evaluateSerializedSegmentRules(rules, state),
        expected,
        reason: 'op=$op value=$value actual=$actual',
      );
    }
  });

  test('event_count gte matches', () {
    const rules = SerializedSegmentRules(
      eventCounts: <EventCountRule>[
        EventCountRule(
          eventName: 'login',
          op: EventCountOp.gte,
          count: 3,
          windowDays: 7,
        ),
      ],
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(
          eventCounts: <String, Map<int, int>>{
            'login': <int, int>{7: 5},
          },
        ),
      ),
      isTrue,
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(
          eventCounts: <String, Map<int, int>>{
            'login': <int, int>{7: 2},
          },
        ),
      ),
      isFalse,
    );
  });

  test('combined predicates use implicit AND', () {
    const rules = SerializedSegmentRules(
      userProperties: <UserPropertyRule>[
        UserPropertyRule(
          key: 'plan',
          op: UserPropertyOp.eq,
          value: 'pro',
        ),
      ],
      eventCounts: <EventCountRule>[
        EventCountRule(
          eventName: 'login',
          op: EventCountOp.gte,
          count: 1,
          windowDays: 30,
        ),
      ],
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(
          properties: <String, Object?>{'plan': 'pro'},
          eventCounts: <String, Map<int, int>>{
            'login': <int, int>{30: 3},
          },
        ),
      ),
      isTrue,
    );
    expect(
      evaluateSerializedSegmentRules(
        rules,
        const UserState(
          properties: <String, Object?>{'plan': 'pro'},
          eventCounts: <String, Map<int, int>>{
            'login': <int, int>{30: 0},
          },
        ),
      ),
      isFalse,
    );
  });
}
