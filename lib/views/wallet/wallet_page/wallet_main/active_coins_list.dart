import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';

import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';
import 'package:web_dex/views/wallet/common/address_icon.dart';
import 'package:web_dex/views/wallet/common/address_text.dart';
import 'package:web_dex/views/wallet/wallet_page/common/expandable_coin_list_item.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_activation_status_bar.dart';

class ActiveCoinsList extends StatelessWidget {
  const ActiveCoinsList({
    super.key,
    required this.searchPhrase,
    required this.withBalance,
    required this.onCoinItemTap,
    this.onStatisticsTap,
    this.arrrActivationService,
  });

  final String searchPhrase;
  final bool withBalance;
  final Function(Coin) onCoinItemTap;
  final void Function(Coin)? onStatisticsTap;
  final ArrrActivationService? arrrActivationService;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoinsBloc, CoinsState>(
      builder: (context, state) {
        final coins = state.walletCoins.values.toList();
        final Iterable<Coin> displayedCoins = _getDisplayedCoins(
          coins,
          context.sdk,
        );

        if (displayedCoins.isEmpty &&
            (searchPhrase.isNotEmpty || withBalance)) {
          return SliverToBoxAdapter(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(LocaleKeys.walletPageNoSuchAsset.tr()),
            ),
          );
        }

        List<Coin> sorted = sortByPriorityAndBalance(
          displayedCoins.toList(),
          context.sdk,
        );

        if (!context.read<SettingsBloc>().state.testCoinsEnabled) {
          sorted = removeTestCoins(sorted);
        }

        return SliverMainAxisGroup(
          slivers: [
            // ZHTLC Activation Status Bar
            if (arrrActivationService != null)
              SliverToBoxAdapter(
                child: ZhtlcActivationStatusBar(
                  activationService: arrrActivationService!,
                ),
              ),

            // Coin List
            SliverList.builder(
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final coin = sorted[index];

                // Fetch pubkeys if not already loaded
                if (!state.pubkeys.containsKey(coin.abbr)) {
                  // TODO: Investigate if this is causing performance issues
                  context.read<CoinsBloc>().add(
                    CoinsPubkeysRequested(coin.abbr),
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: ExpandableCoinListItem(
                    // Changed from ExpandableCoinListItem
                    key: Key('coin-list-item-${coin.abbr.toLowerCase()}'),
                    coin: coin,
                    pubkeys: state.pubkeys[coin.abbr],
                    isSelected: false,
                    onTap: () => onCoinItemTap(coin),
                    onStatisticsTap: onStatisticsTap == null
                        ? null
                        : () => onStatisticsTap!(coin),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Iterable<Coin> _getDisplayedCoins(Iterable<Coin> coins, KomodoDefiSdk sdk) =>
      filterCoinsByPhrase(coins, searchPhrase).where((Coin coin) {
        if (!coin.isActive && !coin.isActivating) {
          return false;
        }
        if (withBalance) {
          return (coin.lastKnownBalance(sdk)?.total ?? Decimal.zero) >
              Decimal.zero;
        }
        return true;
      }).toList();
}

class AddressBalanceList extends StatelessWidget {
  const AddressBalanceList({
    super.key,
    required this.coin,
    required this.onCreateNewAddress,
    required this.pubkeys,
    required this.cantCreateNewAddressReasons,
  });

  final Coin coin;
  final AssetPubkeys pubkeys;
  final VoidCallback onCreateNewAddress;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;

  bool get canCreateNewAddress => cantCreateNewAddressReasons?.isEmpty ?? true;

  @override
  Widget build(BuildContext context) {
    if (pubkeys.keys.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Sort addresses by balance
    final sortedAddresses = [...pubkeys.keys]
      ..sort((a, b) => b.balance.spendable.compareTo(a.balance.spendable));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Address list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedAddresses.length,
          itemBuilder: (context, index) {
            final pubkey = sortedAddresses[index];
            return AddressBalanceCard(pubkey: pubkey, coin: coin);
          },
        ),

        // Create address button
        if (canCreateNewAddress)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Tooltip(
              message: _getTooltipMessage(),
              child: ElevatedButton.icon(
                onPressed: canCreateNewAddress ? onCreateNewAddress : null,
                icon: const Icon(Icons.add),
                label: Text(LocaleKeys.createNewAddress.tr()),
              ),
            ),
          ),
      ],
    );
  }

  String _getTooltipMessage() {
    if (cantCreateNewAddressReasons?.isEmpty ?? true) {
      return '';
    }

    return cantCreateNewAddressReasons!
        .map((reason) {
          return switch (reason) {
            // TODO: Localise and possibly also move localisations to the SDK.
            CantCreateNewAddressReason.maxGapLimitReached =>
              'Maximum gap limit reached - please use existing unused addresses first',
            CantCreateNewAddressReason.maxAddressesReached =>
              'Maximum number of addresses reached for this asset',
            CantCreateNewAddressReason.missingDerivationPath =>
              'Missing derivation path configuration',
            CantCreateNewAddressReason.protocolNotSupported =>
              'Protocol does not support multiple addresses',
            CantCreateNewAddressReason.derivationModeNotSupported =>
              'Current wallet mode does not support multiple addresses',
            CantCreateNewAddressReason.noActiveWallet =>
              'No active wallet - please sign in first',
          };
        })
        .join('\n');
  }
}

class AddressBalanceCard extends StatelessWidget {
  const AddressBalanceCard({
    super.key,
    required this.pubkey,
    required this.coin,
  });

  final PubkeyInfo pubkey;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address row
            Row(
              children: [
                AddressIcon(address: pubkey.address),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AddressText(address: pubkey.address),
                          AddressCopyButton(
                            address: pubkey.address,
                            coinAbbr: coin.abbr,
                          ),
                          if (pubkey.isActiveForSwap)
                            // TODO: Refactor to use "DexPill" component from the SDK UI library (not yet created)
                            Padding(
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
                            ),
                        ],
                      ),
                      if (pubkey.derivationPath != null)
                        Text(
                          'Derivation: ${pubkey.derivationPath}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(),

            // Balance row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hideBalances
                          ? '$maskedBalanceText ${coin.abbr}'
                          : '${formatBalance(pubkey.balance.spendable.toBigInt())} ${coin.abbr}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _AddressFiatBalance(
                      coin: coin,
                      balance: pubkey.balance.spendable.toDouble(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrCode(
                                address: pubkey.address,
                                coinAbbr: coin.abbr,
                              ),
                              const SizedBox(height: 16),
                              SelectableText(pubkey.address),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String formatBalance(BigInt balance) {
    return doubleToString(balance.toDouble());
  }
}

class _AddressFiatBalance extends StatelessWidget {
  const _AddressFiatBalance({
    required this.coin,
    required this.balance,
    this.style,
  });

  final Coin coin;
  final double balance;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    if (hideBalances) {
      return Text(maskedBalanceText, style: style);
    }

    final sdk = context.sdk;
    final price = sdk.marketData.priceIfKnown(coin.id);

    if (price == null) {
      return Text(formatUsdValue(null), style: style);
    }

    final fiatValue = (Decimal.parse(balance.toString()) * price).toDouble();
    return Text(formatUsdValue(fiatValue), style: style);
  }
}
