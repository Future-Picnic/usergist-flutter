# usergist_feedback

For account IDs, backend-verified guests, token expiry, property updates, and logout, see [the identity integration guide](https://usergist.com/docs/integrations/identity). The identity lifecycle APIs require SDK **0.1.4** and the coordinated backend update; verify the installed version before copying examples into an older app.


Flutter SDK for [userGist](https://usergist.com). It implements
the same authenticated protocol and durable-delivery guarantees as the native
and React Native SDKs.

## Install

```yaml
dependencies:
  usergist_feedback: ^0.1.4
```

Initialization finishes after local storage is hydrated. Session and mutation
warm-up continue in the background, so offline networking does not delay
`runApp`. Host rendering must not wait for consent/identity network confirmation.

## Startup presentation readiness

Initialize with `presentationPaused` enabled at app launch. Analytics, consent,
identity, and networking continue while campaign UI waits. After the existing
startup loading and navigation have finished and the loaded screen is visible,
call `resumePresentation()`. Mount any required UserGist UI provider before that
callback. Readiness must work for both anonymous and identified users.

Call `pausePresentation()` before another flow that must not be interrupted.
Pausing does not dismiss an already visible SDK surface. Queued feedback,
surveys, and in-app messages are discarded if their consent is withdrawn or
the user changes, even if consent is granted again before resuming. Repeated
initialization keeps the first readiness setting; repeated resume calls do not
show the same queued work twice. The option defaults to false for existing
integrations, so upgrading alone does not enable startup deferral.

Do not resume from a splash screen, an app-root mount that still shows loading,
a disappearing screen, or a fixed timer. Use the host's existing completion
callback; the SDK cannot infer when arbitrary startup navigation has finished.

```dart
// In the loaded screen’s existing startup/navigation completion callback:
UserGist.resumePresentation();
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:usergist_feedback/usergist_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserGist.init(writeKey: 'rk_live_xxx', presentationPaused: true);
  await UserGist.setConsent(
    const Consent(analytics: true, feedback: true, survey: true),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: UserGistProvider(
        child: const HomeScreen(),
      ),
    );
  }
}
```

If the provider must be installed through `MaterialApp.builder`, give
`MaterialApp` a `GlobalKey<NavigatorState>` and pass that same key to
`UserGistProvider.navigatorKey`. A builder context is above the app Navigator.

Identify only with a subject token minted by your authenticated backend:

```dart
await UserGist.identify(
  'user_42',
  properties: const <String, Object?>{'plan': 'pro'},
  subjectToken: subjectToken, // st_...; never embed an rtk_ token
);
UserGist.track(
  'checkout_completed',
  properties: const <String, Object?>{'amount_cents': 4999},
);
```

The SDK keeps anonymous and identified users distinct, persists identified
segment properties and bounded event history, and uses durable queues for
events, identify/feedback/survey mutations, and server instructions. Armed
prompt, survey, and in-app campaigns are evaluated locally only when the server
marks them client-side eligible. All SDK-owned routes share one modal FIFO.

## Public API

See `lib/src/usergist.dart`.

Push token lifecycle, silent acks, beacons, channel preferences, and host-
forwarded receive/open/action/dismiss callbacks are implemented. Flutter apps
must still own APNs/FCM permission and delivery plumbing (for example through
their existing messaging package); automatic enable/disable, badge, and initial-
notification helpers are not yet mirrored. The userGist APNs and FCM delivery
paths have passed end-to-end physical-device validation. Every integrating app
must still provide its own provider credentials and platform identifiers,
forward callbacks from its messaging package, and confirm a test notification
arrives in its running app.

## Verification

```sh
flutter test
flutter analyze --no-fatal-infos
dart doc
dart pub publish --dry-run
```

All analyzer errors and warnings are release-blocking. Documentation-only info
diagnostics remain visible, and the public Dart API must generate with zero
dartdoc warnings or errors.

## License

MIT © 2025-2026 userGist
