import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show AssetIdFaucetExtension;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_reason.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_type_tag.dart';
import 'package:web_dex/shared/widgets/gasless_info_dialog.dart';
import 'package:web_dex/shared/widgets/truncate_middle_text.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_button.dart';
import 'package:web_dex/views/wallet/coin_details/receive/trezor_new_address_confirmation.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';
import 'package:web_dex/views/wallet/common/address_icon.dart';

/// Which of a pubkey's two KDF-reported addresses a row or receive dialog
/// displays: the standard address or the GasFree custody address. A gasless
/// pubkey blends into two sibling rows in the address list, one per variant.
enum AddressDisplayVariant { standard, gasfree }

/// One visible address rail. The custody rail deliberately references the
/// canonical KDF pubkey instead of fabricating a second [PubkeyInfo].
@immutable
class AddressRailRow {
  const AddressRailRow({required this.pubkey, required this.variant});

  final PubkeyInfo pubkey;
  final AddressDisplayVariant variant;

  String get address => _addressForVariant(pubkey, variant);
}

String _addressForVariant(PubkeyInfo address, AddressDisplayVariant variant) =>
    variant == AddressDisplayVariant.gasfree &&
        (address.gasfreeAddress?.isNotEmpty ?? false)
    ? address.gasfreeAddress!
    : address.address;

/// Whether [address] carries a KDF-reported GasFree custody address for [coin].
/// Depositing to it lands funds ready to send gaslessly — the network fee is
/// normally paid in the token; exceptional recovery may still require TRX.
bool _isGaslessReceiveAddress(
  Coin coin,
  PubkeyInfo address, {
  required bool gaslessReceiveEnabled,
  required bool isHdWallet,
}) =>
    gaslessReceiveEnabled &&
    coin.id.subClass == CoinSubClass.trc20 &&
    isCanonicalTronGaslessPubkey(address, isHdWallet: isHdWallet) &&
    (address.gasfreeAddress?.isNotEmpty ?? false);

bool _isGaslessCustodyAddress(
  Coin coin,
  PubkeyInfo address, {
  required bool gaslessCustodyVisible,
  required bool isHdWallet,
}) =>
    gaslessCustodyVisible &&
    coin.id.subClass == CoinSubClass.trc20 &&
    isCanonicalTronGaslessPubkey(address, isHdWallet: isHdWallet) &&
    (address.gasfreeAddress?.isNotEmpty ?? false);

bool _isVerifiedGaslessReceiveForAddress(
  BuildContext context,
  Coin coin,
  CoinAddressesState state,
  PubkeyInfo address, {
  AuthBlocState? authState,
}) {
  try {
    final currentUser =
        (authState ?? context.read<AuthBloc>().state).currentUser;
    final walletType = currentUser?.wallet.config.type;
    final currentWalletHash = currentUser?.walletId.pubkeyHash?.trim();
    final attestedWalletHash = state.gaslessReceiveWalletPubkeyHash?.trim();
    if (currentWalletHash == null ||
        currentWalletHash.isEmpty ||
        attestedWalletHash == null ||
        attestedWalletHash.isEmpty ||
        currentWalletHash != attestedWalletHash) {
      return false;
    }
    final isHdWallet = walletType == WalletType.hdwallet;
    if (walletType != WalletType.iguana && !isHdWallet) return false;
    final canonical = state.addresses
        .where(
          (candidate) =>
              isCanonicalTronGaslessPubkey(candidate, isHdWallet: isHdWallet),
        )
        .toList(growable: false);
    if (canonical.length != 1 || canonical.single.address != address.address) {
      return false;
    }
    final accountStatus = state.gaslessAccountStatus;
    if (accountStatus == null ||
        !isVerifiedTronGaslessReceiveStatus(
          accountStatus,
          custodyAddress: address.gasfreeAddress ?? '',
          expectedServiceProvider: tronGaslessServiceProvider,
        )) {
      return false;
    }

    return isVerifiedTronGaslessReceive(
      context.sdk,
      coin.toSdkAsset(context.sdk),
      capabilityReady: state.gaslessReceiveStatus == GaslessReceiveStatus.ready,
      accountStatus: accountStatus,
      accountStatusObservedAt: state.gaslessAccountStatusObservedAt,
      verifiedAddress: state.verifiedGasfreeAddress,
      custodyAddress: address.gasfreeAddress,
      expectedServiceProvider: tronGaslessServiceProvider,
    );
  } catch (_) {
    return false;
  }
}

bool _passesGaslessActionTimeRevalidation(
  BuildContext context,
  PubkeyInfo address,
) {
  final walletEpoch = context
      .read<AuthBloc>()
      .state
      .currentUser
      ?.walletId
      .pubkeyHash
      ?.trim();
  final custodyAddress = address.gasfreeAddress?.trim();
  if (walletEpoch == null ||
      walletEpoch.isEmpty ||
      custodyAddress == null ||
      custodyAddress.isEmpty) {
    return false;
  }
  return context.read<CoinAddressesBloc>().revalidateGaslessReceiveForAction(
    custodyAddress: custodyAddress,
    walletEpoch: walletEpoch,
  );
}

/// Whether the faucet button may be shown on a row displaying [variant]. The
/// faucet drips to the standard (EOA) address, so it belongs on the standard
/// row — dripping while the custody address is displayed would land funds
/// stranded outside the shown account.
bool showFaucetForAddress(Coin coin, AddressDisplayVariant variant) =>
    coin.id.hasFaucet && variant == AddressDisplayVariant.standard;

void _showGaslessReceivePaused(BuildContext context) {
  context.read<CoinAddressesBloc>().add(
    const CoinAddressesGaslessReceiveRefreshRequested(),
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(LocaleKeys.receiveGaslessPausedNotice.tr())),
  );
}

