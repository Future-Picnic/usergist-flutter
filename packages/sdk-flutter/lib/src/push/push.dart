/// UserGist Push — Flutter public surface.
///
/// Host apps own FCM / APNs plumbing (via `firebase_messaging` or similar).
/// They forward tokens and payloads here.
library;

import 'dart:convert';

import '../usergist.dart';

enum PushPermissionStatus {
  notDetermined,
  denied,
  granted,
  provisional,
  ephemeral,
}

class UserGistPushMessage {
  const UserGistPushMessage({
    this.campaignId,
    this.variantId,
    this.deliveryId,
    this.language,
    this.deepLink,
    this.title,
    this.body,
    this.actionButtons = const <PushActionButton>[],
  });

  final String? campaignId;
  final String? variantId;
  final String? deliveryId;
  final String? language;
  final String? deepLink;
  final String? title;
  final String? body;
  final List<PushActionButton> actionButtons;

  static UserGistPushMessage? parseIos(Map<String, Object?> userInfo) {
    final usergist = userInfo['usergist'];
    if (usergist is! Map) return null;
    final usergistMap = Map<String, Object?>.from(usergist);
    final aps = userInfo['aps'];
    Map<String, Object?>? alert;
    if (aps is Map && aps['alert'] is Map) {
      alert = Map<String, Object?>.from(aps['alert'] as Map);
    }
    return UserGistPushMessage(
      campaignId: usergistMap['campaignId'] as String?,
      variantId: usergistMap['variantId'] as String?,
      deliveryId: usergistMap['deliveryId'] as String?,
      language: usergistMap['language'] as String?,
      deepLink: usergistMap['deepLink'] as String?,
      title: alert?['title'] as String?,
      body: alert?['body'] as String?,
      actionButtons: PushActionButton.parseList(usergistMap['actionButtons']),
    );
  }

  static UserGistPushMessage? parseFcm(
    Map<String, String> data, {
    String? title,
    String? body,
  }) {
    final campaignId = data['usergist_campaign_id'];
    if (campaignId == null) return null;
    return UserGistPushMessage(
      campaignId: campaignId,
      variantId: data['usergist_variant_id'],
      deliveryId: data['usergist_delivery_id'],
      language: data['usergist_language'],
      deepLink: data['usergist_deep_link'],
      title: title,
      body: body,
      actionButtons: PushActionButton.parseList(data['usergist_actions']),
    );
  }
}

class PushActionButton {
  const PushActionButton({
    required this.label,
    required this.action,
    this.target,
    this.actionJson,
  });

  final String label;
  final String action;
  final String? target;
  final Map<String, Object?>? actionJson;

  static List<PushActionButton> parseList(Object? value) {
    Object? candidate = value;
    if (candidate is String) {
      try {
        candidate = jsonDecode(candidate);
      } on FormatException {
        return const <PushActionButton>[];
      }
    }
    if (candidate is! List) return const <PushActionButton>[];
    return candidate.whereType<Map<Object?, Object?>>().map((raw) {
      final map = Map<String, Object?>.from(raw);
      final json = map['actionJson'];
      return PushActionButton(
        label: map['label'] as String? ?? '',
        action: map['action'] as String? ?? 'open_app',
        target: map['target'] as String?,
        actionJson: json is Map<Object?, Object?>
            ? Map<String, Object?>.from(json)
            : null,
      );
    }).toList(growable: false);
  }
}

typedef OnReceive = void Function(
  UserGistPushMessage message,
  Map<String, Object?> raw,
);
typedef OnOpen = void Function(UserGistPushMessage message);
typedef OnAction = void Function(
  UserGistPushMessage message,
  String actionButton,
);
typedef OnJsonAction = void Function(
  Map<String, Object?> action,
  UserGistPushMessage message,
  String actionButton,
);
typedef OnDismiss = void Function(UserGistPushMessage message);
typedef OnSilent = void Function(String pingId);
typedef OnPushEvent = void Function(
  String name,
  Map<String, Object?> properties,
);

