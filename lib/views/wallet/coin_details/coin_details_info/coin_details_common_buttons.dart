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
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';
import 'package:web_dex/views/bitrefill/bitrefill_button.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/contract_address_button.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_dialog.dart';

@immutable
class _ReceiveRailSelection {
  const _ReceiveRailSelection({required this.address, required this.variant});

  final PubkeyInfo address;
  final AddressDisplayVariant variant;
}

bool _isVerifiedGaslessReceiveSelection(
  KomodoDefiSdk sdk,
  Coin coin,
  CoinAddressesState state,
  PubkeyInfo address, {
  required bool isHdWallet,
  required String? currentWalletPubkeyHash,
}) {
  try {
    final normalizedCurrentWallet = currentWalletPubkeyHash?.trim();
    final attestedWallet = state.gaslessReceiveWalletPubkeyHash?.trim();
    if (normalizedCurrentWallet == null ||
        normalizedCurrentWallet.isEmpty ||
        attestedWallet == null ||
        attestedWallet.isEmpty ||
        normalizedCurrentWallet != attestedWallet) {
      return false;
    }
    final canonical = state.addresses
        .where(
          (candidate) =>
              isCanonicalTronGaslessPubkey(candidate, isHdWallet: isHdWallet),
        )
        .toList(growable: false);
    if (canonical.length != 1 || canonical.single.address != address.address) {
      return false;
    }

    return isVerifiedTronGaslessReceive(
      sdk,
      coin.toSdkAsset(sdk),
      capabilityReady: state.gaslessReceiveStatus == GaslessReceiveStatus.ready,
      accountStatus: state.gaslessAccountStatus,
      accountStatusObservedAt: state.gaslessAccountStatusObservedAt,
      verifiedAddress: state.verifiedGasfreeAddress,
      custodyAddress: address.gasfreeAddress,
      expectedServiceProvider: tronGaslessServiceProvider,
    );
  } catch (_) {
    return false;
  }
}

