import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/survey.dart';
import 'package:usergist_feedback/src/ui/survey_rating_input.dart';
import 'package:usergist_feedback/src/ui/theme_resolver.dart';

void main() {
  const theme = ResolvedPromptTheme(
    primary: Color(0xFF6548E8),
    background: Colors.white,
    text: Color(0xFF1D1933),
    subtext: Color(0xFF6B6680),
    border: Color(0xFFE5E1F0),
    radius: 16,
  );
  const question = SurveyQuestion(
    id: 'survey-rating',
    type: 'rating',
    title: 'How reliable did it feel?',
    required: true,
    options: <SurveyChoice>[],
    items: <SurveyChoice>[],
    scale: 5,
  );

  testWidgets('survey rating uses the prompt star control by default', (
    tester,
  ) async {
    int? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SurveyRatingInput(
            question: question,
            theme: theme,
            onChanged: (value) => answer = value,
          ),
        ),
      ),
    );

    expect(find.text('★'), findsNWidgets(5));
    expect(find.text('1'), findsNothing);
    await tester.tap(find.text('★').at(2));
    expect(answer, 3);
  });

  testWidgets('survey rating restores a saved star selection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SurveyRatingInput(
            question: question,
            theme: theme,
            initialValue: 4,
            onChanged: _ignore,
          ),
        ),
      ),
    );

    final stars = tester.widgetList<Text>(find.text('★')).toList();
    expect(
      stars.take(4).every((star) => star.style?.color == theme.primary),
      isTrue,
    );
    expect(stars.last.style?.color, theme.border);
  });
}

void _ignore(int? _) {}
