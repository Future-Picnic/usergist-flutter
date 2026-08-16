/// UserGist Push — Flutter public surface.
///
/// Host apps own FCM / APNs plumbing (via `firebase_messaging` or similar).
/// They forward tokens and payloads here.

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
  });

  final String? campaignId;
  final String? variantId;
  final String? deliveryId;
  final String? language;
  final String? deepLink;
  final String? title;
  final String? body;

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
    );
  }
}

typedef OnReceive = void Function(
    UserGistPushMessage message, Map<String, Object?> raw);
typedef OnOpen = void Function(UserGistPushMessage message);
typedef OnAction = void Function(UserGistPushMessage message, String actionButton);

class PushHandlers {
  PushHandlers({this.onReceive, this.onOpen, this.onAction});

  OnReceive? onReceive;
  OnOpen? onOpen;
  OnAction? onAction;
}

class Push {
  Push._();

  static final Push instance = Push._();

  PushHandlers _handlers = PushHandlers();

  void setHandlers(PushHandlers handlers) {
    _handlers = handlers;
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

  void handleReceived({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? title,
    String? body,
  }) {
    UserGistPushMessage? msg;
    if (userInfo != null) msg = UserGistPushMessage.parseIos(userInfo);
    if (msg == null && data != null) msg = UserGistPushMessage.parseFcm(data, title: title, body: body);
    if (msg == null) return;
    UserGist.track('\$push_received', <String, Object?>{
      'campaign_id': msg.campaignId,
      'variant_id': msg.variantId,
      'delivery_id': msg.deliveryId,
      'language': msg.language,
    });
    _handlers.onReceive?.call(msg, (userInfo ?? data ?? const <String, Object?>{}) as Map<String, Object?>);
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
      UserGist.track('\$push_action_clicked', <String, Object?>{
        'campaign_id': msg.campaignId,
        'variant_id': msg.variantId,
        'delivery_id': msg.deliveryId,
        'action_button': actionIdentifier,
      });
      _handlers.onAction?.call(msg, actionIdentifier);
    } else {
      UserGist.track('\$push_opened', <String, Object?>{
        'campaign_id': msg.campaignId,
        'variant_id': msg.variantId,
        'delivery_id': msg.deliveryId,
      });
      _handlers.onOpen?.call(msg);
    }
  }
}
