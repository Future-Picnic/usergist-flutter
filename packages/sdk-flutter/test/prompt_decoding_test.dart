import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';

void main() {
  test('decodes rating question', () {
    final q = Question.fromJson(<String, Object?>{
      'id': 'q1',
      'type': 'rating',
      'title': 'How was it?',
      'imageUrl': 'https://example.com/rating.png',
      'scale': 5,
      'display': 'emoji',
      'lowLabel': 'Bad',
      'highLabel': 'Great',
    });
    expect(q, isA<RatingQuestion>());
    final r = q as RatingQuestion;
    expect(r.scale, 5);
    expect(r.display, RatingDisplayMode.emoji);
    expect(r.lowLabel, 'Bad');
    expect(r.highLabel, 'Great');
    expect(r.imageUrl, 'https://example.com/rating.png');
  });

  test('defaults rating display to stars', () {
    final q = Question.fromJson(<String, Object?>{
      'id': 'q-default',
      'type': 'rating',
      'title': 'How was it?',
      'scale': 5,
    }) as RatingQuestion;
    expect(q.display, RatingDisplayMode.stars);
  });

  test('decodes NPS question', () {
    final q = Question.fromJson(<String, Object?>{
      'id': 'q2',
      'type': 'nps',
      'title': 'Would you recommend us?',
      'followUp': 'Why?',
      'lowLabel': 'Never',
      'highLabel': 'Absolutely',
    });
    expect(q, isA<NpsQuestion>());
    final nps = q as NpsQuestion;
    expect(nps.followUp, 'Why?');
    expect(nps.lowLabel, 'Never');
    expect(nps.highLabel, 'Absolutely');
  });

  test('decodes multiple-choice question', () {
    final q = Question.fromJson(<String, Object?>{
      'id': 'q3',
      'type': 'multiple_choice',
      'title': 'Pick one',
      'multiSelect': false,
      'options': <Object?>[
        <String, Object?>{'id': 'a', 'label': 'A'},
        <String, Object?>{'id': 'b', 'label': 'B'},
      ],
    });
    expect(q, isA<MultipleChoiceQuestion>());
    final m = q as MultipleChoiceQuestion;
    expect(m.multiSelect, isFalse);
    expect(m.options, hasLength(2));
    expect(m.options[0].id, 'a');
    expect(m.options[1].label, 'B');
  });

  test('decodes short-text question', () {
    final q = Question.fromJson(<String, Object?>{
      'id': 'q4',
      'type': 'short_text',
      'title': 'Tell us more',
      'placeholder': 'Type here…',
      'maxLength': 140,
    });
    expect(q, isA<ShortTextQuestion>());
    final s = q as ShortTextQuestion;
    expect(s.placeholder, 'Type here…');
    expect(s.maxLength, 140);
  });

  test('decodes an ArmedTrigger with an embedded ClientPrompt', () {
    final at = ArmedTrigger.fromJson(<String, Object?>{
      'promptId': 'p1',
      'eventName': 'checkout_completed',
      'clientSideEligible': false,
      'frequency': <String, Object?>{'perPromptDays': 30, 'perUserDays': 7},
      'segmentRules': <String, Object?>{
        'userProperties': <Object?>[
          <String, Object?>{'key': 'plan', 'op': 'eq', 'value': 'pro'},
        ],
      },
      'prompt': <String, Object?>{
        'id': 'p1',
        'questions': <Object?>[
          <String, Object?>{
            'id': 'q1',
            'type': 'rating',
            'title': 'Rate us',
            'scale': 10,
          },
        ],
        'theme': <String, Object?>{
          'colors': <String, Object?>{
            'primary': '#112233',
          },
          'radius': 16,
        },
      },
    });
    expect(at.promptId, 'p1');
    expect(at.eventName, 'checkout_completed');
    expect(at.clientSideEligible, isFalse);
    expect(at.frequency.perPromptDays, 30);
    expect(at.prompt.questions, hasLength(1));
    expect((at.prompt.questions.first as RatingQuestion).scale, 10);
    expect(at.prompt.theme?.radius, 16);
  });
}
