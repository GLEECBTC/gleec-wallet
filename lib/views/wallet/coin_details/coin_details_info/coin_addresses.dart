import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:web_dex/shared/constants.dart';
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

/// Which of a pubkey's two addresses a row or receive dialog displays: the
/// standard (EOA) address, or the deterministic GasFree (CREATE2) custody
/// address derived from it. A gasless pubkey blends into two sibling rows in
/// the address list, one per variant.
enum AddressDisplayVariant { standard, gasfree }

/// One visible row of the address list: a pubkey shown as one of its
/// [AddressDisplayVariant]s.
typedef AddressRowEntry = ({PubkeyInfo pubkey, AddressDisplayVariant variant});

String _addressForVariant(PubkeyInfo address, AddressDisplayVariant variant) =>
    variant == AddressDisplayVariant.gasfree &&
        (address.gasfreeAddress?.isNotEmpty ?? false)
    ? address.gasfreeAddress!
    : address.address;

/// Whether [address] carries a GasFree (CREATE2) custody address for [coin].
/// Depositing to it lands funds ready to send gaslessly — the network fee is
/// paid in the token, so the user never needs TRX.
bool _isGaslessReceiveAddress(Coin coin, PubkeyInfo address) =>
    coin.id.subClass == CoinSubClass.trc20 &&
    (address.gasfreeAddress?.isNotEmpty ?? false);

/// Whether the faucet button may be shown on a row displaying [variant]. The
/// faucet drips to the standard (EOA) address, so it belongs on the standard
/// row — dripping while the custody address is displayed would land funds
/// stranded outside the shown account.
bool showFaucetForAddress(Coin coin, AddressDisplayVariant variant) =>
    coin.id.hasFaucet && variant == AddressDisplayVariant.standard;

