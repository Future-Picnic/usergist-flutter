/// UserGist mobile feedback SDK for Flutter.
///
/// Public entrypoint. Import as:
///
/// ```dart
/// import 'package:usergist_feedback/usergist_feedback.dart';
/// ```
library;

export 'src/usergist.dart' show UserGist, UserGistEnvironment;
export 'src/provider.dart' show UserGistProvider;
export 'src/models/consent.dart' show Consent;
export 'src/models/diagnostic.dart' show SdkDiagnostic;
export 'src/models/inapp_message.dart'
    show ArmedInAppMessage, InAppCta, InAppCtaClick, InAppHandlers;
export 'src/models/theme.dart' show PromptTheme, PromptThemeColors;
export 'src/models/question.dart'
    show
        Question,
        QuestionType,
        RatingDisplayMode,
        RatingQuestion,
        NpsQuestion,
        MultipleChoiceQuestion,
        MultipleChoiceOption,
        ShortTextQuestion;
export 'src/models/response_info.dart'
    show PromptResponseInfo, ResponseAnswer, AnswerValue;
export 'src/models/prompt.dart' show ClientPrompt, ArmedTrigger, FrequencyCaps;
export 'src/push/push.dart'
    show
        Push,
        PushHandlers,
        UserGistPushChannel,
        UserGistPushMessage,
        PushPermissionStatus;
export 'src/models/survey.dart' show SurveySummary, SurveyHandlers;
export 'src/models/request.dart'
    show
        RequestStatus,
        RequestFollowSource,
        RequestSort,
        RequestPersonalFilter,
        FeatureRequest,
        RequestSummary,
        RequestSearchResult,
        RequestVote,
        RequestFollow,
        GetRequestsOptions,
        GetRequestsResult,
        RequestStatusChangedNotice,
        RequestsHandlers;