String _gaslessReceiveUnavailableMessage(GaslessReceiveReasonCode? reason) {
  return switch (reason) {
    GaslessReceiveReasonCode.receiveBuildDisabled =>
      LocaleKeys.receiveGaslessBuildDisabledNotice.tr(),
    GaslessReceiveReasonCode.providerTemporarilyUnavailable ||
    GaslessReceiveReasonCode.accountStatusUnavailable =>
      LocaleKeys.receiveGaslessProviderUnavailableNotice.tr(),
    GaslessReceiveReasonCode.pendingTransfer =>
      LocaleKeys.receiveGaslessPendingTransferNotice.tr(),
    GaslessReceiveReasonCode.tokenUnsupported =>
      LocaleKeys.receiveGaslessTokenUnsupportedNotice.tr(),
    GaslessReceiveReasonCode.tokenDecimalsMismatch =>
      LocaleKeys.receiveGaslessDecimalsMismatchNotice.tr(),
    GaslessReceiveReasonCode.custodyAddressMismatch =>
      LocaleKeys.receiveGaslessCustodyMismatchNotice.tr(),
    GaslessReceiveReasonCode.providerIdentityMismatch =>
      LocaleKeys.receiveGaslessProviderMismatchNotice.tr(),
    GaslessReceiveReasonCode.reactivationRequired =>
      LocaleKeys.receiveGaslessReactivationRequiredNotice.tr(),
    GaslessReceiveReasonCode.canonicalAddressAmbiguous ||
    GaslessReceiveReasonCode.custodyAddressMissing =>
      LocaleKeys.receiveGaslessAttestationMissingNotice.tr(),
    GaslessReceiveReasonCode.providerConfigurationInvalid ||
    GaslessReceiveReasonCode.malformedAccountStatus =>
      LocaleKeys.receiveGaslessSecurityBlockedNotice.tr(),
    _ => LocaleKeys.receiveGaslessPausedNotice.tr(),
  };
}

bool _offersOfficialGaslessRecovery(
  GaslessReceiveStatus status,
  GaslessReceiveReasonCode? reason,
  GaslessAccountStatusResponse? accountStatus,
) =>
    status == GaslessReceiveStatus.unsupported &&
    reason == GaslessReceiveReasonCode.tokenUnsupported &&
    accountStatus?.availability == GaslessAccountAvailability.tokenUnsupported;

/// Whether the "GasFree deposits paused" notice belongs on this coin's page.
///
/// [isGaslessRecoveryAsset] is the gate that matters, and it is why TRX is
/// excluded. GasFree is a property of the eligible TRC-20 token, never of the
/// platform coin: `isTronGaslessAssetIdEligible` rejects anything whose
/// subclass is not `trc20` on its first line.
///
/// Without that gate the TRX page raised the banner for a coin that never had
/// GasFree deposits to pause. KDF returns a `gasfree_address` on *every* TRON
/// address, so [hasRetainedCustodyAddress] is true there; nothing sets a
/// reason code on that path, so it fell through to the generic paused copy and
/// read like a provider outage.
///
/// TRX remains inside `isGaslessSingleAddressScope` for address-creation
/// gating - it shares one HD address list with its TRC-20 tokens. That is a
/// separate question from whether a GasFree notice belongs on its page.
bool shouldShowGaslessRecoveryBanner({
  required bool isGaslessRecoveryAsset,
  required bool gaslessReceiveEnabled,
  required bool hasRetainedCustodyAddress,
  required bool gaslessCustodyVisible,
}) =>
    isGaslessRecoveryAsset &&
    !gaslessReceiveEnabled &&
    hasRetainedCustodyAddress &&
    // Reduced from `(!isGaslessRecoveryAsset || !gaslessCustodyVisible)`,
    // which is equivalent once the asset gate above holds. The custody rows
    // already carry their own paused tag, so the banner is for the case where
    // no custody surface is rendered to carry it.
    !gaslessCustodyVisible;

/// Expands pubkeys into display rows: a gasless pubkey becomes a gas-free
/// (custody) row followed by a standard (EOA) row; others stay one row. The
/// gas-free row is exempt from the zero-balance toggle — it is the account
/// itself, and its displayed balance is the asset-level custody balance, not
/// the pubkey's EOA balance — while standard rows follow the normal rule.
List<AddressRailRow> visibleAddressRows(
  Coin coin,
  List<PubkeyInfo> addresses, {
  required bool hideZeroBalance,
  required bool gaslessReceiveEnabled,
  required bool isHdWallet,
  bool? gaslessCustodyVisible,
}) {
  final showCustody = gaslessCustodyVisible ?? gaslessReceiveEnabled;
  final entries = <AddressRailRow>[
    for (final address in addresses) ...[
      if (_isGaslessCustodyAddress(
        coin,
        address,
        gaslessCustodyVisible: showCustody,
        isHdWallet: isHdWallet,
      ))
        AddressRailRow(pubkey: address, variant: AddressDisplayVariant.gasfree),
      AddressRailRow(pubkey: address, variant: AddressDisplayVariant.standard),
    ],
  ];
  return entries
      .where(
        (entry) =>
            !hideZeroBalance ||
            entry.variant == AddressDisplayVariant.gasfree ||
            entry.pubkey.balance.spendable != Decimal.zero,
      )
      .toList();
}

/// A green "gasless" pill shown only after the TRC-20 custody address has been
/// freshly verified. When [assetName] is provided, a trailing info affordance
/// opens [GaslessInfoDialog] (fees, recovery, and provider dependence).
class _GaslessReceiveBadge extends StatelessWidget {
  const _GaslessReceiveBadge({this.assetName});

  final String? assetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.success);
    final name = assetName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 18, color: style.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.receiveGaslessBadgeTitle.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: style.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  LocaleKeys.receiveGaslessBadgeSubtitle.tr(
                    args: [name ?? 'USDT'],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: style.foreground,
                  ),
                ),
              ],
            ),
          ),
          if (name != null)
            IconButton(
              key: const Key('receive-gasless-info-button'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: style.accent,
              ),
              tooltip: LocaleKeys.gaslessInfoTitle.tr(),
              onPressed: () => GaslessInfoDialog.show(context, assetName: name),
            ),
        ],
      ),
    );
  }
}

/// Stable, rail-specific progress treatment shown after Standard addresses
/// have loaded but while the short-lived GasFree status is being refreshed.
class _GaslessReceiveCheckingBanner extends StatelessWidget {
  const _GaslessReceiveCheckingBanner();

