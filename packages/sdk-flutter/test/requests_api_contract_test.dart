import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:usergist_feedback/src/internal/requests/requests_api.dart';
import 'package:usergist_feedback/src/internal/transport/api_client.dart';

void main() {
  test('submit and comment include required idempotency keys', () async {
    final bodies = <Map<String, Object?>>[];
    final mock = MockClient((request) async {
      bodies.add(
        jsonDecode(request.body) as Map<String, Object?>,
      );
      final isComment = request.url.path.endsWith('/comments');
      return http.Response(
        jsonEncode(<String, Object?>{
          'success': true,
          'data': isComment ? commentJson : requestJson,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_test',
      sdkVersion: '0.1.4',
      httpClient: mock,
    )..setSubjectToken('st_test');
    final api = RequestsApi(client);

    expect(
      await api.submit(
        anonymousId: 'anon-1',
        title: 'Title',
        description: 'Description',
      ),
      isNotNull,
    );
    expect(
      await api.postComment(
        requestId: 'request-1',
        anonymousId: 'anon-1',
        body: 'Comment',
      ),
      isNotNull,
    );

    expect(bodies, hasLength(2));
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (final body in bodies) {
      expect(body['idempotencyKey'], matches(uuidV4));
    }
  });
}

const requestJson = <String, Object?>{
  'id': 'request-1',
  'appId': 'app-1',
  'title': 'Title',
  'description': 'Description',
  'status': 'under_review',
  'devResponse': null,
  'upvoteCount': 0,
  'followerCount': 0,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
  'statusChangedAt': '2026-01-01T00:00:00Z',
  'lastRespondedAt': null,
  'viewerHasUpvoted': false,
  'viewerIsFollowing': false,
  'viewerIsSubmitter': true,
};

const commentJson = <String, Object?>{
  'id': 'comment-1',
  'requestId': 'request-1',
  'body': 'Comment',
  'authorAnonymousId': 'anon-1',
  'authorExternalId': null,
  'viewerIsAuthor': true,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};
