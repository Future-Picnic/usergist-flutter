/// Ritmus Push — Flutter public surface.
///
/// Host apps own FCM / APNs plumbing (via `firebase_messaging` or similar).
/// They forward tokens and payloads here.

import '../ritmus.dart';

enum PushPermissionStatus {
  notDetermined,
  denied,
  granted,
  provisional,
  ephemeral,
}

class RitmusPushMessage {
  const RitmusPushMessage({
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

  static RitmusPushMessage? parseIos(Map<String, Object?> userInfo) {
    final ritmus = userInfo['ritmus'];
    if (ritmus is! Map) return null;
    final ritmusMap = Map<String, Object?>.from(ritmus);
    final aps = userInfo['aps'];
    Map<String, Object?>? alert;
    if (aps is Map && aps['alert'] is Map) {
      alert = Map<String, Object?>.from(aps['alert'] as Map);
    }
    return RitmusPushMessage(
      campaignId: ritmusMap['campaignId'] as String?,
      variantId: ritmusMap['variantId'] as String?,
      deliveryId: ritmusMap['deliveryId'] as String?,
      language: ritmusMap['language'] as String?,
      deepLink: ritmusMap['deepLink'] as String?,
      title: alert?['title'] as String?,
      body: alert?['body'] as String?,
    );
  }

  static RitmusPushMessage? parseFcm(
    Map<String, String> data, {
    String? title,
    String? body,
  }) {
    final campaignId = data['ritmus_campaign_id'];
    if (campaignId == null) return null;
    return RitmusPushMessage(
      campaignId: campaignId,
      variantId: data['ritmus_variant_id'],
      deliveryId: data['ritmus_delivery_id'],
      language: data['ritmus_language'],
      deepLink: data['ritmus_deep_link'],
      title: title,
      body: body,
    );
  }
}

typedef OnReceive = void Function(
    RitmusPushMessage message, Map<String, Object?> raw);
typedef OnOpen = void Function(RitmusPushMessage message);
typedef OnAction = void Function(RitmusPushMessage message, String actionButton);

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
    await Ritmus.registerPushToken(token, platform, environment);
  }

  Future<void> invalidateDeviceToken(String token) async {
    await Ritmus.invalidatePushToken(token);
  }

  void handleReceived({
    Map<String, Object?>? userInfo,
    Map<String, String>? data,
    String? title,
    String? body,
  }) {
    RitmusPushMessage? msg;
    if (userInfo != null) msg = RitmusPushMessage.parseIos(userInfo);
    if (msg == null && data != null) msg = RitmusPushMessage.parseFcm(data, title: title, body: body);
    if (msg == null) return;
    Ritmus.track('\$push_received', <String, Object?>{
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
    RitmusPushMessage? msg;
    if (userInfo != null) msg = RitmusPushMessage.parseIos(userInfo);
    if (msg == null && data != null) msg = RitmusPushMessage.parseFcm(data);
    if (msg == null) return;
    if (actionIdentifier != null && actionIdentifier.isNotEmpty) {
      Ritmus.track('\$push_action_clicked', <String, Object?>{
        'campaign_id': msg.campaignId,
        'variant_id': msg.variantId,
        'delivery_id': msg.deliveryId,
        'action_button': actionIdentifier,
      });
      _handlers.onAction?.call(msg, actionIdentifier);
    } else {
      Ritmus.track('\$push_opened', <String, Object?>{
        'campaign_id': msg.campaignId,
        'variant_id': msg.variantId,
        'delivery_id': msg.deliveryId,
      });
      _handlers.onOpen?.call(msg);
    }
  }
}
