/// Drop-in Flutter UI for the Feature Requests pillar.
///
/// Host apps mount `UserGistProvider` below a Navigator, or provide its root
/// navigator key.
/// `UserGist.openRequestsBoard()` then pushes a route onto the host's
/// Navigator — no host-side UI work required.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../internal/logger.dart';
import '../internal/requests/requests_api.dart';
import '../models/request.dart';
import '../usergist.dart';

const Color _fallbackAccent = Color(0xFF5B4BFF);

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
  const _StatusPill({required this.status});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(89)),
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
            style: TextStyle(
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

// ============================================================
// Board
// ============================================================

class _BoardScreen extends StatefulWidget {
  const _BoardScreen({required this.branding});
  final _Branding branding;

  @override
  State<_BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<_BoardScreen> {
  bool _loading = true;
  List<RequestSummary> _items = const [];
  final Set<String> _voteInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await UserGist.getRequests(
      options: const GetRequestsOptions(sort: RequestSort.top, limit: 50),
    );
    if (!mounted) return;
    setState(() {
      _items = r.items;
      _loading = false;
    });
  }

  Future<void> _toggleVote(RequestSummary item) async {
    if (_voteInFlight.contains(item.id)) return;
    final next = !item.viewerHasUpvoted;
    setState(() {
      _voteInFlight.add(item.id);
      _items = _items
          .map((r) => r.id == item.id ? _voteSummary(r, next) : r)
          .toList(growable: false);
    });
    try {
      final result = await UserGist.voteOnRequest(item.id, vote: next);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((r) => r.id == item.id ? _voteSummaryResult(r, result) : r)
            .toList(growable: false);
      });
    } catch (_) {
      unawaited(_load());
    } finally {
      if (mounted) setState(() => _voteInFlight.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.branding.accent;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.branding.entryLabel),
        actions: [
          Semantics(
            button: true,
            label: 'Create new request',
            excludeSemantics: true,
            child: TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final created = await navigator.push<FeatureRequest?>(
                  MaterialPageRoute<FeatureRequest?>(
                    builder: (_) => _SubmitScreen(branding: widget.branding),
                  ),
                );
                if (created != null && mounted) {
                  navigator.push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => _DetailScreen(
                        requestId: created.id,
                        branding: widget.branding,
                      ),
                    ),
                  );
                  unawaited(_load());
                }
              },
              child: Text(
                '+ New',
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: accent,
              child: _items.isEmpty
                  ? _emptyState(accent)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _RequestCard(
                        item: _items[i],
                        accent: accent,
                        voteEnabled: !_voteInFlight.contains(_items[i].id),
                        onUpvote: () => _toggleVote(_items[i]),
                        onOpen: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => _DetailScreen(
                              requestId: _items[i].id,
                              branding: widget.branding,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
    );
  }

  Widget _emptyState(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: const [
        Text(
          '💡',
          style: TextStyle(fontSize: 48),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 16),
        Text(
          'No suggestions yet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111111),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        Text(
          'Be the first to share an idea — what would make this app better?',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.accent,
    required this.voteEnabled,
    required this.onUpvote,
    required this.onOpen,
  });
  final RequestSummary item;
  final Color accent;
  final bool voteEnabled;
  final VoidCallback onUpvote;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accentSoft = accent.withAlpha(26);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UpvoteButton(
                count: item.upvoteCount,
                active: item.viewerHasUpvoted,
                accent: accent,
                accentSoft: accentSoft,
                semanticsLabel: voteEnabled
                    ? item.viewerHasUpvoted
                        ? 'Remove vote from ${item.title}'
                        : 'Upvote ${item.title}'
                    : 'Updating vote for ${item.title}',
                onPress: voteEnabled ? onUpvote : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _StatusPill(status: item.status),
                        const SizedBox(width: 8),
                        if (item.viewerIsFollowing)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '✓ Following',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpvoteButton extends StatelessWidget {
  const _UpvoteButton({
    required this.count,
    required this.active,
    required this.accent,
    required this.accentSoft,
    required this.semanticsLabel,
    required this.onPress,
  });
  final int count;
  final bool active;
  final Color accent;
  final Color accentSoft;
  final String semanticsLabel;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPress != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? accent : accentSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? accent : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '▲',
                style: TextStyle(
                  color: active ? Colors.white : accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$count',
                style: TextStyle(
                  color: active ? Colors.white : accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Detail
// ============================================================

class _DetailScreen extends StatefulWidget {
  const _DetailScreen({required this.requestId, required this.branding});
  final String requestId;
  final _Branding branding;

  @override
  State<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<_DetailScreen> {
  FeatureRequest? _data;
  bool _loading = true;
  List<FlutterRequestComment> _comments = const [];
  final _commentCtrl = TextEditingController();
  bool _posting = false;
  bool _requestMutationInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      UserGist.getRequest(widget.requestId),
      UserGist.getComments(widget.requestId),
    ]);
    if (!mounted) return;
    setState(() {
      _data = results[0] as FeatureRequest?;
      _comments = (results[1] as List<FlutterRequestComment>?) ?? const [];
      _loading = false;
    });
  }

  Future<void> _toggleVote() async {
    final data = _data;
    if (data == null || _requestMutationInFlight) return;
    final next = !data.viewerHasUpvoted;
    setState(() {
      _requestMutationInFlight = true;
      _data = _vote(data, next);
    });
    try {
      final result = await UserGist.voteOnRequest(data.id, vote: next);
      if (mounted) setState(() => _data = _voteResult(_data!, result));
    } catch (_) {
      if (mounted) setState(() => _data = data);
    } finally {
      if (mounted) setState(() => _requestMutationInFlight = false);
    }
  }

  Future<void> _toggleFollow() async {
    final data = _data;
    if (data == null || _requestMutationInFlight) return;
    final next = !data.viewerIsFollowing;
    setState(() {
      _requestMutationInFlight = true;
      _data = _follow(data, next);
    });
    try {
      final result = await UserGist.followRequest(data.id, follow: next);
      if (mounted) setState(() => _data = _followResult(_data!, result));
    } catch (_) {
      if (mounted) setState(() => _data = data);
    } finally {
      if (mounted) setState(() => _requestMutationInFlight = false);
    }
  }

  Future<void> _postComment() async {
    final body = _commentCtrl.text.trim();
    if (_posting || body.isEmpty || body.length > 1000) return;
    setState(() {
      _posting = true;
      _commentCtrl.clear();
    });
    try {
      final c = await UserGist.postComment(widget.requestId, body);
      if (c != null && mounted) {
        setState(() {
          _comments = [..._comments, c];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (_commentCtrl.text.isEmpty) _commentCtrl.text = body;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.branding.accent;
    final data = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'SUGGESTION',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading || data == null
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StatusPill(status: data.status),
                const SizedBox(height: 12),
                Text(
                  data.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                _statsRow(data, accent),
                const SizedBox(height: 20),
                Text(
                  data.description,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF1F2937),
                  ),
                ),
                if (data.devResponse != null) ...[
                  const SizedBox(height: 24),
                  _devResponseCard(data.devResponse!, accent),
                ],
                const SizedBox(height: 28),
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: _commentsSection(accent),
                ),
              ],
            ),
      bottomNavigationBar: data == null
          ? null
          : SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _actionBtn(
                        active: data.viewerHasUpvoted,
                        activeBg: accent,
                        inactiveBg: accent.withAlpha(38),
                        label: data.viewerHasUpvoted
                            ? '▲ Upvoted (${data.upvoteCount})'
                            : '▲ Upvote (${data.upvoteCount})',
                        textColor:
                            data.viewerHasUpvoted ? Colors.white : accent,
                        semanticsLabel: _requestMutationInFlight
                            ? 'Updating request vote'
                            : data.viewerHasUpvoted
                                ? 'Remove request vote'
                                : 'Upvote request',
                        onPress: _requestMutationInFlight ? null : _toggleVote,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionBtn(
                        active: data.viewerIsFollowing,
                        activeBg: const Color(0xFF111111),
                        inactiveBg: const Color(0xFFF3F4F6),
                        label:
                            data.viewerIsFollowing ? '✓ Following' : 'Follow',
                        textColor: data.viewerIsFollowing
                            ? Colors.white
                            : const Color(0xFF111111),
                        semanticsLabel: _requestMutationInFlight
                            ? 'Updating request follow'
                            : data.viewerIsFollowing
                                ? 'Unfollow request'
                                : 'Follow request',
                        onPress:
                            _requestMutationInFlight ? null : _toggleFollow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statsRow(FeatureRequest data, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: '${data.upvoteCount} upvotes',
              excludeSemantics: true,
              child: _stat('${data.upvoteCount}', 'upvotes', accent),
            ),
          ),
          Container(width: 1, height: 30, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: Semantics(
              label: '${data.followerCount} followers',
              excludeSemantics: true,
              child: _stat('${data.followerCount}', 'followers', null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color? valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }

  Widget _devResponseCard(String body, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
                child: const Center(
                  child: Text(
                    '✓',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'FROM THE TEAM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF111111),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentsSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _comments.isEmpty ? 'COMMENTS' : 'COMMENTS · ${_comments.length}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF3F4F6)),
          ),
          child: Column(
            children: [
              Semantics(
                label: 'Request comment',
                textField: true,
                child: TextField(
                  controller: _commentCtrl,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment…',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_commentCtrl.text.length}/1000',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: _posting
                        ? 'Posting request comment'
                        : 'Post request comment',
                    excludeSemantics: true,
                    child: ElevatedButton(
                      onPressed: _posting ? null : _postComment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(_posting ? 'Posting…' : 'Post'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No comments yet — be the first to weigh in.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ..._comments.map((c) => _commentRow(c, accent)),
      ],
    );
  }

  Widget _commentRow(FlutterRequestComment c, Color accent) {
    final isViewer = c.viewerIsAuthor;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isViewer ? accent : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isViewer ? 'You' : 'Anon',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isViewer ? Colors.white : const Color(0xFF374151),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatRelative(c.createdAt),
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: 'Request comment body: ${c.body}',
            excludeSemantics: true,
            child: Text(
              c.body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF111111),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required bool active,
    required Color activeBg,
    required Color inactiveBg,
    required String label,
    required Color textColor,
    required String semanticsLabel,
    required VoidCallback? onPress,
  }) {
    return Semantics(
      button: true,
      enabled: onPress != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: ElevatedButton(
        onPressed: onPress,
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? activeBg : inactiveBg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Submit
// ============================================================

class _SubmitScreen extends StatefulWidget {
  const _SubmitScreen({required this.branding});
  final _Branding branding;

  @override
  State<_SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<_SubmitScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final t = _titleCtrl.text.trim();
    final d = _descCtrl.text.trim();
    return !_submitting &&
        t.isNotEmpty &&
        t.length <= 120 &&
        d.isNotEmpty &&
        d.length <= 1500;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final created = await UserGist.submitRequest(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.branding.accent;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('New suggestion'),
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              _submitting ? 'Posting…' : 'Post',
              style: TextStyle(
                color: _canSubmit ? accent : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Tell us what you'd like to see. Other users can upvote your "
            'idea, and the team will respond as work progresses.',
            style:
                TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
          ),
          const SizedBox(height: 20),
          _field(
            label: 'Title',
            controller: _titleCtrl,
            maxLength: 120,
            placeholder: 'A short, clear title',
            autofocus: true,
            accent: accent,
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Description',
            controller: _descCtrl,
            maxLength: 1500,
            placeholder:
                'What does this do? Who is it for? Why does it matter?',
            multiline: true,
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required int maxLength,
    required String placeholder,
    required Color accent,
    bool autofocus = false,
    bool multiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
            Text(
              '${controller.text.length}/$maxLength',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label:
              label == 'Title' ? 'Suggestion title' : 'Suggestion description',
          textField: true,
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            maxLines: multiline ? 6 : 1,
            autofocus: autofocus,
            decoration: InputDecoration(
              counterText: '',
              hintText: placeholder,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: accent.withAlpha(140),
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
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
