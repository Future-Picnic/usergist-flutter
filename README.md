# usergist_feedback

Experimental Flutter SDK for [userGist](https://usergist.studio). This package
is not launch-supported until authenticated subject sessions, durable server
instructions, and release-build verification are complete.

The current package contains offline event ingest, consent gating, local rule
evaluation, and a themeable prompt renderer. Do not assume React Native API or
security parity; consult `packages/PARITY.md` before integration.

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
  await UserGist.init(writeKey: 'wk_xxx');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return UserGistProvider(
      child: MaterialApp(
        home: const HomeScreen(),
      ),
    );
  }
}
```

Call `UserGist.setConsent(Consent(feedback: true, analytics: true))`
before `identify` / `track` — the SDK is consent-gated by design.

## Public API

See `lib/src/usergist.dart`.

## License

MIT
