/// Queued updates are durably stored; only synced updates are server-confirmed.
enum IdentifyResult { synced, queued, rejected }

class IdentityState {
  const IdentityState(
      {required this.status, required this.anonymousId, this.externalId});
  final String status;
  final String anonymousId;
  final String? externalId;
}

typedef SubjectTokenProvider = Future<String> Function(String externalId);

/// Control-plane registration and SDK consent, separate from OS permission.
class PushSubscriptionState {
  const PushSubscriptionState(
      {required this.tokenAvailable,
      required this.registered,
      required this.optedIn,
      required this.anonymousId,
      this.externalId});
  final bool tokenAvailable;
  final bool registered;
  final bool optedIn;
  final String anonymousId;
  final String? externalId;
}
