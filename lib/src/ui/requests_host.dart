/// Drop-in Flutter UI for the Feature Requests pillar.
///
/// Host apps mount `UserGistProvider` below a Navigator, or provide its root
/// navigator key.
/// `UserGist.openRequestsBoard()` then pushes a route onto the host's
/// Navigator — no host-side UI work required.
///
/// Requests reuse the app's SDK theme (font, colours, radius) and take the
/// primary colour from the requests branding accent, so the board matches
/// feedback and surveys instead of using fixed greys.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../internal/logger.dart';
import '../internal/requests/requests_api.dart';
import '../models/request.dart';
import '../models/theme.dart';
import '../usergist.dart';
import 'surface_controls.dart';
import 'surface_primitives.dart';
import 'surface_tokens.dart';
import 'theme_resolver.dart';

part 'requests_board.dart';
part 'requests_detail.dart';
part 'requests_comments.dart';
part 'requests_submit.dart';

const Color _fallbackAccent = Color(0xFF5B4BFF);
const int _commentMax = 1000;

/// Stream events emitted by `UserGist.openRequestsBoard` / `openRequestDetail`.
/// The provider listens and pushes the appropriate route.
class RequestsNav {
  RequestsNav._();
  static final StreamController<_NavEvent> _ctrl =
      StreamController<_NavEvent>.broadcast();

  static Stream<Object> get stream => _ctrl.stream;

  static void board() => _ctrl.add(const _BoardEvent());
  static void detail(String requestId) => _ctrl.add(_DetailEvent(requestId));
}

sealed class _NavEvent {
  const _NavEvent();
}

class _BoardEvent extends _NavEvent {
  const _BoardEvent();
}

class _DetailEvent extends _NavEvent {
  const _DetailEvent(this.requestId);
  final String requestId;
}

/// Mount inside `UserGistProvider` to wire up the requests UI.
class RequestsNavHost extends StatefulWidget {
  const RequestsNavHost({this.navigatorKey, super.key});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<RequestsNavHost> createState() => _RequestsNavHostState();
}

class _RequestsNavHostState extends State<RequestsNavHost> {
  StreamSubscription<_NavEvent>? _sub;
  _Branding? _branding;

  @override
  void initState() {
    super.initState();
    _sub = RequestsNav.stream.cast<_NavEvent>().listen(_onNav);
    unawaited(_loadBranding());
  }

  Future<void> _loadBranding() async {
    final b = await UserGist.getRequestBranding();
    if (!mounted || b == null) return;
    setState(() => _branding = _Branding.fromApi(b));
  }

  void _onNav(_NavEvent ev) {
    final nav = widget.navigatorKey?.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);
    if (nav == null) {
      log.e(
        'Requests UI requires UserGistProvider below a Navigator or with a '
        'navigatorKey',
      );
      return;
    }
    final branding = _branding ?? _Branding.fallback;
    switch (ev) {
      case _BoardEvent():
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => _BoardScreen(branding: branding),
          ),
        );
      case _DetailEvent(:final requestId):
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => _DetailScreen(
              requestId: requestId,
              branding: branding,
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Branding {
  const _Branding({required this.entryLabel, required this.accent});
  final String entryLabel;
  final Color accent;

  static const _Branding fallback =
      _Branding(entryLabel: 'Suggestions', accent: _fallbackAccent);

  factory _Branding.fromApi(FlutterRequestBranding b) {
    return _Branding(
      entryLabel: b.entryLabel,
      accent: _parseHex(b.accentColor) ?? _fallbackAccent,
    );
  }
}

Color? _parseHex(String? s) {
  if (s == null) return null;
  final cleaned = s.replaceAll('#', '');
  if (cleaned.length != 6) return null;
  final v = int.tryParse(cleaned, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// The app's SDK theme with the requests branding accent as primary.
ResolvedPromptTheme _requestsTheme(BuildContext context, _Branding branding) =>
    ResolvedPromptTheme.of(
      context,
      overrides: UserGist.internalThemeOverrides,
      serverTheme: PromptTheme(
        colors: PromptThemeColors(primary: branding.accent),
      ),
    );

// Status colours stay semantic (review, planned, shipped…) across themes.
const Map<RequestStatus, Color> _statusColors = {
  RequestStatus.underReview: Color(0xFF9CA3AF),
  RequestStatus.planned: Color(0xFF3B82F6),
  RequestStatus.inProgress: Color(0xFFF59E0B),
  RequestStatus.shipped: Color(0xFF22C55E),
  RequestStatus.declined: Color(0xFFEF4444),
};

const Map<RequestStatus, String> _statusLabels = {
  RequestStatus.underReview: 'Under review',
  RequestStatus.planned: 'Planned',
  RequestStatus.inProgress: 'In progress',
  RequestStatus.shipped: 'Shipped',
  RequestStatus.declined: 'Declined',
};

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.theme});
  final RequestStatus status;
  final ResolvedPromptTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(0x18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(0x55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _statusLabels[status]!,
            style: theme.textStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Themed page frame shared by board, detail and submit: background,
/// status-bar style, safe edges and a hairline under the header.
class _RequestsFrame extends StatelessWidget {
  const _RequestsFrame({
    required this.theme,
    required this.header,
    required this.body,
    this.bottom,
  });

  final ResolvedPromptTheme theme;
  final Widget header;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final footer = bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.background.computeLuminance() > 0.5
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.border, width: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: header,
                ),
              ),
              Expanded(child: body),
              if (footer != null) footer,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _headerTitle(ResolvedPromptTheme theme, String title, {String? sub}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textStyle(
          color: theme.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (sub != null)
        Text(
          sub,
          style: theme.textStyle(
            color: theme.subtext,
            fontSize: 13,
            tabular: true,
          ),
        ),
    ],
  );
}

/// Centred message used for empty and error states.
Widget _centeredMessage(
  ResolvedPromptTheme theme, {
  required String title,
  required String body,
  Widget? action,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textStyle(
            color: theme.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textStyle(
              color: theme.subtext,
              fontSize: 15,
              lineHeight: 22,
            ),
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: action,
          ),
        ],
      ],
    ),
  );
}

