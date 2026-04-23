/// Ritmus mobile feedback SDK for Flutter.
///
/// Public entrypoint. Import as:
///
/// ```dart
/// import 'package:ritmus_feedback/ritmus_feedback.dart';
/// ```
library;

export 'src/ritmus.dart' show Ritmus, RitmusEnvironment;
export 'src/provider.dart' show RitmusProvider;
export 'src/models/consent.dart' show Consent;
export 'src/models/theme.dart' show PromptTheme, PromptThemeColors;
export 'src/models/question.dart'
    show
        Question,
        QuestionType,
        RatingQuestion,
        NpsQuestion,
        MultipleChoiceQuestion,
        MultipleChoiceOption,
        ShortTextQuestion;
export 'src/models/response_info.dart'
    show PromptResponseInfo, ResponseAnswer, AnswerValue;
export 'src/models/prompt.dart' show ClientPrompt, ArmedTrigger, FrequencyCaps;
