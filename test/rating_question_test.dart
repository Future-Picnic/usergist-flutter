import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/questions/rating_question.dart';
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

  testWidgets('default rating uses stars and reports the selected score', (
    tester,
  ) async {
    int? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatingQuestionView(
            question: const RatingQuestion(
              id: 'q',
              title: 'Rate',
              scale: 5,
            ),
            theme: theme,
            onChanged: (value) => answer = value,
          ),
        ),
      ),
    );

    expect(find.text('★'), findsNWidgets(5));
    expect(find.text('1'), findsNothing);
    final star = tester.widget<Text>(find.text('★').first);
    expect(star.style?.fontSize, 32);
    final semantics = tester.getSemantics(find.bySemanticsLabel('Rate 5'));
    expect(semantics.label, 'Rate 5');
    await tester.tap(find.text('★').at(3));
    expect(answer, 4);
  });

  testWidgets('numeric rating preserves numbered score chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatingQuestionView(
            question: const RatingQuestion(
              id: 'q',
              title: 'Rate',
              scale: 5,
              display: RatingDisplayMode.numeric,
            ),
            theme: theme,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('★'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });
}