// helpers

/// Spec §9: upvoting auto-creates a follow; un-upvoting does NOT remove it.
RequestSummary _voteSummary(RequestSummary r, bool next) => RequestSummary(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      upvoteCount: (r.upvoteCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      followerCount:
          next && !r.viewerIsFollowing ? r.followerCount + 1 : r.followerCount,
      createdAt: r.createdAt,
      statusChangedAt: r.statusChangedAt,
      viewerHasUpvoted: next,
      viewerIsFollowing: next ? true : r.viewerIsFollowing,
    );

RequestSummary _voteSummaryResult(RequestSummary r, RequestVote result) =>
    RequestSummary(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      upvoteCount: result.upvoteCount,
      followerCount: result.followerCount,
      createdAt: r.createdAt,
      statusChangedAt: r.statusChangedAt,
      viewerHasUpvoted: result.upvoted,
      viewerIsFollowing: result.followed,
    );

FeatureRequest _vote(FeatureRequest r, bool next) => FeatureRequest(
      id: r.id,
      appId: r.appId,
      title: r.title,
      description: r.description,
      status: r.status,
      devResponse: r.devResponse,
      upvoteCount: (r.upvoteCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      followerCount:
          next && !r.viewerIsFollowing ? r.followerCount + 1 : r.followerCount,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      statusChangedAt: r.statusChangedAt,
      lastRespondedAt: r.lastRespondedAt,
      viewerHasUpvoted: next,
      viewerIsFollowing: next ? true : r.viewerIsFollowing,
      viewerIsSubmitter: r.viewerIsSubmitter,
    );

FeatureRequest _follow(FeatureRequest r, bool next) => FeatureRequest(
      id: r.id,
      appId: r.appId,
      title: r.title,
      description: r.description,
      status: r.status,
      devResponse: r.devResponse,
      upvoteCount: r.upvoteCount,
      followerCount: (r.followerCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      statusChangedAt: r.statusChangedAt,
      lastRespondedAt: r.lastRespondedAt,
      viewerHasUpvoted: r.viewerHasUpvoted,
      viewerIsFollowing: next,
      viewerIsSubmitter: r.viewerIsSubmitter,
    );

FeatureRequest _voteResult(FeatureRequest r, RequestVote result) =>
    FeatureRequest(
      id: r.id,
      appId: r.appId,
      title: r.title,
      description: r.description,
      status: r.status,
      devResponse: r.devResponse,
      upvoteCount: result.upvoteCount,
      followerCount: result.followerCount,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      statusChangedAt: r.statusChangedAt,
      lastRespondedAt: r.lastRespondedAt,
      viewerHasUpvoted: result.upvoted,
      viewerIsFollowing: result.followed,
      viewerIsSubmitter: r.viewerIsSubmitter,
    );

FeatureRequest _followResult(FeatureRequest r, RequestFollow result) =>
    FeatureRequest(
      id: r.id,
      appId: r.appId,
      title: r.title,
      description: r.description,
      status: r.status,
      devResponse: r.devResponse,
      upvoteCount: r.upvoteCount,
      followerCount: result.followerCount,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      statusChangedAt: r.statusChangedAt,
      lastRespondedAt: r.lastRespondedAt,
      viewerHasUpvoted: r.viewerHasUpvoted,
      viewerIsFollowing: result.following,
      viewerIsSubmitter: r.viewerIsSubmitter,
    );

String _formatRelative(String iso) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
}

/// Readable list width (content measure plus the list's side padding).
const double _listMaxWidth = kSurfaceContentMaxWidth + 32;
