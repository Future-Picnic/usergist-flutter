/// Server-authorized in-app message rendered by the SDK.
class ArmedInAppMessage {
  const ArmedInAppMessage({
    required this.messageId,
    required this.eventName,
    required this.format,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.backgroundColor,
    required this.accentColor,
    required this.backdropEnabled,
    required this.ctas,
    required this.autoDismissSeconds,
    required this.screenAllowlist,
    required this.screenDenylist,
    required this.forceShow,
    this.clientSideEligible,
  });

  final String messageId;
  final String eventName;
  final bool? clientSideEligible;
  final String format;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? backgroundColor;
  final String? accentColor;
  final bool backdropEnabled;
  final List<InAppCta> ctas;
  final double? autoDismissSeconds;
  final List<String> screenAllowlist;
  final List<String> screenDenylist;
  final bool forceShow;

  factory ArmedInAppMessage.fromJson(Map<String, Object?> json) {
    final format = json['format'] as String? ?? 'modal';
    if (!const <String>{'modal', 'modal_full', 'slideup'}.contains(format)) {
      throw const FormatException('unsupported in-app message format');
    }
    final rawCtas = json['ctas'];
    return ArmedInAppMessage(
      messageId: json['messageId'] as String? ?? '',
      eventName: json['eventName'] as String? ?? 'server',
      clientSideEligible: json['clientSideEligible'] as bool?,
      format: format,
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      imageUrl: json['imageUrl'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      accentColor: json['accentColor'] as String?,
      backdropEnabled: json['backdropEnabled'] as bool? ?? true,
      ctas: rawCtas is List<Object?>
          ? rawCtas
              .whereType<Map<String, Object?>>()
              .map(InAppCta.fromJson)
              .toList(growable: false)
          : const <InAppCta>[],
      autoDismissSeconds: (json['autoDismissSeconds'] as num?)?.toDouble(),
      screenAllowlist: _stringList(json['screenAllowlist']),
      screenDenylist: _stringList(json['screenDenylist']),
      forceShow: json['forceShow'] as bool? ?? false,
    );
  }

  static List<String> _stringList(Object? value) => value is List<Object?>
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];
}

/// Action attached to an in-app message button.
class InAppCta {
  const InAppCta({
    required this.label,
    required this.action,
    this.target,
    this.actionJson,
  });

  final String label;
  final String action;
  final String? target;
  final Map<String, Object?>? actionJson;

  factory InAppCta.fromJson(Map<String, Object?> json) {
    final action = json['action'] as String? ?? 'dismiss';
    if (!const <String>{
      'open_url',
      'deep_link',
      'dismiss',
      'custom_event',
      'json',
    }.contains(action)) {
      throw const FormatException('unsupported in-app CTA action');
    }
    return InAppCta(
      label: json['label'] as String? ?? '',
      action: action,
      target: json['target'] as String?,
      actionJson: json['actionJson'] is Map<Object?, Object?>
          ? Map<String, Object?>.from(
              json['actionJson'] as Map<Object?, Object?>,
            )
          : null,
    );
  }
}

/// Details emitted to [InAppHandlers.onCtaClick].
class InAppCtaClick {
  const InAppCtaClick({
    required this.messageId,
    required this.action,
    required this.label,
    required this.index,
    this.target,
    this.actionJson,
  });

  final String messageId;
  final String action;
  final String? target;
  final String label;
  final int index;
  final Map<String, Object?>? actionJson;
}

/// Optional lifecycle callbacks for SDK-rendered in-app messages.
class InAppHandlers {
  const InAppHandlers({
    this.onShow,
    this.onDismiss,
    this.onCtaClick,
    this.onJsonAction,
  });

  final void Function(String messageId)? onShow;
  final void Function(String messageId, String reason)? onDismiss;
  final void Function(InAppCtaClick click)? onCtaClick;
  final void Function(Map<String, Object?> action, InAppCtaClick click)?
      onJsonAction;
}
