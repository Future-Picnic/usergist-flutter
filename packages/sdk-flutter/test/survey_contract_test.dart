import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/survey.dart';

void main() {
  test('decodes the server survey flow and attempt contract', () {
    final survey = SurveyCampaignWithFlow.fromJson(<String, Object?>{
      'id': 'survey-1',
      'name': 'Checkout study',
      'flow': <String, Object?>{
        'startQuestionId': 'q1',
        'progressStyle': 'dots',
        'backNavigation': true,
        'questions': <Object?>[
          <String, Object?>{
            'id': 'q1',
            'type': 'single_choice',
            'title': 'Was checkout easy?',
            'required': true,
            'options': <Object?>[
              <String, Object?>{'id': 'yes', 'label': 'Yes'},
              <String, Object?>{'id': 'no', 'label': 'No'},
            ],
          },
          <String, Object?>{
            'id': 'q2',
            'type': 'long_text',
            'title': 'What went wrong?',
          },
          <String, Object?>{
            'id': 'q3',
            'type': 'info_screen',
            'title': 'All done',
          },
        ],
        'branches': <Object?>[
          <String, Object?>{
            'fromQuestionId': 'q1',
            'condition': <String, Object?>{'op': 'eq', 'value': 'yes'},
            'toQuestionId': 'q3',
          },
        ],
      },
    });
    final attempt = SurveyAttemptSession.fromJson(<String, Object?>{
      'attemptId': 'attempt-1',
      'startQuestionId': 'q1',
      'progressSnapshot': <String, Object?>{'q1': 'no'},
      'currentQuestionId': 'q2',
      'resumed': true,
    });

    expect(survey.flow.questions, hasLength(3));
    expect(survey.flow.progressStyle, 'dots');
    expect(
      survey.flow.nextQuestionId('q1', <String, Object?>{'q1': 'yes'}),
      'q3',
    );
    expect(
      survey.flow.nextQuestionId('q1', <String, Object?>{'q1': 'no'}),
      'q2',
    );
    expect(attempt.currentQuestionId, 'q2');
    expect(attempt.progressSnapshot['q1'], 'no');
  });

  test('supports answered, numeric, and end-sentinel branches', () {
    final flow = SurveyFlow.fromJson(<String, Object?>{
      'startQuestionId': 'q1',
      'questions': <Object?>[
        <String, Object?>{'id': 'q1', 'type': 'rating', 'title': 'Rate'},
        <String, Object?>{'id': 'q2', 'type': 'short_text', 'title': 'Why?'},
      ],
      'branches': <Object?>[
        <String, Object?>{
          'fromQuestionId': 'q1',
          'condition': <String, Object?>{'op': 'gte', 'value': 4},
          'toQuestionId': '__end__',
        },
      ],
      'progressStyle': 'bar',
      'backNavigation': true,
    });

    expect(flow.nextQuestionId('q1', <String, Object?>{'q1': 5}), isNull);
    expect(flow.nextQuestionId('q1', <String, Object?>{'q1': 2}), 'q2');
  });

  test('decodes armed survey targeting and embedded content', () {
    final armed = ArmedSurvey.fromJson(<String, Object?>{
      'campaignId': 'survey-1',
      'eventName': 'checkout_completed',
      'clientSideEligible': false,
      'cooldownSeconds': 90,
      'segmentRules': <String, Object?>{
        'userProperties': <Object?>[
          <String, Object?>{'key': 'plan', 'op': 'eq', 'value': 'pro'},
        ],
      },
      'frequencyCap': <String, Object?>{
        'perCampaignDays': 7,
        'perPillarDays': 1,
      },
      'survey': <String, Object?>{
        'id': 'survey-1',
        'name': 'Checkout',
        'flow': <String, Object?>{
          'startQuestionId': 'q1',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'type': 'info_screen',
              'title': 'Done',
            },
          ],
        },
      },
    });

    expect(armed.clientSideEligible, isFalse);
    expect(armed.cooldownSeconds, 90);
    expect(armed.frequencyCap.perCampaignDays, 7);
    expect(armed.survey.name, 'Checkout');
  });
}
