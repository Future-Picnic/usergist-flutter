// PORTED FROM: packages/sdk-react-native/src/internal/requests.ts
//
// In-memory snapshot of recently-touched feature requests. Lets the SDK
// render upvote / follow counts immediately on tap, then reconcile against
// the server response. Spec §9 invariants enforced here, matching RN:
//   - Upvoting auto-creates a follow (followerCount += 1 only if the
//     user wasn't already following).
//   - Un-upvoting does NOT remove the follow.
//
// Each optimistic mutation captures the pre-mutation snapshot and returns
// a rollback closure. Concurrent taps each get their own captured snapshot,
// so rollback always restores the value seen at call time — never "the
// current value" at the moment of rollback.

import 'dart:math';

import '../../models/request.dart';

typedef RequestsCacheListener = void Function(String id, FeatureRequest req);
typedef Rollback = void Function();

class RequestsCache {
  final Map<String, FeatureRequest> _store = <String, FeatureRequest>{};
  final Map<int, RequestsCacheListener> _listeners =
      <int, RequestsCacheListener>{};
  int _listenerSeq = 0;

  void upsert(FeatureRequest req) {
    _store[req.id] = req;
    _emit(req.id, req);
  }

  void upsertList(List<FeatureRequest> list) {
    for (final r in list) {
      _store[r.id] = r;
    }
  }

  FeatureRequest? get(String id) => _store[id];

  /// Optimistically apply an upvote toggle. Returns a closure that restores
  /// the captured pre-call snapshot. No-op if [id] is unknown.
  Rollback applyOptimisticVote(String id, bool vote) {
    final before = _store[id];
    if (before == null) return () {};
    var upvoteDelta = 0;
    if (vote && !before.viewerHasUpvoted) {
      upvoteDelta = 1;
    } else if (!vote && before.viewerHasUpvoted) {
      upvoteDelta = -1;
    }
    // Auto-follow: upvoting bumps follower count if not already following.
    final followDelta = (vote && !before.viewerIsFollowing) ? 1 : 0;
    final next = before.copyWith(
      upvoteCount: max(0, before.upvoteCount + upvoteDelta),
      followerCount: max(0, before.followerCount + followDelta),
      viewerHasUpvoted: vote,
      viewerIsFollowing: vote ? true : before.viewerIsFollowing,
    );
    _store[id] = next;
    _emit(id, next);
    return () {
      _store[id] = before;
      _emit(id, before);
    };
  }

  /// Optimistically apply a follow toggle. Returns a closure that restores
  /// the captured pre-call snapshot. No-op if [id] is unknown.
  Rollback applyOptimisticFollow(String id, bool follow) {
    final before = _store[id];
    if (before == null) return () {};
    var delta = 0;
    if (follow && !before.viewerIsFollowing) {
      delta = 1;
    } else if (!follow && before.viewerIsFollowing) {
      delta = -1;
    }
    final next = before.copyWith(
      followerCount: max(0, before.followerCount + delta),
      viewerIsFollowing: follow,
    );
    _store[id] = next;
    _emit(id, next);
    return () {
      _store[id] = before;
      _emit(id, before);
    };
  }

  void commitVote(String id, RequestVote result) {
    final before = _store[id];
    if (before == null) return;
    final next = before.copyWith(
      upvoteCount: result.upvoteCount,
      followerCount: result.followerCount,
      viewerHasUpvoted: result.upvoted,
      viewerIsFollowing: result.followed,
    );
    _store[id] = next;
    _emit(id, next);
  }

  void commitFollow(String id, RequestFollow result) {
    final before = _store[id];
    if (before == null) return;
    final next = before.copyWith(
      followerCount: result.followerCount,
      viewerIsFollowing: result.following,
    );
    _store[id] = next;
    _emit(id, next);
  }

  /// Subscribe to mutations. Returns an unsubscribe closure.
  void Function() subscribe(RequestsCacheListener cb) {
    final token = ++_listenerSeq;
    _listeners[token] = cb;
    return () {
      _listeners.remove(token);
    };
  }

  void _emit(String id, FeatureRequest req) {
    // Snapshot listeners so a listener that unsubscribes during its own
    // callback does not mutate the iterator.
    final snapshot = _listeners.values.toList(growable: false);
    for (final cb in snapshot) {
      cb(id, req);
    }
  }
}

extension FeatureRequestCopy on FeatureRequest {
  /// Returns a copy of this request with the given fields overridden.
  /// Mirrors the `{ ...before, ... }` spread used in the RN reference.
  FeatureRequest copyWith({
    int? upvoteCount,
    int? followerCount,
    bool? viewerHasUpvoted,
    bool? viewerIsFollowing,
  }) {
    return FeatureRequest(
      id: id,
      appId: appId,
      title: title,
      description: description,
      status: status,
      devResponse: devResponse,
      upvoteCount: upvoteCount ?? this.upvoteCount,
      followerCount: followerCount ?? this.followerCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      statusChangedAt: statusChangedAt,
      lastRespondedAt: lastRespondedAt,
      viewerHasUpvoted: viewerHasUpvoted ?? this.viewerHasUpvoted,
      viewerIsFollowing: viewerIsFollowing ?? this.viewerIsFollowing,
      viewerIsSubmitter: viewerIsSubmitter,
    );
  }
}
