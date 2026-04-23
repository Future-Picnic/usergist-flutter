# ritmus_feedback

Flutter SDK for [Ritmus](https://ritmus.studio) — a mobile feedback tool.

Offline-first event ingest, GDPR consent gating, client-side trigger
evaluation, and native bottom-sheet prompt rendering with themeable UI.

## Install

```yaml
dependencies:
  ritmus_feedback: ^0.1.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:ritmus_feedback/ritmus_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Ritmus.init(writeKey: 'wk_xxx');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RitmusProvider(
      child: MaterialApp(
        home: const HomeScreen(),
      ),
    );
  }
}
```

Call `Ritmus.setConsent(Consent(feedback: true, analytics: true))`
before `identify` / `track` — the SDK is consent-gated by design.

## Public API

See `lib/src/ritmus.dart`.

## License

MIT
