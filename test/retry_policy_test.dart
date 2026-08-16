import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/transport/retry_policy.dart';

void main() {
  test('isRetryable flags 5xx / 429 / 408', () {
    final rp = RetryPolicy();
    expect(rp.isRetryable(500), isTrue);
    expect(rp.isRetryable(503), isTrue);
    expect(rp.isRetryable(429), isTrue);
    expect(rp.isRetryable(408), isTrue);
    expect(rp.isRetryable(400), isFalse);
    expect(rp.isRetryable(404), isFalse);
    expect(rp.isRetryable(200), isFalse);
  });

  test('delay grows exponentially with jitter', () {
    // Deterministic rng for reproducibility.
    final rp = RetryPolicy(
      baseDelayMs: 100,
      maxDelayMs: 10000,
      jitter: 0.0,
      random: Random(42),
    );
    final d1 = rp.delayFor(1).inMilliseconds;
    final d2 = rp.delayFor(2).inMilliseconds;
    final d3 = rp.delayFor(3).inMilliseconds;
    expect(d1, 100);
    expect(d2, 200);
    expect(d3, 400);
  });

  test('delay is capped at maxDelayMs', () {
    final rp = RetryPolicy(
      baseDelayMs: 100,
      maxDelayMs: 500,
      jitter: 0.0,
      random: Random(1),
    );
    final d = rp.delayFor(10);
    expect(d.inMilliseconds, 500);
  });

  test('jitter keeps delays within +/- jitter fraction', () {
    final rp = RetryPolicy(
      baseDelayMs: 1000,
      maxDelayMs: 10000,
      jitter: 0.25,
      random: Random(7),
    );
    for (var i = 0; i < 20; i++) {
      final d = rp.delayFor(1).inMilliseconds;
      expect(d, greaterThanOrEqualTo(750));
      expect(d, lessThanOrEqualTo(1250));
    }
  });

  test('Retry-After header overrides the backoff', () {
    final rp = RetryPolicy(baseDelayMs: 100, maxDelayMs: 60000);
    final d = rp.delayFor(1, retryAfterSeconds: 5);
    expect(d.inMilliseconds, 5000);
  });

  test('Retry-After is capped at maxDelayMs', () {
    final rp = RetryPolicy(baseDelayMs: 100, maxDelayMs: 2000);
    final d = rp.delayFor(1, retryAfterSeconds: 30);
    expect(d.inMilliseconds, 2000);
  });
}
