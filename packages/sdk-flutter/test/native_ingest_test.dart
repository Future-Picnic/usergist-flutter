import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/transport/native_ingest.dart';
import 'package:usergist_feedback/src/models/context.dart';
import 'package:usergist_feedback/src/models/event.dart';

List<IngestEvent> events(int count) => List.generate(count, (i) => IngestEvent(
  eventId: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
  purpose: EventPurpose.analytics, name: 'qa.remote.$i',
  timestamp: '2026-11-11T00:00:00.000Z', anonymousId: 'installation',
  sdkVersion: '0.2.0', platform: 'android',
));
const context = IngestContext(anonymousId: 'installation', sdkVersion: '0.2.0', platform: 'android');

void main() {
  test('single-event retry authorizes the exact ingested event', () {
    final batch = events(1), payload = nativeIngestPayload(batch, context);
    expect((payload['delivery'] as Map?)?['eventIds'], batch.map((e) => e.eventId).toList());
  });
  test('twenty-event boundary retains every authorization', () {
    final batch = events(20), payload = nativeIngestPayload(batch, context);
    expect((payload['delivery'] as Map?)?['eventIds'], batch.map((e) => e.eventId).toList());
  });
  test('oversized and empty native delivery batches are rejected', () {
    expect(() => nativeIngestPayload(events(21), context), throwsArgumentError);
    expect(() => nativeIngestPayload(events(0), context), throwsArgumentError);
  });
}
