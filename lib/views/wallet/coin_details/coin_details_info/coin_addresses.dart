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
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_type_tag.dart';
import 'package:web_dex/shared/widgets/truncate_middle_text.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_button.dart';
import 'package:web_dex/views/wallet/coin_details/receive/trezor_new_address_confirmation.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';
import 'package:web_dex/views/wallet/common/address_icon.dart';

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
            final addresses = state.addresses
                .where(
                  (address) =>
                      !state.hideZeroBalance ||
                      address.balance.spendable != Decimal.zero,
                )
                .toList();
            final bool hasMore = addresses.length > _collapsedLimit;
            final bool showAll = _showAllAddresses || !hasMore;
            final List<PubkeyInfo> visibleAddresses = showAll
                ? addresses
                : addresses.take(_collapsedLimit).toList();

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
                          ),
                          const SizedBox(height: 12),
                          ...visibleAddresses.asMap().entries.map((entry) {
                            final index = entry.key;
                            final address = entry.value;

                            return AddressCard(
                              address: address,
                              index: index,
                              coin: widget.coin,
                              setPageType: widget.setPageType,
                            );
                          }),
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
  });

  final FormStatus status;
  final FormStatus createAddressStatus;
  final bool hideZeroBalance;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;

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
    required this.index,
    required this.coin,
    required this.setPageType,
  });

  final PubkeyInfo address;
  final int index;
  final Coin coin;
  final void Function(CoinPageType) setPageType;

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
                onShowFullAddress: () => _showFullAddressDialog(context),
              )
            : _DesktopAddressContent(
                address: address,
                coin: coin,
                onShowFullAddress: () => _showFullAddressDialog(context),
              ),
      ),
    );
  }

  void _showFullAddressDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(LocaleKeys.address.tr()),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    address.address,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: LocaleKeys.copyAddressToClipboard.tr(
                    args: [coin.abbr],
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => copyToClipBoard(
                    context,
                    address.address,
                    LocaleKeys.copiedAddressToClipboard.tr(args: [coin.abbr]),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(LocaleKeys.close.tr()),
            ),
          ],
        );
      },
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.address, required this.coin});

  final PubkeyInfo address;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final balance = address.balance.total.toDouble();
    final price = coin.lastKnownUsdPrice(context.sdk);
    final usdValue = price == null ? null : price * balance;
    final fiat = hideBalances ? maskedBalanceText : formatUsdValue(usdValue);

    return Text(
      hideBalances
          ? '${maskedBalanceText} ${abbr2Ticker(coin.abbr)} ($fiat)'
          : '${doubleToString(balance)} ${abbr2Ticker(coin.abbr)} ($fiat)',
      style: TextStyle(fontSize: isMobile ? 12 : 14),
    );
  }
}

class _MobileAddressContent extends StatelessWidget {
  const _MobileAddressContent({
    required this.address,
    required this.coin,
    required this.onShowFullAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final VoidCallback onShowFullAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AddressIcon(address: address.address),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onShowFullAddress,
                child: TruncatedMiddleText(
                  address.address,
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
            AddressCopyButton(address: address.address, coinAbbr: coin.abbr),
            QrButton(coin: coin, address: address),
            if (coin.id.hasFaucet)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
                child: FaucetButton(coinAbbr: coin.abbr, address: address),
              ),
            SwapAddressTag(address: address),
          ],
        ),
        const SizedBox(height: 8),
        _Balance(address: address, coin: coin),
      ],
    );
  }
}

class _DesktopAddressContent extends StatelessWidget {
  const _DesktopAddressContent({
    required this.address,
    required this.coin,
    required this.onShowFullAddress,
  });

  final PubkeyInfo address;
  final Coin coin;
  final VoidCallback onShowFullAddress;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AddressIcon(address: address.address),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onShowFullAddress,
            child: TruncatedMiddleText(
              address.address,
              style:
                  Theme.of(context).textTheme.bodyMedium ??
                  const TextStyle(fontSize: 14),
            ),
          ),
        ),
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
                AddressCopyButton(
                  address: address.address,
                  coinAbbr: coin.abbr,
                ),
                QrButton(coin: coin, address: address),
                if (coin.id.hasFaucet)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 80,
                      maxWidth: 160,
                    ),
                    child: FaucetButton(coinAbbr: coin.abbr, address: address),
                  ),
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
            child: _Balance(address: address, coin: coin),
          ),
        ),
      ],
    );
  }
}

class QrButton extends StatelessWidget {
  const QrButton({super.key, required this.address, required this.coin});

  final PubkeyInfo address;
  final Coin coin;

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
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    LocaleKeys.receive.tr(),
                    style: const TextStyle(fontSize: 16),
                  ),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.hardEdge,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
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
                    QrCode(address: address.address, coinAbbr: coin.abbr),
                    const SizedBox(height: 16),
                    // Address row with copy and explorer link
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // Address text
                          Expanded(
                            child: TruncatedMiddleText(
                              address.address,
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
                              tooltip: LocaleKeys.copyAddressToClipboard.tr(
                                args: [coin.abbr],
                              ),
                              icon: const Icon(Icons.copy_rounded, size: 20),
                              onPressed: () => copyToClipBoard(
                                context,
                                address.address,
                                LocaleKeys.copiedAddressToClipboard.tr(
                                  args: [coin.abbr],
                                ),
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
                                final url = getAddressExplorerUrl(
                                  coin,
                                  address.address,
                                );
                                if (url.isNotEmpty) {
                                  launchURLString(url, inSeparateTab: true);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        LocaleKeys.explorerUnavailable.tr(),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      LocaleKeys.scanTheQrCode.tr(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PubkeyReceiveDialog extends StatelessWidget {
  const PubkeyReceiveDialog({
    super.key,
    required this.coin,
    required this.address,
  });

  final Coin coin;
  final PubkeyInfo address;

  @override
  Widget build(BuildContext context) {
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
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
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
            QrCode(address: address.address, coinAbbr: coin.abbr),
            const SizedBox(height: 16),
            // Address row with copy and explorer link
            Container(
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
                      address.address,
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
                      tooltip: LocaleKeys.copyAddressToClipboard.tr(
                        args: [coin.abbr],
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () => copyToClipBoard(
                        context,
                        address.address,
                        LocaleKeys.copiedAddressToClipboard.tr(
                          args: [coin.abbr],
                        ),
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
                        final url = getAddressExplorerUrl(
                          coin,
                          address.address,
                        );
                        if (url.isNotEmpty) {
                          launchURLString(url, inSeparateTab: true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LocaleKeys.explorerUnavailable.tr(),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              LocaleKeys.scanTheQrCode.tr(),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
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
    super.key,
  });

  final FormStatus status;
  final FormStatus createAddressStatus;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = _getTooltipMessage();

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
            foregroundColor: theme.custom.dexPageTheme.emptyPlace,
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
