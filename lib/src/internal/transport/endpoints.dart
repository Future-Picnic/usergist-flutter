/// Endpoint paths for the SDK-facing API. See `sdk-core/contract/endpoints.ts`.
class SdkEndpoints {
  SdkEndpoints._();

  /// Opens or refreshes the authenticated subject session.
  static const String session = '/v1/sdk/session';

  /// Revokes the active subject session during reset.
  static const String sessionRevoke = '/v1/sdk/session/revoke';

  /// Durable server-to-SDK instruction inbox.
  static const String instructions = '/v1/sdk/instructions';

  /// Acknowledges durable instructions after local persistence/dispatch.
  static const String instructionsAck = '/v1/sdk/instructions/ack';

  /// Ingest events.
  static const String ingest = '/v1/sdk/ingest';

  /// Armed-triggers fetch.
  static const String armedTriggers = '/v1/sdk/armed-triggers';

  /// Armed survey campaigns eligible for local evaluation.
  static const String armedSurveys = '/v1/sdk/armed-surveys';

  /// Armed in-app messages eligible for local evaluation.
  static const String armedInAppMessages = '/v1/sdk/armed-inapp-messages';

  /// Consent upload.
  static const String consent = '/v1/sdk/consent';

  /// Identify user.
  static const String identify = '/v1/sdk/identify';

  /// Prompt responses.
  static const String responses = '/v1/sdk/responses';

  static String surveyComplete(String attemptId) =>
      '/v1/sdk/surveys/attempts/$attemptId/complete';

  static String surveyAbandon(String attemptId) =>
      '/v1/sdk/surveys/attempts/$attemptId/abandon';

  static const String availableSurveys = '/v1/sdk/surveys/available';

  static const String resolveSurveyLink = '/v1/sdk/surveys/resolve-link';

  static String survey(String surveyId) => '/v1/sdk/surveys/$surveyId';

  static String surveyAttempts(String surveyId) =>
      '/v1/sdk/surveys/$surveyId/attempts';

  static String surveyProgress(String attemptId) =>
      '/v1/sdk/surveys/attempts/$attemptId';

  /// Push — device token registration.
  static const String pushRegisterToken = '/v1/sdk/push/register-token';

  /// Push — device token update.
  static const String pushUpdateToken = '/v1/sdk/push/update-token';

  /// Push — device token invalidation.
  static const String pushInvalidateToken = '/v1/sdk/push/invalidate-token';

  /// Push — rebind the last token after identify.
  static const String pushRebind = '/v1/sdk/push/rebind';

  /// Push — app reachability beacon.
  static const String pushAppOpen = '/v1/sdk/push/app-open';

  static const String pushDelivered = '/v1/sdk/push/delivered';
  static const String pushDisplayed = '/v1/sdk/push/displayed';
  static const String pushDismissed = '/v1/sdk/push/dismissed';
  static const String pushSilentAck = '/v1/sdk/push/silent-ack';
  static const String pushChannels = '/v1/sdk/push/channels';
  static const String pushChannelSubscription =
      '/v1/sdk/push/channels/subscription';

  /// Feature requests — list / submit.
  static const String requests = '/v1/sdk/requests';

  /// Feature requests — fetch by id.
  static String request(String id) => '/v1/sdk/requests/$id';

  /// Feature requests — vote toggle.
  static String requestVote(String id) => '/v1/sdk/requests/$id/vote';

  /// Feature requests — follow toggle.
  static String requestFollow(String id) => '/v1/sdk/requests/$id/follow';

  /// Feature requests — comments list / post.
  static String requestComments(String id) => '/v1/sdk/requests/$id/comments';

  /// Feature requests — single comment (edit / delete).
  static String requestComment(String requestId, String commentId) =>
      '/v1/sdk/requests/$requestId/comments/$commentId';

  /// Feature requests — per-app branding for the SDK UI.
  static const String requestBranding = '/v1/sdk/request-branding';
}

/// Default base URLs for each deployment environment.
class DefaultApiUrls {
  DefaultApiUrls._();

  /// Production API.
  static const String production = 'https://api.usergist.com';

  /// Staging API.
  /// Staging identifies customer app data; it is served by the same public
  /// UserGist edge and isolated by app id and write key.
  static const String staging = 'https://api.usergist.com';

  /// Development API (local or dev cluster).
  static const String development = 'http://localhost:28743';
}
