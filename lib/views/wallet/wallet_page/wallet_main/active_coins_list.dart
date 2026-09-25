import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';

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
        final List<Coin> displayedCoins = _getDisplayedCoins(
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
          displayedCoins,
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

                // Pubkeys are requested by CoinsBloc when a coin reaches the
                // active state. Dispatching from here re-fired for every row on
                // every emission, and each response emitted again.
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

  List<Coin> _getDisplayedCoins(Iterable<Coin> coins, KomodoDefiSdk sdk) =>
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
