import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../json.dart';
import '../logger.dart';
import 'retry_policy.dart';
import 'tls_pinning.dart';

/// A single HTTP call's outcome.
class ApiResult<T> {
  /// Creates a result.
  const ApiResult({required this.success, this.data, this.error, this.status});

  /// `true` if the request succeeded (2xx) and decoding worked.
  final bool success;

  /// Decoded response payload.
  final T? data;

  /// Human-readable error message when [success] is `false`.
  final String? error;

  /// HTTP status of the final attempt, if one was made.
  final int? status;
}

/// Minimal API client used by the SDK. Batches-of-events go here, plus
/// identify / consent / responses / armed-triggers calls.
class ApiClient {
  /// Creates an API client.
  ApiClient({
    required this.baseUrl,
    required this.writeKey,
    required this.sdkVersion,
    http.Client? httpClient,
    RetryPolicy? retryPolicy,
    List<TlsPinSet>? pinSets,
  })  : _http =
            httpClient ?? buildPinnedHttpClient(pinSets ?? defaultTlsPinSets()),
        _retry = retryPolicy ?? RetryPolicy();

  /// Base URL (no trailing slash).
  final String baseUrl;

  /// Per-app write key, sent as the bearer token.
  final String writeKey;

  /// SDK version (used for telemetry headers).
  final String sdkVersion;

  final http.Client _http;
  final RetryPolicy _retry;
  String? _subjectToken;

  /// Installs the server-minted subject credential used by every SDK route
  /// except `/v1/sdk/session`.
  void setSubjectToken(String? token) {
    _subjectToken = token != null && token.startsWith('st_') ? token : null;
  }

  /// Closes underlying resources.
  void dispose() {
    _http.close();
  }

  Map<String, String> _headers([String? subjectTokenOverride]) =>
      <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        'authorization': 'Bearer $writeKey',
        'x-usergist-sdk-version': 'flutter/$sdkVersion',
        'x-usergist-platform': 'flutter',
        if (subjectTokenOverride ?? _subjectToken case final token?)
          'x-usergist-subject-token': token,
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse('$base$path');
    if (query == null || query.isEmpty) return url;
    return url.replace(
      queryParameters: <String, String>{
        ...url.queryParameters,
        ...query,
      },
    );
  }

  /// Performs a POST with a JSON body and retries on retryable failures.
  Future<ApiResult<Map<String, Object?>>> postJson(
    String path,
    Object body, {
    bool requiresSubject = true,
    bool idempotent = true,
    String? subjectTokenOverride,
  }) =>
      _sendWithRetry(
        method: 'POST',
        path: path,
        body: body,
        requiresSubject: requiresSubject,
        idempotent: idempotent,
        subjectTokenOverride: subjectTokenOverride,
      );

  /// Performs a GET with query parameters and retries on retryable failures.
  Future<ApiResult<Map<String, Object?>>> getJson(
    String path, {
    Map<String, String>? query,
    bool requiresSubject = true,
  }) =>
      _sendWithRetry(
        method: 'GET',
        path: path,
        query: query,
        requiresSubject: requiresSubject,
      );

  /// Performs a PATCH with a JSON body and retries on retryable failures.
  Future<ApiResult<Map<String, Object?>>> patchJson(
    String path,
    Object body, {
    bool requiresSubject = true,
  }) =>
      _sendWithRetry(
        method: 'PATCH',
        path: path,
        body: body,
        requiresSubject: requiresSubject,
      );

  /// Performs a DELETE with optional query params and retries on retryable
  /// failures. Body is intentionally not supported — the SDK uses query
  /// strings to carry author identity on author-checked deletes.
  Future<ApiResult<Map<String, Object?>>> deleteJson(
    String path, {
    Map<String, String>? query,
    bool requiresSubject = true,
  }) =>
      _sendWithRetry(
        method: 'DELETE',
        path: path,
        query: query,
        requiresSubject: requiresSubject,
      );

  Future<ApiResult<Map<String, Object?>>> _sendWithRetry({
    required String method,
    required String path,
    Object? body,
    Map<String, String>? query,
    bool requiresSubject = true,
    bool idempotent = true,
    String? subjectTokenOverride,
  }) async {
    final requestSubjectToken = subjectTokenOverride ?? _subjectToken;
    if (requiresSubject && requestSubjectToken == null) {
      return const ApiResult<Map<String, Object?>>(
        success: false,
        error: 'subject-session-unavailable',
      );
    }
    Object? lastError;
    int? lastStatus;
    for (var attempt = 1; attempt <= _retry.maxAttempts; attempt++) {
      try {
        final uri = _uri(path, query);
        final req = http.Request(method, uri);
        req.headers.addAll(_headers(subjectTokenOverride));
        if (body != null) {
          req.body = safeEncode(body);
        }
        final streamed = await _http.send(req).timeout(
              const Duration(seconds: 15),
            );
        final res = await http.Response.fromStream(streamed);
        lastStatus = res.statusCode;
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (res.bodyBytes.isEmpty) {
            return ApiResult<Map<String, Object?>>(
              success: true,
              data: const <String, Object?>{},
              status: res.statusCode,
            );
          }
          final decoded = safeDecode(utf8.decode(res.bodyBytes));
          if (decoded is Map<String, Object?>) {
            final payload =
                decoded['success'] == true && decoded.containsKey('data')
                    ? decoded['data']
                    : decoded;
            if (payload is Map<String, Object?>) {
              return ApiResult<Map<String, Object?>>(
                success: true,
                data: payload,
                status: res.statusCode,
              );
            }
            if (payload is Map<Object?, Object?>) {
              return ApiResult<Map<String, Object?>>(
                success: true,
                data: payload.map((k, v) => MapEntry(k.toString(), v)),
                status: res.statusCode,
              );
            }
            return ApiResult<Map<String, Object?>>(
              success: true,
              data: const <String, Object?>{},
              status: res.statusCode,
            );
          }
          if (decoded is Map<Object?, Object?>) {
            return ApiResult<Map<String, Object?>>(
              success: true,
              data: decoded.map(
                (k, v) => MapEntry(k.toString(), v),
              ),
              status: res.statusCode,
            );
          }
          return ApiResult<Map<String, Object?>>(
            success: true,
            data: const <String, Object?>{},
            status: res.statusCode,
          );
        }
        if (!_retry.isRetryable(res.statusCode) ||
            !idempotent ||
            attempt == _retry.maxAttempts) {
          return ApiResult<Map<String, Object?>>(
            success: false,
            error: 'HTTP ${res.statusCode}',
            status: res.statusCode,
          );
        }
        final retryAfter = _parseRetryAfter(res.headers['retry-after']);
        final delay = _retry.delayFor(attempt, retryAfterSeconds: retryAfter);
        log.d('retrying $method $path in ${delay.inMilliseconds}ms '
            '(status ${res.statusCode}, attempt $attempt)');
        await Future<void>.delayed(delay);
      } on Object catch (err, st) {
        lastError = err;
        log.e('network attempt $attempt failed', err, st);
        if (!idempotent || attempt == _retry.maxAttempts) break;
        final delay = _retry.delayFor(attempt);
        await Future<void>.delayed(delay);
      }
    }
    return ApiResult<Map<String, Object?>>(
      success: false,
      error: lastError?.toString() ?? 'network failure',
      status: lastStatus,
    );
  }

  int? _parseRetryAfter(String? header) {
    if (header == null || header.isEmpty) return null;
    final v = int.tryParse(header.trim());
    if (v != null) return v;
    return null;
  }
}
