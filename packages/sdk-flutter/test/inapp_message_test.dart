import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/inapp_message.dart';

void main() {
  test('decodes the authenticated in-app instruction payload', () {
    final message = ArmedInAppMessage.fromJson(<String, Object?>{
      'messageId': 'message-1',
      'eventName': 'checkout_completed',
      'clientSideEligible': true,
      'format': 'slideup',
      'title': 'How did checkout go?',
      'body': 'Tell us while it is fresh.',
      'backdropEnabled': false,
      'autoDismissSeconds': 4,
      'ctas': <Object?>[
        <String, Object?>{
          'label': 'Share feedback',
          'action': 'custom_event',
          'target': 'checkout_feedback_requested',
        },
      ],
      'screenAllowlist': <Object?>['Checkout'],
      'screenDenylist': <Object?>[],
      'forceShow': false,
    });

    expect(message.messageId, 'message-1');
    expect(message.format, 'slideup');
    expect(message.backdropEnabled, isFalse);
    expect(message.autoDismissSeconds, 4);
    expect(message.ctas.single.action, 'custom_event');
    expect(message.screenAllowlist, <String>['Checkout']);
  });

  test('rejects unknown formats and CTA actions', () {
    expect(
      () => ArmedInAppMessage.fromJson(<String, Object?>{
        'messageId': 'message-1',
        'format': 'toast',
      }),
      throwsFormatException,
    );
    expect(
      () => InAppCta.fromJson(<String, Object?>{
        'label': 'Do it',
        'action': 'run_code',
      }),
      throwsFormatException,
    );
  });

  test('decodes a JSON in-app action', () {
    final message = ArmedInAppMessage.fromJson(<String, Object?>{
      'messageId': 'message-json',
      'format': 'modal',
      'title': 'Selected offer',
      'ctas': <Object?>[
        <String, Object?>{
          'label': 'Show price',
          'action': 'json',
          'actionJson': <String, Object?>{
            'type': 'show_special_price',
            'price': 19,
          },
        },
      ],
    });

    expect(message.ctas.single.action, 'json');
    expect(message.ctas.single.actionJson, <String, Object?>{
      'type': 'show_special_price',
      'price': 19,
    });
  });
}
