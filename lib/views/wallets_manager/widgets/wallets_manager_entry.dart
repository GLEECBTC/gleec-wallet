import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_list.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_credential_cleanup_notice.dart';

/// The single first screen of wallet setup.
///
/// Replaces two screens: a wallet-type router ("Connect Gleec Wallet" /
/// "Connect Hardware wallet") and, behind it, a bare Create/Import button pair
/// with no heading and no copy. Both decisions now live here.
///
/// The Create CTA is dominant through **fill and elevation only**. The import
/// row keeps a full-width tap target of the same height, because the failure
/// this screen exists to prevent is a returning holder with a recovery phrase
/// not finding the way in - and a demoted-but-present row is what every shipped
/// wallet that gets this right actually does.
///
/// Note `Theme.of(context).extension<ColorSchemeExtension>()` is **null** in
/// this subtree: the semantic scale is registered only on the "new theme" data,
/// while `MaterialApp.router` runs on `theme.global.*`. Use base `ThemeData`
/// tokens here, or the forms rendered one tap later in the same dialog will
/// diverge visually.
class WalletsManagerEntry extends StatefulWidget {
  const WalletsManagerEntry({
    required this.onAction,
    required this.onHardwareWallet,
    required this.onWalletSelected,
    required this.onCancel,
    this.cancelLabel,
    this.onUserIntent,
    super.key,
  });

  final void Function(WalletsManagerAction) onAction;
  final VoidCallback onHardwareWallet;
  final void Function(Wallet, WalletsManagerExistWalletAction) onWalletSelected;
  final VoidCallback onCancel;
  final String? cancelLabel;
  final VoidCallback? onUserIntent;

  @override
  State<WalletsManagerEntry> createState() => _WalletsManagerEntryState();
}