/// Expands pubkeys into display rows: a gasless pubkey becomes a gas-free
/// (custody) row followed by a standard (EOA) row; others stay one row. The
/// gas-free row is exempt from the zero-balance toggle — it is the account
/// itself, and its displayed balance is the asset-level custody balance, not
/// the pubkey's EOA balance — while standard rows follow the normal rule.
List<AddressRowEntry> visibleAddressRows(
  Coin coin,
  List<PubkeyInfo> addresses, {
  required bool hideZeroBalance,
}) {
  final entries = <AddressRowEntry>[
    for (final address in addresses) ...[
      if (_isGaslessReceiveAddress(coin, address))
        (pubkey: address, variant: AddressDisplayVariant.gasfree),
      (pubkey: address, variant: AddressDisplayVariant.standard),
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

/// A green "gasless" pill shown on the receive surface for a TRC-20 GasFree
/// custody address, reassuring the user that funds received here can be sent
/// gaslessly with no TRX required. When [assetName] is provided, a trailing
/// info affordance opens [GaslessInfoDialog] (fees + provider-dependence
/// disclosure).
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
                  LocaleKeys.receiveGaslessBadgeSubtitle.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (name != null)
            IconButton(
              key: const Key('receive-gasless-info-button'),
              visualDensity: VisualDensity.compact,
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

/// Compact per-row tag telling the two blended rows of a gasless pubkey
/// apart: a success-toned "Gas-free" pill on the custody row and a muted
/// "Standard · uses TRX" chip on the EOA row. Only rendered for gasless
/// pubkeys — plain coins keep untagged rows.
class _AddressVariantTag extends StatelessWidget {
  const _AddressVariantTag({required this.variant});

  final AddressDisplayVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (variant == AddressDisplayVariant.gasfree) {
      final style = NoticeBanner.styleOf(context, NoticeBannerVariant.success);
      return Container(
        key: const Key('address-row-gasfree-tag'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 14, color: style.accent),
            const SizedBox(width: 4),
            Text(
              LocaleKeys.addressRowGasfreeTag.tr(),
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

class _CoinAddressesState extends State<CoinAddresses> {
  // No need to store a reference to the bloc since we don't manage its lifecycle
  bool _showAllAddresses = false;

  int get _collapsedLimit => isMobile ? 3 : 5;

  @override
  void dispose() {
    // Remove bloc.close() - the bloc is owned and managed by the parent widget
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
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
            final errorMessage = state.errorMessage?.trim();
            final rows = visibleAddressRows(
              widget.coin,
              state.addresses,
              hideZeroBalance: state.hideZeroBalance,
            );
            // Gasless assets are single-address by design: the custody model
            // (headline balance, gasless::account_status) only covers the
            // primary address, so creating further addresses would strand
            // deposits invisibly. Scoped to TRX as well as TRC-20 — they
            // share one address list, and a TRX-created address would be
            // hidden by the SDK's phantom filter until funded. The gate is
            // CONFIG-driven (not derived from pubkeys) so a provider outage
            // that leaves gasfreeAddress empty can't open a creation window.
            // The custody count, used for the custody-balance pairing, stays
            // pubkey-driven (one per key, not per blended row) and is counted
            // on the unfiltered list so a pubkey hidden by the zero-balance
            // toggle still counts.
            final gaslessSingleAddress = widget.coin
                .isGaslessSingleAddressScope(context.sdk);
            final gaslessAddressCount = state.addresses
                .where(
                  (address) => _isGaslessReceiveAddress(widget.coin, address),
                )
                .length;
            final bool hasMore = rows.length > _collapsedLimit;
            final bool showAll = _showAllAddresses || !hasMore;
            final List<AddressRowEntry> visibleRows = showAll
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
                            ),
                          ),
                          if (hasMore)
                            Align(
                              alignment: Alignment.centerLeft,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const AddressesTitle(),
        const Spacer(),
        HideZeroBalanceCheckbox(hideZeroBalance: hideZeroBalance),
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: SizedBox(
              width: 200,
              child: CreateButton(
                status: status,
                createAddressStatus: createAddressStatus,
                cantCreateNewAddressReasons: cantCreateNewAddressReasons,
                gaslessSingleAddress: gaslessSingleAddress,
              ),
            ),
          ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      color: theme.custom.dexPageTheme.emptyPlace,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: isMobile
            ? _MobileAddressContent(
                address: address,
                coin: coin,
                variant: variant,
                isSoleGaslessRow: isSoleGaslessRow,
                onTapAddress: () => showPubkeyReceiveDialog(
                  context,
                  coin,
                  address,
                  variant: variant,
                ),
              )
            : _DesktopAddressContent(
                address: address,
                coin: coin,
                variant: variant,
                isSoleGaslessRow: isSoleGaslessRow,
                onTapAddress: () => showPubkeyReceiveDialog(
                  context,
                  coin,
                  address,
                  variant: variant,
                ),
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
}) {
  showDialog<void>(
    context: context,
    builder: (context) =>
        PubkeyReceiveDialog(coin: coin, address: address, variant: variant),
  );
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.address,
    required this.coin,
    required this.variant,
    required this.isSoleGaslessRow,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    // The gas-free row displays the custody address, so it must pair it with
    // the custody balance (the SDK balance cache is custody-substituted for
    // gasless TRC-20) — pairing the custody address with the standard-address
    // balance would attribute stranded EOA funds to the wrong address. Only
    // valid for a SOLE gasless pubkey: the cache is asset-level (primary
    // address custody), so with 2+ custody rows each would show the same
    // aggregate number. The standard sibling row always shows the pubkey's
    // own EOA balance — the same source the stranded-balance notice sums.
    final balanceInfo =
        variant == AddressDisplayVariant.gasfree && isSoleGaslessRow
        ? (context.sdk.balances.lastKnown(coin.id) ?? address.balance)
        : address.balance;
    final balance = balanceInfo.total.toDouble();
    final price = coin.lastKnownUsdPrice(context.sdk);
    final usdValue = price == null ? null : price * balance;
    final fiat = hideBalances ? maskedBalanceText : formatUsdValue(usdValue);

    return Text(
      hideBalances
          ? '$maskedBalanceText ${abbr2Ticker(coin.abbr)} ($fiat)'
          : '${doubleToString(balance)} ${abbr2Ticker(coin.abbr)} ($fiat)',
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
    required this.onTapAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;
  final VoidCallback onTapAddress;

  @override
  Widget build(BuildContext context) {
    final rowAddress = _addressForVariant(address, variant);
    final isGaslessPubkey = _isGaslessReceiveAddress(coin, address);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AddressIcon(address: rowAddress),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onTapAddress,
                child: TruncatedMiddleText(
                  rowAddress,
                  style:
                      Theme.of(context).textTheme.bodyMedium ??
                      const TextStyle(fontSize: 14),
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
            if (isGaslessPubkey) _AddressVariantTag(variant: variant),
            AddressCopyButton(address: rowAddress, coinAbbr: coin.abbr),
            QrButton(coin: coin, address: address, variant: variant),
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
    required this.onTapAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final AddressDisplayVariant variant;
  final bool isSoleGaslessRow;
  final VoidCallback onTapAddress;

  @override
  Widget build(BuildContext context) {
    final rowAddress = _addressForVariant(address, variant);
    final isGaslessPubkey = _isGaslessReceiveAddress(coin, address);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AddressIcon(address: rowAddress),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onTapAddress,
            child: TruncatedMiddleText(
              rowAddress,
              style:
                  Theme.of(context).textTheme.bodyMedium ??
                  const TextStyle(fontSize: 14),
            ),
          ),
        ),
        // Outside the fixed-width actions box: the tag would force the Wrap
        // onto a second line there.
        if (isGaslessPubkey) ...[
          const SizedBox(width: 8),
          _AddressVariantTag(variant: variant),
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
                AddressCopyButton(address: rowAddress, coinAbbr: coin.abbr),
                QrButton(coin: coin, address: address, variant: variant),
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
            ),
          ),
        ),
      ],
    );
  }
}

class QrButton extends StatelessWidget {
  const QrButton({
    super.key,
    required this.address,
    required this.coin,
    this.variant,
  });

  final PubkeyInfo address;
  final Coin coin;

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
        onPressed: () =>
            showPubkeyReceiveDialog(context, coin, address, variant: variant),
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
  });

  final Coin coin;
  final PubkeyInfo address;

  /// Which of [address]'s addresses to receive on. Null picks automatically:
  /// the gas-free (custody) address when available, else the standard one.
  final AddressDisplayVariant? variant;

  @override
  Widget build(BuildContext context) {
    final isGaslessPubkey = _isGaslessReceiveAddress(coin, address);
    final effectiveVariant =
        variant ??
        (isGaslessPubkey
            ? AddressDisplayVariant.gasfree
            : AddressDisplayVariant.standard);
    final receiveAddress = _addressForVariant(address, effectiveVariant);
    final showGasfreeSurface =
        isGaslessPubkey && effectiveVariant == AddressDisplayVariant.gasfree;
    final showStandardCaveat =
        isGaslessPubkey && effectiveVariant == AddressDisplayVariant.standard;
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(LocaleKeys.receive.tr(), style: const TextStyle(fontSize: 16)),
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
                LocaleKeys.onlySendToThisAddress.tr(
                  args: [abbr2Ticker(coin.abbr)],
                ),
                style: const TextStyle(fontSize: 14),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      LocaleKeys.network.tr(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    CoinTypeTag(coin),
                  ],
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
              _AddressCopyRow(coin: coin, address: receiveAddress),
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
  const _AddressCopyRow({required this.coin, required this.address});

  final Coin coin;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Address text
          Expanded(
            child: TruncatedMiddleText(
              address,
              style:
                  Theme.of(context).textTheme.bodySmall ??
                  const TextStyle(fontSize: 12),
            ),
          ),
          // Copy button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.hardEdge,
            child: IconButton(
              tooltip: LocaleKeys.copyAddressToClipboard.tr(args: [coin.abbr]),
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => copyToClipBoard(
                context,
                address,
                LocaleKeys.copiedAddressToClipboard.tr(args: [coin.abbr]),
              ),
            ),
          ),
          // Explorer link button
          Material(
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
                    SnackBar(
                      content: Text(LocaleKeys.explorerUnavailable.tr()),
                    ),
                  );
                }
              },
            ),
          ),
        ],
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
      child: TextButton.icon(
        key: const Key('receive-standard-address-toggle'),
        onPressed: () => setState(() => _expanded = !_expanded),
        icon: Icon(
          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          size: 18,
        ),
        label: Text(
          LocaleKeys.receiveStandardAddressToggle.tr(),
          style: theme.textTheme.bodySmall,
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

  /// Gasless assets are single-address by design: the custody model (headline
  /// balance, `gasless::account_status`) only covers the primary address, so
  /// additional addresses would receive custody deposits invisibly.
  final bool gaslessSingleAddress;

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = gaslessSingleAddress
        ? LocaleKeys.gaslessSingleAddressTooltip.tr()
        : _getTooltipMessage();

    return Tooltip(
      message: tooltipMessage,
      child: UiPrimaryButton(
        height: 40,
        borderRadius: 20,
        backgroundColor: isMobile ? theme.custom.dexPageTheme.emptyPlace : null,
        text: createAddressStatus == FormStatus.submitting
            ? '${LocaleKeys.creating.tr()}...'
            : LocaleKeys.createAddress.tr(),
        prefix: createAddressStatus == FormStatus.submitting
            ? null
            : const Icon(Icons.add, size: 16),
        onPressed:
            !gaslessSingleAddress &&
                canCreateNewAddress &&
                status != FormStatus.submitting &&
                createAddressStatus != FormStatus.submitting
            ? () {
                context.read<CoinAddressesBloc>().add(
                  const CoinAddressesAddressCreationSubmitted(),
                );
              }
            : null,
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
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: QrImageView(
            data: address,
            backgroundColor: Theme.of(context).textTheme.bodyMedium!.color!,
            eyeStyle: QrEyeStyle(color: theme.custom.dexPageTheme.emptyPlace),
            dataModuleStyle: QrDataModuleStyle(
              color: theme.custom.dexPageTheme.emptyPlace,
            ),
            version: QrVersions.auto,
            size: 200.0,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
        ),
        Positioned(child: AssetIcon.ofTicker(coinAbbr, size: 40)),
      ],
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
