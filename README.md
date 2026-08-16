# usergist_feedback

Flutter SDK for [userGist](https://usergist.studio) — a mobile feedback tool.

Offline-first event ingest, GDPR consent gating, client-side trigger
evaluation, and native bottom-sheet prompt rendering with themeable UI.

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
