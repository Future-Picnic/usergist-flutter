part of 'requests_host.dart';

// New suggestion. Close leading, Post trailing in the header so the keyboard
// never covers the action. A failed post shows an inline message.

const int _titleMax = 120;
const int _descriptionMax = 1500;

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onText);
    _descCtrl.addListener(_onText);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit {
    final t = _titleCtrl.text.trim();
    final d = _descCtrl.text.trim();
    return !_submitting &&
        t.isNotEmpty &&
        t.length <= _titleMax &&
        d.isNotEmpty &&
        d.length <= _descriptionMax;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await UserGist.submitRequest(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        setState(() => _error = "Your suggestion wasn't posted. $e");
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _requestsTheme(context, widget.branding);
    final error = _error;
    return _RequestsFrame(
      theme: theme,
      header: SurfaceHeader(
        leading: SurfaceClose(
          key: const ValueKey<String>('request-submit-cancel'),
          onPressed: () => Navigator.of(context).maybePop(),
          color: theme.text,
          label: 'Cancel new suggestion',
        ),
        center: _headerTitle(theme, 'New suggestion'),
        trailing: SurfaceNext(
          key: const ValueKey<String>('request-submit-post'),
          onPressed: () => unawaited(_submit()),
          theme: theme,
          label: 'Post',
          disabled: !_canSubmit,
          loading: _submitting,
          compact: true,
        ),
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: SurfaceMeasure(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share an idea. Others can upvote it, and the team posts '
                'updates as work moves forward.',
                style: theme.textStyle(
                  color: theme.subtext,
                  fontSize: 15,
                  lineHeight: 22,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                SurfaceNotice(message: error, theme: theme),
              ],
              const SizedBox(height: 20),
              _label(theme, 'Title'),
              const SizedBox(height: 8),
              SurfaceField(
                theme: theme,
                controller: _titleCtrl,
                maxLength: _titleMax,
                hintText: 'A short, clear title',
                autofocus: true,
                textInputAction: TextInputAction.next,
                semanticsLabel: 'Suggestion title',
              ),
              const SizedBox(height: 20),
              _label(theme, 'Description'),
              const SizedBox(height: 8),
              SurfaceField(
                theme: theme,
                controller: _descCtrl,
                maxLength: _descriptionMax,
                hintText:
                    'What should it do, who is it for, and why does it matter?',
                multiline: true,
                minHeight: 140,
                semanticsLabel: 'Suggestion description',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ResolvedPromptTheme theme, String text) => Text(
        text,
        style: theme.textStyle(
          color: theme.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );
}
