part of 'requests_host.dart';

// Comments list and composer beneath a suggestion. The viewer can edit or
// delete their own comments through the existing SDK calls; every change is
// optimistic and reverts with a message if the server refuses it.

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.requestId,
    required this.theme,
    required this.comments,
    required this.loading,
    required this.onChanged,
  });

  final String requestId;
  final ResolvedPromptTheme theme;
  final List<FlutterRequestComment> comments;
  final bool loading;
  final ValueChanged<List<FlutterRequestComment>> onChanged;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final TextEditingController _draft = TextEditingController();
  bool _posting = false;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraft);
  }

  @override
  void dispose() {
    _draft
      ..removeListener(_onDraft)
      ..dispose();
    super.dispose();
  }

  void _onDraft() {
    if (mounted) setState(() {});
  }

  bool get _canPost {
    final body = _draft.text.trim();
    return !_posting && body.isNotEmpty && body.length <= _commentMax;
  }

  void _notify(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _post() async {
    final body = _draft.text.trim();
    if (!_canPost) return;
    setState(() => _posting = true);
    _draft.clear();
    try {
      final c = await UserGist.postComment(widget.requestId, body);
      if (c != null && mounted) {
        widget.onChanged(<FlutterRequestComment>[...widget.comments, c]);
      }
    } catch (error) {
      if (mounted) {
        if (_draft.text.isEmpty) _draft.text = body;
        _notify('Could not post: $error');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _saveEdit(FlutterRequestComment comment, String body) async {
    final before = widget.comments;
    widget.onChanged(
      before
          .map(
            (c) => c.id == comment.id
                ? FlutterRequestComment(
                    id: c.id,
                    requestId: c.requestId,
                    body: body,
                    authorAnonymousId: c.authorAnonymousId,
                    authorExternalId: c.authorExternalId,
                    viewerIsAuthor: c.viewerIsAuthor,
                    createdAt: c.createdAt,
                    updatedAt: DateTime.now().toUtc().toIso8601String(),
                  )
                : c,
          )
          .toList(growable: false),
    );
    setState(() => _editingId = null);
    try {
      final updated =
          await UserGist.editComment(widget.requestId, comment.id, body);
      if (updated != null && mounted) {
        widget.onChanged(
          widget.comments
              .map((c) => c.id == comment.id ? updated : c)
              .toList(growable: false),
        );
      }
    } catch (error) {
      if (!mounted) return;
      widget.onChanged(before);
      _notify('Could not save: $error');
    }
  }

  Future<void> _delete(FlutterRequestComment comment) async {
    final theme = widget.theme;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: theme.scrim,
      builder: (context) => _ConfirmDialog(
        theme: theme,
        title: 'Delete comment?',
        body: 'This cannot be undone.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirmed != true || !mounted) return;
    final before = widget.comments;
    widget.onChanged(
      before.where((c) => c.id != comment.id).toList(growable: false),
    );
    try {
      final deleted =
          await UserGist.deleteComment(widget.requestId, comment.id);
      if (!deleted && mounted) {
        widget.onChanged(before);
        _notify('Could not delete this comment.');
      }
    } catch (error) {
      if (!mounted) return;
      widget.onChanged(before);
      _notify('Could not delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final comments = widget.comments;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              comments.isEmpty ? 'Comments' : 'Comments (${comments.length})',
              style: theme.textStyle(
                color: theme.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SurfaceField(
            key: const ValueKey<String>('request-comment-input'),
            theme: theme,
            controller: _draft,
            hintText: 'Add a comment',
            maxLength: _commentMax,
            multiline: true,
            minHeight: 72,
            semanticsLabel: 'Request comment',
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SurfaceNext(
              key: const ValueKey<String>('request-comment-post'),
              onPressed: () => unawaited(_post()),
              theme: theme,
              label: 'Post comment',
              disabled: !_canPost,
              loading: _posting,
              compact: true,
            ),
          ),
          if (widget.loading)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: CircularProgressIndicator(color: theme.primary),
              ),
            )
          else if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'No comments yet. Start the conversation.',
                style: theme.textStyle(
                  color: theme.subtext,
                  fontSize: 15,
                  lineHeight: 21,
                ),
              ),
            )
          else
            for (final c in comments)
              _CommentRow(
                key: ValueKey<String>(c.id),
                comment: c,
                theme: theme,
                editing: _editingId == c.id,
                onStartEdit: () => setState(() => _editingId = c.id),
                onCancelEdit: () => setState(() => _editingId = null),
                onSave: (body) => unawaited(_saveEdit(c, body)),
                onDelete: () => unawaited(_delete(c)),
              ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.comment,
    required this.theme,
    required this.editing,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
    required this.onDelete,
    super.key,
  });

  final FlutterRequestComment comment;
  final ResolvedPromptTheme theme;
  final bool editing;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<String> onSave;
  final VoidCallback onDelete;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  late final TextEditingController _edit =
      TextEditingController(text: widget.comment.body);

  @override
  void initState() {
    super.initState();
    _edit.addListener(_onEdit);
  }

  @override
  void didUpdateWidget(_CommentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editing && _edit.text != widget.comment.body) {
      _edit.text = widget.comment.body;
    }
  }

  @override
  void dispose() {
    _edit
      ..removeListener(_onEdit)
      ..dispose();
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final c = widget.comment;
    final mine = c.viewerIsAuthor;
    final edited = c.updatedAt != null && c.updatedAt != c.createdAt;
    final trimmed = _edit.text.trim();
    final canSave = trimmed.isNotEmpty && trimmed.length <= _commentMax;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: mine ? theme.tint : theme.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  mine ? 'You' : 'Anonymous',
                  style: theme.textStyle(
                    color: mine ? theme.primary : theme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_formatRelative(c.createdAt)}${edited ? ', edited' : ''}',
                  style: theme.textStyle(color: theme.subtext, fontSize: 13),
                ),
              ),
              if (mine && !widget.editing) _menu(theme),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.editing) ...[
            SurfaceField(
              theme: theme,
              controller: _edit,
              maxLength: _commentMax,
              multiline: true,
              minHeight: 72,
              autofocus: true,
              semanticsLabel: 'Edit comment',
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SurfaceSecondary(
                  onPressed: widget.onCancelEdit,
                  theme: theme,
                  label: 'Cancel',
                  compact: true,
                ),
                const SizedBox(width: 8),
                SurfaceNext(
                  onPressed: () => widget.onSave(trimmed),
                  theme: theme,
                  label: 'Save',
                  disabled: !canSave,
                  compact: true,
                ),
              ],
            ),
          ] else
            Semantics(
              label: 'Request comment body: ${c.body}',
              container: true,
              excludeSemantics: true,
              child: Text(
                c.body,
                style: theme.textStyle(
                  color: theme.text,
                  fontSize: 15,
                  lineHeight: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _menu(ResolvedPromptTheme theme) {
    return PopupMenuButton<String>(
      key: const ValueKey<String>('request-comment-actions'),
      tooltip: 'Comment actions',
      color: theme.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.fieldRadius),
        side: BorderSide(color: theme.border, width: 0.5),
      ),
      onSelected: (value) {
        if (value == 'edit') widget.onStartEdit();
        if (value == 'delete') widget.onDelete();
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: Text('Edit', style: theme.textStyle(color: theme.text)),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete', style: theme.textStyle(color: theme.text)),
        ),
      ],
      child: SizedBox(
        width: 44,
        height: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.subtext,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.theme,
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final ResolvedPromptTheme theme;
  final String title;
  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: theme.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textStyle(
                  color: theme.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textStyle(
                  color: theme.subtext,
                  fontSize: 15,
                  lineHeight: 22,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SurfaceSecondary(
                    onPressed: () => Navigator.of(context).pop(false),
                    theme: theme,
                    label: 'Cancel',
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  SurfaceNext(
                    onPressed: () => Navigator.of(context).pop(true),
                    theme: theme,
                    label: confirmLabel,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
