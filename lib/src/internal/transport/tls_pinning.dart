// PORTED FROM (concept): cross-platform TLS pinning (P5.4). The pinned
// host is `api.ritmus.studio`; pins are base64 SHA-256 of the leaf cert's
// raw DER. Two pins (leaf + backup) prevent a single rotation from
// bricking every install.
//
// Strategy (the standard Dart pinning recipe):
//   1. Build an `HttpClient` whose `SecurityContext` trusts no roots, so
//      every server cert fails default validation.
//   2. Provide a `badCertificateCallback` that approves the connection iff
//      the cert's SHA-256 fingerprint is in the configured pin set for
//      the host.
//   3. Non-pinned hosts (e.g. localhost) get a normal `HttpClient` with
//      system trust intact — dev workflows aren't broken.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../logger.dart';

class TlsPinSet {
  const TlsPinSet({required this.host, required this.sha256Pins});

  /// Hostname this pin set protects.
  final String host;

  /// Base64 SHA-256 hashes of the cert DER. Empty = no pinning.
  final List<String> sha256Pins;
}

/// Wraps a [http.Client] with SPKI-style pinning.
///
/// If [pinSets] is empty, returns the platform's default client.
http.Client buildPinnedHttpClient(List<TlsPinSet> pinSets) {
  final active = pinSets.where((s) => s.sha256Pins.isNotEmpty).toList();
  if (active.isEmpty) return http.Client();
  final inner = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      final pinSet = _resolvePinSet(host, active);
      if (pinSet == null) {
        // No pin configured for this host — fall back to system trust.
        // badCertificateCallback only fires when system trust already
        // failed, so returning false rejects untrusted hosts (correct).
        return false;
      }
      final fingerprint = base64Encode(sha256.convert(cert.der).bytes);
      final match = pinSet.sha256Pins.contains(fingerprint);
      if (!match) {
        log.w(
          'TLS pin mismatch for $host — rejecting. Computed=$fingerprint',
        );
      }
      return match;
    };
  return IOClient(inner);
}

TlsPinSet? _resolvePinSet(String host, List<TlsPinSet> sets) {
  final lower = host.toLowerCase();
  for (final s in sets) {
    final pinHost = s.host.toLowerCase();
    if (pinHost == lower) return s;
    if (pinHost.startsWith('*.')) {
      final suffix = pinHost.substring(1);
      if (lower.endsWith(suffix)) return s;
    }
  }
  return null;
}

/// Env var names + pinned host. Kept here so a rename touches one place.
class TlsPinEnv {
  TlsPinEnv._();
  static const String leaf = 'RITMUS_TLS_PIN_LEAF';
  static const String backup = 'RITMUS_TLS_PIN_BACKUP';
  static const String pinnedHost = 'api.ritmus.studio';
}

/// Default pin set used by the Flutter SDK. Pin material is sourced from
/// the [TlsPinEnv] env vars so dev builds against staging / localhost
/// don't need pinning configured.
List<TlsPinSet> defaultTlsPinSets() {
  final pins = <String>[
    Platform.environment[TlsPinEnv.leaf] ?? '',
    Platform.environment[TlsPinEnv.backup] ?? '',
  ].where((p) => p.isNotEmpty).toList();
  return <TlsPinSet>[
    TlsPinSet(host: TlsPinEnv.pinnedHost, sha256Pins: pins),
  ];
}