class _WalletsManagerEntryState extends State<WalletsManagerEntry> {
  late final Stream<List<Wallet>> _walletsStream;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // The stream lives here rather than in `WalletsList` because this screen
    // needs to know whether wallets exist *before* it can choose a layout.
    // It also means the wallets cache is primed on every entry into setup,
    // which the legacy-migration name check reads synchronously.
    final walletsRepository = context.read<WalletsRepository>();
    _walletsStream = walletsRepository.watchWallets();
    unawaited(
      walletsRepository.refreshWallets().catchError((Object error) {
        debugPrint('Failed to refresh wallets list: $error');
        return <Wallet>[];
      }),
    );
  }

  Future<void> _onAction(WalletsManagerAction action) async {
    widget.onUserIntent?.call();
    if (action != WalletsManagerAction.create) {
      widget.onAction(action);
      return;
    }
    if (_creating) return;
    setState(() => _creating = true);
    final agreement = await awaitLegalAgreement(context);
    if (!mounted) return;
    if (agreement == null) {
      setState(() => _creating = false);
      return;
    }
    context.read<LegalAgreementBloc>().add(
      LegalAgreementSubmitted('wallet-creation', snapshot: agreement.snapshot),
    );
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      initialData:
          context.read<WalletsRepository>().wallets ?? const <Wallet>[],
      stream: _walletsStream,
      builder: (context, snapshot) {
        final wallets = snapshot.data ?? const <Wallet>[];
        final hasWallets = wallets.isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WalletCredentialCleanupNotice(),
            _OnboardingHeader(hasWallets: hasWallets),
            if (!hasWallets) ...[
              const SizedBox(height: 12),
              Text(
                'authCreationProtectionNotice'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            if (hasWallets) ...[
              WalletsList(
                walletType: WalletType.iguana,
                wallets: wallets,
                onWalletClick: (wallet, action) {
                  widget.onUserIntent?.call();
                  widget.onWalletSelected(wallet, action);
                },
              ),
              const SizedBox(height: 16),
              const UiDivider(),
              const SizedBox(height: 8),
            ],
            LegalConsentAction(
              builder: (allowed) => _OnboardingActions(
                canCreate: allowed && !_creating,
                hasWallets: hasWallets,
                onAction: _onAction,
                onHardwareWallet: () {
                  widget.onUserIntent?.call();
                  widget.onHardwareWallet();
                },
              ),
            ),
            const SizedBox(height: 12),
            TermsConsentText(
              actionLabel: LocaleKeys.onboardingCreateWallet.tr(),
            ),
            const SizedBox(height: 12),
            UiUnderlineTextButton(
              key: const Key('onboarding-cancel-button'),
              text: widget.cancelLabel ?? LocaleKeys.cancel.tr(),
              onPressed: () {
                widget.onUserIntent?.call();
                widget.onCancel();
              },
            ),
          ],
        );
      },
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.hasWallets});

  final bool hasWallets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compat: `test_integration/helpers/connect_wallet.dart` taps this key to
    // get past the wallet-type router screen that used to sit here. Tapping the
    // header is a no-op, which is what the helper needs now that the screen is
    // gone. Deliberately NOT on the Create CTA - the helper taps it and then
    // looks for `create-wallet-button`, so a real navigation here would break
    // every suite that restores a wallet. Remove once the helper's conditional
    // tap has shipped and integration CI is green.
    return GestureDetector(
      key: const Key('wallet-type-list-item-iguana'),
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              hasWallets
                  ? LocaleKeys.onboardingReturningTitle.tr()
                  : LocaleKeys.onboardingTitle.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasWallets
                ? LocaleKeys.onboardingReturningSubtitle.tr()
                : LocaleKeys.onboardingSubtitle.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _OnboardingActions extends StatelessWidget {
  const _OnboardingActions({
    required this.hasWallets,
    required this.canCreate,
    required this.onAction,
    required this.onHardwareWallet,
  });

  final bool hasWallets;
  final void Function(WalletsManagerAction) onAction;
  final VoidCallback onHardwareWallet;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hardware wallets have never been offered on native mobile.
    final showHardware = !PlatformTuner.isNativeMobile;

    final importRow = Semantics(
      button: true,
      child: UiListActionRow(
        rowKey: const Key('import-wallet-button'),
        title: LocaleKeys.onboardingImportTitle.tr(),
        // The load-bearing string on this screen. "I already have a wallet" asks
        // the user to classify themselves; naming the artifact in their hand asks
        // them only to recognise it.
        subtitle: LocaleKeys.onboardingImportSubtitle.tr(),
        backgroundColor: hasWallets ? theme.cardColor : null,
        onTap: () => onAction(WalletsManagerAction.import),
      ),
    );

    final hardwareRow = Semantics(
      button: true,
      child: UiListActionRow(
        rowKey: const Key('connect-hardware-wallet-button'),
        title: LocaleKeys.onboardingHardwareTitle.tr(),
        backgroundColor: hasWallets ? theme.cardColor : null,
        onTap: onHardwareWallet,
      ),
    );

    // With wallets already on the device the list is the dominant element, so
    // Create drops to the same weight as Import rather than competing with it.
    if (hasWallets) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: canCreate,
            child: UiListActionRow(
              rowKey: const Key('create-wallet-button'),
              title: LocaleKeys.onboardingCreateWallet.tr(),
              backgroundColor: theme.cardColor,
              onTap: canCreate
                  ? () => onAction(WalletsManagerAction.create)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          importRow,
          if (showHardware) ...[const SizedBox(height: 8), hardwareRow],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiPrimaryButton(
          expandForText: true,
          key: const Key('create-wallet-button'),
          height: 56,
          text: LocaleKeys.onboardingCreateWallet.tr(),
          onPressed: canCreate
              ? () => onAction(WalletsManagerAction.create)
              : null,
        ),
        const SizedBox(height: 16),
        const UiDivider(),
        const SizedBox(height: 4),
        importRow,
        if (showHardware) hardwareRow,
      ],
    );
  }
}
