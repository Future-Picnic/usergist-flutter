part of 'requests_host.dart';

// Suggestion detail: body, team response, comments and the vote/follow
// action bar. Theme colours only. Optimistic vote/follow logic is unchanged.

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
  bool _commentsLoading = true;
  bool _requestMutationInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _commentsLoading = true;
    });
    FeatureRequest? data;
    var comments = const <FlutterRequestComment>[];
    try {
      final results = await Future.wait<Object?>([
        UserGist.getRequest(widget.requestId),
        UserGist.getComments(widget.requestId),
      ]);
      data = results[0] as FeatureRequest?;
      comments = (results[1] as List<FlutterRequestComment>?) ?? const [];
    } on Object catch (error, stack) {
      log.e('request detail load failed', error, stack);
    }
    if (!mounted) return;
    setState(() {
      _data = data;
      _comments = comments;
      _loading = false;
      _commentsLoading = false;
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

  @override
  Widget build(BuildContext context) {
    final theme = _requestsTheme(context, widget.branding);
    final data = _data;
    return _RequestsFrame(
      theme: theme,
      header: SurfaceHeader(
        leading: SurfaceBack(
          key: const ValueKey<String>('request-detail-back'),
          onPressed: () => Navigator.of(context).maybePop(),
          color: theme.text,
          label: 'Back to requests',
        ),
        center: _headerTitle(theme, 'Suggestion'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : data == null
              ? Center(
                  child: SingleChildScrollView(
                    child: _centeredMessage(
                      theme,
                      title: "This suggestion couldn't load",
                      body: 'Check your connection and try again.',
                      action: SurfaceSecondary(
                        onPressed: () => unawaited(_load()),
                        theme: theme,
                        label: 'Try again',
                      ),
                    ),
                  ),
                )
              : _content(theme, data),
      bottom: data == null || _loading ? null : _actionBar(theme, data),
    );
  }

  Widget _content(ResolvedPromptTheme theme, FeatureRequest data) {
    final radius = BorderRadius.circular(math.min(theme.radius, 16));
    final response = data.devResponse;
    final hasResponse = response != null && response.isNotEmpty;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: SurfaceMeasure(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusPill(status: data.status, theme: theme),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                data.title,
                style: theme.textStyle(
                  color: theme.text,
                  fontSize: 24,
                  lineHeight: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _stat(theme, data.upvoteCount, 'upvote', 'upvotes'),
                _stat(theme, data.followerCount, 'follower', 'followers'),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              data.description,
              style: theme.textStyle(color: theme.text, lineHeight: 24),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasResponse ? theme.tint : theme.fill,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasResponse ? 'Update from the team' : 'No update yet',
                    style: theme.textStyle(
                      color: hasResponse ? theme.primary : theme.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasResponse
                        ? response
                        : 'Follow this suggestion to hear when the team '
                            'posts an update.',
                    style: theme.textStyle(
                      color: hasResponse ? theme.text : theme.subtext,
                      fontSize: 15,
                      lineHeight: 22,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: _CommentsSection(
                requestId: widget.requestId,
                theme: theme,
                comments: _comments,
                loading: _commentsLoading,
                onChanged: (next) => setState(() => _comments = next),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ResolvedPromptTheme theme, int value, String one, String many) {
    final noun = value == 1 ? one : many;
    return Semantics(
      label: '$value $many',
      container: true,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$value',
              style: theme.textStyle(
                color: theme.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                tabular: true,
              ),
            ),
            TextSpan(text: ' $noun'),
          ],
        ),
        style: theme.textStyle(color: theme.subtext, fontSize: 15),
      ),
    );
  }

  Widget _actionBar(ResolvedPromptTheme theme, FeatureRequest data) {
    final voted = data.viewerHasUpvoted;
    final following = data.viewerIsFollowing;
    final busy = _requestMutationInFlight;
    final bottom = math.max(MediaQuery.viewPaddingOf(context).bottom, 12.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(top: BorderSide(color: theme.border, width: 0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        child: SurfaceMeasure(
          child: Row(
            children: [
              Expanded(
                child: _ActionPill(
                  key: const ValueKey<String>('request-detail-vote'),
                  label: voted
                      ? 'Upvoted, ${data.upvoteCount}'
                      : 'Upvote, ${data.upvoteCount}',
                  semanticsLabel: busy
                      ? 'Updating request vote'
                      : voted
                          ? 'Remove request vote'
                          : 'Upvote request',
                  selected: voted,
                  background: voted ? theme.primary : theme.tint,
                  foreground: voted ? theme.onPrimary : theme.primary,
                  glyph: SurfaceGlyph.up,
                  theme: theme,
                  onPress: busy ? null : () => unawaited(_toggleVote()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionPill(
                  key: const ValueKey<String>('request-detail-follow'),
                  label: following ? 'Following' : 'Follow',
                  semanticsLabel: busy
                      ? 'Updating request follow'
                      : following
                          ? 'Unfollow request'
                          : 'Follow request',
                  selected: following,
                  background: following ? theme.fill : Colors.transparent,
                  foreground: theme.text,
                  outline: following ? theme.quietOutline : theme.border,
                  theme: theme,
                  onPress: busy ? null : () => unawaited(_toggleFollow()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.background,
    required this.foreground,
    required this.theme,
    required this.onPress,
    this.outline,
    this.glyph,
    super.key,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final Color background;
  final Color foreground;
  final Color? outline;
  final SurfaceGlyph? glyph;
  final ResolvedPromptTheme theme;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final border = outline;
    final shape = StadiumBorder(
      side: border == null
          ? BorderSide.none
          : BorderSide(color: border, width: 1.5),
    );
    final icon = glyph;
    return Semantics(
      button: true,
      enabled: onPress != null,
      selected: selected,
      label: semanticsLabel,
      container: true,
      excludeSemantics: true,
      onTap: onPress,
      child: Material(
        color: background,
        shape: shape,
        child: InkWell(
          onTap: onPress,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    SizedBox(
                      width: 12,
                      height: 10,
                      child: CustomPaint(
                        painter: SurfaceGlyphPainter(
                          icon,
                          foreground,
                          stroke: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        tabular: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
