# usergist_feedback

Flutter SDK for [userGist](https://usergist.com). It implements
the same authenticated protocol and durable-delivery guarantees as the native
and React Native SDKs.

## Install

```yaml
dependencies:
  usergist_feedback: ^0.1.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:usergist_feedback/usergist_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserGist.init(writeKey: 'rk_live_xxx');
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
forward callbacks from its messaging package, and test its signed build on its
own physical devices.

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
