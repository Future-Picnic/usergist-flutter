import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../internal/logger.dart';
import '../models/survey.dart';
import '../models/theme.dart';
import 'theme_resolver.dart';
import 'modal_coordinator.dart';

class SurveyShowRequest {
  const SurveyShowRequest({
    required this.survey,
    required this.attempt,
    required this.source,
  });

  final SurveyCampaignWithFlow survey;
  final SurveyAttemptSession attempt;
  final String source;
}

/// Owns the host Navigator context and serializes native survey routes.
class SurveyPresenter {
  SurveyPresenter({
    required this.stream,
    required this.onSaveProgress,
    required this.onCompleteAttempt,
    required this.onAbandonAttempt,
    required this.onShown,
    required this.onPresentationFailed,
    required this.onComplete,
    required this.onAbandon,
    required this.coordinator,
    this.themeOverrides,
  });

  final Stream<SurveyShowRequest> stream;
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
  final ValueChanged<String> onPresentationFailed;
  final void Function(String surveyId, String attemptId) onComplete;
  final void Function(String surveyId, String attemptId) onAbandon;
  final SdkModalCoordinator coordinator;
  PromptTheme? themeOverrides;

  StreamSubscription<SurveyShowRequest>? _subscription;
  BuildContext? _context;
  final List<SurveyShowRequest> _pending = <SurveyShowRequest>[];
  bool _isPresenting = false;
  bool _routeActive = false;

  void attach(BuildContext context) {
    _context = context;
    _subscription ??= stream.listen((request) {
      _pending.add(request);
      unawaited(_drain());
    });
    unawaited(_drain());
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    _context = null;
    for (final request in _pending) {
      onPresentationFailed(request.survey.id);
    }
    _pending.clear();
    _isPresenting = false;
  }

