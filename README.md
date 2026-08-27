# usergist_feedback

Experimental Flutter SDK for [userGist](https://usergist.studio). It implements
the React Native reference protocol, but is not launch-supported until package
release validation and physical-device push testing are complete. Consult
`packages/PARITY.md` before production integration.

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
notification helpers are not yet mirrored. Real credentials and a physical
device are required for end-to-end validation.

## Verification

```sh
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
```

The analyzer currently reports the package's existing lint backlog; compilation
errors are treated as failures.

## License

MIT
