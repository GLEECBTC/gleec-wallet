import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';

/// Labels are supplied by the application localization boundary.
class WalletLockLabels {
  const WalletLockLabels({
    this.title = 'Unlock your wallet',
    this.message,
    this.unlock = 'Unlock',
    this.unlocking = 'Unlocking…',
    this.usePassword = 'Use password',
    this.switchWallet = 'Switch wallet',
    this.recoverWallet = 'Recover wallet',
    this.privacy = 'Wallet content hidden',
  });

  final String title;

  /// A line under the title, for when the title cannot name the wallet.
  final String? message;

  /// Names the method the primary action uses, e.g. "Unlock with passkey".
  final String unlock;
  final String unlocking;
  final String usePassword;
  final String switchWallet;
  final String recoverWallet;
  final String privacy;
}

/// Place above the root Navigator (for example in MaterialApp.builder), so
/// open dialogs and their accessibility nodes are covered along with pages.
/// This does not stop KDF. Financial entry points enforce the operation gate.
class AppLockBoundary extends StatefulWidget {
  const AppLockBoundary({
    required this.coordinator,
    required this.child,
    required this.onUnlock,
    this.onUsePassword,
    this.onSwitchWallet,
    this.onRecoverWallet,
    this.labels = const WalletLockLabels(),
    this.errorMessage,
    this.errorTone = WalletAccessTone.error,
    this.authenticationContent,
    this.observeLifecycle = true,
    super.key,
  });

  final WalletUnlockCoordinator coordinator;
  final Widget child;
  final VoidCallback onUnlock;
  final VoidCallback? onUsePassword;
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecoverWallet;
  final WalletLockLabels labels;
  final String? errorMessage;
  final WalletAccessTone errorTone;

  /// Password/recovery forms live outside the blocked application Navigator.
  /// A regular showDialog in [child] would correctly remain under the cover.
  final Widget? authenticationContent;
  final bool observeLifecycle;

  @override
  State<AppLockBoundary> createState() => _AppLockBoundaryState();
}

