import 'dart:async';

import 'package:flutter/widgets.dart';

import 'internal/logger.dart';
import 'usergist.dart';
import 'ui/prompt_presenter.dart';
import 'ui/inapp_presenter.dart';
import 'ui/survey_presenter.dart';
import 'ui/requests_host.dart';
import 'ui/modal_coordinator.dart';

/// Mounts UserGist presenters below the host app's [Navigator].
///
/// Place it inside the root route:
///
/// ```dart
/// MaterialApp(
///   home: UserGistProvider(child: const HomeScreen()),
/// )
/// ```
///
/// When using `MaterialApp.builder`, assign a navigator key to the app and
/// pass the same key here because the builder context is above the Navigator.
class UserGistProvider extends StatefulWidget {
  /// Creates a provider.
  const UserGistProvider({
    required this.child,
    this.navigatorKey,
    super.key,
  });

  /// The app subtree.
  final Widget child;

  /// Root navigator used when this provider is mounted in `MaterialApp.builder`.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<UserGistProvider> createState() => _UserGistProviderState();
}

class _UserGistProviderState extends State<UserGistProvider> {
  late final PromptPresenter _presenter;
  late final InAppPresenter _inAppPresenter;
  late final SurveyPresenter _surveyPresenter;
  late final SdkModalCoordinator _modalCoordinator;
  StreamSubscription<void>? _resetSubscription;
  bool _reportedMissingNavigator = false;

  @override
  void initState() {
    super.initState();
    _modalCoordinator = SdkModalCoordinator();
    _presenter = PromptPresenter(
      stream: UserGist.internalShowStream,
      onShown: UserGist.internalReportShown,
      onPresentationFailed: UserGist.internalReportPromptPresentationFailed,
      onResponded: UserGist.internalReportResponse,
      themeOverrides: UserGist.internalThemeOverrides,
      coordinator: _modalCoordinator,
    );
    _inAppPresenter = InAppPresenter(
      stream: UserGist.internalInAppShowStream,
      onShown: UserGist.internalReportInAppShown,
      onDismissed: UserGist.internalReportInAppDismissed,
      onCta: UserGist.internalReportInAppCta,
      themeOverrides: UserGist.internalThemeOverrides,
      coordinator: _modalCoordinator,
    );
    _surveyPresenter = SurveyPresenter(
      stream: UserGist.internalSurveyShowStream,
      onSaveProgress: UserGist.internalSaveSurveyProgress,
      onCompleteAttempt: UserGist.internalCompleteSurvey,
      onAbandonAttempt: UserGist.internalAbandonSurvey,
      onShown: UserGist.internalReportSurveyShown,
      onPresentationFailed: UserGist.internalReportSurveyPresentationFailed,
      onComplete: UserGist.internalReportSurveyComplete,
      onAbandon: UserGist.internalReportSurveyAbandon,
      themeOverrides: UserGist.internalThemeOverrides,
      coordinator: _modalCoordinator,
    );
    _resetSubscription = UserGist.internalResetStream.listen((_) {
      _modalCoordinator.clearPending();
      unawaited(
        Future.wait<void>(<Future<void>>[
          _presenter.reset(),
          _inAppPresenter.reset(),
          _surveyPresenter.reset(),
        ]).then<void>((_) {}).catchError((Object error, StackTrace stack) {
          log.e('provider reset failed', error, stack);
        }),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_resetSubscription?.cancel().catchError(_logDisposeError));
    unawaited(_presenter.detach().catchError(_logDisposeError));
    unawaited(_inAppPresenter.detach().catchError(_logDisposeError));
    unawaited(_surveyPresenter.detach().catchError(_logDisposeError));
    super.dispose();
  }

  void _logDisposeError(Object error, StackTrace stack) {
    log.e('provider dispose failed', error, stack);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerCtx) {
        // Attach on the next frame so the context has a full
        // Navigator ancestry available.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final navigator = widget.navigatorKey?.currentState ??
              Navigator.maybeOf(innerCtx, rootNavigator: true);
          final presentationContext = navigator?.overlay?.context;
          if (presentationContext == null) {
            if (!_reportedMissingNavigator) {
              _reportedMissingNavigator = true;
              log.e(
                'UserGistProvider must be mounted below a Navigator or receive '
                'the MaterialApp navigatorKey',
              );
            }
            return;
          }
          _reportedMissingNavigator = false;
          _presenter
            ..updateThemeOverrides(UserGist.internalThemeOverrides)
            ..attach(presentationContext);
          _inAppPresenter
            ..updateThemeOverrides(UserGist.internalThemeOverrides)
            ..attach(presentationContext);
          _surveyPresenter
            ..updateThemeOverrides(UserGist.internalThemeOverrides)
            ..attach(presentationContext);
        });
        return Stack(
          children: [
            widget.child,
            // 0×0 widget — only attaches its initState/dispose to listen
            // for openRequestsBoard / openRequestDetail events.
            RequestsNavHost(navigatorKey: widget.navigatorKey),
          ],
        );
      },
    );
  }
}
