import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usergist_feedback/src/internal/core.dart';
import 'package:usergist_feedback/src/internal/transport/api_client.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local startup completes while the session request is still waiting',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final previousPaths = PathProviderPlatform.instance;
    final directory =
        await Directory.systemTemp.createTemp('usergist-startup-');
    PathProviderPlatform.instance = _Paths(directory.path);
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    var networkCalls = 0;
    final client = MockClient((request) async {
      networkCalls++;
      if (request.url.path.endsWith('/session')) {
        if (!requested.isCompleted) requested.complete();
        return response.future;
      }
      return http.Response('{"success":true,"data":{}}', 200);
    });
    final core = UserGistCore(
      writeKey: 'startup-test',
      baseUrl: 'https://example.test',
      sdkVersion: '0.1.3',
      flushInterval: const Duration(hours: 1),
      flushBatchSize: 10,
      maxQueueSize: 100,
      triggerSyncInterval: const Duration(hours: 1),
      apiClient: ApiClient(
          baseUrl: 'https://example.test',
          writeKey: 'startup-test',
          sdkVersion: '0.1.3',
          httpClient: client),
    );
    try {
      await core.start().timeout(const Duration(seconds: 2));
      await requested.future.timeout(const Duration(seconds: 2));
      expect(response.isCompleted, isFalse);
      expect(core.identity.anonymousId, isNotEmpty);
    } finally {
      await core.dispose();
      response.complete(http.Response(
          '{"success":true,"data":{"subjectToken":"st_test"}}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      PathProviderPlatform.instance = previousPaths;
    }
    expect(networkCalls, 1,
        reason: 'Disposal must not restart background delivery');
  });
}
