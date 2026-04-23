# Changelog

## 0.1.0

- Initial release of the Flutter SDK.
- Public API: `Ritmus.init`, `identify`, `track`, `setConsent`, `reset`,
  `setThemeOverrides`, `flush`, `setDebug`, `anonymousId`, `onPromptShown`,
  `onResponse`.
- `RitmusProvider` widget for mounting the prompt presenter.
- Persistent event queue, batched HTTPS transport with exponential backoff.
- Armed-triggers cache with client-side segment evaluation.
- Frequency caps with sliding windows.
- Four question types: rating, NPS, multiple-choice, short-text.
