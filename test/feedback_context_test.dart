import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usergist_feedback/src/internal/core.dart';
import 'package:usergist_feedback/src/internal/device_context.dart';
import 'package:usergist_feedback/src/internal/transport/api_client.dart';
import 'package:usergist_feedback/src/models/consent.dart';
import 'package:usergist_feedback/src/models/response_info.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final nativeOs in <String?>[null, 'android', 'ios']) {
  test('actual requests carry ${nativeOs ?? 'fallback'} platform and SDK version', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(
      (await Directory.systemTemp.createTemp('usergist-feedback-context-')).path,
    );
    final responseRequest = Completer<http.Request>();
    final eventRequest = Completer<http.Request>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/responses')) {
        if (!responseRequest.isCompleted) responseRequest.complete(request);
      }
      if (request.url.path.endsWith('/ingest')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['events'] as List).any((e) => e['name'] == 'qa.native-platform') &&
            !eventRequest.isCompleted) eventRequest.complete(request);
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': request.url.path.endsWith('/session')
              ? {'subjectToken': 'st_anonymous'}
              : {
                  'triggers': <Object?>[], 'instructions': <Object?>[],
                  'surveys': <Object?>[], 'messages': <Object?>[],
                },
        }),
        200,
      );
    });
    final core = UserGistCore(
      writeKey: 'feedback-test', baseUrl: 'https://feedback.test',
      sdkVersion: 'qa-context-version', flushInterval: const Duration(hours: 1),
      flushBatchSize: 10, maxQueueSize: 100,
      triggerSyncInterval: const Duration(hours: 1),
      deviceContextCollector: nativeOs == null ? null : () async => DeviceContextSnapshot(
        osName: nativeOs, appVersion: '4.3.2+7',
      ),
      apiClient: ApiClient(
        baseUrl: 'https://feedback.test', writeKey: 'feedback-test',
        sdkVersion: 'qa-context-version', httpClient: client,
      ),
    );
    try {
      await core.start();
      await core.setConsent(const Consent(analytics: true, feedback: true));
      core.track('qa.native-platform', <String, Object?>{'typed': true});
      final saved = Completer<void>();
      core.reportResponse(
        const PromptResponseInfo(
          promptId: 'rating-prompt', dismissed: false, latencyMs: 123,
          answers: [ResponseAnswer(questionId: 'rating', value: 5)],
        ),
        onSaved: () => saved.complete(),
      );
      await saved.future.timeout(const Duration(seconds: 5));
      final request = await responseRequest.future.timeout(const Duration(seconds: 5));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['platform'], nativeOs ?? 'flutter');
      expect(body['sdkVersion'], 'qa-context-version');
      expect(body['anonymousId'], core.identity.anonymousId);
      expect(body['answers'], [{'questionId': 'rating', 'value': 5}]);
      final event = await eventRequest.future.timeout(const Duration(seconds: 5));
      final ingest = jsonDecode(event.body) as Map<String, dynamic>;
      final tracked = (ingest['events'] as List).singleWhere((e) => e['name'] == 'qa.native-platform');
      expect((ingest['delivery'] as Map?)?['eventIds'],
        (ingest['events'] as List).map((e) => e['eventId']).toList());
      expect(tracked['platform'], nativeOs ?? 'flutter');
      expect((ingest['context'] as Map)['platform'], nativeOs ?? 'flutter');
      if (nativeOs != null) {
        expect(body['appVersion'], '4.3.2+7');
        expect(tracked['appVersion'], '4.3.2+7');
      }
    } finally {
      await core.dispose();
      PathProviderPlatform.instance = previousPaths;
    }
  });
  }
}
