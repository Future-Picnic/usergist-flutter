// Mirrors the behaviour spec from
// packages/sdk-react-native/src/internal/requests.ts so Flutter / RN stay
// in lockstep: upvote auto-creates follow, un-upvote leaves follow alone,
// rollback restores the captured snapshot.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/requests/debounced_search.dart';
import 'package:usergist_feedback/src/internal/requests/requests_cache.dart';
import 'package:usergist_feedback/src/models/request.dart';

FeatureRequest mkRequest({
  String id = 'r1',
  int upvoteCount = 10,
  int followerCount = 4,
  bool viewerHasUpvoted = false,
  bool viewerIsFollowing = false,
}) {
  return FeatureRequest(
    id: id,
    appId: 'app',
    title: 'Title',
    description: 'Desc',
    status: RequestStatus.underReview,
    devResponse: null,
    upvoteCount: upvoteCount,
    followerCount: followerCount,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    statusChangedAt: '2026-01-01T00:00:00Z',
    lastRespondedAt: null,
    viewerHasUpvoted: viewerHasUpvoted,
    viewerIsFollowing: viewerIsFollowing,
    viewerIsSubmitter: false,
  );
}

void main() {
  group('RequestsCache', () {
    test('reset discards viewer state and late rollbacks', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest(viewerHasUpvoted: true, viewerIsFollowing: true));
      final voteRollback = cache.applyOptimisticVote('r1', false);
      final followRollback = cache.applyOptimisticFollow('r1', false);
      var oldListenerCalled = false;
      cache.subscribe((_, __) {
        oldListenerCalled = true;
      });
      cache.clear();
      expect(cache.get('r1'), isNull);
      cache.upsert(mkRequest(upvoteCount: 25));
      voteRollback();
      followRollback();
      expect(cache.get('r1')!.upvoteCount, 25);
      expect(cache.get('r1')!.viewerHasUpvoted, false);
      expect(cache.get('r1')!.viewerIsFollowing, false);
      expect(oldListenerCalled, false);
    });

    test('optimistic upvote bumps counts and auto-follows', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest());
      cache.applyOptimisticVote('r1', true);
      final after = cache.get('r1')!;
      expect(after.upvoteCount, 11);
      expect(after.followerCount, 5);
      expect(after.viewerHasUpvoted, true);
      expect(after.viewerIsFollowing, true);
    });

    test('un-upvote does not remove the follow', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest(viewerHasUpvoted: true, viewerIsFollowing: true));
      cache.applyOptimisticVote('r1', false);
      final after = cache.get('r1')!;
      expect(after.upvoteCount, 9);
      expect(after.followerCount, 4, reason: 'follower count must stay put');
      expect(after.viewerHasUpvoted, false);
      expect(
        after.viewerIsFollowing,
        true,
        reason: 'follow must NOT be removed by un-upvote',
      );
    });

    test('rollback restores the captured snapshot', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest());
      final rollback = cache.applyOptimisticVote('r1', true);
      rollback();
      final after = cache.get('r1')!;
      expect(after.upvoteCount, 10);
      expect(after.followerCount, 4);
      expect(after.viewerHasUpvoted, false);
      expect(after.viewerIsFollowing, false);
    });

    test('concurrent taps each rollback to their own snapshot', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest());
      final rb1 = cache.applyOptimisticVote('r1', true);
      // Now: 11/5, hasUpvoted=true, isFollowing=true.
      final rb2 = cache.applyOptimisticFollow('r1', false);
      // Now: 11/4, hasUpvoted=true, isFollowing=false.

      rb2();
      expect(cache.get('r1')!.viewerIsFollowing, true);
      expect(cache.get('r1')!.followerCount, 5);

      rb1();
      final finalState = cache.get('r1')!;
      expect(finalState.upvoteCount, 10);
      expect(finalState.followerCount, 4);
      expect(finalState.viewerHasUpvoted, false);
      expect(finalState.viewerIsFollowing, false);
    });

    test('commitVote overwrites with server truth', () {
      final cache = RequestsCache();
      cache.upsert(mkRequest());
      cache.applyOptimisticVote('r1', true);
      cache.commitVote(
        'r1',
        const RequestVote(
          requestId: 'r1',
          upvoted: true,
          followed: true,
          upvoteCount: 42,
          followerCount: 17,
        ),
      );
      final after = cache.get('r1')!;
      expect(after.upvoteCount, 42);
      expect(after.followerCount, 17);
    });
  });

  group('DebouncedSearch', () {
    test('only the final query in a burst reaches subscribers', () async {
      final calls = <String>[];
      final search = DebouncedSearch<List<String>>(
        delay: const Duration(milliseconds: 50),
        fn: (q) async {
          calls.add(q);
          return <String>['hit-for-$q'];
        },
      );
      final received = <String>[];
      search.subscribe((q, r) => received.add(q));

      search.query('a');
      search.query('ab');
      search.query('abc');
      // Wait past the debounce window.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(calls, ['abc'], reason: 'only the last query should fire');
      expect(received, ['abc']);
    });

    test('stale in-flight results are dropped', () async {
      final completers = <String, Completer<List<String>>>{};
      final search = DebouncedSearch<List<String>>(
        delay: const Duration(milliseconds: 10),
        fn: (q) {
          final c = Completer<List<String>>();
          completers[q] = c;
          return c.future;
        },
      );
      final received = <String>[];
      search.subscribe((q, r) => received.add(q));

      search.query('a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // 'a' is now in-flight. Issue another query; the earlier seq is stale.
      search.query('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      completers['a']?.complete(<String>['hit-a']);
      completers['b']?.complete(<String>['hit-b']);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, ['b'], reason: '"a" was stale by the time it returned');
    });
  });
}
