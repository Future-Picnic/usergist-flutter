import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/any_value.dart';

void main() {
  test('event properties match reference bounds and scalar contract', () {
    final clean = sanitizeProperties(<String, Object?>{
      'plan': 'pro',
      'account.email': 'private@example.com',
      'nested': <String, Object?>{'bad': true},
      'list': <int>[1, 2],
      'score': 4.5,
      'enabled': true,
      'nothing': null,
      'long': 'x' * 10001,
    });

    expect(clean['plan'], 'pro');
    expect(clean['score'], 4.5);
    expect(clean['enabled'], true);
    expect(clean.containsKey('nothing'), true);
    expect((clean['long']! as String).length, 10000);
    expect(clean.containsKey('account.email'), false);
    expect(clean.containsKey('nested'), false);
    expect(clean.containsKey('list'), false);
    expect(clean.length, lessThanOrEqualTo(100));
  });
}
