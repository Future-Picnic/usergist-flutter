import 'dart:math';

/// Retry-policy helper: exponential backoff with jitter, capped at a
/// maximum, plus explicit `Retry-After` support for 429/503.
class RetryPolicy {
  /// Creates a policy.
  RetryPolicy({
    this.maxAttempts = 5,
    this.baseDelayMs = 500,
    this.maxDelayMs = 30000,
    this.jitter = 0.25,
    Random? random,
  }) : _rng = random ?? Random();

  /// Maximum attempts (including the first try).
  final int maxAttempts;

  /// Base delay for attempt 1 — doubles each attempt.
  final int baseDelayMs;

  /// Upper bound on any single delay.
  final int maxDelayMs;

  /// Jitter factor in `[0, 1]`.
  final double jitter;

  final Random _rng;

  /// Returns the delay to wait before [attempt] (1-indexed), honoring
  /// an optional server-provided [retryAfterSeconds] hint.
  Duration delayFor(int attempt, {int? retryAfterSeconds}) {
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      final ms = (retryAfterSeconds * 1000).clamp(0, maxDelayMs);
      return Duration(milliseconds: ms);
    }
    final exp = baseDelayMs * pow(2, attempt - 1);
    final capped = exp.clamp(0, maxDelayMs).toDouble();
    final jitterMs = capped * jitter;
    final low = capped - jitterMs;
    final high = capped + jitterMs;
    final chosen = low + _rng.nextDouble() * (high - low);
    final clamped = chosen.clamp(0, maxDelayMs.toDouble());
    return Duration(milliseconds: clamped.round());
  }

  /// Returns whether [statusCode] is retryable.
  bool isRetryable(int statusCode) {
    if (statusCode == 408 || statusCode == 429) return true;
    if (statusCode >= 500 && statusCode <= 599) return true;
    return false;
  }
}