Future<_ReceiveRailSelection?> _showGaslessReceiveRailSelector(
  BuildContext context, {
  required KomodoDefiSdk sdk,
  required Coin coin,
  required WalletId initialWalletId,
}) {
  // CoinAddressesBloc is scoped to CoinDetailsInfo, below the app Navigator.
  // Dialog routes are built under the Navigator overlay and therefore cannot
  // inherit that page-scoped provider unless it is carried into the route.
  final addressesBloc = context.read<CoinAddressesBloc>();
  return showDialog<_ReceiveRailSelection>(
    context: context,
    builder: (dialogContext) {
      return BlocListener<AuthBloc, AuthBlocState>(
        listenWhen: (previous, current) =>
            previous.currentUser?.walletId != current.currentUser?.walletId,
        listener: (context, state) {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        },
        child: BlocBuilder<AuthBloc, AuthBlocState>(
          builder: (context, authState) {
            final currentUser = authState.currentUser;
            if (currentUser?.walletId != initialWalletId) {
              return const SizedBox.shrink();
            }
            final walletType = currentUser?.wallet.config.type;
            final isHdWallet = walletType == WalletType.hdwallet;
            return BlocBuilder<CoinAddressesBloc, CoinAddressesState>(
              bloc: addressesBloc,
              builder: (context, addressesState) {
                final options = <_ReceiveRailSelection>[
                  for (final address in addressesState.addresses) ...[
                    if (_isVerifiedGaslessReceiveSelection(
                      sdk,
                      coin,
                      addressesState,
                      address,
                      isHdWallet: isHdWallet,
                      currentWalletPubkeyHash: currentUser?.walletId.pubkeyHash,
                    ))
                      _ReceiveRailSelection(
                        address: address,
                        variant: AddressDisplayVariant.gasfree,
                      ),
                    _ReceiveRailSelection(
                      address: address,
                      variant: AddressDisplayVariant.standard,
                    ),
                  ],
                ];
                final hasGasfree = options.any(
                  (option) => option.variant == AddressDisplayVariant.gasfree,
                );

                return SimpleDialog(
                  title: Text(LocaleKeys.addresses.tr()),
                  children: [
                    if (!hasGasfree)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Text(
                          LocaleKeys.receiveGaslessPausedNotice.tr(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final option in options)
                      SimpleDialogOption(
                        key: ValueKey(
                          'receive-rail-${option.variant.name}-'
                          '${option.address.address}',
                        ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(option),
                        child: Row(
                          children: [
                            Icon(
                              option.variant == AddressDisplayVariant.gasfree
                                  ? Icons.bolt_rounded
                                  : Icons.account_balance_wallet_outlined,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.variant ==
                                            AddressDisplayVariant.gasfree
                                        ? LocaleKeys.addressRowGasfreeTag.tr()
                                        : LocaleKeys.addressRowStandardTag.tr(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.variant ==
                                            AddressDisplayVariant.gasfree
                                        ? option.address.gasfreeAddress!
                                        : option.address.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.variant ==
                                            AddressDisplayVariant.gasfree
                                        ? LocaleKeys.receiveGasfreeAddressStatus
                                              .tr(
                                                args: [
                                                  formatDexAmt(
                                                    addressesState
                                                            .gaslessAccountStatus
                                                            ?.spendableBalance ??
                                                        Decimal.zero,
                                                  ),
                                                  abbr2Ticker(coin.abbr),
                                                ],
                                              )
                                        : LocaleKeys.addressBalanceAvailable.tr(
                                            args: [
                                              formatDexAmt(
                                                option
                                                    .address
                                                    .balance
                                                    .spendable,
                                              ),
                                              abbr2Ticker(coin.abbr),
                                            ],
                                          ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      );
    },
  );
}

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
    final sendButton = CoinDetailsSendButton(
      isMobile: isMobile,
      coin: coin,
      selectWidget: selectWidget,
      context: context,
    );
    final receiveButton = CoinDetailsReceiveButton(
      isMobile: isMobile,
      coin: coin,
      selectWidget: selectWidget,
      context: context,
    );
    final secondaryActions = <Widget>[
      if (isBitrefillIntegrationEnabled)
        BitrefillButton(
          key: Key('coin-details-bitrefill-button-${coin.abbr.toLowerCase()}'),
          coin: coin,
          onPaymentRequested: (_) => selectWidget(CoinPageType.send),
          tooltip: _getBitrefillTooltip(coin),
        ),
      if (!coin.walletOnly)
        CoinDetailsSwapButton(
          isMobile: isMobile,
          coin: coin,
          onClickSwapButton: clickSwapButton,
          context: context,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Visibility(
              visible: coin.protocolData?.contractAddress.isNotEmpty ?? false,
              child: ContractAddressButton(coin),
            ),
            const SizedBox(height: 12),
            if (stackActions) ...[
              sendButton,
              const SizedBox(height: 12),
              receiveButton,
            ] else
              Row(
                children: [
                  Expanded(child: sendButton),
                  const SizedBox(width: 15),
                  Expanded(child: receiveButton),
                ],
              ),
            if (secondaryActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (stackActions)
                for (var index = 0; index < secondaryActions.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == secondaryActions.length - 1 ? 0 : 12,
                    ),
                    child: secondaryActions[index],
                  )
              else
                Row(
                  children: [
                    for (
                      var index = 0;
                      index < secondaryActions.length;
                      index++
                    ) ...[
                      Expanded(child: secondaryActions[index]),
                      if (index != secondaryActions.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                ),
            ],
            if (coin.id.subClass == CoinSubClass.zhtlc) ...[
              const SizedBox(height: 12),
              ZhtlcConfigButton(coin: coin, isMobile: isMobile),
            ],
          ],
        );
      },
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
    // Warn before the address picker rather than after a selection. The gate
    // inside showPubkeyReceiveDialog still backs up its other call sites, and
    // the per-session acknowledgement means asking here does not double-prompt.
    final mayReveal = await ensureSeedBackedUp(
      context,
      reason: SeedBackupGateReason.receiveAddress,
      isTestCoin: coin.isTestCoin,
    );
    if (!mayReveal || !context.mounted) return;

    // Get coin addresses bloc from the parent widget
    final addressesBloc = context.read<CoinAddressesBloc>();
    final addressesState = addressesBloc.state;
    final addresses = addressesState.addresses;
    final currentUser = context.read<AuthBloc>().state.currentUser;
    final walletType = currentUser?.wallet.config.type;
    final walletPubkeyHash = currentUser?.walletId.pubkeyHash;
    final initialWalletId = currentUser?.walletId;
    final sdk = context.sdk;
    final gaslessReceiveEnabled =
        (walletType == WalletType.iguana ||
            walletType == WalletType.hdwallet) &&
        coin.isGaslessReceiveAsset(sdk) &&
        addresses.any(
          (address) => _isVerifiedGaslessReceiveSelection(
            sdk,
            coin,
            addressesState,
            address,
            isHdWallet: walletType == WalletType.hdwallet,
            currentWalletPubkeyHash: walletPubkeyHash,
          ),
        );

    final _ReceiveRailSelection? selected;
    if (gaslessReceiveEnabled && initialWalletId != null) {
      selected = await _showGaslessReceiveRailSelector(
        context,
        sdk: sdk,
        coin: coin,
        initialWalletId: initialWalletId,
      );
    } else {
      final selectedAddress = await showAddressSearch(
        context,
        addresses: addresses,
        assetNameLabel: coin.abbr,
      );
      selected = selectedAddress == null
          ? null
          : _ReceiveRailSelection(
              address: selectedAddress,
              variant: AddressDisplayVariant.standard,
            );
    }

    if (selected != null && context.mounted) {
      if (context.read<AuthBloc>().state.currentUser?.walletId !=
          initialWalletId) {
        return;
      }
      final selectedAddress = selected.address;
      final selectedWasGasfree =
          selected.variant == AddressDisplayVariant.gasfree;
      var currentGaslessReceiveEnabled = false;
      if (selectedWasGasfree) {
        final currentWalletType = context
            .read<AuthBloc>()
            .state
            .currentUser
            ?.wallet
            .config
            .type;
        final currentState = addressesBloc.state;
        final currentWalletPubkeyHash = context
            .read<AuthBloc>()
            .state
            .currentUser
            ?.walletId
            .pubkeyHash;
        currentGaslessReceiveEnabled =
            (currentWalletType == WalletType.iguana ||
                currentWalletType == WalletType.hdwallet) &&
            _isVerifiedGaslessReceiveSelection(
              sdk,
              coin,
              currentState,
              selectedAddress,
              isHdWallet: currentWalletType == WalletType.hdwallet,
              currentWalletPubkeyHash: currentWalletPubkeyHash,
            );
        if (!currentGaslessReceiveEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LocaleKeys.receiveGaslessPausedNotice.tr())),
          );
          return;
        }
      } else if (!addressesBloc.state.addresses.any(
        (address) => address.address == selectedAddress.address,
      )) {
        return;
      }

      showPubkeyReceiveDialog(
        context,
        coin,
        selectedAddress,
        variant: selectedWasGasfree
            ? AddressDisplayVariant.gasfree
            : AddressDisplayVariant.standard,
        gaslessReceiveEnabled: currentGaslessReceiveEnabled,
      );
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

class CoinDetailsSendButton extends StatefulWidget {
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
  State<CoinDetailsSendButton> createState() => _CoinDetailsSendButtonState();
}

class _CoinDetailsSendButtonState extends State<CoinDetailsSendButton> {
  /// Held for the widget's lifetime - see [CoinBalance] for why creating this
  /// in [build] restarts the SDK balance watcher on every rebuild.
  late Stream<BalanceInfo> _balanceStream;

  @override
  void initState() {
    super.initState();
    _balanceStream = RepositoryProvider.of<KomodoDefiSdk>(
      context,
    ).balances.watchBalance(widget.coin.id);
  }

  @override
  void didUpdateWidget(covariant CoinDetailsSendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coin.id != widget.coin.id) {
      _balanceStream = RepositoryProvider.of<KomodoDefiSdk>(
        context,
      ).balances.watchBalance(widget.coin.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coin = widget.coin;
    final isMobile = widget.isMobile;
    final selectWidget = widget.selectWidget;
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final ThemeData themeData = Theme.of(context);
    final walletType = context
        .watch<AuthBloc>()
        .state
        .currentUser
        ?.wallet
        .config
        .type;
    final gaslessEnabled =
        (walletType == WalletType.iguana ||
            walletType == WalletType.hdwallet) &&
        coin.isGaslessAsset(sdk);
    final hasGasfreeAddress =
        gaslessEnabled &&
        context.watch<CoinAddressesBloc>().state.addresses.any(
          (address) =>
              isCanonicalTronGaslessPubkey(
                address,
                isHdWallet: walletType == WalletType.hdwallet,
              ) &&
              (address.gasfreeAddress?.isNotEmpty ?? false),
        );

    // Gate Send on *confirmed* activation. The coin must be fully active in
    // KDF before a withdraw can be previewed: enabling Send while the coin is
    // only `activating` (relying on a cached balance / gas-free address) lets
    // the user fire `init_withdraw` against a coin KDF has not registered yet,
    // which fails with `NoSuchCoin`. A funded balance is shown for context, but
    // it does not by itself imply the coin is active in the current session.
    return StreamBuilder<BalanceInfo>(
      initialData: sdk.balances.lastKnown(coin.id),
      stream: _balanceStream,
      builder: (context, snapshot) {
        // Fall back to the last known balance on a transient stream error
        // (e.g. wallet change) so a funded button does not flicker to disabled.
        final balance = snapshot.hasError
            ? sdk.balances.lastKnown(coin.id)?.total ?? Decimal.zero
            : snapshot.data?.total ?? Decimal.zero;
        final canSend =
            coin.isActive && (balance > Decimal.zero || hasGasfreeAddress);

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
          onPressed: canSend
              ? () {
                  selectWidget(CoinPageType.send);
                }
              : null,
          text: LocaleKeys.send.tr(),
        );
      },
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
