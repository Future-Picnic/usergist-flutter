import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:usergist_feedback/src/internal/transport/api_client.dart';
import 'package:usergist_feedback/src/internal/transport/retry_policy.dart';

void main() {
  test('postJson sends auth + payload and decodes a 200 response', () async {
    final seen = <http.BaseRequest>[];
    final mock = MockClient((req) async {
      seen.add(req);
      return http.Response(
        jsonEncode(<String, Object?>{
          'success': true,
          'data': <String, Object?>{'accepted': 3},
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
    );
    client.setSubjectToken('st_test');
    final res = await client.postJson('/v1/sdk/ingest', <String, Object?>{
      'events': <Object?>[],
      'context': <String, Object?>{'anonymousId': 'anon'},
    });
    expect(res.success, isTrue);
    expect(res.status, 200);
    expect(res.data, isNotNull);
    expect(res.data!['accepted'], 3);
    expect(seen, hasLength(1));
    final sent = seen.single;
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.test/v1/sdk/ingest');
    expect(sent.headers['authorization'], 'Bearer wk_abc');
    expect(sent.headers['x-usergist-sdk-version'], 'flutter/0.1.4');
    expect(sent.headers['x-usergist-platform'], 'flutter');
    expect(sent.headers['x-usergist-subject-token'], 'st_test');
  });

  test('request credential override does not replace the shared credential',
      () async {
    final seenTokens = <String?>[];
    final mock = MockClient((req) async {
      seenTokens.add(req.headers['x-usergist-subject-token']);
      return http.Response('{}', 200);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
    )..setSubjectToken('st_anonymous');

    await client.postJson(
      '/v1/sdk/identify',
      const <String, Object?>{},
      subjectTokenOverride: 'st_identified',
    );
    await client.postJson('/v1/sdk/consent', const <String, Object?>{});

    expect(seenTokens, <String?>['st_identified', 'st_anonymous']);
  });

  test('retries on 500 and eventually succeeds', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      if (calls < 3) return http.Response('server boom', 500);
      return http.Response('{}', 200);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        baseDelayMs: 1,
        maxDelayMs: 5,
        jitter: 0,
        random: Random(1),
      ),
    );
    client.setSubjectToken('st_test');
    final res = await client.postJson('/v1/sdk/ingest', <String, Object?>{});
    expect(res.success, isTrue);
    expect(calls, 3);
  });

  test('gives up after maxAttempts on persistent 500', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response('nope', 500);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        maxAttempts: 3,
        baseDelayMs: 1,
        maxDelayMs: 2,
        jitter: 0,
        random: Random(1),
      ),
    );
    client.setSubjectToken('st_test');
    final res = await client.postJson('/v1/sdk/ingest', <String, Object?>{});
    expect(res.success, isFalse);
    expect(res.status, 500);
    expect(calls, 3);
  });

  test('non-retryable status fails immediately', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response('forbidden', 403);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        baseDelayMs: 1,
        maxDelayMs: 1,
        jitter: 0,
      ),
    );
    client.setSubjectToken('st_test');
    final res = await client.postJson('/v1/sdk/ingest', <String, Object?>{});
    expect(res.success, isFalse);
    expect(res.status, 403);
    expect(calls, 1);
  });

  test('non-idempotent post does not retry a lost session response', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return http.Response('server unavailable', 503);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        baseDelayMs: 1,
        maxDelayMs: 1,
        jitter: 0,
      ),
    );

    final res = await client.postJson(
      '/v1/sdk/session',
      <String, Object?>{'anonymousId': 'anon-1'},
      requiresSubject: false,
      idempotent: false,
    );

    expect(res.success, isFalse);
    expect(calls, 1);
  });

  test('getJson propagates query params', () async {
    Uri? seenUri;
    final mock = MockClient((req) async {
      seenUri = req.url;
      return http.Response('{"triggers":[]}', 200);
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.4',
      httpClient: mock,
    );
    client.setSubjectToken('st_test');
    final res = await client.getJson(
      '/v1/sdk/armed-triggers',
      query: <String, String>{'anonymousId': 'anon-1', 'externalId': 'u-1'},
    );
    expect(res.success, isTrue);
    expect(seenUri, isNotNull);
    expect(seenUri!.queryParameters['anonymousId'], 'anon-1');
    expect(seenUri!.queryParameters['externalId'], 'u-1');
  });
}
