part of 'requests_host.dart';

// Board: header, status filters, list and empty/error states. Theme colours
// only; status dots keep their semantic colours.

class _BoardScreen extends StatefulWidget {
  const _BoardScreen({required this.branding});
  final _Branding branding;

  @override
  State<_BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<_BoardScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  List<RequestSummary> _items = const [];
  RequestStatus? _filter;
  final Set<String> _voteInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = _items.isEmpty);
    try {
      final r = await UserGist.getRequests(
        options: const GetRequestsOptions(sort: RequestSort.top, limit: 50),
      );
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _loading = false;
        _loadFailed = false;
      });
    } on Object catch (error, stack) {
      log.e('requests board load failed', error, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
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

  Future<void> _openSubmit() async {
    final navigator = Navigator.of(context);
    final created = await navigator.push<FeatureRequest?>(
      MaterialPageRoute<FeatureRequest?>(
        builder: (_) => _SubmitScreen(branding: widget.branding),
      ),
    );
    if (created != null && mounted) {
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _DetailScreen(
              requestId: created.id,
              branding: widget.branding,
            ),
          ),
        ),
      );
      unawaited(_load());
    }
  }

  void _openDetail(String id) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _DetailScreen(
            requestId: id,
            branding: widget.branding,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _requestsTheme(context, widget.branding);
    final count = _items.length;
    return _RequestsFrame(
      theme: theme,
      header: SurfaceHeader(
        leading: SurfaceClose(
          key: const ValueKey<String>('requests-board-close'),
          onPressed: () => Navigator.of(context).maybePop(),
          color: theme.text,
          label: 'Close requests board',
        ),
        center: _headerTitle(
          theme,
          widget.branding.entryLabel,
          sub: '$count ${count == 1 ? 'idea' : 'ideas'}',
        ),
        trailing: SurfaceNext(
          key: const ValueKey<String>('requests-board-create'),
          onPressed: () => unawaited(_openSubmit()),
          theme: theme,
          label: 'New idea',
          compact: true,
        ),
      ),
      body: _body(theme),
    );
  }

  Widget _body(ResolvedPromptTheme theme) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.primary));
    }
    if (_loadFailed && _items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: _centeredMessage(
            theme,
            title: "Suggestions couldn't load",
            body: 'Check your connection and try again.',
            action: SurfaceSecondary(
              onPressed: () => unawaited(_load()),
              theme: theme,
              label: 'Try again',
            ),
          ),
        ),
      );
    }
    final filtered = _filter == null
        ? _items
        : _items.where((i) => i.status == _filter).toList(growable: false);
    return Column(
      children: <Widget>[
        if (_items.isNotEmpty) _filters(theme),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: theme.primary,
            backgroundColor: theme.background,
            child: filtered.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(child: _emptyState(theme)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      return Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: _listMaxWidth),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RequestCard(
                              item: item,
                              theme: theme,
                              voteEnabled: !_voteInFlight.contains(item.id),
                              onUpvote: () => unawaited(_toggleVote(item)),
                              onOpen: () => _openDetail(item.id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _filters(ResolvedPromptTheme theme) {
    final counts = <RequestStatus, int>{
      for (final s in RequestStatus.values) s: 0,
    };
    for (final item in _items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          _FilterChip(
            label: 'All',
            count: _items.length,
            active: _filter == null,
            theme: theme,
            onTap: () => setState(() => _filter = null),
          ),
          for (final status in _statusLabels.keys)
            if ((counts[status] ?? 0) > 0) ...<Widget>[
              const SizedBox(width: 8),
              _FilterChip(
                label: _statusLabels[status]!,
                count: counts[status]!,
                active: _filter == status,
                dot: _statusColors[status],
                theme: theme,
                onTap: () => setState(() => _filter = status),
              ),
            ],
        ],
      ),
    );
  }

  Widget _emptyState(ResolvedPromptTheme theme) {
    if (_items.isNotEmpty) {
      return _centeredMessage(
        theme,
        title: 'Nothing with this status',
        body: 'Choose All to see every suggestion.',
      );
    }
    return _centeredMessage(
      theme,
      title: 'No suggestions yet',
      body: 'Share the first idea for making this app better.',
      action: SurfaceNext(
        onPressed: () => unawaited(_openSubmit()),
        theme: theme,
        label: 'Share an idea',
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.theme,
    required this.onTap,
    this.dot,
  });

  final String label;
  final int count;
  final bool active;
  final ResolvedPromptTheme theme;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: active ? theme.primary : theme.border,
        width: 1.5,
      ),
    );
    final dotColor = dot;
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $count',
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: active ? theme.tint : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (dotColor != null) ...<Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textStyle(
                    color: active ? theme.primary : theme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: theme.textStyle(
                    color: active ? theme.primary : theme.subtext,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.theme,
    required this.voteEnabled,
    required this.onUpvote,
    required this.onOpen,
  });
  final RequestSummary item;
  final ResolvedPromptTheme theme;
  final bool voteEnabled;
  final VoidCallback onUpvote;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(math.min(theme.radius, 18));
    final followers = item.followerCount;
    return Semantics(
      container: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.border),
        ),
        child: InkWell(
          onTap: onOpen,
          borderRadius: radius,
          highlightColor: theme.fill,
          splashColor: theme.fill,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UpvoteButton(
                  count: item.upvoteCount,
                  active: item.viewerHasUpvoted,
                  theme: theme,
                  semanticsLabel: voteEnabled
                      ? item.viewerHasUpvoted
                          ? 'Remove vote from ${item.title}'
                          : 'Upvote ${item.title}'
                      : 'Updating vote for ${item.title}',
                  onPress: voteEnabled ? onUpvote : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Semantics(
                    label: 'Open request ${item.title}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyle(
                            color: theme.text,
                            lineHeight: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyle(
                            color: theme.subtext,
                            fontSize: 14,
                            lineHeight: 20,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _StatusPill(status: item.status, theme: theme),
                            Text(
                              item.viewerIsFollowing
                                  ? 'Following'
                                  : '$followers ${followers == 1 ? 'follower' : 'followers'}',
                              style: theme.textStyle(
                                color: theme.subtext,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    required this.theme,
    required this.semanticsLabel,
    required this.onPress,
  });
  final int count;
  final bool active;
  final ResolvedPromptTheme theme;
  final String semanticsLabel;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final fg = active ? theme.onPrimary : theme.primary;
    final radius = BorderRadius.circular(theme.cellRadius);
    return Semantics(
      button: true,
      enabled: onPress != null,
      selected: active,
      label: semanticsLabel,
      container: true,
      excludeSemantics: true,
      onTap: onPress,
      child: Material(
        color: active ? theme.primary : theme.tint,
        borderRadius: radius,
        child: InkWell(
          onTap: onPress,
          borderRadius: radius,
          child: Container(
            width: 52,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 10,
                  child: CustomPaint(
                    painter: SurfaceGlyphPainter(SurfaceGlyph.up, fg, stroke: 2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: theme.textStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
