import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/views/bitrefill/bitrefill_button.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/contract_address_button.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_dialog.dart';

class CoinDetailsCommonButtons extends StatelessWidget {
  const CoinDetailsCommonButtons({
    required this.isMobile,
    required this.selectWidget,
    required this.onClickSwapButton,
    required this.coin,
    super.key,
  });

  final bool isMobile;
  final Coin coin;
  final void Function(CoinPageType) selectWidget;
  final VoidCallback? onClickSwapButton;

  @override
  Widget build(BuildContext context) {
    return isMobile
        ? CoinDetailsCommonButtonsMobileLayout(
            coin: coin,
            isMobile: isMobile,
            selectWidget: selectWidget,
            clickSwapButton: onClickSwapButton,
            context: context,
          )
        : CoinDetailsCommonButtonsDesktopLayout(
            isMobile: isMobile,
            coin: coin,
            selectWidget: selectWidget,
            clickSwapButton: onClickSwapButton,
            context: context,
          );
  }
}

class CoinDetailsCommonButtonsMobileLayout extends StatelessWidget {
  const CoinDetailsCommonButtonsMobileLayout({
    required this.coin,
    required this.isMobile,
    required this.selectWidget,
    required this.clickSwapButton,
    required this.context,
    super.key,
  });

  final Coin coin;
  final bool isMobile;
  final void Function(CoinPageType p1) selectWidget;
  final VoidCallback? clickSwapButton;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Visibility(
          visible: coin.protocolData?.contractAddress.isNotEmpty ?? false,
          child: ContractAddressButton(coin),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: CoinDetailsSendButton(
                isMobile: isMobile,
                coin: coin,
                selectWidget: selectWidget,
                context: context,
              ),
            ),
            const SizedBox(width: 15),
            Flexible(
              child: CoinDetailsReceiveButton(
                isMobile: isMobile,
                coin: coin,
                selectWidget: selectWidget,
                context: context,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isBitrefillIntegrationEnabled) ...[
              Flexible(
                child: BitrefillButton(
                  key: Key(
                    'coin-details-bitrefill-button-${coin.abbr.toLowerCase()}',
                  ),
                  coin: coin,
                  onPaymentRequested: (_) => selectWidget(CoinPageType.send),
                  tooltip: _getBitrefillTooltip(coin),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (!coin.walletOnly)
              Flexible(
                child: CoinDetailsSwapButton(
                  isMobile: isMobile,
                  coin: coin,
                  onClickSwapButton: clickSwapButton,
                  context: context,
                ),
              ),
          ],
        ),
        if (coin.id.subClass == CoinSubClass.zhtlc) ...[
          const SizedBox(height: 12),
          ZhtlcConfigButton(coin: coin, isMobile: isMobile),
        ],
      ],
    );
  }
}

class CoinDetailsCommonButtonsDesktopLayout extends StatelessWidget {
  const CoinDetailsCommonButtonsDesktopLayout({
    required this.isMobile,
    required this.coin,
    required this.selectWidget,
    required this.clickSwapButton,
    required this.context,
    super.key,
  });

  final bool isMobile;
  final Coin coin;
  final void Function(CoinPageType p1) selectWidget;
  final VoidCallback? clickSwapButton;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final tradingState = context.watch<TradingStatusBloc>().state;
    final canTradeCoin =
        !coin.walletOnly && tradingState.canTradeAssets([coin.id]);

    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: CoinDetailsSendButton(
            isMobile: isMobile,
            coin: coin,
            selectWidget: selectWidget,
            context: context,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(left: 21),
          constraints: const BoxConstraints(maxWidth: 120),
          child: CoinDetailsReceiveButton(
            isMobile: isMobile,
            coin: coin,
            selectWidget: selectWidget,
            context: context,
          ),
        ),
        if (canTradeCoin)
          Container(
            margin: const EdgeInsets.only(left: 21),
            constraints: const BoxConstraints(maxWidth: 120),
            child: CoinDetailsSwapButton(
              isMobile: isMobile,
              coin: coin,
              onClickSwapButton: clickSwapButton,
              context: context,
            ),
          ),
        if (isBitrefillIntegrationEnabled)
          Container(
            margin: const EdgeInsets.only(left: 21),
            constraints: const BoxConstraints(maxWidth: 120),
            child: BitrefillButton(
              key: Key(
                'coin-details-bitrefill-button-${coin.abbr.toLowerCase()}',
              ),
              coin: coin,
              onPaymentRequested: (_) => selectWidget(CoinPageType.send),
              tooltip: _getBitrefillTooltip(coin),
            ),
          ),
        if (coin.id.subClass == CoinSubClass.zhtlc)
          Container(
            margin: const EdgeInsets.only(left: 21),
            constraints: const BoxConstraints(maxWidth: 120),
            child: ZhtlcConfigButton(coin: coin, isMobile: isMobile),
          ),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: coin.protocolData?.contractAddress.isNotEmpty ?? false
                ? SizedBox(width: 230, child: ContractAddressButton(coin))
                : null,
          ),
        ),
      ],
    );
  }
}

class CoinDetailsReceiveButton extends StatelessWidget {
  const CoinDetailsReceiveButton({
    required this.isMobile,
    required this.coin,
    required this.selectWidget,
    required this.context,
    super.key,
  });

