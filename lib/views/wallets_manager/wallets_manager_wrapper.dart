import 'package:flutter/material.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/analytics/events/auth_events.dart';
import 'package:web_dex/analytics/events/user_acquisition_events.dart';
import 'package:web_dex/analytics/onboarding_funnel.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_manager.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_manager_entry.dart';

/// Which screen of the setup dialog is showing.
enum _WalletsManagerRoute { entry, iguana, trezor }

class WalletsManagerWrapper extends StatefulWidget {
  const WalletsManagerWrapper({
    required this.eventType,
    this.onSuccess,
    this.selectedWallet,
    this.initialAction = WalletsManagerAction.none,
    this.initialHdMode = false,
    this.rememberMe = false,
    this.onCancel,
    this.entryCancelLabel,
    this.onUserIntent,
    super.key = const Key('wallets-manager-wrapper'),
  });

  final Function(Wallet)? onSuccess;
  final WalletsManagerEventType eventType;
  final Wallet? selectedWallet;
  final WalletsManagerAction initialAction;
  final bool initialHdMode;
  final bool rememberMe;
  final VoidCallback? onCancel;
  final String? entryCancelLabel;
  final VoidCallback? onUserIntent;

  @override
  State<WalletsManagerWrapper> createState() => _WalletsManagerWrapperState();
}

class _WalletsManagerWrapperState extends State<WalletsManagerWrapper> {
  _WalletsManagerRoute _route = _WalletsManagerRoute.entry;
  WalletsManagerAction _pendingAction = WalletsManagerAction.none;

  /// Set when someone who already has wallets asks for another: creation then
  /// waits for a deliberate Create on its own card.
  bool _confirmCreation = false;
  WalletsManagerExistWalletAction _pendingWalletAction =
      WalletsManagerExistWalletAction.logIn;
  Wallet? _pendingWallet;

  /// True when the dialog opened straight onto a wallet's login form (the
  /// remembered-wallet prompt). There is no entry screen behind it, so Back
  /// must dismiss rather than reveal one the user never chose to open.
  late bool _enteredDirectly;

  late final OnboardingFunnel _funnel;

  @override
  void initState() {
    super.initState();

    _pendingWallet = widget.selectedWallet;
    _enteredDirectly = widget.selectedWallet != null;
    if (_enteredDirectly) _route = _WalletsManagerRoute.iguana;
    if (widget.initialAction == WalletsManagerAction.import) {
      _pendingAction = WalletsManagerAction.import;
      _route = _WalletsManagerRoute.iguana;
    }

    final walletsRepository = context.read<WalletsRepository>();
    _funnel = OnboardingFunnel(
      analytics: context.read<AnalyticsBloc>(),
      entryPoint: widget.eventType.name,
      existingWalletCount: () => walletsRepository.wallets?.length,
    );

    // Fired even for the remembered-wallet deep-link. That inflates the top of
    // the funnel with returning users, which is exactly what
    // `existing_wallet_count` separates, and it makes login-vs-onboarding
    // volume measurable for free.
    _funnel.enter(OnboardingStep.walletManagerOpened);
    if (!_enteredDirectly) {
      // Completed, not abandoned: reaching the entry screen *is* what finishes
      // the anchor step. Letting `enter` auto-close it would record every
      // single session as abandoning step 0.
      _funnel
        ..complete()
        ..enter(OnboardingStep.setupActionSelect);
    }
  }

