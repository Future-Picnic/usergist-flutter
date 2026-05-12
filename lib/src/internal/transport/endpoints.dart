/// Endpoint paths for the SDK-facing API. See `sdk-core/contract/endpoints.ts`.
class SdkEndpoints {
  SdkEndpoints._();

  /// Ingest events.
  static const String ingest = '/v1/sdk/ingest';

  /// Armed-triggers fetch.
  static const String armedTriggers = '/v1/sdk/armed-triggers';

  /// Consent upload.
  static const String consent = '/v1/sdk/consent';

  /// Identify user.
  static const String identify = '/v1/sdk/identify';

  /// Prompt responses.
  static const String responses = '/v1/sdk/responses';

  /// Push — device token registration.
  static const String pushRegisterToken = '/v1/sdk/push/register-token';

  /// Push — device token update.
  static const String pushUpdateToken = '/v1/sdk/push/update-token';

  /// Push — device token invalidation.
  static const String pushInvalidateToken = '/v1/sdk/push/invalidate-token';

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
}

/// Default base URLs for each deployment environment.
class DefaultApiUrls {
  DefaultApiUrls._();

  /// Production API.
  static const String production = 'https://api.ritmus.studio';

  /// Staging API.
  static const String staging = 'https://staging.api.ritmus.studio';

  /// Development API (local or dev cluster).
  static const String development = 'http://localhost:3000';
}
