import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/views/swap/common/swap_buttons.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_picker_sheet.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_action.dart';

/// The row of quick actions under the balance.
///
/// [highlight] fills one action with the brand colour: Receive while the
/// wallet is empty, since adding funds is the only useful next step.
class WalletQuickActions extends StatelessWidget {
  const WalletQuickActions({this.highlight, super.key});

  final WalletQuickAction? highlight;

  @override
  Widget build(BuildContext context) {
    final isHardwareWallet = context.select<AuthBloc, bool>(
      (bloc) => bloc.state.currentUser?.wallet.isHW ?? false,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WalletHomeGeometry.gutter,
      ),
      child: Row(
        spacing: 10,
        children: [
          for (final action in WalletQuickAction.values)
            Expanded(
              child: _ActionTile(
                action: action,
                emphasised: action == highlight,
                // Trezor wallets run wallet-only, as in the navigation bar.
                disabledReason:
                    isHardwareWallet &&
                        (action == WalletQuickAction.swap ||
                            action == WalletQuickAction.buy)
                    ? LocaleKeys.trezorWalletOnlyTooltip.tr()
                    : null,
                onPressed: () => runWalletQuickAction(context, action),
              ),
            ),
        ],
      ),
    );
  }
}

/// Does [action]: Swap and Buy open their tabs; Send and Receive ask which
/// asset first, then open its page with the action under way.
Future<void> runWalletQuickAction(
  BuildContext context,
  WalletQuickAction action,
) async {
  SwapHaptics.selection();
  switch (action) {
    case WalletQuickAction.swap:
      routingState.selectedMenu = MainMenuValue.dex;
    case WalletQuickAction.buy:
      routingState.selectedMenu = MainMenuValue.fiat;
    case WalletQuickAction.send:
    case WalletQuickAction.receive:
      final purpose = action == WalletQuickAction.send
          ? CoinQuickAction.send
          : CoinQuickAction.receive;
      final pick = await showWalletAssetPicker(context, purpose: purpose);
      final instead = pick?.instead;
      final coin = pick?.coin;
      if (instead != null && context.mounted) {
        await runWalletQuickAction(context, instead);
      } else if (coin != null) {
        routingState.walletState.openCoin(coin.abbr, quickAction: purpose);
      }
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.emphasised,
    required this.onPressed,
    this.disabledReason,
  });

  final WalletQuickAction action;
  final bool emphasised;
  final VoidCallback onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final enabled = disabledReason == null;
    final foreground = emphasised ? palette.onBrand : palette.text;
    final tile = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: emphasised ? palette.brand : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: emphasised
              ? BorderSide.none
              : BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: action.key,
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: emphasised
                          ? palette.onBrand.withValues(alpha: 0.18)
                          : palette.selected,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        action.icon,
                        size: 20,
                        color: emphasised
                            ? palette.onBrand
                            : palette.brandHover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      action.label,
                      maxLines: 1,
                      style: WalletHomeText.action(context)
                          .copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final semantic = SwapButtonSemantics(
      label: action.label,
      onTap: enabled ? onPressed : null,
      child: tile,
    );
    return disabledReason == null
        ? semantic
        : Tooltip(message: disabledReason, child: semantic);
  }
}