  @override
  void dispose() {
    _funnel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      // The forms finish their own sign-ins. The list has none, so a wallet
      // opened elsewhere, as by the remembered-wallet prompt, finishes here.
      listenWhen: (previous, current) =>
          previous.currentUser == null && current.currentUser != null,
      listener: (_, auth) {
        if (_route == _WalletsManagerRoute.entry) {
          widget.onSuccess?.call(auth.currentUser!.wallet);
        }
      },
      child: BlocProvider(
        create: (context) =>
            LegalAgreementBloc(context.read<LegalDocumentsRepository>())
              ..add(const LegalAgreementOpened()),
        child: Builder(builder: _buildRoute),
      ),
    );
  }

  Widget _buildRoute(BuildContext context) {
    switch (_route) {
      case _WalletsManagerRoute.entry:
        return WalletsManagerEntry(
          onAction: _onAction,
          onCreateAnother: () =>
              _onAction(WalletsManagerAction.create, confirmCreation: true),
          onHardwareWallet: _onHardwareWallet,
          onWalletSelected: _onWalletSelected,
          onCancel: _handleCancel,
          cancelLabel: widget.entryCancelLabel,
          onUserIntent: widget.onUserIntent,
        );

      case _WalletsManagerRoute.iguana:
      case _WalletsManagerRoute.trezor:
        return WalletsManager(
          key: ValueKey((
            _pendingWallet?.id,
            _pendingAction,
            _pendingWalletAction,
            _confirmCreation,
            _route,
          )),
          // Only where there is no list behind the sheet. Reached from the
          // list, Cancel already returns there.
          onSwitchWallet: _enteredDirectly ? _showWalletSelector : null,
          onRecover: () => _onAction(WalletsManagerAction.import),
          eventType: widget.eventType,
          walletType: _route == _WalletsManagerRoute.trezor
              ? WalletType.trezor
              : WalletType.iguana,
          initialAction: _pendingAction,
          initialWalletAction: _pendingWalletAction,
          confirmCreation: _confirmCreation,
          close: _closeWalletManager,
          onSuccess: widget.onSuccess ?? (_) {},
          selectedWallet: _pendingWallet,
          initialHdMode: _pendingWallet?.config.type == WalletType.hdwallet
              ? true
              : widget.initialHdMode,
          rememberMe: widget.rememberMe,
        );
    }
  }

  void _onAction(WalletsManagerAction action, {bool confirmCreation = false}) {
    final isCreate = action == WalletsManagerAction.create;
    _funnel
      ..setFlow(
        isCreate ? OnboardingFlowKind.create : OnboardingFlowKind.importSeed,
      )
      // Closed before the child mounts, so at most one funnel holds an open
      // step at any instant and disposing both emits at most one `abandoned`.
      ..complete();

    context.read<AnalyticsBloc>().logEvent(
      OnboardingStartedEventData(
        method: isCreate ? 'create' : 'import',
        referralSource: widget.eventType.name,
      ),
    );
    setState(() {
      _pendingAction = action;
      _confirmCreation = confirmCreation;
      _pendingWallet = null;
      _route = _WalletsManagerRoute.iguana;
    });
  }

  void _showWalletSelector() {
    setState(() {
      _enteredDirectly = false;
      _pendingWallet = null;
      _pendingAction = WalletsManagerAction.none;
      _route = _WalletsManagerRoute.entry;
    });
  }

  void _onHardwareWallet() {
    _funnel
      ..setFlow(OnboardingFlowKind.hardware)
      ..complete();
    setState(() {
      _pendingAction = WalletsManagerAction.none;
      _pendingWallet = null;
      _route = _WalletsManagerRoute.trezor;
    });
  }

  void _onWalletSelected(
    Wallet wallet,
    WalletsManagerExistWalletAction action,
  ) {
    final open = context.read<AuthBloc>().state.currentUser;
    if (action == WalletsManagerExistWalletAction.logIn &&
        open != null &&
        open.walletId.name == wallet.name) {
      // Its unlock would be a second sign-in, which the engine refuses.
      widget.onSuccess?.call(open.wallet);
      return;
    }
    // Acting on an existing wallet is not onboarding.
    _funnel
      ..complete()
      ..finish();
    setState(() {
      _pendingWallet = wallet;
      _pendingWalletAction = action;
      _pendingAction = WalletsManagerAction.none;
      _route = _WalletsManagerRoute.iguana;
    });
  }

  /// Back from any form. Two meanings now instead of three: the entry screen
  /// closes the dialog, and every form returns to the entry screen.
  void _closeWalletManager() {
    if (_enteredDirectly) {
      _handleCancel();
      return;
    }
    setState(() {
      _route = _WalletsManagerRoute.entry;
      _pendingAction = WalletsManagerAction.none;
      _pendingWallet = null;
    });
    _funnel
      ..setFlow(OnboardingFlowKind.undecided)
      ..enter(OnboardingStep.setupActionSelect);
  }

  void _handleCancel() {
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
      return;
    }
    Navigator.of(context).maybePop();
  }
}
