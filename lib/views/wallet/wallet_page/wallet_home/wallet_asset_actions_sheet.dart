import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';
import 'package:web_dex/views/wallet/common/open_swap_with_asset.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/asset_display_name.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_row.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

/// What can be done with one asset, on a long press of its row: the same
/// actions as its page, without opening it first.
Future<void> showWalletAssetActions(BuildContext context, Coin coin) {
  SwapHaptics.medium();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: SwapPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _AssetActionsSheet(
      coin: coin,
      // The sheet's own context goes when it closes; the actions run after.
      host: context,
    ),
  );
}

class _AssetActionsSheet extends StatelessWidget {
  const _AssetActionsSheet({required this.coin, required this.host});

  final Coin coin;
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final names = assetDisplayParts(coin);
    final network = names.network;
    final spendable =
        context.sdk.balances.lastKnown(coin.id)?.spendable ?? Decimal.zero;
    final isHardwareWallet = context.select<AuthBloc, bool>(
      (bloc) => bloc.state.currentUser?.wallet.isHW ?? false,
    );
    final canTrade = context.select<TradingStatusBloc, bool>(
      (bloc) => bloc.state.canTradeAssets([coin.id]),
    );

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  AssetLogo.ofId(coin.id, size: WalletHomeGeometry.logoSize),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      names.name,
                      style: SwapText.heading(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (network != null) ...[
                    const SizedBox(width: 8),
                    NetworkChip(label: network),
                  ],
                ],
              ),
            ),
            _ActionItem(
              key: const Key('wallet-asset-action-send'),
              icon: Icons.north_east_rounded,
              label: LocaleKeys.send.tr(),
              onTap: coin.isActive && spendable > Decimal.zero
                  ? () => run(
                      () => routingState.walletState.openCoin(
                        coin.abbr,
                        quickAction: CoinQuickAction.send,
                      ),
                    )
                  : null,
            ),
            _ActionItem(
              key: const Key('wallet-asset-action-receive'),
              icon: Icons.south_west_rounded,
              label: LocaleKeys.receive.tr(),
              onTap: coin.isActive || coin.isActivating
                  ? () => run(
                      () => routingState.walletState.openCoin(
                        coin.abbr,
                        quickAction: CoinQuickAction.receive,
                      ),
                    )
                  : null,
            ),
            if (!isHardwareWallet)
              _ActionItem(
                key: const Key('wallet-asset-action-swap'),
                icon: Icons.swap_horiz_rounded,
                label: LocaleKeys.swap.tr(),
                onTap: canTrade && coin.isActive
                    ? () => run(() => openSwapWithAsset(host, coin))
                    : null,
              ),
            _ActionItem(
              key: const Key('wallet-asset-action-details'),
              icon: Icons.info_outline_rounded,
              label: LocaleKeys.walletHomeAssetDetails.tr(),
              onTap: () =>
                  run(() => routingState.walletState.openCoin(coin.abbr)),
            ),
            _ActionItem(
              key: const Key('wallet-asset-action-disable'),
              icon: Icons.visibility_off_outlined,
              label: LocaleKeys.disable.tr(),
              destructive: true,
              onTap: () => run(() => confirmBeforeDisablingCoin(coin, host)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final color = onTap == null
        ? palette.onDisabled
        : destructive
        ? palette.danger
        : palette.text;
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      minTileHeight: 52,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: WalletHomeText.title(context).copyWith(color: color),
      ),
    );
  }
}
