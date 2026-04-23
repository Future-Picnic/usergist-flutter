import 'dart:async';

import 'package:flutter/widgets.dart';

import 'ritmus.dart';
import 'ui/prompt_presenter.dart';

/// Mounts the Ritmus prompt presenter on top of the host app's
/// navigator so prompts can render as modal bottom sheets over the
/// current screen.
///
/// Use it as the `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   builder: (ctx, child) => RitmusProvider(child: child!),
///   home: const HomeScreen(),
/// )
/// ```
///
/// Placing it this way ensures there is a [Navigator] ancestor so the
/// SDK can call `showModalBottomSheet` against the caller's navigator.
class RitmusProvider extends StatefulWidget {
  /// Creates a provider.
  const RitmusProvider({
    required this.child,
    super.key,
  });

  /// The app subtree.
  final Widget child;

  @override
  State<RitmusProvider> createState() => _RitmusProviderState();
}

class _RitmusProviderState extends State<RitmusProvider> {
  late final PromptPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = PromptPresenter(
      stream: Ritmus.internalShowStream,
      onShown: Ritmus.internalReportShown,
      onResponded: Ritmus.internalReportResponse,
      themeOverrides: Ritmus.internalThemeOverrides,
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
            ..updateThemeOverrides(Ritmus.internalThemeOverrides)
            ..attach(innerCtx);
        });
        return widget.child;
      },
    );
  }
}
