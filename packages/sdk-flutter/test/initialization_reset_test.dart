import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usergist_feedback/src/internal/hashing.dart';
import 'package:usergist_feedback/src/models/identity_state.dart';
import 'package:usergist_feedback/src/usergist.dart';

class _PausedPaths extends PathProviderPlatform {
  final entered = Completer<void>();
  final release = Completer<String?>();

  @override
  Future<String?> getApplicationSupportPath() {
    if (!entered.isCompleted) entered.complete();
    return release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout during hydration waits and clears the restored account',
      () async {
    const key = 'bootstrap-reset-test';
    final prefix = 'usergist.${shortHash(key)}.secure.';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      '${prefix}identity.anonymousId': 'installation-a',
      '${prefix}identity.externalId': 'account-a',
      '${prefix}session.subjectToken': 'st_previous_account',
    });
    final previousPaths = PathProviderPlatform.instance;
    final paths = _PausedPaths();
    PathProviderPlatform.instance = paths;
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final states = <IdentityState>[];
    UserGist.setIdentityStateHandler(states.add);
    final starting = UserGist.init(
      writeKey: key,
      apiUrl: 'https://bootstrap.test',
      flushInterval: const Duration(hours: 1),
      triggerSyncInterval: const Duration(hours: 1),
    );
    await paths.entered.future;
    var completed = false;
    final resetting = UserGist.resetAsync().then((value) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    paths.release.complete(
        (await Directory.systemTemp.createTemp('usergist-bootstrap-reset-'))
            .path);
    await starting;
    expect(await resetting, true);
    expect(UserGist.externalId, isNull);
    expect(UserGist.anonymousId, isNot('installation-a'));
    expect(states.any((state) => state.status == 'identified'), false);
    expect(states.any((state) => state.status == 'resetting'), true);
    expect(
        await const FlutterSecureStorage()
            .read(key: '${prefix}identity.externalId'),
        isNull);
  });
}