  final bool isMobile;
  final Coin coin;
  final void Function(CoinPageType p1) selectWidget;
  final BuildContext context;

  Future<void> _handleReceive(BuildContext context) async {
    // Get coin addresses bloc from the parent widget
    final addressesBloc = context.read<CoinAddressesBloc>();
    final addresses = addressesBloc.state.addresses;

    final selectedAddress = await showAddressSearch(
      context,
      addresses: addresses,
      assetNameLabel: coin.abbr,
    );

    if (selectedAddress != null && context.mounted) {
      showPubkeyReceiveDialog(context, coin, selectedAddress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAddresses = context
        .watch<CoinAddressesBloc>()
        .state
        .addresses
        .isNotEmpty;
    final ThemeData themeData = Theme.of(context);
    return UiPrimaryButton(
      key: const Key('coin-details-receive-button'),
      height: isMobile ? 52 : 40,
      prefix: Container(
        padding: const EdgeInsets.only(right: 14),
        child: SvgPicture.asset('$assetsPath/others/receive.svg'),
      ),
      textStyle: themeData.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: themeData.colorScheme.tertiary,
      onPressed: coin.isSuspended || !hasAddresses
          ? null
          : () => _handleReceive(context),
      text: LocaleKeys.receive.tr(),
    );
  }
}

class CoinDetailsSendButton extends StatelessWidget {
  const CoinDetailsSendButton({
    required this.isMobile,
    required this.coin,
    required this.selectWidget,
    required this.context,
    super.key,
  });

  final bool isMobile;
  final Coin coin;
  final void Function(CoinPageType p1) selectWidget;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final lastKnownBalance =
        sdk.balances.lastKnown(coin.id)?.total ?? Decimal.zero;

    final ThemeData themeData = Theme.of(context);
    return UiPrimaryButton(
      key: const Key('coin-details-send-button'),
      height: isMobile ? 52 : 40,
      prefix: Container(
        padding: const EdgeInsets.only(right: 14),
        child: SvgPicture.asset('$assetsPath/others/send.svg'),
      ),
      textStyle: themeData.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: themeData.colorScheme.tertiary,
      onPressed: !coin.isActive || lastKnownBalance == Decimal.zero
          ? null
          : () {
              selectWidget(CoinPageType.send);
            },
      text: LocaleKeys.send.tr(),
    );
  }
}

class CoinDetailsSwapButton extends StatelessWidget {
  const CoinDetailsSwapButton({
    required this.isMobile,
    required this.coin,
    required this.onClickSwapButton,
    required this.context,
    super.key,
  });

  final bool isMobile;
  final Coin coin;
  final VoidCallback? onClickSwapButton;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final currentWallet = context.watch<AuthBloc>().state.currentUser?.wallet;
    if (currentWallet?.config.type != WalletType.iguana &&
        currentWallet?.config.type != WalletType.hdwallet) {
      return const SizedBox.shrink();
    }

    final ThemeData themeData = Theme.of(context);
    return UiPrimaryButton(
      key: const Key('coin-details-swap-button'),
      height: isMobile ? 52 : 40,
      textStyle: themeData.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: themeData.colorScheme.tertiary,
      text: LocaleKeys.swap.tr(),
      prefix: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SvgPicture.asset('$assetsPath/others/swap.svg'),
      ),
      onPressed: !coin.isActive ? null : onClickSwapButton,
    );
  }
}

/// Gets the appropriate tooltip message for the Bitrefill button
String? _getBitrefillTooltip(Coin coin) {
  if (!coin.isActive) {
    return '${coin.abbr} is currently suspended';
  }

  // Check if coin has zero balance (this could be enhanced with actual balance check)
  return null; // Let BitrefillButton handle the zero balance tooltip
}

class ZhtlcConfigButton extends StatelessWidget {
  const ZhtlcConfigButton({
    required this.coin,
    required this.isMobile,
    super.key,
  });

  final Coin coin;
  final bool isMobile;

  Future<void> _handleConfigUpdate(BuildContext context) async {
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final arrrService = RepositoryProvider.of<ArrrActivationService>(context);
    final coinsBloc = context.read<CoinsBloc>();

    // Get the asset from the SDK
    final asset = sdk.assets.available[coin.id];
    if (asset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Asset ${coin.id.id} not found'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    ZhtlcUserConfig? newConfig;
    try {
      newConfig = await confirmZhtlcConfiguration(context, asset: asset);
      if (newConfig != null && context.mounted) {
        coinsBloc.add(CoinsDeactivated({coin.id.id}));
        await arrrService.updateZhtlcConfig(asset, newConfig);

        // Forcefully navigate back to wallet page so that the zhtlc status bar
        // is visible, rather than allowing periodic balance, pubkey, and tx
        // history requests to continue running and failing during activation
        routingState.selectedMenu = MainMenuValue.wallet;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating configuration: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (newConfig != null) {
        coinsBloc.add(CoinsActivated([asset.id.id]));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    return UiPrimaryButton(
      key: const Key('coin-details-zhtlc-config-button'),
      height: isMobile ? 52 : 40,
      prefix: Container(
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(Icons.settings, size: 18),
      ),
      textStyle: themeData.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: themeData.colorScheme.tertiary,
      onPressed: coin.isActive ? () => _handleConfigUpdate(context) : null,
      text: LocaleKeys.zhtlcConfigButton.tr(),
    );
  }
}
