// PORTED FROM: packages/sdk-react-native/src/UserGist.ts (requests methods)
//
// HTTP wiring for the Feature Requests pillar. Maps directly to the
// endpoints declared in packages/sdk-core/src/contract/endpoints.ts.

import '../../models/request.dart';
import '../logger.dart';
import '../transport/api_client.dart';
import '../transport/endpoints.dart';

class FlutterRequestComment {
  const FlutterRequestComment({
    required this.id,
    required this.requestId,
    required this.body,
    required this.createdAt,
    required this.isFromTeam,
    this.authorAnonymousId,
    this.authorRole,
    this.updatedAt,
  });
  final String id;
  final String requestId;
  final String body;
  final String createdAt;
  final String? updatedAt;
  final String? authorAnonymousId;
  final String? authorRole;
  final bool isFromTeam;
}

class FlutterRequestBranding {
  const FlutterRequestBranding({
    required this.entryLabel,
    this.accentColor,
    this.logoUrl,
    this.introCopy,
  });
  final String entryLabel;
  final String? accentColor;
  final String? logoUrl;
  final String? introCopy;
}

class RequestsApi {
  RequestsApi(this._api);

  final ApiClient _api;

  Future<GetRequestsResult> list({
    required String anonymousId,
    String? externalId,
    GetRequestsOptions options = const GetRequestsOptions(),
  }) async {
    final query = <String, String>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      if (options.sort != null) 'sort': options.sort!.raw,
      if (options.statuses != null && options.statuses!.isNotEmpty)
        'statuses': options.statuses!.map((s) => s.raw).join(','),
      if (options.mine != null) 'mine': options.mine!.raw,
      if (options.q != null && options.q!.isNotEmpty) 'q': options.q!,
      if (options.cursor != null) 'cursor': options.cursor!,
      if (options.limit != null) 'limit': '${options.limit}',
    };
    final res = await _api.getJson(SdkEndpoints.requests, query: query);
    if (!res.success || res.data == null) {
      log.w('requests.list failed: ${res.error}');
      return const GetRequestsResult(items: [], nextCursor: null);
    }
    final items = (res.data!['items'] as List?) ?? const <Object?>[];
    return GetRequestsResult(
      items: items
          .whereType<Map<String, Object?>>()
          .map(_decodeSummary)
          .toList(growable: false),
      nextCursor: res.data!['nextCursor'] as String?,
    );
  }

  Future<FeatureRequest?> getOne({
    required String requestId,
    required String anonymousId,
    String? externalId,
  }) async {
    final query = <String, String>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
    };
    final res =
        await _api.getJson(SdkEndpoints.request(requestId), query: query);
    if (!res.success || res.data == null) return null;
    return _decodeRequest(res.data!);
  }

  Future<FeatureRequest?> submit({
    required String anonymousId,
    String? externalId,
    required String title,
    required String description,
  }) async {
    final body = <String, Object?>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      'title': title,
      'description': description,
    };
    final res = await _api.postJson(SdkEndpoints.requests, body);
    if (!res.success || res.data == null) return null;
    return _decodeRequest(res.data!);
  }

  Future<RequestVote?> vote({
    required String requestId,
    required String anonymousId,
    String? externalId,
    required bool vote,
  }) async {
    final body = <String, Object?>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      'vote': vote,
    };
    final res = await _api.postJson(SdkEndpoints.requestVote(requestId), body);
    if (!res.success || res.data == null) return null;
    final d = res.data!;
    return RequestVote(
      requestId: (d['requestId'] as String?) ?? requestId,
      upvoted: (d['upvoted'] as bool?) ?? vote,
      followed: (d['followed'] as bool?) ?? false,
      upvoteCount: (d['upvoteCount'] as num?)?.toInt() ?? 0,
      followerCount: (d['followerCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<RequestFollow?> follow({
    required String requestId,
    required String anonymousId,
    String? externalId,
    required bool follow,
  }) async {
    final body = <String, Object?>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      'follow': follow,
    };
    final res =
        await _api.postJson(SdkEndpoints.requestFollow(requestId), body);
    if (!res.success || res.data == null) return null;
    final d = res.data!;
    final sourceRaw = (d['source'] as String?) ?? 'manual';
    final source = RequestFollowSource.values.firstWhere(
      (s) => s.raw == sourceRaw,
      orElse: () => RequestFollowSource.manual,
    );
    return RequestFollow(
      requestId: (d['requestId'] as String?) ?? requestId,
      following: (d['following'] as bool?) ?? follow,
      followerCount: (d['followerCount'] as num?)?.toInt() ?? 0,
      source: source,
    );
  }

  Future<List<FlutterRequestComment>> comments({
    required String requestId,
    required String anonymousId,
    String? externalId,
  }) async {
    final query = <String, String>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
    };
    final res = await _api.getJson(
      SdkEndpoints.requestComments(requestId),
      query: query,
    );
    if (!res.success || res.data == null) return const [];
    final items = (res.data!['items'] as List?) ?? const <Object?>[];
    return items
        .whereType<Map<String, Object?>>()
        .map(_decodeComment)
        .toList(growable: false);
  }

  Future<FlutterRequestComment?> postComment({
    required String requestId,
    required String anonymousId,
    String? externalId,
    required String body,
  }) async {
    final payload = <String, Object?>{
      'anonymousId': anonymousId,
      if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      'body': body,
    };
    final res =
        await _api.postJson(SdkEndpoints.requestComments(requestId), payload);
    if (!res.success || res.data == null) return null;
    return _decodeComment(res.data!);
  }

  Future<FlutterRequestComment?> editComment({
    required String requestId,
    required String commentId,
    required String anonymousId,
    required String body,
  }) async {
    final payload = <String, Object?>{'anonymousId': anonymousId, 'body': body};
    final res = await _api.patchJson(
      SdkEndpoints.requestComment(requestId, commentId),
      payload,
    );
    if (!res.success || res.data == null) return null;
    return _decodeComment(res.data!);
  }

  Future<bool> deleteComment({
    required String requestId,
    required String commentId,
    required String anonymousId,
  }) async {
    final res = await _api.deleteJson(
      SdkEndpoints.requestComment(requestId, commentId),
      query: {'anonymousId': anonymousId},
    );
    return res.success;
  }

  Future<FlutterRequestBranding?> getBranding() async {
    final res = await _api.getJson(SdkEndpoints.requestBranding);
    if (!res.success || res.data == null) return null;
    final m = res.data!;
    return FlutterRequestBranding(
      entryLabel: (m['entryLabel'] as String?) ?? 'Suggestions',
      accentColor: m['accentColor'] as String?,
      logoUrl: m['logoUrl'] as String?,
      introCopy: m['introCopy'] as String?,
    );
  }

  // --- decoders ---

  FeatureRequest _decodeRequest(Map<String, Object?> m) {
    final statusRaw = (m['status'] as String?) ?? 'under_review';
    return FeatureRequest(
      id: m['id'] as String? ?? '',
      appId: m['appId'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      status: RequestStatus.values.firstWhere(
        (s) => s.raw == statusRaw,
        orElse: () => RequestStatus.underReview,
      ),
      devResponse: m['devResponse'] as String?,
      upvoteCount: (m['upvoteCount'] as num?)?.toInt() ?? 0,
      followerCount: (m['followerCount'] as num?)?.toInt() ?? 0,
      createdAt: m['createdAt'] as String? ?? '',
      updatedAt: m['updatedAt'] as String? ?? '',
      statusChangedAt: m['statusChangedAt'] as String? ?? '',
      lastRespondedAt: m['lastRespondedAt'] as String?,
      viewerHasUpvoted: (m['viewerHasUpvoted'] as bool?) ?? false,
      viewerIsFollowing: (m['viewerIsFollowing'] as bool?) ?? false,
      viewerIsSubmitter: (m['viewerIsSubmitter'] as bool?) ?? false,
    );
  }

  RequestSummary _decodeSummary(Map<String, Object?> m) {
    final statusRaw = (m['status'] as String?) ?? 'under_review';
    return RequestSummary(
      id: m['id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      status: RequestStatus.values.firstWhere(
        (s) => s.raw == statusRaw,
        orElse: () => RequestStatus.underReview,
      ),
      upvoteCount: (m['upvoteCount'] as num?)?.toInt() ?? 0,
      followerCount: (m['followerCount'] as num?)?.toInt() ?? 0,
      createdAt: m['createdAt'] as String? ?? '',
      statusChangedAt: m['statusChangedAt'] as String? ?? '',
      viewerHasUpvoted: (m['viewerHasUpvoted'] as bool?) ?? false,
      viewerIsFollowing: (m['viewerIsFollowing'] as bool?) ?? false,
    );
  }

  FlutterRequestComment _decodeComment(Map<String, Object?> m) {
    return FlutterRequestComment(
      id: m['id'] as String? ?? '',
      requestId: m['requestId'] as String? ?? '',
      body: m['body'] as String? ?? '',
      createdAt: m['createdAt'] as String? ?? '',
      updatedAt: m['updatedAt'] as String?,
      authorAnonymousId: m['authorAnonymousId'] as String?,
      authorRole: m['authorRole'] as String?,
      isFromTeam: (m['isFromTeam'] as bool?) ?? false,
    );
  }
}
