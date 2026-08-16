import 'dart:async';

import 'package:flutter/widgets.dart';

import 'usergist.dart';
import 'ui/prompt_presenter.dart';
import 'ui/requests_host.dart';

/// Mounts the UserGist prompt presenter on top of the host app's
/// navigator so prompts can render as modal bottom sheets over the
/// current screen.
///
/// Use it as the `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   builder: (ctx, child) => UserGistProvider(child: child!),
///   home: const HomeScreen(),
/// )
/// ```
///
/// Placing it this way ensures there is a [Navigator] ancestor so the
/// SDK can call `showModalBottomSheet` against the caller's navigator.
class UserGistProvider extends StatefulWidget {
  /// Creates a provider.
  const UserGistProvider({
    required this.child,
    super.key,
  });

  /// The app subtree.
  final Widget child;

  @override
  State<UserGistProvider> createState() => _UserGistProviderState();
}

class _UserGistProviderState extends State<UserGistProvider> {
  late final PromptPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = PromptPresenter(
      stream: UserGist.internalShowStream,
      onShown: UserGist.internalReportShown,
      onResponded: UserGist.internalReportResponse,
      themeOverrides: UserGist.internalThemeOverrides,
    );
  }

  @override
  void dispose() {
    unawaited(_presenter.detach());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerCtx) {
        // Attach on the next frame so the context has a full
        // Navigator ancestry available.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _presenter
            ..updateThemeOverrides(UserGist.internalThemeOverrides)
            ..attach(innerCtx);
        });
        return Stack(
          children: [
            widget.child,
            // 0×0 widget — only attaches its initState/dispose to listen
            // for openRequestsBoard / openRequestDetail events.
            const RequestsNavHost(),
          ],
        );
      },
    );
  }
}
