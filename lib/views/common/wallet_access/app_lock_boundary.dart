import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';

/// Labels are supplied by the application localization boundary.
class WalletLockLabels {
  const WalletLockLabels({
    this.title = 'Unlock your wallet',
    this.message = 'Use your device or wallet password to continue.',
    this.unlock = 'Unlock',
    this.unlocking = 'Unlocking…',
    this.usePassword = 'Use password',
    this.switchWallet = 'Switch wallet',
    this.recoverWallet = 'Recover wallet',
    this.privacy = 'Wallet content hidden',
  });

  final String title;
  final String message;
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

  /// Password/recovery forms live outside the blocked application Navigator.
  /// A regular showDialog in [child] would correctly remain under the cover.
  final Widget? authenticationContent;
  final bool observeLifecycle;

  @override
  State<AppLockBoundary> createState() => _AppLockBoundaryState();
}

class _AppLockBoundaryState extends State<AppLockBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      final current = WidgetsBinding.instance.lifecycleState;
      if (current != null) didChangeAppLifecycleState(current);
    }
  }

  @override
  void didUpdateWidget(AppLockBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observeLifecycle == widget.observeLifecycle) return;
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.coordinator.resume();
      case AppLifecycleState.inactive:
        widget.coordinator.inactive();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.coordinator.background();
    }
  }

  @override
  void dispose() {
    if (widget.observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<WalletUnlockState>(
    stream: widget.coordinator.changes,
    initialData: widget.coordinator.state,
    builder: (context, snapshot) {
      final state = snapshot.data ?? widget.coordinator.state;
      final covered = state.coversContent;
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: covered,
            child: ExcludeFocus(
              excluding: covered,
              child: IgnorePointer(
                ignoring: covered,
                child: TickerMode(enabled: !covered, child: widget.child),
              ),
            ),
          ),
          if (covered)
            Positioned.fill(
              child: BlockSemantics(
                child: _WalletLockSurface(
                  state: state,
                  labels: widget.labels,
                  errorMessage: widget.errorMessage,
                  authenticationContent: widget.authenticationContent,
                  onUnlock: widget.onUnlock,
                  onUsePassword: widget.onUsePassword,
                  onSwitchWallet: widget.onSwitchWallet,
                  onRecoverWallet: widget.onRecoverWallet,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _WalletLockSurface extends StatelessWidget {
  const _WalletLockSurface({
    required this.state,
    required this.labels,
    required this.onUnlock,
    required this.onUsePassword,
    required this.onSwitchWallet,
    required this.onRecoverWallet,
    this.errorMessage,
    this.authenticationContent,
  });

  final WalletUnlockState state;
  final WalletLockLabels labels;
  final String? errorMessage;
  final Widget? authenticationContent;
  final VoidCallback onUnlock;
  final VoidCallback? onUsePassword;
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecoverWallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!state.isForeground) {
      return ColoredBox(
        key: const Key('wallet-privacy-cover'),
        color: theme.scaffoldBackgroundColor,
        child: Semantics(
          label: labels.privacy,
          child: const Center(child: Icon(Icons.lock_outline, size: 40)),
        ),
      );
    }
    final authentication = authenticationContent;
    if (authentication != null) {
      return Material(
        key: const Key('wallet-lock-authentication'),
        color: theme.scaffoldBackgroundColor,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            child: FocusTraversalGroup(
              child: FocusScope(autofocus: true, child: authentication),
            ),
          ),
        ),
      );
    }
    final busy = state.unlockInProgress;
    return Material(
      key: const Key('wallet-lock-screen'),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: FocusTraversalGroup(
          child: FocusScope(
            autofocus: true,
            child: Center(
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
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text(
                          labels.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        labels.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      UiPrimaryButton(
                        expandForText: true,
                        key: const Key('wallet-lock-unlock'),
                        height: 50,
                        text: busy ? labels.unlocking : labels.unlock,
                        onPressed: busy ? null : onUnlock,
                      ),
                      if (onUsePassword != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                          key: const Key('wallet-lock-use-password'),
                          onPressed: busy ? null : onUsePassword,
                          child: Text(labels.usePassword),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (onSwitchWallet != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                          key: const Key('wallet-lock-switch-wallet'),
                          onPressed: onSwitchWallet,
                          child: Text(labels.switchWallet),
                        ),
                      if (onRecoverWallet != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                          key: const Key('wallet-lock-recover-wallet'),
                          onPressed: onRecoverWallet,
                          child: Text(labels.recoverWallet),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
