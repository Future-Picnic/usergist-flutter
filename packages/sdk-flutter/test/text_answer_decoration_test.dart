import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/questions/short_text_question.dart';
import 'package:usergist_feedback/src/ui/theme_resolver.dart';

void main() {
  const theme = ResolvedPromptTheme(
    primary: Color(0xFF00A47C),
    background: Color(0xFFE8FFF7),
    text: Color(0xFF17122E),
    subtext: Color(0xFF766F8A),
    border: Color(0xFFE1DCEC),
    radius: 16,
    fontFamily: 'Plus Jakarta Sans',
  );

  testWidgets('text answers use the prompt theme instead of the host fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        home: Scaffold(
          body: ShortTextQuestionView(
            question: const ShortTextQuestion(
              id: 'details',
              title: 'What should improve?',
              placeholder: 'Tell us more',
              maxLength: 1000,
            ),
            theme: theme,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.decoration?.filled, isTrue);
    expect(input.decoration?.fillColor, theme.background);
    expect(input.decoration?.counterText, isEmpty);
    expect(input.cursorColor, theme.primary);
    expect(
      (input.decoration?.enabledBorder as OutlineInputBorder).borderSide.color,
      theme.border,
    );
    expect(
      (input.decoration?.focusedBorder as OutlineInputBorder).borderSide.color,
      theme.primary,
    );
  });
}