class _AppLockBoundaryState extends State<AppLockBoundary>
    with WidgetsBindingObserver {
  final _contentFocus = FocusNode(debugLabel: 'wallet content');
  late WalletUnlockState _state;
  StreamSubscription<WalletUnlockState>? _changes;

  /// What was focused in [AppLockBoundary.child] most recently. Covering the
  /// content takes its focus away, and on desktop the framework has already
  /// parked focus on the root scope by the time the cover is known.
  FocusNode? _lastContentFocus;
  FocusNode? _focusBeforeCover;
  bool _lockRequiredWhileCovered = false;

  @override
  void initState() {
    super.initState();
    _listen();
    FocusManager.instance.addListener(_rememberContentFocus);
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      final current = WidgetsBinding.instance.lifecycleState;
      if (current != null) didChangeAppLifecycleState(current);
    }
  }

  @override
  void didUpdateWidget(AppLockBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.coordinator, widget.coordinator)) _listen();
    if (oldWidget.observeLifecycle == widget.observeLifecycle) return;
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  void _listen() {
    unawaited(_changes?.cancel());
    _state = widget.coordinator.state;
    _changes = widget.coordinator.changes.listen(_onState);
  }

  void _rememberContentFocus() {
    if (_state.coversContent) return;
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused.ancestors.contains(_contentFocus)) {
      _lastContentFocus = focused;
    }
  }

  void _onState(WalletUnlockState next) {
    if (!mounted) return;
    final wasCovered = _state.coversContent;
    final covers = next.coversContent;
    if (covers && !wasCovered) {
      _focusBeforeCover = _lastContentFocus;
      _lockRequiredWhileCovered = false;
    }
    if (covers && next.isLocked) _lockRequiredWhileCovered = true;
    FocusNode? restore;
    if (wasCovered && !covers) {
      // After an unlock the user starts afresh; only a cover that lifted on
      // its own hands focus back to where they were typing.
      if (!_lockRequiredWhileCovered) restore = _focusBeforeCover;
      _focusBeforeCover = null;
    }
    setState(() => _state = next);
    if (restore == null) return;
    final node = restore;
    // The content accepts focus again only once this state has been built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _state.coversContent) return;
      if ((node.context?.mounted ?? false) && node.canRequestFocus) {
        node.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.coordinator.resume();
      case AppLifecycleState.inactive:
        // On desktop and web this is only another window taking input focus:
        // the wallet stays readable and the re-lock clock does not start.
        if (focusLossLeavesApp) widget.coordinator.inactive();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.coordinator.background();
    }
  }

  @override
  void dispose() {
    if (widget.observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_rememberContentFocus);
    unawaited(_changes?.cancel());
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final covered = state.coversContent;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: covered,
          // ExcludeFocus with a node of our own, to tell content focus apart.
          child: Focus(
            focusNode: _contentFocus,
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            descendantsAreFocusable: !covered,
            child: IgnorePointer(
              ignoring: covered,
              child: TickerMode(enabled: !covered, child: widget.child),
            ),
          ),
        ),
        if (covered)
          Positioned.fill(
            child: BlockSemantics(
              child: !state.isForeground
                  ? _PrivacyCover(label: widget.labels.privacy)
                  : _CoverOverlay(
                      child: _WalletLockSurface(
                        busy: state.unlockInProgress,
                        labels: widget.labels,
                        errorMessage: widget.errorMessage,
                        errorTone: widget.errorTone,
                        authenticationContent: widget.authenticationContent,
                        onUnlock: widget.onUnlock,
                        onUsePassword: widget.onUsePassword,
                        onSwitchWallet: widget.onSwitchWallet,
                        onRecoverWallet: widget.onRecoverWallet,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('wallet-privacy-cover'),
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Semantics(
      label: label,
      child: const Center(child: Icon(Icons.lock_outline, size: 40)),
    ),
  );
}

/// The cover sits above the app's Navigator and so above its Overlay. Text
/// selection handles, the Paste toolbar and tooltips all need one, so the
/// cover brings its own; it fills the boundary so they land where they should.
class _CoverOverlay extends StatefulWidget {
  const _CoverOverlay({required this.child});
  final Widget child;

  @override
  State<_CoverOverlay> createState() => _CoverOverlayState();
}

class _CoverOverlayState extends State<_CoverOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_CoverOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _WalletLockSurface extends StatelessWidget {
  const _WalletLockSurface({
    required this.busy,
    required this.labels,
    required this.errorTone,
    required this.onUnlock,
    required this.onUsePassword,
    required this.onSwitchWallet,
    required this.onRecoverWallet,
    this.errorMessage,
    this.authenticationContent,
  });

  final bool busy;
  final WalletLockLabels labels;
  final String? errorMessage;
  final WalletAccessTone errorTone;
  final Widget? authenticationContent;
  final VoidCallback onUnlock;
  final VoidCallback? onUsePassword;
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecoverWallet;

  @override
  Widget build(BuildContext context) {
    final authentication = authenticationContent;
    return Material(
      key: Key(
        authentication == null
            ? 'wallet-lock-screen'
            : 'wallet-lock-authentication',
      ),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: FocusTraversalGroup(
            child: FocusScope(
              autofocus: true,
              child:
                  authentication ??
                  WalletLockPanel(
                    title: labels.title,
                    message: labels.message,
                    children: [
                      if (errorMessage != null) ...[
                        WalletAccessNotice(
                          text: errorMessage!,
                          tone: errorTone,
                        ),
                        const SizedBox(height: 16),
                      ],
                      WalletAccessPrimaryButton(
                        buttonKey: const Key('wallet-lock-unlock'),
                        autofocus: true,
                        text: labels.unlock,
                        busy: busy,
                        busyText: labels.unlocking,
                        onPressed: onUnlock,
                      ),
                      if (onUsePassword != null) ...[
                        const SizedBox(height: 8),
                        WalletAccessSecondaryButton(
                          key: const Key('wallet-lock-use-password'),
                          text: labels.usePassword,
                          onPressed: onUsePassword,
                        ),
                      ],
                      if (onSwitchWallet != null || onRecoverWallet != null)
                        const SizedBox(height: 16),
                      if (onSwitchWallet != null)
                        WalletAccessTertiaryButton(
                          key: const Key('wallet-lock-switch-wallet'),
                          text: labels.switchWallet,
                          onPressed: onSwitchWallet,
                        ),
                      if (onRecoverWallet != null)
                        WalletAccessTertiaryButton(
                          key: const Key('wallet-lock-recover-wallet'),
                          text: labels.recoverWallet,
                          onPressed: onRecoverWallet,
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

/// The lock screen's column: the lock, a title that names the wallet, and the
/// caller's controls. Centred and scrollable, so it holds at narrow widths and
/// large text.
class WalletLockPanel extends StatelessWidget {
  const WalletLockPanel({
    required this.title,
    required this.children,
    this.message,
    super.key,
  });

  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
