part of 'survey_presenter.dart';

// Full-screen survey. Header: when Back is usable it takes the leading slot
// and Close moves to the trailing slot; otherwise Close is leading and the
// trailing slot stays empty. Progress stays centred. Next/Submit (or the end
// CTA) is one full-width action in a readable-width footer outside the
// scrolling question, above the keyboard, in portrait and landscape alike.

class _SurveyScreen extends StatefulWidget {
  const _SurveyScreen({
    required this.request,
    required this.themeOverrides,
    required this.onSaveProgress,
    required this.onCompleteAttempt,
    required this.onAbandonAttempt,
    required this.onShown,
    required this.onComplete,
    required this.onAbandon,
  });

  final SurveyShowRequest request;
  final PromptTheme? themeOverrides;
  final Future<void> Function(
    String attemptId,
    String? currentQuestionId,
    Map<String, Object?> answers,
  ) onSaveProgress;
  final Future<bool> Function(
    String attemptId,
    Map<String, Object?> answers,
  ) onCompleteAttempt;
  final Future<bool> Function(String attemptId) onAbandonAttempt;
  final ValueChanged<String> onShown;
  final void Function(String surveyId, String attemptId) onComplete;
  final void Function(String surveyId, String attemptId) onAbandon;

  @override
  State<_SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<_SurveyScreen> {
  late Map<String, Object?> _answers;
  late String? _currentId;
  final List<String> _history = <String>[];
  Timer? _saveTimer;
  bool _ended = false;
  bool _submitting = false;
  String? _error;
  bool _retryable = false;
  TextEditingController? _textController;
  List<SurveyChoice>? _ranking;

  SurveyCampaignWithFlow get _survey => widget.request.survey;
  SurveyAttemptSession get _attempt => widget.request.attempt;
  SurveyFlow get _flow => _survey.flow;
  SurveyQuestion? get _current {
    final index =
        _flow.questions.indexWhere((question) => question.id == _currentId);
    return index < 0 ? null : _flow.questions[index];
  }

  @override
  void initState() {
    super.initState();
    _answers = Map<String, Object?>.from(_attempt.progressSnapshot);
    _currentId = _attempt.currentQuestionId ?? _attempt.startQuestionId;
    _prepareQuestionState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown(_survey.id);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _textController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ResolvedPromptTheme.of(
      context,
      serverTheme: _survey.theme,
      overrides: widget.themeOverrides,
    );
    final layout = SurfaceLayout.of(context);
    final landscape = layout.landscape;
    final question = _current;
    final needsNext =
        !_ended && question != null && !_autoAdvances(question.type);
    final canGoBack = _flow.backNavigation &&
        _history.isNotEmpty &&
        !_ended &&
        !_submitting;
    final back = canGoBack
        ? SurfaceBack(
            key: const ValueKey<String>('survey-back'),
            onPressed: _goBack,
            color: theme.text,
          )
        : null;
    final next = question == null
        ? null
        : SurfaceNext(
            key: const ValueKey<String>('survey-next'),
            onPressed: () => unawaited(_advance()),
            theme: theme,
            label: _isFinal(question) ? 'Submit' : 'Next',
            disabled: !_inlineNextEnabled(question),
            loading: _submitting,
            expand: true,
          );
    final endCta = _ended ? _endAction(theme) : null;
    final close = SurfaceClose(
      key: const ValueKey<String>('survey-close'),
      onPressed: _ended
          ? () => Navigator.of(context).pop()
          : () => unawaited(_requestClose()),
      color: theme.text,
    );
    final footerAction = endCta ?? (needsNext ? next : null);
    final footerBottom =
        layout.keyboard > 0 ? 12.0 : math.max(layout.safe.bottom, 16.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.background.computeLuminance() > 0.5
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _ended,
        onPopInvoked: (didPop) {
          if (!didPop) unawaited(_requestClose());
        },
        child: Scaffold(
          backgroundColor: theme.background,
          body: Padding(
            padding: EdgeInsets.only(
              left: layout.safe.left,
              right: layout.safe.right,
            ),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    layout.safe.top + (landscape ? 8 : 4),
                    12,
                    4,
                  ),
                  child: SurfaceHeader(
                    leading: back ?? close,
                    center: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _progress(theme),
                      ),
                    ),
                    trailing: back != null ? close : null,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    ),
                    child: _ended
                        ? _endScreen(theme, landscape)
                        : _questionScreen(theme, landscape),
                  ),
                ),
                if (footerAction != null)
                  Padding(
                    key: const ValueKey<String>('survey-footer'),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      landscape ? 6 : 8,
                      24,
                      footerBottom,
                    ),
                    child: SurfaceMeasure(child: footerAction),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(ResolvedPromptTheme theme) {
    if (_ended || _flow.progressStyle == 'none') {
      return const SizedBox.shrink();
    }
    final index = _flow.questions.indexWhere((q) => q.id == _currentId);
    final step = index < 0 ? 0 : index;
    final total = _flow.questions.length;
    if (_flow.progressStyle == 'dots') {
      return Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: List<Widget>.generate(
          total,
          (dot) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: dot == step ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: dot <= step ? theme.primary : theme.fillStrong,
            ),
          ),
        ),
      );
    }
    final value = total == 0 ? 0.0 : ((step + 1) / total).clamp(0.0, 1.0);
    return Semantics(
      label: 'Progress',
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: ColoredBox(color: theme.fillStrong)),
              FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionScreen(ResolvedPromptTheme theme, bool landscape) {
    final question = _current;
    if (question == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This survey is unavailable.',
            textAlign: TextAlign.center,
            style: theme.textStyle(color: theme.text),
          ),
        ),
      );
    }
    final error = _error;
    return SingleChildScrollView(
      key: ValueKey<String>(question.id),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        24,
        landscape ? 8 : 24,
        24,
        landscape ? 24 : 40,
      ),
      child: SurfaceMeasure(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SurveyQuestionBody(
              question: question,
              answer: _answers[question.id],
              theme: theme,
              onAnswer: (value) => _setAnswer(question.id, value),
              onAnswerAndAdvance: (value) =>
                  _setAndAdvance(question.id, value),
              onRating: (value) => _setRatingAndAdvance(question.id, value),
              onPickDate: () => unawaited(_pickDate(question)),
              textController: _textController,
              ranking: _ranking,
              onRankingChanged: (order) {
                setState(() => _ranking = order);
                _setAnswer(
                  question.id,
                  order.map((choice) => choice.id).toList(growable: false),
                );
              },
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 20),
              SurfaceNotice(
                message: error,
                theme: theme,
                action: _retryable
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SurfaceSecondary(
                          key: const ValueKey<String>('survey-retry'),
                          onPressed: () => unawaited(_advance()),
                          theme: theme,
                          label: 'Try again',
                          compact: true,
                        ),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _endScreen(ResolvedPromptTheme theme, bool landscape) {
    final end = _survey.endScreen ?? _flow.endScreen;
    final body = end?.body;
    return Center(
      key: const ValueKey<String>('survey-complete'),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, landscape ? 8 : 24, 24, 24),
        child: SurfaceMeasure(
          child: Column(
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration:
                    BoxDecoration(color: theme.tint, shape: BoxShape.circle),
                child: CustomPaint(painter: _EndTickPainter(theme.primary)),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  end?.headline ?? 'Thanks!',
                  textAlign: TextAlign.center,
                  style: theme.textStyle(
                    color: theme.text,
                    fontSize: 24,
                    lineHeight: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (body != null && body.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textStyle(
                      color: theme.subtext,
                      lineHeight: 24,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _endAction(ResolvedPromptTheme theme) {
    final end = _survey.endScreen ?? _flow.endScreen;
    final cta = end?.cta;
    return SurfaceNext(
      key: const ValueKey<String>('survey-complete-close'),
      onPressed: () => unawaited(_endCta(cta)),
      theme: theme,
      label: cta?.label ?? 'Done',
      expand: true,
    );
  }

  void _setAnswer(String questionId, Object? value, {bool notify = true}) {
    if (notify) {
      setState(() {
        _answers[questionId] = value;
        _error = null;
        _retryable = false;
      });
    } else {
      _answers[questionId] = value;
      _error = null;
      _retryable = false;
    }
    _scheduleSave();
  }

  void _setAndAdvance(String questionId, Object value) {
    _setAnswer(questionId, value);
    unawaited(_advance());
  }

  void _setRatingAndAdvance(String questionId, int value) {
    _setAnswer(questionId, value);
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted && _currentId == questionId) unawaited(_advance());
    });
  }

  bool _autoAdvances(String type) =>
      type == 'single_choice' ||
      type == 'rating' ||
      type == 'nps' ||
      type == 'likert';

  bool _inlineNextEnabled(SurveyQuestion question) {
    if (question.type != 'short_text' && question.type != 'long_text') {
      return true;
    }
    return _answered(_answers[question.id]);
  }

  bool _isFinal(SurveyQuestion question) =>
      _flow.nextQuestionId(question.id, _answers) == null;

  Future<void> _advance() async {
    final question = _current;
    if (question == null || _submitting) return;
    if (question.type == 'ranking' && !_answers.containsKey(question.id)) {
      _answers[question.id] = (_ranking ?? question.items)
          .map((choice) => choice.id)
          .toList(growable: false);
    }
    if (question.type == 'info_screen') {
      _answers[question.id] = '';
    }
    final answer = _answers[question.id];
    if (question.required && !_answered(answer)) {
      setState(() {
        _error = 'Answer this question to continue.';
        _retryable = false;
      });
      return;
    }
    if (question.type == 'multi_choice') {
      final count = (answer as List<Object?>?)?.length ?? 0;
      if (question.minSelections != null && count < question.minSelections!) {
        setState(() {
          _error = 'Select at least ${question.minSelections} options.';
          _retryable = false;
        });
        return;
      }
    }
    final next = _flow.nextQuestionId(question.id, _answers);
    if (next == null) {
      await _complete();
      return;
    }
    setState(() {
      _history.add(question.id);
      _currentId = next;
      _error = null;
      _retryable = false;
      _prepareQuestionState();
    });
    _scheduleSave();
  }

  void _goBack() {
    if (_history.isEmpty) return;
    setState(() {
      _currentId = _history.removeLast();
      _error = null;
      _retryable = false;
      _prepareQuestionState();
    });
  }

  void _prepareQuestionState() {
    _textController?.dispose();
    _textController = null;
    _ranking = null;
    final question = _current;
    if (question == null) return;
    if (question.type == 'short_text' || question.type == 'long_text') {
      _textController = TextEditingController(
        text: _answers[question.id] as String? ?? '',
      );
    } else if (question.type == 'ranking') {
      final order = (_answers[question.id] as List<Object?>?)
          ?.whereType<String>()
          .toList();
      if (order != null && order.isNotEmpty) {
        final byId = <String, SurveyChoice>{
          for (final item in question.items) item.id: item,
        };
        _ranking =
            order.map((id) => byId[id]).whereType<SurveyChoice>().toList();
      } else {
        _ranking = <SurveyChoice>[...question.items];
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(
        widget.onSaveProgress(
          _attempt.attemptId,
          _currentId,
          Map<String, Object?>.from(_answers),
        ),
      );
    });
  }

  Future<void> _complete() async {
    setState(() {
      _submitting = true;
      _error = null;
      _retryable = false;
    });
    final delivered = await widget.onCompleteAttempt(
      _attempt.attemptId,
      Map<String, Object?>.from(_answers),
    );
    if (!mounted) return;
    if (!delivered) {
      setState(() {
        _submitting = false;
        _error = 'Your answers are saved on this device. '
            'Check your connection and try again.';
        _retryable = true;
      });
      return;
    }
    widget.onComplete(_survey.id, _attempt.attemptId);
    setState(() {
      _submitting = false;
      _ended = true;
    });
  }

  Future<void> _requestClose() async {
    final theme = ResolvedPromptTheme.of(
      context,
      serverTheme: _survey.theme,
      overrides: widget.themeOverrides,
    );
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: theme.scrim,
      builder: (context) => _LeaveSurveyDialog(theme: theme),
    );
    if (leave != true || !mounted) return;
    await widget.onAbandonAttempt(_attempt.attemptId);
    if (!mounted) return;
    widget.onAbandon(_survey.id, _attempt.attemptId);
    Navigator.of(context).pop();
  }

  Future<void> _pickDate(SurveyQuestion question) async {
    final current = DateTime.tryParse(_answers[question.id] as String? ?? '');
    final min = DateTime.tryParse(question.minDate ?? '') ?? DateTime(1900);
    final max = DateTime.tryParse(question.maxDate ?? '') ?? DateTime(2100);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(current ?? DateTime.now(), min, max),
      firstDate: min,
      lastDate: max,
    );
    if (picked == null) return;
    _setAnswer(
      question.id,
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _endCta(SurveyEndCta? cta) async {
    final target = cta?.target;
    if ((cta?.kind == 'url' || cta?.kind == 'deep_link') && target != null) {
      final uri = Uri.tryParse(target);
      if (uri != null && uri.hasScheme) await launchUrl(uri);
    }
    if (mounted) Navigator.of(context).pop();
  }

  bool _answered(Object? value) {
    if (value == null) return false;
    if (value is String) return value.isNotEmpty;
    if (value is Iterable<Object?>) return value.isNotEmpty;
    return true;
  }

  DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
    if (value.isBefore(minimum)) return minimum;
    if (value.isAfter(maximum)) return maximum;
    return value;
  }
}

/// Themed confirmation before abandoning an unfinished survey.
class _LeaveSurveyDialog extends StatelessWidget {
  const _LeaveSurveyDialog({required this.theme});

  final ResolvedPromptTheme theme;

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
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Leave this survey?',
                  style: theme.textStyle(
                    color: theme.text,
                    fontSize: 19,
                    lineHeight: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your answers so far are saved, and the survey is marked '
                'as not finished.',
                style: theme.textStyle(
                  color: theme.subtext,
                  fontSize: 15,
                  lineHeight: 22,
                ),
              ),
              const SizedBox(height: 20),
              SurfaceNext(
                onPressed: () => Navigator.of(context).pop(false),
                theme: theme,
                label: 'Keep answering',
                expand: true,
              ),
              const SizedBox(height: 10),
              SurfaceSecondary(
                onPressed: () => Navigator.of(context).pop(true),
                theme: theme,
                label: 'Leave survey',
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndTickPainter extends CustomPainter {
  const _EndTickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(c.dx - 12, c.dy + 1)
      ..lineTo(c.dx - 3.5, c.dy + 9)
      ..lineTo(c.dx + 13, c.dy - 8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EndTickPainter old) => old.color != color;
}
