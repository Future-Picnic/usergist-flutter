import 'package:flutter/material.dart';

import '../models/question.dart';
import '../models/survey.dart';
import 'questions/rating_question.dart';
import 'theme_resolver.dart';

/// Routes survey ratings through the same star-first control used by prompts.
class SurveyRatingInput extends StatelessWidget {
  /// Creates a survey rating backed by the shared prompt rating control.
  const SurveyRatingInput({
    required this.question,
    required this.theme,
    required this.onChanged,
    this.initialValue,
    super.key,
  });

  /// Survey question whose rating metadata is displayed.
  final SurveyQuestion question;

  /// Fully resolved dashboard and SDK theme.
  final ResolvedPromptTheme theme;

  /// Called when the user selects a star value.
  final ValueChanged<int?> onChanged;

  /// Previously saved answer restored when the survey resumes.
  final int? initialValue;

  @override
  Widget build(BuildContext context) => RatingQuestionView(
        question: RatingQuestion(
          id: question.id,
          title: question.title,
          subtitle: question.subtitle,
          imageUrl: question.imageUrl,
          scale: question.scale == 10 ? 10 : 5,
          lowLabel: question.lowLabel,
          highLabel: question.highLabel,
        ),
        theme: theme,
        initialValue: initialValue,
        onChanged: onChanged,
      );
}
