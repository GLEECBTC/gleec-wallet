import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_activation_status_bar.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_actions_sheet.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_row.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

/// The wallet's assets as one rounded group, best first. At its foot, the
/// switch that hides empty assets, saying how many it hides, and Add assets.
class WalletHomeAssets extends StatelessWidget {
  const WalletHomeAssets({
    required this.searchPhrase,
    required this.hideZeroBalances,
    required this.onHideZeroBalances,
    this.arrrActivationService,
    super.key,
  });

  final String searchPhrase;
  final bool hideZeroBalances;
  final ValueChanged<bool> onHideZeroBalances;
  final ArrrActivationService? arrrActivationService;

  @override
  Widget build(BuildContext context) {
    final includeTestCoins = context.select(
      (SettingsBloc bloc) => bloc.state.testCoinsEnabled,
    );
    return BlocBuilder<CoinsBloc, CoinsState>(
      builder: (context, state) {
        List<Coin> assets({required bool hideZero}) => walletHomeAssets(
          state.walletCoins.values,
          sdk: context.sdk,
          searchPhrase: searchPhrase,
          hideZeroBalances: hideZero,
          includeTestCoins: includeTestCoins,
        );
        final coins = assets(hideZero: hideZeroBalances);
        final hidden = hideZeroBalances
            ? assets(hideZero: false).length - coins.length
            : 0;
        final filtering = searchPhrase.isNotEmpty || hideZeroBalances;
        final service = arrrActivationService;
        return SliverMainAxisGroup(
          slivers: [
            if (service != null)
              SliverToBoxAdapter(
                child: ZhtlcActivationStatusBar(activationService: service),
              ),
            if (coins.isEmpty && filtering)
              SliverToBoxAdapter(
                child: _Message(LocaleKeys.walletPageNoSuchAsset.tr()),
              )
            // The wallet's coins arrive a moment after sign-in.
            else if (state.walletCoins.isEmpty)
              const _LoadingGroup()
            else if (coins.isEmpty)
              SliverToBoxAdapter(
                child: _Message(LocaleKeys.walletHomeNoAssets.tr()),
              )
            else
              _Group(
                itemCount: coins.length,
                itemBuilder: (context, index, radius) {
                  final coin = coins[index];
                  return WalletAssetRow(
                    key: Key('coin-list-item-${coin.abbr.toLowerCase()}'),
                    coin: coin,
                    showDivider: index > 0,
                    borderRadius: radius,
                    onTap: () => routingState.walletState.openCoin(coin.abbr),
                    onLongPress: () => showWalletAssetActions(context, coin),
                  );
                },
              ),
            if (state.walletCoins.isNotEmpty)
              SliverToBoxAdapter(
                child: _HideZeroBalances(
                  value: hideZeroBalances,
                  hidden: hidden,
                  onChanged: onHideZeroBalances,
                ),
              ),
            const SliverToBoxAdapter(child: _AddAssetsButton()),
          ],
        );
      },
    );
  }
}

/// The assets the home lists: active or activating, matching the search,
/// holding a balance if [hideZeroBalances], best first.
List<Coin> walletHomeAssets(
  Iterable<Coin> walletCoins, {
  required KomodoDefiSdk sdk,
  required String searchPhrase,
  required bool hideZeroBalances,
  required bool includeTestCoins,
}) {
  final shown = filterCoinsByPhrase(walletCoins, searchPhrase).where((coin) {
    if (!coin.isActive && !coin.isActivating) return false;
    if (!includeTestCoins && coin.isTestCoin) return false;
    if (!hideZeroBalances) return true;
    return (sdk.balances.lastKnown(coin.id)?.total ?? Decimal.zero) >
        Decimal.zero;
  }).toList();
  return sortByPriorityAndBalance(shown, sdk);
}

typedef _RowBuilder = Widget Function(
  BuildContext context,
  int index,
  BorderRadius radius,
);

/// Rows on one rounded surface; the first and last rows clip their press
/// highlight to its corners.
class _Group extends StatelessWidget {
  const _Group({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final _RowBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    const corner = Radius.circular(WalletHomeGeometry.groupRadius);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: WalletHomeGeometry.gutter,
      ),
      sliver: DecoratedSliver(
        decoration: walletHomeGroupDecoration(context),
        sliver: SliverList.builder(
          itemCount: itemCount,
          itemBuilder: (context, index) => itemBuilder(
            context,
            index,
            BorderRadius.vertical(
              top: index == 0 ? corner : Radius.zero,
              bottom: index == itemCount - 1 ? corner : Radius.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingGroup extends StatelessWidget {
  const _LoadingGroup();

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return _Group(
      itemCount: 4,
      itemBuilder: (context, index, _) => Padding(
        padding: WalletHomeGeometry.rowPadding,
        child: Row(
          children: [
            Container(
              width: WalletHomeGeometry.logoSize,
              height: WalletHomeGeometry.logoSize,
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(96, 14), const SizedBox(height: 8), bar(64, 10)],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [bar(64, 14), const SizedBox(height: 8), bar(44, 10)],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Padding(
      key: const Key('wallet-home-assets-message'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 32, color: palette.textTertiary),
          const SizedBox(height: 10),
          Text(
            text,
            style: SwapText.body(context),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Hides the assets with nothing in them, and says how many that hides, so
/// a hidden asset is never simply missing.
class _HideZeroBalances extends StatelessWidget {
  const _HideZeroBalances({
    required this.value,
    required this.hidden,
    required this.onChanged,
  });

  final bool value;
  final int hidden;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: MergeSemantics(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: () => onChanged(!value),
          leading: Icon(
            Icons.visibility_off_outlined,
            size: 20,
            color: palette.textTertiary,
          ),
          title: Text(
            LocaleKeys.withBalance.tr(),
            style: WalletHomeText.title(context)
                .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: value && hidden > 0
              ? Text(
                  LocaleKeys.walletHomeHiddenAssets.plural(hidden),
                  style: WalletHomeText.caption(context),
                )
              : null,
          trailing: Switch(
            key: const Key('coins-with-balance-checkbox'),
            value: value,
            onChanged: onChanged,
            activeThumbColor: palette.onBrand,
            activeTrackColor: palette.brand,
          ),
        ),
      ),
    );
  }
}

class _AddAssetsButton extends StatelessWidget {
  const _AddAssetsButton();

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextButton.icon(
        key: const Key('add-assets-button'),
        onPressed: () {
          context.read<CoinsManagerBloc>().add(
            const CoinsManagerCoinsListReset(CoinsManagerAction.add),
          );
          routingState.walletState.action = coinsManagerRouteAction.addAssets;
        },
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: palette.brandHover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.border),
          ),
          textStyle: SwapText.strong(context),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(LocaleKeys.addAssets.tr()),
      ),
    );
  }
}