class PushHandlers {
  PushHandlers({
    this.onReceive,
    this.onOpen,
    this.onAction,
    this.onJsonAction,
    this.onDismiss,
    this.onSilent,
    this.onEvent,
  });

  OnReceive? onReceive;
  OnOpen? onOpen;
  OnAction? onAction;
  OnJsonAction? onJsonAction;
  OnDismiss? onDismiss;
  OnSilent? onSilent;
  OnPushEvent? onEvent;
}

/// Server-defined channel metadata. Host apps map this to Android
/// NotificationChannel / iOS UNNotificationCategory as appropriate.
class UserGistPushChannel {
  const UserGistPushChannel({
    required this.id,
    required this.displayName,
    this.description,
    required this.importance,
    this.defaultSound,
    required this.defaultVibrate,
    required this.defaultBadge,
    required this.category,
  });

  final String id;
  final String displayName;
  final String? description;
  final int importance;
  final String? defaultSound;
  final bool defaultVibrate;
  final bool defaultBadge;
  final String category;

  factory UserGistPushChannel.fromJson(Map<String, Object?> json) =>
      UserGistPushChannel(
        id: json['channel_id'] as String? ?? json['channelId'] as String? ?? '',
        displayName: json['display_name'] as String? ??
            json['displayName'] as String? ??
            '',
        description: json['description'] as String?,
        importance: (json['importance'] as num?)?.toInt() ?? 3,
        defaultSound:
            json['default_sound'] as String? ?? json['defaultSound'] as String?,
        defaultVibrate: json['default_vibrate'] as bool? ??
            json['defaultVibrate'] as bool? ??
            false,
        defaultBadge: json['default_badge'] as bool? ??
            json['defaultBadge'] as bool? ??
            true,
        category: json['category'] as String? ?? 'general',
      );
}

class Push {
  Push._();

  static final Push instance = Push._();

  PushHandlers _handlers = PushHandlers();

  void setHandlers(PushHandlers handlers) {
    _handlers = handlers;
  }

  void dispatchSdkEvent(String name, Map<String, Object?> properties) {
    _handlers.onEvent?.call(name, properties);
  }

  Future<void> registerDeviceToken(
    String token,
    String platform, {
    String environment = 'production',
  }) async {
    await UserGist.registerPushToken(token, platform, environment);
  }

  Future<void> invalidateDeviceToken(String token) async {
    await UserGist.invalidatePushToken(token);
  }

  Future<void> rebindDeviceToken(String externalId) async {
    await UserGist.rebindPushToken(externalId);
  }

  Future<void> appDidBecomeActive() => UserGist.pushAppOpen();

  Future<void> beaconDelivered(String deliveryId) =>
      UserGist.pushBeacon('delivered', deliveryId);

  Future<void> beaconDisplayed(String deliveryId) =>
      UserGist.pushBeacon('displayed', deliveryId);

  Future<void> beaconDismissed(String deliveryId) =>
      UserGist.pushBeacon('dismissed', deliveryId);

  Future<List<UserGistPushChannel>> fetchChannels() async {
    final raw = await UserGist.pushFetchChannels();
    return raw.map(UserGistPushChannel.fromJson).toList(growable: false);
  }

  Future<void> setChannelSubscription(String channelId, bool subscribed) =>
      UserGist.pushSetChannelSubscription(channelId, subscribed);

  /// Detects and acknowledges a silent reachability ping. Returns true when
  /// the host must suppress notification UI for this payload.
  Future<bool> handleSilentIfPresent(Map<String, String> data) async {
    if (data['usergist_silent'] != '1') return false;
    final pingId = data['usergist_ping_id'];
    if (pingId != null && pingId.isNotEmpty) {
      _handlers.onSilent?.call(pingId);
      await UserGist.pushAckSilent(pingId);
    }
    return true;
  }

