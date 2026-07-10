import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/main_menu/main_menu_bar_mobile_item.dart';

class MainMenuBarMobile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final MainMenuValue selected = routingState.selectedMenu;
    final currentWallet = context.watch<AuthBloc>().state.currentUser?.wallet;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final bool isMMBotEnabled = state.mmBotSettings.isMMBotEnabled;
        final bool tradingEnabled = context
            .watch<TradingStatusBloc>()
            .state
            .isEnabled;
        final bool isHardwareWallet = currentWallet?.isHW == true;

        String tradingTooltipMessage() {
          if (isHardwareWallet) {
            return LocaleKeys.trezorWalletOnlyTooltip.tr();
          }
          if (!tradingEnabled) {
            return LocaleKeys.tradingDisabledTooltip.tr();
          }
          return '';
        }

        String walletOnlyTooltipMessage() {
          return isHardwareWallet
              ? LocaleKeys.trezorWalletOnlyTooltip.tr()
              : '';
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.currentGlobal.cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -10),
                blurRadius: 10,
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              height: 75,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: MainMenuBarMobileItem(
                      value: MainMenuValue.wallet,
                      isActive: selected == MainMenuValue.wallet,
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: tradingTooltipMessage(),
                      child: MainMenuBarMobileItem(
                        value: MainMenuValue.dex,
                        enabled: currentWallet?.isHW != true,
                        isActive: selected == MainMenuValue.dex,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: walletOnlyTooltipMessage(),
                      child: MainMenuBarMobileItem(
                        value: MainMenuValue.card,
                        enabled: currentWallet?.isHW != true,
                        isActive: selected == MainMenuValue.card,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: walletOnlyTooltipMessage(),
                      child: MainMenuBarMobileItem(
                        value: MainMenuValue.fiat,
                        enabled: currentWallet?.isHW != true,
                        isActive: selected == MainMenuValue.fiat,
                      ),
                    ),
                  ),
                  Expanded(
                    child: MainMenuBarMobileItem(
                      value: MainMenuValue.more,
                      isActive: _moreDestinations(
                        isMMBotEnabled,
                      ).contains(selected),
                      onTap: () => _showMore(
                        context,
                        isMMBotEnabled: isMMBotEnabled,
                        hardwareWallet: isHardwareWallet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<MainMenuValue> _moreDestinations(bool isMMBotEnabled) => [
    MainMenuValue.bridge,
    if (isMMBotEnabled) MainMenuValue.marketMakerBot,
    MainMenuValue.nft,
    MainMenuValue.settings,
    MainMenuValue.support,
  ];

  Future<void> _showMore(
    BuildContext context, {
    required bool isMMBotEnabled,
    required bool hardwareWallet,
  }) async {
    final selected = await showModalBottomSheet<MainMenuValue>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            for (final destination in _moreDestinations(isMMBotEnabled))
              ListTile(
                leading: NavIcon(
                  item: destination,
                  isActive: routingState.selectedMenu == destination,
                ),
                title: Text(destination.title),
                enabled:
                    destination != MainMenuValue.nft &&
                    (!hardwareWallet ||
                        destination == MainMenuValue.settings ||
                        destination == MainMenuValue.support),
                onTap: () => Navigator.pop(context, destination),
              ),
          ],
        ),
      ),
    );
    if (selected != null) routingState.selectedMenu = selected;
  }
}
