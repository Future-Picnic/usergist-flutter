/// Feature requests (5th pillar) — public Dart types.
///
/// Transport, optimistic cache behavior, and SDK-owned UI are implemented;
/// PARITY.md tracks remaining release testing.
library;

enum RequestStatus {
  underReview('under_review'),
  planned('planned'),
  inProgress('in_progress'),
  shipped('shipped'),
  declined('declined');

  final String raw;
  const RequestStatus(this.raw);

  static RequestStatus fromRaw(String raw) {
    for (final value in RequestStatus.values) {
      if (value.raw == raw) return value;
    }
    return RequestStatus.underReview;
  }
}

enum RequestFollowSource {
  upvoteAuto('upvote_auto'),
  manual('manual');

  final String raw;
  const RequestFollowSource(this.raw);
}

enum RequestSort {
  top('top'),
  newest('newest'),
  recentlyUpdated('recently_updated');

  final String raw;
  const RequestSort(this.raw);
}

enum RequestPersonalFilter {
  submitted('submitted'),
  upvoted('upvoted'),
  following('following');

  final String raw;
  const RequestPersonalFilter(this.raw);
}

class FeatureRequest {
  final String id;
  final String appId;
  final String title;
  final String description;
  final RequestStatus status;
  final String? devResponse;
  final int upvoteCount;
  final int followerCount;
  final String createdAt;
  final String updatedAt;
  final String statusChangedAt;
  final String? lastRespondedAt;
  final bool viewerHasUpvoted;
  final bool viewerIsFollowing;
  final bool viewerIsSubmitter;

  const FeatureRequest({
    required this.id,
    required this.appId,
    required this.title,
    required this.description,
    required this.status,
    required this.devResponse,
    required this.upvoteCount,
    required this.followerCount,
    required this.createdAt,
    required this.updatedAt,
    required this.statusChangedAt,
    required this.lastRespondedAt,
    required this.viewerHasUpvoted,
    required this.viewerIsFollowing,
    required this.viewerIsSubmitter,
  });
}

class RequestSummary {
  final String id;
  final String title;
  final String description;
  final RequestStatus status;
  final int upvoteCount;
  final int followerCount;
  final String createdAt;
  final String statusChangedAt;
  final bool viewerHasUpvoted;
  final bool viewerIsFollowing;

  const RequestSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.upvoteCount,
    required this.followerCount,
    required this.createdAt,
    required this.statusChangedAt,
    required this.viewerHasUpvoted,
    required this.viewerIsFollowing,
  });
}

class RequestSearchResult {
  final String id;
  final String title;
  final RequestStatus status;
  final int upvoteCount;

  const RequestSearchResult({
    required this.id,
    required this.title,
    required this.status,
    required this.upvoteCount,
  });
}

class RequestVote {
  final String requestId;
  final bool upvoted;
  final bool followed;
  final int upvoteCount;
  final int followerCount;

  const RequestVote({
    required this.requestId,
    required this.upvoted,
    required this.followed,
    required this.upvoteCount,
    required this.followerCount,
  });
}

class RequestFollow {
  final String requestId;
  final bool following;
  final int followerCount;
  final RequestFollowSource source;

  const RequestFollow({
    required this.requestId,
    required this.following,
    required this.followerCount,
    required this.source,
  });
}

class GetRequestsOptions {
  final RequestSort? sort;
  final List<RequestStatus>? statuses;
  final RequestPersonalFilter? mine;
  final String? q;
  final String? cursor;
  final int? limit;

  const GetRequestsOptions({
    this.sort,
    this.statuses,
    this.mine,
    this.q,
    this.cursor,
    this.limit,
  });
}

class GetRequestsResult {
  final List<RequestSummary> items;
  final String? nextCursor;

  const GetRequestsResult({required this.items, required this.nextCursor});
}

class RequestStatusChangedNotice {
  final String requestId;
  final String title;
  final RequestStatus oldStatus;
  final RequestStatus newStatus;
  final String? devResponseExcerpt;

  const RequestStatusChangedNotice({
    required this.requestId,
    required this.title,
    required this.oldStatus,
    required this.newStatus,
    required this.devResponseExcerpt,
  });
}

class RequestsHandlers {
  final void Function(FeatureRequest)? onSubmit;
  final void Function(RequestVote)? onVote;
  final void Function(RequestFollow)? onFollow;
  final void Function(RequestStatusChangedNotice)? onStatusChanged;

  const RequestsHandlers({
    this.onSubmit,
    this.onVote,
    this.onFollow,
    this.onStatusChanged,
  });
}
