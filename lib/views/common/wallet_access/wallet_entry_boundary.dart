import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/shared/widgets/remember_wallet_service.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

/// Retains an explicit guest choice across phone/wide shell and coin routes.
/// This is process-local presentation state, never an unlocked-session marker.
class WalletEntryScope extends StatefulWidget {
  const WalletEntryScope({required this.child, super.key});
  final Widget child;

  @override
  State<WalletEntryScope> createState() => _WalletEntryScopeState();
}

class _WalletEntryScopeState extends State<WalletEntryScope> {
  final _browsing = ValueNotifier(false);

  @override
  void dispose() {
    _browsing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthBloc, AuthBlocState>(
    listenWhen: (previous, current) =>
        previous.currentUser?.walletId != current.currentUser?.walletId,
    listener: (_, _) => _browsing.value = false,
    child: _GuestWalletChoice(notifier: _browsing, child: widget.child),
  );
}

class _GuestWalletChoice extends InheritedNotifier<ValueNotifier<bool>> {
  const _GuestWalletChoice({required super.notifier, required super.child});
}

/// Makes setup the signed-out wallet landing page. Public prices remain an
/// explicit choice; returning-wallet authentication is owned by the app host.
class WalletEntryBoundary extends StatefulWidget {
  const WalletEntryBoundary({
    required this.child,
    this.isWalletRoot = true,
    super.key,
  });

  final Widget child;
  final bool isWalletRoot;

  @override
  State<WalletEntryBoundary> createState() => _WalletEntryBoundaryState();
}

class _WalletEntryBoundaryState extends State<WalletEntryBoundary> {
  bool _browsing = false;

  void _browse(bool value) {
    final choice = context
        .dependOnInheritedWidgetOfExactType<_GuestWalletChoice>();
    if (choice != null) {
      choice.notifier!.value = value;
    } else {
      setState(() => _browsing = value);
    }
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AuthBloc, AuthBlocState>(
    listenWhen: (previous, current) =>
        previous.currentUser?.walletId != current.currentUser?.walletId,
    listener: (_, _) => _browsing = false,
    builder: (context, auth) {
      if (auth.isSignedIn || !widget.isWalletRoot) return widget.child;
      final choice = context
          .dependOnInheritedWidgetOfExactType<_GuestWalletChoice>();
      if (choice?.notifier?.value ?? _browsing) {
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  key: const Key('open-wallet-setup'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => _browse(false),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text('authOpenWalletSetup'.tr()),
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: WalletsManagerWrapper(
              eventType: WalletsManagerEventType.wallet,
              onUserIntent: RememberWalletService.cancelPendingAutomaticEntry,
              entryCancelLabel: 'authExplorePrices'.tr(),
              onCancel: () => _browse(true),
            ),
          ),
        ),
      );
    },
  );
}
