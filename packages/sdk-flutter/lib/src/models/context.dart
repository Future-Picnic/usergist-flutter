/// Host-device / host-app context attached to every ingest batch.
class IngestContext {
  /// Creates an ingest context snapshot.
  const IngestContext({
    required this.anonymousId,
    required this.sdkVersion,
    this.externalId,
    this.appVersion,
    this.locale,
    this.timezone,
    this.osName,
    this.osVersion,
    this.deviceModel,
    this.platform = 'flutter',
  });

  /// Anonymous identifier (stable across installs that share state).
  final String anonymousId;

  /// External identifier if the user has been identified.
  final String? externalId;

  /// SDK version.
  final String sdkVersion;

  /// Host app version (from `package_info_plus`).
  final String? appVersion;

  /// Device locale string (e.g. `en-US`).
  final String? locale;

  /// IANA timezone identifier.
  final String? timezone;

  /// OS family (`ios`, `android`, `macos`, `windows`, `linux`).
  final String? osName;

  /// OS version string.
  final String? osVersion;

  /// Device model identifier.
  final String? deviceModel;

  /// SDK platform identifier. Always `flutter`.
  final String platform;

  /// JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
        'anonymousId': anonymousId,
        if (externalId != null) 'externalId': externalId,
        'sdkVersion': sdkVersion,
        'platform': platform,
        if (appVersion != null) 'appVersion': appVersion,
        if (locale != null) 'locale': locale,
        if (timezone != null) 'timezone': timezone,
        if (osName != null) 'osName': osName,
        if (osVersion != null) 'osVersion': osVersion,
        if (deviceModel != null) 'deviceModel': deviceModel,
      };

  /// Returns a copy with fields replaced.
  IngestContext copyWith({
    String? anonymousId,
    String? externalId,
    String? sdkVersion,
    String? appVersion,
    String? locale,
    String? timezone,
    String? osName,
    String? osVersion,
    String? deviceModel,
  }) =>
      IngestContext(
        anonymousId: anonymousId ?? this.anonymousId,
        externalId: externalId ?? this.externalId,
        sdkVersion: sdkVersion ?? this.sdkVersion,
        appVersion: appVersion ?? this.appVersion,
        locale: locale ?? this.locale,
        timezone: timezone ?? this.timezone,
        osName: osName ?? this.osName,
        osVersion: osVersion ?? this.osVersion,
        deviceModel: deviceModel ?? this.deviceModel,
      );
}