  /// Clears queued surveys and closes the active SDK survey route without
  /// emitting an abandon lifecycle event.
  Future<void> reset() async {
    _pending.clear();
    final context = _context;
    if (!_routeActive || context == null || !context.mounted) return;
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  void updateThemeOverrides(PromptTheme? theme) {
    themeOverrides = theme;
  }

  Future<void> _drain() async {
    final context = _context;
    if (_isPresenting ||
        _pending.isEmpty ||
        context == null ||
        !context.mounted) {
      return;
    }
    _isPresenting = true;
    final request = _pending.removeAt(0);
    try {
      await coordinator.schedule(() async {
        if (!context.mounted) {
          _pending.insert(0, request);
          return;
        }
        _routeActive = true;
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _SurveyScreen(
              request: request,
              themeOverrides: themeOverrides,
              onSaveProgress: onSaveProgress,
              onCompleteAttempt: onCompleteAttempt,
              onAbandonAttempt: onAbandonAttempt,
              onShown: onShown,
              onComplete: onComplete,
              onAbandon: onAbandon,
            ),
          ),
        );
        _routeActive = false;
      });
    } on Object catch (error, stack) {
      onPresentationFailed(request.survey.id);
      log.e('survey presentation failed', error, stack);
    } finally {
      _routeActive = false;
      _isPresenting = false;
      unawaited(_drain());
    }
  }
}

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
    return PopScope(
      canPop: _ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          foregroundColor: theme.text,
          elevation: 0,
          leading: _flow.backNavigation && _history.isNotEmpty && !_ended
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          automaticallyImplyLeading: false,
          actions: <Widget>[
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed:
                  _ended ? () => Navigator.of(context).pop() : _requestClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              _progress(theme),
              Expanded(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  child: _ended ? _endScreen(theme) : _questionScreen(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress(ResolvedPromptTheme theme) {
    if (_ended || _flow.progressStyle == 'none') {
      return const SizedBox(height: 4);
    }
    final index = _flow.questions.indexWhere((q) => q.id == _currentId);
    final value = _flow.questions.isEmpty
        ? 0.0
        : ((index < 0 ? 0 : index) + 1) / _flow.questions.length;
    if (_flow.progressStyle == 'dots') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          spacing: 6,
          children: List<Widget>.generate(
            _flow.questions.length,
            (dot) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot <= index ? theme.primary : theme.border,
              ),
            ),
          ),
        ),
      );
    }
    return LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: 4,
      color: theme.primary,
      backgroundColor: theme.border,
    );
  }

  Widget _questionScreen(ResolvedPromptTheme theme) {
    final question = _current;
    if (question == null) {
      return Center(
        child: Text(
          'This survey is unavailable.',
          style: TextStyle(color: theme.text),
        ),
      );
    }
    return SingleChildScrollView(
      key: ValueKey<String>(question.id),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (question.imageUrl case final imageUrl?) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(theme.radius),
                  child: Image.network(
                    imageUrl,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                question.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: theme.text,
                      fontFamily: theme.fontFamily,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (question.subtitle case final subtitle?) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: theme.subtext,
                        fontFamily: theme.fontFamily,
                      ),
                ),
              ],
              const SizedBox(height: 24),
              _input(question, theme),
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (!_autoAdvances(question.type)) ...<Widget>[
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: _contrastOn(theme.primary),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _submitting ? null : _advance,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          question.type == 'info_screen' ? 'Continue' : 'Next',
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(SurveyQuestion question, ResolvedPromptTheme theme) {
    final answer = _answers[question.id];
    switch (question.type) {
      case 'single_choice':
        return Column(
          children: question.options
              .map(
                (option) => RadioListTile<String>(
                  value: option.id,
                  groupValue: answer as String?,
                  title: Text(option.label),
                  activeColor: theme.primary,
                  onChanged: (value) {
                    if (value != null) _setAndAdvance(question.id, value);
                  },
                ),
              )
              .toList(growable: false),
        );
      case 'multi_choice':
        final selected =
            (answer as List<Object?>?)?.whereType<String>().toSet() ??
                <String>{};
        return Column(
          children: question.options.map((option) {
            final checked = selected.contains(option.id);
            return CheckboxListTile(
              value: checked,
              title: Text(option.label),
              activeColor: theme.primary,
              onChanged: (_) {
                final next = <String>{...selected};
                if (checked) {
                  next.remove(option.id);
                } else if (question.maxSelections == null ||
                    next.length < question.maxSelections!) {
                  next.add(option.id);
                }
                _setAnswer(question.id, next.toList(growable: false));
              },
            );
          }).toList(growable: false),
        );
      case 'rating':
      case 'nps':
        final start = question.type == 'nps' ? 0 : 1;
        final end = question.type == 'nps' ? 10 : (question.scale ?? 5);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var value = start; value <= end; value++)
              ChoiceChip(
                label: Text('$value'),
                selected: answer == value,
                selectedColor: theme.primary,
                onSelected: (_) => _setAndAdvance(question.id, value),
              ),
          ],
        );
      case 'likert':
        final labels = question.labels.isEmpty
            ? const <String>[
                'Strongly disagree',
                'Disagree',
                'Neutral',
                'Agree',
                'Strongly agree',
              ]
            : question.labels;
        return Column(
          children: labels.indexed
              .map(
                (entry) => RadioListTile<int>(
                  value: entry.$1 + 1,
                  groupValue: answer as int?,
                  title: Text(entry.$2),
                  activeColor: theme.primary,
                  onChanged: (value) {
                    if (value != null) _setAndAdvance(question.id, value);
                  },
                ),
              )
              .toList(growable: false),
        );
      case 'short_text':
      case 'long_text':
        return TextField(
          controller: _textController,
          minLines: question.type == 'long_text' ? 4 : 1,
          maxLines: question.type == 'long_text' ? 8 : 3,
          maxLength: question.maxLength,
          decoration: InputDecoration(
            hintText: question.placeholder,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => _setAnswer(question.id, value),
        );
      case 'ranking':
        final ranking = _ranking ?? question.items;
        return ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ranking.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = ranking.removeAt(oldIndex);
              ranking.insert(newIndex, item);
              _ranking = ranking;
              _setAnswer(
                question.id,
                ranking.map((choice) => choice.id).toList(growable: false),
                notify: false,
              );
            });
          },
          itemBuilder: (_, index) => ListTile(
            key: ValueKey<String>(ranking[index].id),
            leading: Text('${index + 1}'),
            title: Text(ranking[index].label),
            trailing: const Icon(Icons.drag_handle),
          ),
        );
      case 'single_date':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(answer as String? ?? 'Choose a date'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDate(question),
        );
      case 'info_screen':
        return Text(
          question.body ?? '',
          style: TextStyle(color: theme.subtext, height: 1.45),
        );
      default:
        return Text('Unsupported question type: ${question.type}');
    }
  }

  Widget _endScreen(ResolvedPromptTheme theme) {
    final end = _survey.endScreen ?? _flow.endScreen;
    final cta = end?.cta;
    return Center(
      key: const ValueKey<String>('survey-complete'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: <Widget>[
              Icon(Icons.check_circle, color: theme.primary, size: 56),
              const SizedBox(height: 20),
              Text(
                end?.headline ?? 'Thanks for your feedback',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (end?.body case final body?) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.subtext),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: _contrastOn(theme.primary),
                  minimumSize: const Size(180, 48),
                ),
                onPressed: () => _endCta(cta),
                child: Text(cta?.label ?? 'Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setAnswer(String questionId, Object? value, {bool notify = true}) {
    if (notify) {
      setState(() {
        _answers[questionId] = value;
        _error = null;
      });
    } else {
      _answers[questionId] = value;
      _error = null;
    }
    _scheduleSave();
  }

  void _setAndAdvance(String questionId, Object value) {
    _setAnswer(questionId, value);
    unawaited(_advance());
  }

  bool _autoAdvances(String type) =>
      type == 'single_choice' ||
      type == 'rating' ||
      type == 'nps' ||
      type == 'likert';

  Future<void> _advance() async {
    final question = _current;
    if (question == null) return;
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
      setState(() => _error = 'Please answer this question to continue.');
      return;
    }
    if (question.type == 'multi_choice') {
      final count = (answer as List<Object?>?)?.length ?? 0;
      if (question.minSelections != null && count < question.minSelections!) {
        setState(
          () => _error = 'Select at least ${question.minSelections} options.',
        );
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
      _prepareQuestionState();
    });
    _scheduleSave();
  }

  void _goBack() {
    if (_history.isEmpty) return;
    setState(() {
      _currentId = _history.removeLast();
      _error = null;
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
    });
    final delivered = await widget.onCompleteAttempt(
      _attempt.attemptId,
      Map<String, Object?>.from(_answers),
    );
    if (!mounted) return;
    if (!delivered) {
      setState(() {
        _submitting = false;
        _error =
            'Your answers are saved on this device. Reconnect and retry to finish.';
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
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this survey?'),
        content: const Text(
          'Your current answers will be saved, but the survey will be marked abandoned.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep answering'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave survey'),
          ),
        ],
      ),
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

  Color _contrastOn(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark
          ? Colors.white
          : Colors.black;

  DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
    if (value.isBefore(minimum)) return minimum;
    if (value.isAfter(maximum)) return maximum;
    return value;
  }
}
