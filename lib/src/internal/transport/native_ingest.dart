import '../../models/context.dart';
import '../../models/event.dart';

/// Shared batch/single-retry wire construction for the native SDK.
Map<String, Object?> nativeIngestPayload(
  List<IngestEvent> events,
  IngestContext context,
) {
  if (events.isEmpty || events.length > 20) {
    throw ArgumentError('Native delivery requires between 1 and 20 events');
  }
  return <String, Object?>{
    'events': events.map((e) => e.toWireJson()).toList(growable: false),
    'context': context.toJson(),
    'delivery': <String, Object?>{
      'eventIds': events.map((e) => e.eventId).toList(growable: false),
    },
  };
}
