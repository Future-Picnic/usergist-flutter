import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/prompt_sheet.dart';

void main() {
  testWidgets('all prompt question types follow the reference flow', (
    tester,
  ) async {
    PromptSheetResult? outcome;
    const prompt = ClientPrompt(
      id: 'prompt',
      questions: <Question>[
        RatingQuestion(id: 'rating', title: 'Rate it', scale: 5),
        NpsQuestion(
          id: 'nps',
          title: 'Recommend it?',
          followUp: 'What led to your score?',
        ),
        MultipleChoiceQuestion(
          id: 'single',
          title: 'Pick one',
          options: <MultipleChoiceOption>[
            MultipleChoiceOption(id: 'single-a', label: 'Single A'),
            MultipleChoiceOption(id: 'single-b', label: 'Single B'),
          ],
        ),
        MultipleChoiceQuestion(
          id: 'multi',
          title: 'Pick several',
          multiSelect: true,
          options: <MultipleChoiceOption>[
            MultipleChoiceOption(id: 'multi-a', label: 'Multi A'),
            MultipleChoiceOption(id: 'multi-b', label: 'Multi B'),
          ],
        ),
        ShortTextQuestion(
          id: 'text',
          title: 'Tell us more',
          placeholder: 'Type here',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                outcome = await showModalBottomSheet<PromptSheetResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const PromptSheet(
                    prompt: prompt,
                    themeOverrides: null,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rate it'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.text('★').at(3));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recommend it?'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    final npsDisabled = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(npsDisabled.onPressed, isNull);

    await tester.ensureVisible(find.text('7'));
    await tester.tap(find.text('7'));
    await tester.pump();
    expect(find.text('What led to your score?'), findsOneWidget);
    final npsEnabled = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(npsEnabled.onPressed, isNotNull);
    await tester.enterText(find.byType(TextFormField), 'Fast and focused');
    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pick one'), findsOneWidget);

    await tester.tap(find.text('Single A'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pick several'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Multi A'));
    await tester.tap(find.text('Multi B'));
    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tell us more'), findsOneWidget);

    final disabled = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(disabled.onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Detailed feedback');
    await tester.pump();
    final enabled = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(enabled.onPressed, isNotNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(outcome?.dismissed, isFalse);
    expect(outcome?.answers.map((answer) => answer.questionId), <String>[
      'rating',
      'nps',
      'nps__followUp',
      'single',
      'multi',
      'text',
    ]);
    expect(outcome?.answers[0].value, 4);
    expect(outcome?.answers[1].value, 7);
    expect(outcome?.answers[2].value, 'Fast and focused');
    expect(outcome?.answers[3].value, <String>['single-a']);
    expect(outcome?.answers[4].value, <String>['multi-a', 'multi-b']);
    expect(outcome?.answers[5].value, 'Detailed feedback');
  });

  testWidgets('dismiss preserves answers already selected', (tester) async {
    PromptSheetResult? outcome;
    const prompt = ClientPrompt(
      id: 'prompt',
      questions: <Question>[
        RatingQuestion(id: 'rating', title: 'Rate it', scale: 5),
        ShortTextQuestion(id: 'text', title: 'Tell us more'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                outcome = await showModalBottomSheet<PromptSheetResult>(
                  context: context,
                  builder: (_) => const PromptSheet(
                    prompt: prompt,
                    themeOverrides: null,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('★').first);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(outcome?.dismissed, isTrue);
    expect(outcome?.answers.single.questionId, 'rating');
    expect(outcome?.answers.single.value, 1);
  });
}
