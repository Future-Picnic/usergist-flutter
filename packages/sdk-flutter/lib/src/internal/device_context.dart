import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'logger.dart';

/// Snapshot of host-device / host-app context. Collected on SDK start.
class DeviceContextSnapshot {
  /// Creates a snapshot.
  const DeviceContextSnapshot({
    this.appVersion,
    this.locale,
    this.timezone,
    this.osName,
    this.osVersion,
    this.deviceModel,
  });

  /// Host app version string.
  final String? appVersion;

  /// Device locale name.
  final String? locale;

  /// Device timezone name.
  final String? timezone;

  /// Operating system family.
  final String? osName;

  /// Operating system version.
  final String? osVersion;

  /// Device model identifier.
  final String? deviceModel;
}

/// Collects a [DeviceContextSnapshot] from platform plugins. Every
/// call is defensively wrapped — a missing plugin never crashes the
/// SDK.
Future<DeviceContextSnapshot> collectDeviceContext() async {
  String? appVersion;
  String? locale;
  String? timezone;
  String? osName;
  String? osVersion;
  String? deviceModel;

  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } on Object catch (err) {
    log.d('package_info unavailable: $err');
  }
  try {
    locale = Platform.localeName;
  } on Object catch (_) {
    // ignore
  }
  try {
    timezone = DateTime.now().timeZoneName;
  } on Object catch (_) {
    // ignore
  }
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final d = await plugin.androidInfo;
      osName = 'android';
      osVersion = d.version.release;
      deviceModel = '${d.manufacturer} ${d.model}';
    } else if (Platform.isIOS) {
      final d = await plugin.iosInfo;
      osName = 'ios';
      osVersion = d.systemVersion;
      deviceModel = d.utsname.machine;
    } else if (Platform.isMacOS) {
      osName = 'macos';
    } else if (Platform.isWindows) {
      osName = 'windows';
    } else if (Platform.isLinux) {
      osName = 'linux';
    }
  } on Object catch (err) {
    log.d('device_info unavailable: $err');
  }

  return DeviceContextSnapshot(
    appVersion: appVersion,
    locale: locale,
    timezone: timezone,
    osName: osName,
    osVersion: osVersion,
    deviceModel: deviceModel,
  );
}
