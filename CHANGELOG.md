# Changelog

## 0.1.6

- Include the partial-answer fix below and exclude release metadata from the pub.dev archive.

## 0.1.5 (source tag only; pub.dev publication blocked)

- Preserve partial feedback answers when the sheet is dismissed by tapping the backdrop or pressing system Back. Account reset continues to close the sheet without submitting a user response.

## 0.1.4 — identity lifecycle

- Coordinate logout with startup before starting network delivery, confirm restored identity only after session validation, and keep explicit push invalidation effective across retries and restart.
- Confirmed identity state and asynchronous completion, with backend token renewal and retained account identity after expiration.
- Property set/unset using the active session; profile PII follows the app's server allowlist, while event filtering remains in place.
- Installation-bound credentials, anonymous ownership proof, and canonical profile adoption on identify.
- Local account reset with cancellation and independent durable logout cleanup; stale responses cannot restore the old account.
- Clear request-board viewer state on reset and discard delayed vote/follow rollbacks from the previous account.
- Push subscription state reflects server acknowledgement; OS tokens survive restart and retry after consent, connectivity, or identity changes.

Requires the coordinated backend lifecycle deployment. See the [identity integration guide](https://usergist.com/docs/integrations/identity) for backend requirements and account-switching guidance.


## 0.1.3

- Complete initialization after local hydration, with session/mutation warm-up in the background, so slow or offline networking does not hold the app's first frame.
- Preserve queued startup delivery and avoid starting more work after disposal.

# Changelog

## 0.1.2

- Add startup presentation readiness: initialize with `presentationPaused`, then call `resumePresentation()` after the loaded screen is ready.
- Keep analytics and networking running while campaign UI is paused; `pausePresentation()` can protect later host flows without dismissing active UI.
- Invalidate queued presentation work after consent revocation, reset, or identity changes, including requests prepared asynchronously.

## 0.1.0

- Initial release of the Flutter SDK.
- Anonymous and identified-user sessions with backend-minted subject tokens.
- Consent-aware, persistent event and mutation queues with bounded retries.
- `UserGistProvider` widget for mounting the prompt presenter.
- Feedback prompts, multi-step surveys, in-app messages, feature requests,
  local targeting/frequency caps, theme overrides, and lifecycle handlers.
- Host-compatible APNs/FCM token lifecycle, channels, and delivery beacons.
