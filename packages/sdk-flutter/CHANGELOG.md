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
