import 'any_value.dart';
import '../internal/uid.dart';

/// Local consent purpose used to decide whether a queued event may leave
/// the device. This field is persisted but intentionally omitted on the wire.
enum EventPurpose { analytics, feedback }

/// A single tracked event, ready for persistence and ingest.
class IngestEvent {
  /// Creates an event.
  IngestEvent({
    String? eventId,
    this.purpose = EventPurpose.analytics,
    required this.name,
    required this.timestamp,
    required this.anonymousId,
    this.externalId,
    this.properties = const <String, Object?>{},
    this.sessionId,
    this.sdkVersion,
    this.appVersion,
    this.platform = 'flutter',
  }) : eventId = eventId ?? newUuid();

  /// Stable idempotency/correlation identifier for this event.
  final String eventId;

  /// Consent purpose governing transmission of this event.
  final EventPurpose purpose;

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
        'eventId': eventId,
        'purpose': purpose.name,
        'name': name,
        'timestamp': timestamp,
        'anonymousId': anonymousId,
        if (externalId != null) 'externalId': externalId,
        if (properties.isNotEmpty) 'properties': sanitizeProperties(properties),
        if (sessionId != null) 'sessionId': sessionId,
        if (sdkVersion != null) 'sdkVersion': sdkVersion,
        if (appVersion != null) 'appVersion': appVersion,
        'platform': platform,
      };

  /// API representation. Local-only [purpose] is deliberately excluded.
  Map<String, Object?> toWireJson() => <String, Object?>{
        'eventId': eventId,
        'name': name,
        'timestamp': timestamp,
        'anonymousId': anonymousId,
        if (externalId != null) 'externalId': externalId,
        if (properties.isNotEmpty) 'properties': sanitizeProperties(properties),
        if (sessionId != null) 'sessionId': sessionId,
        if (sdkVersion != null) 'sdkVersion': sdkVersion,
        if (appVersion != null) 'appVersion': appVersion,
        'platform': platform,
      };

  /// Parses from JSON.
  factory IngestEvent.fromJson(Map<String, Object?> json) => IngestEvent(
        eventId: json['eventId'] as String? ?? newUuid(),
        purpose: EventPurpose.values.firstWhere(
          (value) => value.name == json['purpose'],
          orElse: () => EventPurpose.analytics,
        ),
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
