import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula_tos_checkboxes.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_list.dart';

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
    super.key,
  });

  final void Function(WalletsManagerAction) onAction;
  final VoidCallback onHardwareWallet;
  final void Function(Wallet, WalletsManagerExistWalletAction) onWalletSelected;
  final VoidCallback onCancel;

  @override
  State<WalletsManagerEntry> createState() => _WalletsManagerEntryState();
}

class _WalletsManagerEntryState extends State<WalletsManagerEntry> {
  late final Stream<List<Wallet>> _walletsStream;

  /// Null until the acceptance check resolves. Treated as "accepted" while
  /// unknown so a slow storage read never blocks the primary action.
  bool? _hasAcceptedCurrentTerms;
  bool _reConsentTicked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveConsent());
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

  Future<void> _resolveConsent() async {
    final accepted = await context
        .read<LegalDocumentsRepository>()
        .hasAcceptedCurrentTerms();
    if (mounted) setState(() => _hasAcceptedCurrentTerms = accepted);
  }

  /// Consent is the act of continuing, so this records and never blocks.
  void _recordConsent(String surface) {
    unawaited(
      context.read<LegalDocumentsRepository>().recordAcceptance(
        surface: surface,
      ),
    );
  }

  bool _actionsEnabled(bool needsReConsent) =>
      !needsReConsent || _reConsentTicked;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      initialData: const <Wallet>[],
      stream: _walletsStream,
      builder: (context, snapshot) {
        final wallets = snapshot.data ?? const <Wallet>[];
        final hasWallets = wallets.isNotEmpty;
        // Only a returning user can have accepted an *older* version, so this
        // never interrupts a genuine first run.
        final needsReConsent = hasWallets && _hasAcceptedCurrentTerms == false;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OnboardingHeader(hasWallets: hasWallets),
            const SizedBox(height: 24),
            if (hasWallets) ...[
              WalletsList(
                walletType: WalletType.iguana,
                wallets: wallets,
                onWalletClick: widget.onWalletSelected,
              ),
              const SizedBox(height: 16),
              const UiDivider(),
              const SizedBox(height: 8),
            ],
            _OnboardingActions(
              hasWallets: hasWallets,
              enabled: _actionsEnabled(needsReConsent),
              onAction: (action) {
                _recordConsent('onboarding');
                widget.onAction(action);
              },
              onHardwareWallet: () {
                _recordConsent('onboarding');
                widget.onHardwareWallet();
              },
            ),
            const SizedBox(height: 16),
            if (needsReConsent)
              // The documents changed under a returning user. Implicit consent
              // is right for a first run, but silently re-accepting on their
              // behalf is not - so this one case asks explicitly.
              EulaTosCheckboxes(
                isChecked: _reConsentTicked,
                onCheck: (checked) =>
                    setState(() => _reConsentTicked = checked),
              )
            else
              const TermsConsentText(),
            const SizedBox(height: 12),
            UiUnderlineTextButton(
              key: const Key('onboarding-cancel-button'),
              text: LocaleKeys.cancel.tr(),
              onPressed: widget.onCancel,
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
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasWallets
                ? LocaleKeys.onboardingReturningTitle.tr()
                : LocaleKeys.onboardingTitle.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
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
    required this.enabled,
    required this.onAction,
    required this.onHardwareWallet,
  });

  final bool hasWallets;
  final bool enabled;
  final void Function(WalletsManagerAction) onAction;
  final VoidCallback onHardwareWallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hardware wallets have never been offered on native mobile.
    final showHardware = !PlatformTuner.isNativeMobile;

    final importRow = UiListActionRow(
      rowKey: const Key('import-wallet-button'),
      title: LocaleKeys.onboardingImportTitle.tr(),
      // The load-bearing string on this screen. "I already have a wallet" asks
      // the user to classify themselves; naming the artifact in their hand asks
      // them only to recognise it.
      subtitle: LocaleKeys.onboardingImportSubtitle.tr(),
      backgroundColor: hasWallets ? theme.cardColor : null,
      onTap: enabled ? () => onAction(WalletsManagerAction.import) : null,
    );

    final hardwareRow = UiListActionRow(
      rowKey: const Key('connect-hardware-wallet-button'),
      title: LocaleKeys.onboardingHardwareTitle.tr(),
      backgroundColor: hasWallets ? theme.cardColor : null,
      onTap: enabled ? onHardwareWallet : null,
    );

    // With wallets already on the device the list is the dominant element, so
    // Create drops to the same weight as Import rather than competing with it.
    if (hasWallets) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiListActionRow(
            rowKey: const Key('create-wallet-button'),
            title: LocaleKeys.onboardingCreateWallet.tr(),
            backgroundColor: theme.cardColor,
            onTap: enabled ? () => onAction(WalletsManagerAction.create) : null,
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
          key: const Key('create-wallet-button'),
          height: 56,
          text: LocaleKeys.onboardingCreateWallet.tr(),
          onPressed: enabled
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
