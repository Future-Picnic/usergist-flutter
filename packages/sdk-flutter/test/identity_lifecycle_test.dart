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
import 'package:usergist_feedback/src/internal/transport/api_client.dart';
import 'package:usergist_feedback/src/models/consent.dart';
import 'package:usergist_feedback/src/models/identity_state.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UserGistCore core;
  late PathProviderPlatform previousPaths;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) reply;
  http.Response success(Map<String, Object?> data, [int status = 200]) =>
      http.Response(jsonEncode({'success': true, 'data': data}), status);

  UserGistCore makeCore() {
    final client = MockClient((request) async {
      requests.add(request);
      return reply(request);
    });
    return UserGistCore(
        writeKey: 'identity-test',
        baseUrl: 'https://identity.test',
        sdkVersion: 'unreleased',
        flushInterval: const Duration(hours: 1),
        flushBatchSize: 10,
        maxQueueSize: 100,
        triggerSyncInterval: const Duration(hours: 1),
        apiClient: ApiClient(
            baseUrl: 'https://identity.test',
            writeKey: 'identity-test',
            sdkVersion: 'unreleased',
            httpClient: client));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(
        (await Directory.systemTemp.createTemp('usergist-identity-')).path);
    requests = [];
    reply = (request) async {
      if (request.url.path.endsWith('/session'))
        return success({'subjectToken': 'st_anonymous'});
      if (request.url.path.endsWith('/identify'))
        return success(
            {'subjectToken': 'st_bound', 'filteredKeys': <String>[]});
      if (request.url.path.endsWith('/user-properties'))
        return success({'applied': true, 'filteredKeys': <String>[]});
      return success(
          {'triggers': [], 'instructions': [], 'surveys': [], 'messages': []});
    };
    core = makeCore();
    await core.start();
    await core.flush();
  });
  tearDown(() async {
    await core.dispose();
    PathProviderPlatform.instance = previousPaths;
  });

  test(
      'guest upgrade preserves identity; profile email and deletion use confirmed token',
      () async {
    await core.setConsent(const Consent(analytics: true));
    final alias = core.identity.anonymousId;
    expect(
        await core.identify('123',
            {'isAnonymous': true, 'email': 'guest@example.test'}, 'st_backend'),
        IdentifyResult.synced);
    final identify =
        requests.firstWhere((r) => r.url.path.endsWith('/identify'));
    expect(jsonDecode(identify.body)['previousSubjectToken'], 'st_anonymous');
    expect(
        jsonDecode(identify.body)['properties']['email'], 'guest@example.test');
    expect(await core.setUserProperties({'isAnonymous': false}, ['email']),
        IdentifyResult.synced);
    final update =
        requests.firstWhere((r) => r.url.path.endsWith('/user-properties'));
    expect(update.headers['x-usergist-subject-token'], 'st_bound');
    expect(jsonDecode(update.body)['unset'], ['email']);
    expect(core.identity.externalId, '123');
    expect(core.identity.anonymousId, alias);
    expect(
        jsonDecode(
            (await core.identity.readExternalProperties())!)['isAnonymous'],
        false);
    expect(
        jsonDecode((await core.identity.readExternalProperties())!)
            .containsKey('email'),
        false);
    for (final event in requests.where((r) => r.url.path.endsWith('/ingest'))) {
      expect(event.body.contains('guest@example.test'), false);
    }
  });

  test('server-filtered profile keys are not persisted locally', () async {
    final previous = reply;
    reply = (request) async => request.url.path.endsWith('/identify')
        ? success({
            'subjectToken': 'st_bound',
            'filteredKeys': ['email']
          })
        : await previous(request);
    await core.setConsent(const Consent(analytics: true));
    expect(
        await core.identify(
            '123',
            {'isAnonymous': true, 'email': 'private@example.test'},
            'st_backend'),
        IdentifyResult.synced);
    expect(
        jsonDecode((await core.identity.readExternalProperties())!)
            .containsKey('email'),
        false);
  });

  test(
      'identification adopts the canonical account profile over anonymous defaults',
      () async {
    await core.setConsent(const Consent(analytics: true));
    await core.setUserProperties({'plan': 'free', 'oldDefault': true}, []);
    final previous = reply;
    reply = (request) async {
      if (request.url.path.endsWith('/identify'))
        return success({
          'subjectToken': 'st_bound',
          'filteredKeys': <String>[],
          'properties': {'plan': 'paid'},
        });
      return previous(request);
    };
    expect(await core.identify('returning-account', null, 'st_backend'),
        IdentifyResult.synced);
    expect(jsonDecode((await core.identity.readExternalProperties())!),
        {'plan': 'paid'});
  });

  test('local logout finishes while old credential cleanup is offline',
      () async {
    await core.identify('account-a', null, 'st_backend');
    final oldAlias = core.identity.anonymousId;
    final cleanup = Completer<http.Response>();
    final previous = reply;
    reply = (request) async => request.url.path.endsWith('/revoke')
        ? await cleanup.future
        : await previous(request);
    await core.reset().timeout(const Duration(seconds: 1));
    expect(core.identity.externalId, isNull);
    expect(core.identity.anonymousId, isNot(oldAlias));
    await Future<void>.delayed(Duration.zero);
    final revoke = requests.firstWhere((r) => r.url.path.endsWith('/revoke'));
    expect(revoke.headers['x-usergist-subject-token'], 'st_bound');
    expect(jsonDecode(revoke.body)['anonymousId'], oldAlias);
    cleanup.complete(success({}));
  });

  test(
      'an OS token is retained before consent and a skipped registration is retried',
      () async {
    final previous = reply;
    var registrations = 0;
    reply = (request) async {
      if (request.url.path.endsWith('/register-token')) {
        registrations++;
        return registrations == 1
            ? success({'skipped': 'consent'}, 202)
            : success({'registered': true});
      }
      return previous(request);
    };
    PushSubscriptionState? state;
    core.onPushSubscriptionState = (value) {
      state = value;
    };
    await core.registerPushToken('os-token', 'ios', 'sandbox');
    expect(registrations, 0);
    expect(state?.tokenAvailable, true);
    expect(state?.registered, false);
    await core.setConsent(const Consent(push: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(registrations, 1);
    expect(state?.registered, false);
    await core.registerPushToken('os-token', 'ios', 'sandbox');
    expect(registrations, 2);
    expect(state?.registered, true);
  });
  test('invalidation survives restart and permits explicit re-registration',
      () async {
    var active = false;
    var registrations = 0;
    final previous = reply;
    reply = (request) async {
      if (request.url.path.endsWith('/register-token')) {
        active = true;
        registrations++;
        return success({'registered': true});
      }
      if (request.url.path.endsWith('/invalidate-token')) {
        active = false;
        return success({});
      }
      return previous(request);
    };
    await core.setConsent(const Consent(push: true));
    await core.registerPushToken('device-token', 'ios', 'sandbox');
    expect(active, true);
    await core.invalidatePushToken('device-token');
    expect(active, false);
    await core.dispose();
    core = makeCore();
    await core.start();
    await core.flush();
    expect(active, false);
    expect(registrations, 1);
    await core.registerPushToken('device-token', 'ios', 'sandbox');
    expect(active, true);
    expect(registrations, 2);
  });

  test(
      'invalidation follows pending registration and clears its acknowledgement',
      () async {
    final entered = Completer<void>(), gate = Completer<http.Response>();
    var invalidations = 0;
    final previous = reply;
    reply = (request) async {
      if (request.url.path.endsWith('/register-token')) {
        entered.complete();
        return gate.future;
      }
      if (request.url.path.endsWith('/invalidate-token')) invalidations++;
      return previous(request);
    };
    PushSubscriptionState? state;
    core.onPushSubscriptionState = (value) => state = value;
    await core.setConsent(const Consent(push: true));
    final registering =
        core.registerPushToken('device-token', 'ios', 'sandbox');
    await entered.future;
    final invalidating = core.invalidatePushToken('device-token');
    expect(invalidations, 0);
    gate.complete(success({'registered': true}));
    await Future.wait([registering, invalidating]);
    await core.flush();
    expect(invalidations, 1);
    expect(state?.registered, false);
    expect(state?.tokenAvailable, false);
  });

  test('restored identity is unconfirmed until the session succeeds', () async {
    await core.identify('account-a', null, 'st_backend');
    await core.dispose();
    final sessionEntered = Completer<void>(), gate = Completer<http.Response>();
    final previous = reply;
    reply = (request) async {
      if (request.url.path.endsWith('/session')) {
        sessionEntered.complete();
        return gate.future;
      }
      return previous(request);
    };
    final states = <IdentityState>[];
    core = makeCore();
    core.onIdentityState = states.add;
    await core.start();
    await sessionEntered.future;
    expect(core.identityState.externalId, 'account-a');
    expect(states.map((state) => state.status), ['identifying']);
    gate.complete(success({'subjectToken': 'st_confirmed'}));
    await core.flush();
    expect(states.last.status, 'identified');
  });

  test('expired restored identity never reports identification without renewal',
      () async {
    await core.identify('account-a', null, 'st_backend');
    await core.dispose();
    final previous = reply;
    reply = (request) async => request.url.path.endsWith('/session')
        ? http.Response('{"success":false}', 401)
        : await previous(request);
    final states = <IdentityState>[];
    core = makeCore();
    core.onIdentityState = states.add;
    await core.start();
    await core.flush();
    expect(states.any((state) => state.status == 'identified'), false);
    expect(core.identityState.status, 'authentication-required');
    expect(core.identity.externalId, 'account-a');
  });
}
