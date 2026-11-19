import 'package:flutter/material.dart';

import 'config.dart';
import 'controller.dart';
import 'copy.dart';

/// Asked before the Update button acts. Return false to stop. Kids apps pass
/// their parental gate here; everyone else leaves it null.
typedef BeforeUpdate = Future<bool> Function(BuildContext context);

/// Touch targets of the prompt: parent-facing, so 56 dp (the child-facing
/// parts of a Kids app use 96 dp, this prompt is not one of them).
const double kUpdateButtonHeight = 56;

UpdateCopy _copyOf(BuildContext context) =>
    UpdateCopy.forLanguage(Localizations.localeOf(context).languageCode);

Future<void> _runUpdate(
  BuildContext context,
  UpdateController controller,
  BeforeUpdate? before,
) async {
  if (before != null && !await before(context)) return;
  if (!context.mounted) return;
  await controller.performUpdate();
}

/// The friendly, dismissible "A new version is ready" card. Collapses to
/// nothing when there is nothing to show. Put it at the top of a home or
/// settings screen.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.controller,
    this.beforeUpdate,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  final UpdateController controller;
  final BeforeUpdate? beforeUpdate;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final restart = controller.readyToRestart;
        if (!restart && !controller.showBanner) {
          return const SizedBox.shrink();
        }
        final copy = _copyOf(context);
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: margin,
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              key: const Key('update_banner'),
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A filled badge, so the card reads as a notice, not a row.
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.primary,
                        child: Icon(
                          restart ? Icons.download_done : Icons.system_update,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                restart ? copy.downloadedTitle : copy.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                key: const Key('update_banner_action'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(
                                    96,
                                    kUpdateButtonHeight,
                                  ),
                                ),
                                onPressed:
                                    restart
                                        ? controller.restartToUpdate
                                        : () => _runUpdate(
                                          context,
                                          controller,
                                          beforeUpdate,
                                        ),
                                child: Text(
                                  restart ? copy.restart : copy.update,
                                ),
                              ),
                              if (!restart)
                                TextButton(
                                  key: const Key('update_banner_later'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      96,
                                      kUpdateButtonHeight,
                                    ),
                                    foregroundColor: scheme.onPrimaryContainer,
                                  ),
                                  onPressed: controller.dismiss,
                                  child: Semantics(
                                    label: copy.dismissLabel,
                                    excludeSemantics: true,
                                    child: Text(copy.later),
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
          ),
        );
      },
    );
  }
}

/// Puts the banner above a page that draws its own top inset (a shell around
/// screens with their own SafeArea/AppBar). While the banner shows, it takes
/// the status-bar inset itself and the page below is told the top inset is
/// already used, so nothing is padded twice. The tree is the same whether or
/// not the banner shows, so the page keeps its state.
///
/// A banner inside a screen's own body (below its AppBar) needs no slot: use
/// [UpdateBanner] directly.
class UpdateBannerSlot extends StatelessWidget {
  const UpdateBannerSlot({
    super.key,
    required this.controller,
    required this.child,
    this.beforeUpdate,
    this.enabled = true,
  });

  final UpdateController controller;
  final Widget child;
  final BeforeUpdate? beforeUpdate;

  /// False on pages that must not carry the banner (only the home does).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final show =
            enabled && (controller.showBanner || controller.readyToRestart);
        return Column(
          children: [
            // Always one child here, so the page below keeps its element
            // (and state) when the banner comes and goes.
            show
                ? SafeArea(
                  bottom: false,
                  child: UpdateBanner(
                    controller: controller,
                    beforeUpdate: beforeUpdate,
                  ),
                )
                : const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: show,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The blocking "Please update" screen for builds the server marked broken.
/// Friendly and calm: no error codes, one big button.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.controller,
    required this.config,
    this.beforeUpdate,
  });

  final UpdateController controller;
  final UpdateConfig config;
  final BeforeUpdate? beforeUpdate;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final copy = UpdateCopy.forLanguage(lang);
    final server = controller.status.policy.messageFor(lang);
    final body =
        server ??
        (config.forParents ? copy.requiredBodyForParents : copy.requiredBody);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('update_required'),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update,
                      size: 72,
                      color: scheme.primary,
                      semanticLabel: '',
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      child: Text(
                        copy.requiredTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      key: const Key('update_required_body'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('update_required_action'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(
                            double.infinity,
                            kUpdateButtonHeight,
                          ),
                        ),
                        onPressed:
                            () => _runUpdate(context, controller, beforeUpdate),
                        child: Text(copy.update),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wire once in `MaterialApp.builder`. Starts the controller, pushes the
/// blocking screen (over the app, above any dialog the app has open) while the
/// build is blocked, and shows a "Restart" snackbar when a Play flexible
/// update has downloaded.
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({
    super.key,
    required this.controller,
    required this.navigatorKey,
    this.beforeUpdate,
    required this.child,
  });

  final UpdateController controller;

  /// The navigator the blocking screen is pushed on (the app's own key).
  final GlobalKey<NavigatorState> navigatorKey;
  final BeforeUpdate? beforeUpdate;
  final Widget child;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  Route<void>? _route;
  bool _scheduled = false;
  bool _snackShown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    widget.controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(UpdatePromptHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      widget.controller.start();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _apply();
    });
    // A callback alone would wait for the next frame, which an idle app may
    // not produce for a while.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _apply() {
    final c = widget.controller;
    final nav = widget.navigatorKey.currentState;
    if (c.isRequired && _route == null && nav != null) {
      final route = PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder:
            (context, _, _) => UpdateRequiredScreen(
              controller: c,
              config: c.config,
              beforeUpdate: widget.beforeUpdate,
            ),
      );
      _route = route;
      nav.push(route);
    } else if (!c.isRequired && _route != null && nav != null) {
      nav.removeRoute(_route!);
      _route = null;
    }
    _showRestartSnack(c);
  }

  void _showRestartSnack(UpdateController c) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (c.readyToRestart && !_snackShown && messenger != null) {
      _snackShown = true;
      final copy = _copyOf(context);
      messenger.showSnackBar(
        SnackBar(
          key: const Key('update_restart_snack'),
          content: Text(copy.downloadedTitle),
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: copy.restart,
            onPressed: c.restartToUpdate,
          ),
        ),
      );
    } else if (!c.readyToRestart) {
      _snackShown = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