  @override
  Widget build(BuildContext context) {
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.info);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        label: LocaleKeys.withdrawGaslessCheckingAvailability.tr(),
        child: NoticeBanner(
          key: const Key('gasless-receive-checking-banner'),
          icon: Icons.sync_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.withdrawGaslessCheckingAvailability.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: disableAnimations
                    ? Container(
                        height: 4,
                        color: style.accent.withValues(alpha: 0.42),
                      )
                    : LinearProgressIndicator(
                        minHeight: 4,
                        color: style.accent,
                        backgroundColor: style.accent.withValues(alpha: 0.16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact per-row tag telling the two blended rows of a gasless pubkey
/// apart: a success-toned "Gas-free" pill on the custody row and a muted
/// "Standard · uses TRX" chip on the EOA row. Only rendered for gasless
/// pubkeys — plain coins keep untagged rows.
class _AddressVariantTag extends StatelessWidget {
  const _AddressVariantTag({
    required this.variant,
    this.receiveEnabled = true,
    this.receiveChecking = false,
  });

  final AddressDisplayVariant variant;
  final bool receiveEnabled;
  final bool receiveChecking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (variant == AddressDisplayVariant.gasfree) {
      if (receiveChecking) {
        final checkingStyle = NoticeBanner.styleOf(
          context,
          NoticeBannerVariant.info,
        );
        return Container(
          key: const Key('address-row-gasfree-checking-tag'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: checkingStyle.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: checkingStyle.accent),
          ),
          child: Text(
            LocaleKeys.addressRowGasfreeCheckingTag.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: checkingStyle.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      final style = NoticeBanner.styleOf(
        context,
        receiveEnabled ? NoticeBannerVariant.success : NoticeBannerVariant.info,
      );
      return Container(
        key: const Key('address-row-gasfree-tag'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.accent.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, size: 14, color: style.accent),
            Text(
              (receiveEnabled
                      ? LocaleKeys.addressRowGasfreeTag
                      : LocaleKeys.addressRowGasfreePausedTag)
                  .tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      LocaleKeys.addressRowStandardTag.tr(),
      key: const Key('address-row-standard-tag'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
      ),
    );
  }
}

class _GaslessRecoveryBanner extends StatelessWidget {
  const _GaslessRecoveryBanner({
    required this.isTestnet,
    required this.status,
    this.reason,
    this.accountStatus,
  });

  final bool isTestnet;
  final GaslessReceiveStatus status;
  final GaslessReceiveReasonCode? reason;
  final GaslessAccountStatusResponse? accountStatus;

  @override
  Widget build(BuildContext context) {
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);
    final offersOfficialRecovery = _offersOfficialGaslessRecovery(
      status,
      reason,
      accountStatus,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NoticeBanner(
        key: const Key('gasless-recovery-banner'),
        icon: Icons.warning_amber_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.gaslessRecoveryTitle.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _gaslessReceiveUnavailableMessage(reason),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: style.foreground),
            ),
            if (offersOfficialRecovery) ...[
              const SizedBox(height: 4),
              Text(
                LocaleKeys.gaslessRecoveryBody.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: style.foreground),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('gasless-official-recovery-action'),
                onPressed: () => launchURLString(
                  tronGaslessRecoveryUrl(isTestnet: isTestnet),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(LocaleKeys.gaslessRecoveryAction.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GaslessRecoveryInline extends StatelessWidget {
  const _GaslessRecoveryInline({
    required this.isTestnet,
    required this.status,
    this.reason,
    this.accountStatus,
  });

  final bool isTestnet;
  final GaslessReceiveStatus status;
  final GaslessReceiveReasonCode? reason;
  final GaslessAccountStatusResponse? accountStatus;

  @override
  Widget build(BuildContext context) {
    final offersOfficialRecovery = _offersOfficialGaslessRecovery(
      status,
      reason,
      accountStatus,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _gaslessReceiveUnavailableMessage(reason),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (offersOfficialRecovery) ...[
            const SizedBox(height: 4),
            Text(
              LocaleKeys.gaslessRecoveryBody.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('gasless-custody-recovery-action'),
              onPressed: () =>
                  launchURLString(tronGaslessRecoveryUrl(isTestnet: isTestnet)),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(LocaleKeys.gaslessRecoveryAction.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

class CoinAddresses extends StatefulWidget {
  const CoinAddresses({
    super.key,
    required this.coin,
    required this.setPageType,
  });

  final Coin coin;
  final void Function(CoinPageType) setPageType;

  @override
  State<CoinAddresses> createState() => _CoinAddressesState();
}

class _CoinAddressesState extends State<CoinAddresses>
    with WidgetsBindingObserver {
  // No need to store a reference to the bloc since we don't manage its lifecycle
  bool _showAllAddresses = false;

  int get _collapsedLimit => isMobile ? 3 : 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    context.read<CoinAddressesBloc>().add(
      CoinAddressesGaslessReceiveVisibilityChanged(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remove bloc.close() - the bloc is owned and managed by the parent widget
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, authState) {
        final walletType = authState.currentUser?.wallet.config.type;
        final isSoftwareWallet =
            walletType == WalletType.iguana ||
            walletType == WalletType.hdwallet;
        final gaslessReceiveConfigured =
            isSoftwareWallet && widget.coin.isGaslessReceiveAsset(context.sdk);
        return BlocConsumer<CoinAddressesBloc, CoinAddressesState>(
          listenWhen: (prev, curr) =>
              prev.createAddressStatus != curr.createAddressStatus ||
              prev.newAddressState?.status != curr.newAddressState?.status,
          listener: (context, blocState) {
            if (blocState.newAddressState?.status ==
                NewAddressStatus.confirmAddress) {
              final coinAddressesBloc = context.read<CoinAddressesBloc>();
              showDialog<void>(
                context: context,
                builder: (context) => BlocProvider.value(
                  value: coinAddressesBloc,
                  child: const _NewAddressDialog(),
                ),
              );
            }
          },
          builder: (context, state) {
            final isHdWallet = walletType == WalletType.hdwallet;
            final hasVerifiedGaslessAddress = state.addresses.any(
              (address) =>
                  isCanonicalTronGaslessPubkey(
                    address,
                    isHdWallet: isHdWallet,
                  ) &&
                  _isVerifiedGaslessReceiveForAddress(
                    context,
                    widget.coin,
                    state,
                    address,
                  ),
            );
            final gaslessReceiveEnabled =
                gaslessReceiveConfigured && hasVerifiedGaslessAddress;
            final gaslessCustodyVisible =
                isSoftwareWallet && widget.coin.isGaslessRecoveryAsset;
            final errorMessage = state.errorMessage?.trim();
            final hasRetainedCustodyAddress = state.addresses.any(
              (address) =>
                  address.gasfreeAddress?.isNotEmpty == true &&
                  (!widget.coin.isGaslessRecoveryAsset ||
                      !isSoftwareWallet ||
                      isCanonicalTronGaslessPubkey(
                        address,
                        isHdWallet: isHdWallet,
                      )),
            );
            final showRecoveryBanner = shouldShowGaslessRecoveryBanner(
              isGaslessRecoveryAsset: widget.coin.isGaslessRecoveryAsset,
              gaslessReceiveEnabled: gaslessReceiveEnabled,
              hasRetainedCustodyAddress: hasRetainedCustodyAddress,
              gaslessCustodyVisible: gaslessCustodyVisible,
            );
            final rows = visibleAddressRows(
              widget.coin,
              state.addresses,
              hideZeroBalance: state.hideZeroBalance,
              gaslessReceiveEnabled: gaslessReceiveEnabled,
              isHdWallet: isHdWallet,
              gaslessCustodyVisible: gaslessCustodyVisible,
            );
            // Gleec's rollout exposes custody only for the primary address,
            // even though KDF and the generic SDK support other valid HD
            // selectors. Scoped to TRX as well as TRC-20 because they share
            // one address list. Existing secondary addresses remain visible
            // for Standard transfers and recovery. The gate is CONFIG-driven
            // (not derived from pubkeys) so a provider outage that leaves
            // gasfreeAddress empty cannot open a creation window.
            // The custody count, used for the custody-balance pairing, stays
            // pubkey-driven (one per key, not per blended row) and is counted
            // on the unfiltered list so a pubkey hidden by the zero-balance
            // toggle still counts.
            final gaslessSingleAddress =
                widget.coin.isGaslessSingleAddressScope(context.sdk) &&
                isSoftwareWallet;
            final gaslessAddressCount = state.addresses
                .where(
                  (address) => _isGaslessCustodyAddress(
                    widget.coin,
                    address,
                    gaslessCustodyVisible: gaslessCustodyVisible,
                    isHdWallet: isHdWallet,
                  ),
                )
                .length;
            final bool hasMore = rows.length > _collapsedLimit;
            final bool showAll = _showAllAddresses || !hasMore;
            final List<AddressRailRow> visibleRows = showAll
                ? rows
                : rows.take(_collapsedLimit).toList();

            return SliverToBoxAdapter(
              child: Column(
                children: [
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    color: theme.custom.dexPageTheme.frontPlate,
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (gaslessReceiveConfigured &&
                              state.gaslessReceiveStatus ==
                                  GaslessReceiveStatus.checking)
                            const _GaslessReceiveCheckingBanner(),
                          if (showRecoveryBanner)
                            _GaslessRecoveryBanner(
                              isTestnet: widget.coin.isTestCoin,
                              status: state.gaslessReceiveStatus,
                              reason: state.gaslessReceiveReason,
                              accountStatus: state.gaslessAccountStatus,
                            ),
                          _Header(
                            status: state.status,
                            createAddressStatus: state.createAddressStatus,
                            hideZeroBalance: state.hideZeroBalance,
                            cantCreateNewAddressReasons:
                                state.cantCreateNewAddressReasons,
                            gaslessSingleAddress: gaslessSingleAddress,
                          ),
                          const SizedBox(height: 12),
                          ...visibleRows.map(
                            (entry) => AddressCard(
                              // Sibling rows share a pubkey, so the variant is
                              // part of the row's identity.
                              key: ValueKey(
                                'address-card-${entry.variant.name}-'
                                '${entry.pubkey.address}',
                              ),
                              address: entry.pubkey,
                              variant: entry.variant,
                              coin: widget.coin,
                              setPageType: widget.setPageType,
                              isSoleGaslessRow: gaslessAddressCount == 1,
                              gaslessReceiveEnabled: gaslessReceiveEnabled,
                              gaslessReceiveStatus: state.gaslessReceiveStatus,
                              gaslessReceiveReason: state.gaslessReceiveReason,
                              gaslessAccountStatus: state.gaslessAccountStatus,
                            ),
                          ),
                          if (hasMore)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                expanded: _showAllAddresses,
                                child: TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _showAllAddresses = !_showAllAddresses;
                                    });
                                  },
                                  child: Text(
                                    _showAllAddresses
                                        ? LocaleKeys.showLessAddresses.tr()
                                        : LocaleKeys.showAllAddresses.tr(),
                                  ),
                                ),
                              ),
                            ),
                          if (state.status == FormStatus.submitting)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20.0),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (state.status == FormStatus.failure ||
                              state.createAddressStatus == FormStatus.failure)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20.0,
                              ),
                              child: Center(
                                child: ErrorDisplay(
                                  message:
                                      (errorMessage != null &&
                                          errorMessage.isNotEmpty)
                                      ? errorMessage
                                      : LocaleKeys.somethingWrong.tr(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (isMobile)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CreateButton(
                        status: state.status,
                        createAddressStatus: state.createAddressStatus,
                        cantCreateNewAddressReasons:
                            state.cantCreateNewAddressReasons,
                        gaslessSingleAddress: gaslessSingleAddress,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.createAddressStatus,
    required this.hideZeroBalance,
    required this.cantCreateNewAddressReasons,
    required this.gaslessSingleAddress,
  });

  final FormStatus status;
  final FormStatus createAddressStatus;
  final bool hideZeroBalance;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;
  final bool gaslessSingleAddress;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      HideZeroBalanceCheckbox(hideZeroBalance: hideZeroBalance),
      if (!isMobile)
        SizedBox(
          width: 200,
          child: CreateButton(
            status: status,
            createAddressStatus: createAddressStatus,
            cantCreateNewAddressReasons: cantCreateNewAddressReasons,
            gaslessSingleAddress: gaslessSingleAddress,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AddressesTitle(),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 12, children: controls),
            ],
          );
        }

        return Row(
          children: [
            const AddressesTitle(),
            const Spacer(),
            ...controls.expand(
              (control) => [const SizedBox(width: 16), control],
            ),
          ],
        );
      },
    );
  }
}

class AddressCard extends StatelessWidget {
  const AddressCard({
    super.key,
    required this.address,
    required this.coin,
    required this.setPageType,
    this.variant = AddressDisplayVariant.standard,
    this.isSoleGaslessRow = false,
    this.gaslessReceiveEnabled = false,
    this.gaslessReceiveStatus = GaslessReceiveStatus.initial,
    this.gaslessReceiveReason,
    this.gaslessAccountStatus,
  });

  final PubkeyInfo address;
  final Coin coin;
  final void Function(CoinPageType) setPageType;

  /// Which of [address]'s addresses this row displays.
  final AddressDisplayVariant variant;

  /// Whether this coin has exactly one gasless (custody) pubkey — the only
  /// case where the asset-level custody balance can be attributed to a
  /// single row. See [_Balance].
  final bool isSoleGaslessRow;
  final bool gaslessReceiveEnabled;
  final GaslessReceiveStatus gaslessReceiveStatus;
  final GaslessReceiveReasonCode? gaslessReceiveReason;
  final GaslessAccountStatusResponse? gaslessAccountStatus;

  @override
  Widget build(BuildContext context) {
    final canOpenReceive =
        variant != AddressDisplayVariant.gasfree || gaslessReceiveEnabled;
    final gaslessReceiveChecking =
        gaslessReceiveStatus == GaslessReceiveStatus.checking;
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      color: theme.custom.dexPageTheme.emptyPlace,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The wide row reserves space for the address, rail badge,
            // actions, and balance. At typical 800px test/window widths the
            // card's own padding leaves too little room for that fixed
            // composition, especially with a long ticker or paused badge.
            final useCompactLayout =
                constraints.maxWidth < 840 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final onTapAddress = canOpenReceive
                ? () => showPubkeyReceiveDialog(
                    context,
                    coin,
                    address,
                    variant: variant,
                    gaslessReceiveEnabled: gaslessReceiveEnabled,
                  )
                : null;

            final content = useCompactLayout
                ? _MobileAddressContent(
                    address: address,
                    coin: coin,
                    variant: variant,
                    isSoleGaslessRow: isSoleGaslessRow,
                    gaslessReceiveEnabled: gaslessReceiveEnabled,
                    gaslessReceiveChecking: gaslessReceiveChecking,
                    gaslessAccountStatus: gaslessAccountStatus,
                    onTapAddress: onTapAddress,
                  )
                : _DesktopAddressContent(
                    address: address,
                    coin: coin,
                    variant: variant,
                    isSoleGaslessRow: isSoleGaslessRow,
                    gaslessReceiveEnabled: gaslessReceiveEnabled,
                    gaslessReceiveChecking: gaslessReceiveChecking,
                    gaslessAccountStatus: gaslessAccountStatus,
                    onTapAddress: onTapAddress,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                if (variant == AddressDisplayVariant.gasfree &&
                    !gaslessReceiveEnabled &&
                    !gaslessReceiveChecking)
                  _GaslessRecoveryInline(
                    isTestnet: coin.isTestCoin,
                    status: gaslessReceiveStatus,
                    reason: gaslessReceiveReason,
                    accountStatus: gaslessAccountStatus,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Same receive/QR dialog as [QrButton] and the Receive flow. A null
/// [variant] lets the dialog pick (gas-free when available), preserving the
/// behavior of call sites that predate the blended rows.
void showPubkeyReceiveDialog(
  BuildContext context,
  Coin coin,
  PubkeyInfo address, {
  AddressDisplayVariant? variant,
  bool gaslessReceiveEnabled = false,
}) {
  final wantsGaslessReceive =
      gaslessReceiveEnabled && variant != AddressDisplayVariant.standard;
  CoinAddressesBloc? addressesBloc;
  if (wantsGaslessReceive) {
    addressesBloc = context.read<CoinAddressesBloc>();
    if (!_passesGaslessActionTimeRevalidation(context, address) ||
        !_isVerifiedGaslessReceiveForAddress(
          context,
          coin,
          addressesBloc.state,
          address,
        )) {
      _showGaslessReceivePaused(context);
      return;
    }
  }

  showDialog<void>(
    context: context,
    builder: (context) {
      final dialog = PubkeyReceiveDialog(
        coin: coin,
        address: address,
        variant: variant,
        gaslessReceiveEnabled: gaslessReceiveEnabled,
      );
      return addressesBloc == null
          ? dialog
          : BlocProvider<CoinAddressesBloc>.value(
              value: addressesBloc,
              child: dialog,
            );
    },
  );
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.address,
    required this.coin,
    required this.variant,
    required this.isSoleGaslessRow,
    this.gaslessAccountStatus,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;
  final GaslessAccountStatusResponse? gaslessAccountStatus;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    // The custody row is populated only from the typed account-status snapshot.
    // This keeps custody-total freshness separate from the standard EOA balance
    // and avoids a second balance source disagreeing with KDF availability.
    // Only a sole canonical GasFree pubkey may consume the asset-level snapshot.
    final isGaslessCustody =
        variant == AddressDisplayVariant.gasfree && isSoleGaslessRow;
    final custodyTotal =
        isGaslessCustody &&
            gaslessAccountStatus?.gasfreeAddress ==
                _addressForVariant(address, variant)
        ? gaslessAccountStatus?.onChainBalance
        : null;
    final Decimal? total = isGaslessCustody
        ? custodyTotal
        : address.balance.total;
    if (total == null) {
      return Text(
        '— ${abbr2Ticker(coin.abbr)}',
        style: TextStyle(fontSize: isMobile ? 12 : 14),
      );
    }
    final price = coin.lastKnownUsdPrice(context.sdk);
    final usdValue = price == null ? null : price * total.toDouble();
    final fiat = hideBalances ? maskedBalanceText : formatUsdValue(usdValue);

    return Text(
      hideBalances
          ? '$maskedBalanceText ${abbr2Ticker(coin.abbr)} ($fiat)'
          : '${doubleToString(total.toDouble())} '
                '${abbr2Ticker(coin.abbr)} ($fiat)',
      style: TextStyle(fontSize: isMobile ? 12 : 14),
    );
  }
}

class _MobileAddressContent extends StatelessWidget {
  const _MobileAddressContent({
    required this.address,
    required this.coin,
    required this.variant,
    required this.isSoleGaslessRow,
    required this.gaslessReceiveEnabled,
    required this.gaslessReceiveChecking,
    this.gaslessAccountStatus,
    this.onTapAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;
  final bool gaslessReceiveEnabled;
  final bool gaslessReceiveChecking;
  final GaslessAccountStatusResponse? gaslessAccountStatus;
  final VoidCallback? onTapAddress;

  @override
  Widget build(BuildContext context) {
    final rowAddress = _addressForVariant(address, variant);
    final isGaslessCustody = variant == AddressDisplayVariant.gasfree;
    final hasGaslessSibling =
        coin.isGaslessRecoveryAsset &&
        (address.gasfreeAddress?.isNotEmpty ?? false) &&
        isCanonicalTronGaslessPubkey(
          address,
          isHdWallet: address.derivationPath != null,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AddressIcon(address: rowAddress),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                key: const Key('address-row-receive-action'),
                button: true,
                enabled: onTapAddress != null,
                label: '${LocaleKeys.receive.tr()}: $rowAddress',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: InkWell(
                    onTap: onTapAddress,
                    excludeFromSemantics: true,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TruncatedMiddleText(
                        rowAddress,
                        style:
                            Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (isGaslessCustody || hasGaslessSibling)
              _AddressVariantTag(
                variant: variant,
                receiveEnabled: gaslessReceiveEnabled,
                receiveChecking: gaslessReceiveChecking,
              ),
            if (!isGaslessCustody || gaslessReceiveEnabled) ...[
              if (isGaslessCustody)
                _GaslessAddressCopyButton(coin: coin, address: address)
              else
                AddressCopyButton(address: rowAddress, coinAbbr: coin.abbr),
              QrButton(
                coin: coin,
                address: address,
                variant: variant,
                gaslessReceiveEnabled: gaslessReceiveEnabled,
              ),
            ],
            if (showFaucetForAddress(coin, variant))
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
                child: FaucetButton(coinAbbr: coin.abbr, address: address),
              ),
            if (variant == AddressDisplayVariant.standard)
              SwapAddressTag(address: address),
          ],
        ),
        const SizedBox(height: 8),
        _Balance(
          address: address,
          coin: coin,
          variant: variant,
          isSoleGaslessRow: isSoleGaslessRow,
          gaslessAccountStatus: gaslessAccountStatus,
        ),
      ],
    );
  }
}

class _DesktopAddressContent extends StatelessWidget {
  const _DesktopAddressContent({
    required this.address,
    required this.coin,
    required this.variant,
    required this.isSoleGaslessRow,
    required this.gaslessReceiveEnabled,
    required this.gaslessReceiveChecking,
    this.gaslessAccountStatus,
    this.onTapAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;
  final bool gaslessReceiveEnabled;
  final bool gaslessReceiveChecking;
  final GaslessAccountStatusResponse? gaslessAccountStatus;
  final VoidCallback? onTapAddress;

  @override
  Widget build(BuildContext context) {
    final rowAddress = _addressForVariant(address, variant);
    final isGaslessCustody = variant == AddressDisplayVariant.gasfree;
    final hasGaslessSibling =
        coin.isGaslessRecoveryAsset &&
        (address.gasfreeAddress?.isNotEmpty ?? false) &&
        isCanonicalTronGaslessPubkey(
          address,
          isHdWallet: address.derivationPath != null,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AddressIcon(address: rowAddress),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            key: const Key('address-row-desktop-receive-action'),
            button: true,
            enabled: onTapAddress != null,
            label: '${LocaleKeys.receive.tr()}: $rowAddress',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: InkWell(
                onTap: onTapAddress,
                excludeFromSemantics: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TruncatedMiddleText(
                    rowAddress,
                    style:
                        Theme.of(context).textTheme.bodyMedium ??
                        const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Outside the fixed-width actions box: the tag would force the Wrap
        // onto a second line there.
        if (isGaslessCustody || hasGaslessSibling) ...[
          const SizedBox(width: 8),
          _AddressVariantTag(
            variant: variant,
            receiveEnabled: gaslessReceiveEnabled,
            receiveChecking: gaslessReceiveChecking,
          ),
        ],
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isGaslessCustody || gaslessReceiveEnabled) ...[
                  if (isGaslessCustody)
                    _GaslessAddressCopyButton(coin: coin, address: address)
                  else
                    AddressCopyButton(address: rowAddress, coinAbbr: coin.abbr),
                  QrButton(
                    coin: coin,
                    address: address,
                    variant: variant,
                    gaslessReceiveEnabled: gaslessReceiveEnabled,
                  ),
                ],
                if (showFaucetForAddress(coin, variant))
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 80,
                      maxWidth: 160,
                    ),
                    child: FaucetButton(coinAbbr: coin.abbr, address: address),
                  ),
                if (variant == AddressDisplayVariant.standard)
                  SwapAddressTag(address: address),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140),
          child: Align(
            alignment: Alignment.centerRight,
            child: _Balance(
              address: address,
              coin: coin,
              variant: variant,
              isSoleGaslessRow: isSoleGaslessRow,
              gaslessAccountStatus: gaslessAccountStatus,
            ),
          ),
        ),
      ],
    );
  }
}

class _GaslessAddressCopyButton extends StatelessWidget {
  const _GaslessAddressCopyButton({required this.coin, required this.address});

  final Coin coin;
  final PubkeyInfo address;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      splashRadius: 18,
      icon: const Icon(Icons.copy, size: 16),
      color: Theme.of(context).textTheme.bodyMedium?.color,
      tooltip: LocaleKeys.copyAddressToClipboard.tr(args: [coin.abbr]),
      onPressed: () {
        final state = context.read<CoinAddressesBloc>().state;
        if (!_passesGaslessActionTimeRevalidation(context, address) ||
            !_isVerifiedGaslessReceiveForAddress(
              context,
              coin,
              state,
              address,
            )) {
          _showGaslessReceivePaused(context);
          return;
        }

        copyToClipBoard(
          context,
          address.gasfreeAddress!,
          LocaleKeys.copiedAddressToClipboard.tr(args: [coin.abbr]),
        );
      },
    );
  }
}

class QrButton extends StatelessWidget {
  const QrButton({
    super.key,
    required this.address,
    required this.coin,
    this.variant,
    this.gaslessReceiveEnabled = false,
  });

  final PubkeyInfo address;
  final Coin coin;
  final bool gaslessReceiveEnabled;

  /// Address variant the opened receive dialog pins to; null lets the dialog
  /// pick (gas-free when available).
  final AddressDisplayVariant? variant;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.hardEdge,
      child: IconButton(
        splashRadius: 18,
        icon: const Icon(Icons.qr_code, size: 16),
        color: Theme.of(context).textTheme.bodyMedium!.color,
        tooltip: LocaleKeys.scanTheQrCode.tr(),
        onPressed: () => showPubkeyReceiveDialog(
          context,
          coin,
          address,
          variant: variant,
          gaslessReceiveEnabled: gaslessReceiveEnabled,
        ),
      ),
    );
  }
}

class PubkeyReceiveDialog extends StatelessWidget {
  const PubkeyReceiveDialog({
    super.key,
    required this.coin,
    required this.address,
    this.variant,
    this.gaslessReceiveEnabled = false,
  });

  final Coin coin;
  final PubkeyInfo address;
  final bool gaslessReceiveEnabled;

  /// Which of [address]'s addresses to receive on. Null picks automatically:
  /// the gas-free (custody) address when available, else the standard one.
  final AddressDisplayVariant? variant;

  @override
  Widget build(BuildContext context) {
    final wantsGasfreeSurface =
        gaslessReceiveEnabled &&
        variant != AddressDisplayVariant.standard &&
        address.gasfreeAddress?.isNotEmpty == true;
    if (wantsGasfreeSurface) {
      final addressesState = context.watch<CoinAddressesBloc>().state;
      final authState = context.watch<AuthBloc>().state;
      if (!_isVerifiedGaslessReceiveForAddress(
        context,
        coin,
        addressesState,
        address,
        authState: authState,
      )) {
        return AlertDialog(
          key: const Key('gasless-receive-paused-dialog'),
          title: Semantics(header: true, child: Text(LocaleKeys.receive.tr())),
          content: SingleChildScrollView(
            child: _GaslessRecoveryBanner(
              isTestnet: coin.isTestCoin,
              status: addressesState.gaslessReceiveStatus,
              reason: addressesState.gaslessReceiveReason,
              accountStatus: addressesState.gaslessAccountStatus,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        );
      }
    }

    final isGaslessPubkey = _isGaslessReceiveAddress(
      coin,
      address,
      gaslessReceiveEnabled: gaslessReceiveEnabled,
      // The dialog receives an already-authorized row from CoinAddressesBloc.
      // Re-derive HD shape from immutable key metadata so isolated routes and
      // widget tests do not need to reach across the tree for AuthBloc.
      isHdWallet: address.derivationPath?.trim().isNotEmpty == true,
    );
    final effectiveVariant = isGaslessPubkey
        ? (variant ?? AddressDisplayVariant.gasfree)
        : AddressDisplayVariant.standard;
    final receiveAddress = _addressForVariant(address, effectiveVariant);
    final showGasfreeSurface =
        isGaslessPubkey && effectiveVariant == AddressDisplayVariant.gasfree;
    final showStandardCaveat =
        isGaslessPubkey && effectiveVariant == AddressDisplayVariant.standard;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                LocaleKeys.receive.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.hardEdge,
            child: IconButton(
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        // Scrollable: the gasless badge + standard-address disclosure can
        // exceed a small phone's dialog height once the disclosure expands.
        // (Not AlertDialog.scrollable — its intrinsic-width pass trips over
        // the QR widget's internal LayoutBuilder.)
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                showGasfreeSurface
                    ? LocaleKeys.receiveGaslessOnlySendToAddress.tr(
                        args: [abbr2Ticker(coin.abbr)],
                      )
                    : LocaleKeys.onlySendToThisAddress.tr(
                        args: [abbr2Ticker(coin.abbr)],
                      ),
                style: const TextStyle(fontSize: 14),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        LocaleKeys.network.tr(),
                        style: const TextStyle(fontSize: 14),
                      ),
                      CoinTypeTag(coin),
                    ],
                  ),
                ),
              ),
              QrCode(address: receiveAddress, coinAbbr: coin.abbr),
              const SizedBox(height: 8),
              // Caption kept directly under its referent — previously it
              // rendered below the address row and the (possibly expanded)
              // disclosure, orphaned from the QR it describes.
              Text(
                LocaleKeys.scanTheQrCode.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _AddressCopyRow(
                coin: coin,
                address: receiveAddress,
                canUseAddress: showGasfreeSurface
                    ? () =>
                          _passesGaslessActionTimeRevalidation(
                            context,
                            address,
                          ) &&
                          _isVerifiedGaslessReceiveForAddress(
                            context,
                            coin,
                            context.read<CoinAddressesBloc>().state,
                            address,
                          )
                    : null,
              ),
              if (showGasfreeSurface) ...[
                const SizedBox(height: 12),
                _GaslessReceiveBadge(assetName: abbr2Ticker(coin.abbr)),
                const SizedBox(height: 8),
                _StandardAddressDisclosure(coin: coin, address: address),
              ],
              if (showStandardCaveat) ...[
                const SizedBox(height: 12),
                _StandardVariantCaveat(coin: coin, address: address),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact address row with copy and explorer-link actions.
class _AddressCopyRow extends StatelessWidget {
  const _AddressCopyRow({
    required this.coin,
    required this.address,
    this.canUseAddress,
  });

  final Coin coin;
  final String address;
  final bool Function()? canUseAddress;

  @override
  Widget build(BuildContext context) {
    Widget addressText() => TruncatedMiddleText(
      address,
      style:
          Theme.of(context).textTheme.bodySmall ??
          const TextStyle(fontSize: 12),
    );

    final copyButton = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.hardEdge,
      child: IconButton(
        tooltip: LocaleKeys.copyAddressToClipboard.tr(args: [coin.abbr]),
        icon: const Icon(Icons.copy_rounded, size: 20),
        onPressed: () {
          if (canUseAddress?.call() == false) {
            _showGaslessReceivePaused(context);
            return;
          }
          copyToClipBoard(
            context,
            address,
            LocaleKeys.copiedAddressToClipboard.tr(args: [coin.abbr]),
          );
        },
      ),
    );
    final explorerButton = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.hardEdge,
      child: IconButton(
        tooltip: LocaleKeys.viewOnExplorer.tr(),
        icon: const Icon(Icons.open_in_new, size: 20),
        onPressed: () {
          final url = getAddressExplorerUrl(coin, address);
          if (url.isNotEmpty) {
            launchURLString(url, inSeparateTab: true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(LocaleKeys.explorerUnavailable.tr())),
            );
          }
        },
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 220 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                addressText(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [copyButton, explorerButton],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: addressText()),
              copyButton,
              explorerButton,
            ],
          );
        },
      ),
    );
  }
}

/// Collapsed escape hatch revealing the standard (EOA) TRON address for
/// exchanges that refuse withdrawals to smart-contract addresses. Copy-only —
/// the QR code stays custody-only so the happy path is unambiguous. Funds
/// received on the standard address are NOT gaslessly spendable, which the
/// amber caveat (and, when funded, the stranded-balance line) makes explicit.
class _StandardAddressDisclosure extends StatefulWidget {
  const _StandardAddressDisclosure({required this.coin, required this.address});

  final Coin coin;
  final PubkeyInfo address;

  @override
  State<_StandardAddressDisclosure> createState() =>
      _StandardAddressDisclosureState();
}

class _StandardAddressDisclosureState
    extends State<_StandardAddressDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);
    final foreground = style.foreground;
    final eoaSpendable = widget.address.balance.spendable;

    // A real toggle in both directions: the caveat block is a side path, so
    // the user can put it away again once the address is copied.
    final toggle = Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        key: const Key('receive-standard-address-disclosure-semantics'),
        expanded: _expanded,
        child: TextButton(
          key: const Key('receive-standard-address-toggle'),
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(48, 48),
          ),
          child: Row(
            children: [
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  LocaleKeys.receiveStandardAddressToggle.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!_expanded) return toggle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        toggle,
        NoticeBanner(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.receiveStandardAddressCaveat.tr(),
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.receiveStandardAddressLabel.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              KeyedSubtree(
                key: const Key('receive-standard-address-row'),
                child: _AddressCopyRow(
                  coin: widget.coin,
                  address: widget.address.address,
                ),
              ),
              if (eoaSpendable > Decimal.zero) ...[
                const SizedBox(height: 8),
                Text(
                  LocaleKeys.receiveStandardBalanceNotice.tr(
                    args: [formatDexAmt(eoaSpendable), widget.coin.abbr],
                  ),
                  key: const Key('receive-standard-balance-notice'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Amber caveat shown when the receive dialog is pinned to the standard (EOA)
/// row of a gasless pubkey: funds received here can't be sent gas-free, and
/// moving them later needs TRX. When the address already holds a stranded
/// balance, it is spelled out — mirroring [_StandardAddressDisclosure], which
/// serves the same warning on the custody-first dialog.
class _StandardVariantCaveat extends StatelessWidget {
  const _StandardVariantCaveat({required this.coin, required this.address});

  final Coin coin;
  final PubkeyInfo address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = NoticeBanner.styleOf(
      context,
      NoticeBannerVariant.warning,
    ).foreground;
    final eoaSpendable = address.balance.spendable;
    return NoticeBanner(
      key: const Key('receive-standard-variant-caveat'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.receiveStandardVariantCaveat.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
          if (eoaSpendable > Decimal.zero) ...[
            const SizedBox(height: 8),
            Text(
              LocaleKeys.receiveStandardBalanceNotice.tr(
                args: [formatDexAmt(eoaSpendable), coin.abbr],
              ),
              key: const Key('receive-standard-balance-notice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SwapAddressTag extends StatelessWidget {
  const SwapAddressTag({super.key, required this.address});

  final PubkeyInfo address;

  @override
  Widget build(BuildContext context) {
    // TODO: Refactor to use "DexPill" component from the SDK UI library (not yet created)
    return address.isActiveForSwap
        ? Padding(
            padding: EdgeInsets.only(left: isMobile ? 4 : 8),
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: isMobile ? 6 : 8,
                horizontal: isMobile ? 8 : 12.0,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Text(
                LocaleKeys.swapAddress.tr(),
                style: TextStyle(fontSize: isMobile ? 9 : 12),
              ),
            ),
          )
        : const SizedBox.shrink();
  }
}

class AddressesTitle extends StatelessWidget {
  const AddressesTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.addresses.tr(),
      style: TextStyle(
        fontSize: isMobile ? 14 : 24,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class HideZeroBalanceCheckbox extends StatelessWidget {
  final bool hideZeroBalance;

  const HideZeroBalanceCheckbox({super.key, required this.hideZeroBalance});

  @override
  Widget build(BuildContext context) {
    return UiCheckbox(
      key: const Key('addresses-with-balance-checkbox'),
      text: LocaleKeys.hideZeroBalanceAddresses.tr(),
      value: hideZeroBalance,
      onChanged: (value) {
        context.read<CoinAddressesBloc>().add(
          CoinAddressesZeroBalanceVisibilityChanged(value),
        );
      },
    );
  }
}

class CreateButton extends StatelessWidget {
  const CreateButton({
    required this.status,
    required this.createAddressStatus,
    required this.cantCreateNewAddressReasons,
    this.gaslessSingleAddress = false,
    super.key,
  });

  final FormStatus status;
  final FormStatus createAddressStatus;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;

  /// Gleec exposes GasFree custody only for the primary address. KDF supports
  /// other HD selectors, but this app keeps them on the Standard/recovery rail.
  final bool gaslessSingleAddress;

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = gaslessSingleAddress
        ? LocaleKeys.gaslessSingleAddressTooltip.tr()
        : _getTooltipMessage();
    final isEnabled =
        !gaslessSingleAddress &&
        canCreateNewAddress &&
        status != FormStatus.submitting &&
        createAddressStatus != FormStatus.submitting;

    return Semantics(
      button: true,
      enabled: isEnabled,
      hint: tooltipMessage.isEmpty ? null : tooltipMessage,
      child: Tooltip(
        message: tooltipMessage,
        child: UiPrimaryButton(
          height: 48,
          borderRadius: 24,
          backgroundColor: isMobile
              ? theme.custom.dexPageTheme.emptyPlace
              : null,
          text: createAddressStatus == FormStatus.submitting
              ? '${LocaleKeys.creating.tr()}...'
              : LocaleKeys.createAddress.tr(),
          prefix: createAddressStatus == FormStatus.submitting
              ? null
              : const Icon(Icons.add, size: 16),
          onPressed: isEnabled
              ? () {
                  context.read<CoinAddressesBloc>().add(
                    const CoinAddressesAddressCreationSubmitted(),
                  );
                }
              : null,
        ),
      ),
    );
  }

  bool get canCreateNewAddress => cantCreateNewAddressReasons?.isEmpty ?? true;

  String _getTooltipMessage() {
    if (cantCreateNewAddressReasons?.isEmpty ?? true) {
      return '';
    }

    return cantCreateNewAddressReasons!
        .map((reason) {
          return switch (reason) {
            CantCreateNewAddressReason.maxGapLimitReached =>
              LocaleKeys.maxGapLimitReached.tr(),
            CantCreateNewAddressReason.maxAddressesReached =>
              LocaleKeys.maxAddressesReached.tr(),
            CantCreateNewAddressReason.missingDerivationPath =>
              LocaleKeys.missingDerivationPath.tr(),
            CantCreateNewAddressReason.protocolNotSupported =>
              LocaleKeys.protocolNotSupported.tr(),
            CantCreateNewAddressReason.derivationModeNotSupported =>
              LocaleKeys.derivationModeNotSupported.tr(),
            CantCreateNewAddressReason.noActiveWallet =>
              LocaleKeys.noActiveWallet.tr(),
          };
        })
        .join('\n');
  }
}

class QrCode extends StatelessWidget {
  final String address;
  final String coinAbbr;

  const QrCode({super.key, required this.address, required this.coinAbbr});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '${LocaleKeys.scanTheQrCode.tr()}: $coinAbbr',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 200.0;
            final qrSize = availableWidth.clamp(0.0, 200.0).toDouble();
            final assetSize = (qrSize * 0.2).clamp(24.0, 40.0).toDouble();

            return SizedBox.square(
              dimension: qrSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QrImageView(
                      data: address,
                      backgroundColor: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.color!,
                      eyeStyle: QrEyeStyle(
                        color: theme.custom.dexPageTheme.emptyPlace,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        color: theme.custom.dexPageTheme.emptyPlace,
                      ),
                      version: QrVersions.auto,
                      size: qrSize,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                  AssetIcon.ofTicker(coinAbbr, size: assetSize),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NewAddressDialog extends StatelessWidget {
  const _NewAddressDialog();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CoinAddressesBloc, CoinAddressesState>(
      listenWhen: (prev, curr) =>
          prev.newAddressState?.status != curr.newAddressState?.status,
      listener: (context, state) {
        final status = state.newAddressState?.status;
        if (status == NewAddressStatus.completed ||
            status == NewAddressStatus.error ||
            status == NewAddressStatus.cancelled) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final newState = state.newAddressState;
        final showAddress = newState?.status == NewAddressStatus.confirmAddress;

        return AlertDialog(
          title: Text(LocaleKeys.creating.tr()),
          content: SizedBox(
            // slightly wider than the default to accommodate longer addresses
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAddress)
                  TrezorNewAddressConfirmation(
                    address: newState?.expectedAddress ?? '',
                  )
                else
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
