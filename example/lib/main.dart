import 'package:flutter/material.dart';
import 'package:ritmus_feedback/ritmus_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Ritmus.init(
    writeKey: 'wk_example_replace_me',
    environment: RitmusEnvironment.development,
    debug: true,
  );
  runApp(const ExampleApp());
}

/// Root widget for the example app.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ritmus SDK Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      builder: (ctx, child) => RitmusProvider(child: child!),
      home: const _HomeScreen(),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  String _status = 'consent not granted';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ritmus example')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _grantConsent,
              child: const Text('Grant consent'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _identify,
              child: const Text('Identify user'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _track,
              child: const Text(r'Track "checkout_completed"'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: Ritmus.flush,
              child: const Text('Flush now'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: Ritmus.reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _grantConsent() async {
    await Ritmus.setConsent(const Consent(analytics: true, feedback: true));
    setState(() => _status = 'consent granted');
  }

  Future<void> _identify() async {
    await Ritmus.identify(
      'user_123',
      properties: <String, Object?>{'plan': 'pro'},
    );
    setState(() => _status = 'identified as user_123');
  }

  void _track() {
    Ritmus.track(
      'checkout_completed',
      properties: <String, Object?>{'amount': 99.0, 'currency': 'USD'},
    );
    setState(() => _status = 'event tracked');
  }
}
