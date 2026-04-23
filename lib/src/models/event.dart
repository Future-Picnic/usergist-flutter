import 'any_value.dart';

/// A single tracked event, ready for persistence and ingest.
class IngestEvent {
  /// Creates an event.
  const IngestEvent({
    required this.name,
    required this.timestamp,
    required this.anonymousId,
    this.externalId,
    this.properties = const <String, Object?>{},
    this.sessionId,
    this.sdkVersion,
    this.appVersion,
    this.platform = 'flutter',
  });

  /// Event name.
  final String name;

  /// ISO-8601 timestamp (UTC).
  final String timestamp;

  /// Anonymous identifier.
  final String anonymousId;

  /// Optional external identifier.
  final String? externalId;

  /// Arbitrary property bag. Values are scalar (JSON-safe).
  final Map<String, Object?> properties;

  /// Optional session id.
  final String? sessionId;

  /// SDK version at track time.
  final String? sdkVersion;

  /// Host app version at track time.
  final String? appVersion;

  /// SDK platform identifier.
  final String platform;

  /// JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'timestamp': timestamp,
        'anonymousId': anonymousId,
        if (externalId != null) 'externalId': externalId,
        if (properties.isNotEmpty)
          'properties': sanitizeProperties(properties),
        if (sessionId != null) 'sessionId': sessionId,
        if (sdkVersion != null) 'sdkVersion': sdkVersion,
        if (appVersion != null) 'appVersion': appVersion,
        'platform': platform,
      };

  /// Parses from JSON.
  factory IngestEvent.fromJson(Map<String, Object?> json) => IngestEvent(
        name: json['name']! as String,
        timestamp: json['timestamp']! as String,
        anonymousId: json['anonymousId']! as String,
        externalId: json['externalId'] as String?,
        properties: (json['properties'] as Map<String, Object?>?) ??
            const <String, Object?>{},
        sessionId: json['sessionId'] as String?,
        sdkVersion: json['sdkVersion'] as String?,
        appVersion: json['appVersion'] as String?,
        platform: (json['platform'] as String?) ?? 'flutter',
      );
}
