import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ritmus_feedback/src/internal/transport/api_client.dart';
import 'package:ritmus_feedback/src/internal/transport/retry_policy.dart';

void main() {
  test('postJson sends auth + payload and decodes a 200 response',
      () async {
    final seen = <http.BaseRequest>[];
    final mock = MockClient((req) async {
      seen.add(req);
      return http.Response(
        jsonEncode(<String, Object?>{'accepted': 3}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = ApiClient(
      baseUrl: 'https://api.test',
      writeKey: 'wk_abc',
      sdkVersion: '0.1.0',
      httpClient: mock,
    );
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
    expect(sent.headers['x-ritmus-sdk'], 'flutter/0.1.0');
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
      sdkVersion: '0.1.0',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        baseDelayMs: 1,
        maxDelayMs: 5,
        jitter: 0,
        random: Random(1),
      ),
    );
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
      sdkVersion: '0.1.0',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        maxAttempts: 3,
        baseDelayMs: 1,
        maxDelayMs: 2,
        jitter: 0,
        random: Random(1),
      ),
    );
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
      sdkVersion: '0.1.0',
      httpClient: mock,
      retryPolicy: RetryPolicy(
        maxAttempts: 5,
        baseDelayMs: 1,
        maxDelayMs: 1,
        jitter: 0,
      ),
    );
    final res = await client.postJson('/v1/sdk/ingest', <String, Object?>{});
    expect(res.success, isFalse);
    expect(res.status, 403);
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
      sdkVersion: '0.1.0',
      httpClient: mock,
    );
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