  void handleReceived({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? title,
    String? body,
  }) {
    final msg = _parse(
      userInfo: userInfo,
      data: data,
      title: title,
      body: body,
    );
    if (msg == null) return;
    UserGist.track(
      '\$push_received',
      properties: <String, Object?>{
        'campaign_id': msg.campaignId,
        'variant_id': msg.variantId,
        'delivery_id': msg.deliveryId,
        'language': msg.language,
      },
    );
    dispatchSdkEvent('\$push_received', _eventProperties(msg));
    _handlers.onReceive?.call(
      msg,
      userInfo ?? Map<String, Object?>.from(data ?? const <String, String>{}),
    );
  }

  void handleDisplayed({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? title,
    String? body,
  }) {
    final msg = _parse(
      userInfo: userInfo,
      data: data,
      title: title,
      body: body,
    );
    if (msg == null) return;
    UserGist.track('\$push_displayed', properties: _eventProperties(msg));
    dispatchSdkEvent('\$push_displayed', _eventProperties(msg));
    final deliveryId = msg.deliveryId;
    if (deliveryId != null) {
      UserGist.pushBeacon('displayed', deliveryId);
    }
  }

  void handleOpened({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? actionIdentifier,
  }) {
    UserGistPushMessage? msg;
    if (userInfo != null) msg = UserGistPushMessage.parseIos(userInfo);
    if (msg == null && data != null) msg = UserGistPushMessage.parseFcm(data);
    if (msg == null) return;
    if (actionIdentifier != null && actionIdentifier.isNotEmpty) {
      UserGist.track(
        '\$push_action_clicked',
        properties: <String, Object?>{
          'campaign_id': msg.campaignId,
          'variant_id': msg.variantId,
          'delivery_id': msg.deliveryId,
          'action_button': actionIdentifier,
        },
      );
      dispatchSdkEvent('\$push_action_clicked', <String, Object?>{
        ..._eventProperties(msg),
        'action_button': actionIdentifier,
      });
      try {
        _handlers.onAction?.call(msg, actionIdentifier);
      } on Object {
        // A host observer cannot prevent the configured action from running.
      }
      final match =
          RegExp(r'^usergist_action_(\d+)$').firstMatch(actionIdentifier);
      final index = match == null ? null : int.tryParse(match.group(1)!);
      PushActionButton? button;
      if (index != null && index >= 0 && index < msg.actionButtons.length) {
        button = msg.actionButtons[index];
      } else {
        for (final candidate in msg.actionButtons) {
          if (candidate.label == actionIdentifier) {
            button = candidate;
            break;
          }
        }
      }
      if (button?.action == 'json' && button?.actionJson != null) {
        try {
          _handlers.onJsonAction?.call(
            button!.actionJson!,
            msg,
            actionIdentifier,
          );
        } on Object {
          // Host action executors must not throw across the SDK boundary.
        }
      }
    } else {
      UserGist.track(
        '\$push_opened',
        properties: <String, Object?>{
          'campaign_id': msg.campaignId,
          'variant_id': msg.variantId,
          'delivery_id': msg.deliveryId,
        },
      );
      dispatchSdkEvent('\$push_opened', _eventProperties(msg));
      _handlers.onOpen?.call(msg);
    }
  }

  void handleDismissed({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
  }) {
    final msg = _parse(userInfo: userInfo, data: data);
    if (msg == null) return;
    UserGist.track('\$push_dismissed', properties: _eventProperties(msg));
    dispatchSdkEvent('\$push_dismissed', _eventProperties(msg));
    final deliveryId = msg.deliveryId;
    if (deliveryId != null) {
      UserGist.pushBeacon('dismissed', deliveryId);
    }
    _handlers.onDismiss?.call(msg);
  }

  UserGistPushMessage? _parse({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? title,
    String? body,
  }) {
    UserGistPushMessage? message;
    if (userInfo != null) message = UserGistPushMessage.parseIos(userInfo);
    if (message == null && data != null) {
      message = UserGistPushMessage.parseFcm(data, title: title, body: body);
    }
    return message;
  }

  Map<String, Object?> _eventProperties(UserGistPushMessage message) =>
      <String, Object?>{
        'campaign_id': message.campaignId,
        'variant_id': message.variantId,
        'delivery_id': message.deliveryId,
        'language': message.language,
      };
}
