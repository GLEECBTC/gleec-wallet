import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/bloc/bitrefill/models/bitrefill_event.dart';
import 'package:web_dex/bloc/bitrefill/models/bitrefill_event_factory.dart';
import 'package:web_dex/bloc/bitrefill/models/bitrefill_payment_intent_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/bitrefill/bitrefill_inappwebview_button.dart';

final class _RefundAddressOption {
  const _RefundAddressOption({
    required this.address,
    required this.isGasfree,
    required this.spendableBalance,
  });

  final String address;
  final bool isGasfree;
  final Decimal? spendableBalance;
}

/// Returns whether an asynchronous Bitrefill refund selection still belongs
/// to the wallet and coin that initiated it.
///
/// [selectionIsCurrent] is deliberately lazy so a disposed widget or stale
/// wallet/coin binding is rejected before any context-dependent validation.
@visibleForTesting
bool isBitrefillRefundSelectionContextCurrent({
  required bool isMounted,
  required WalletId? initialWalletId,
  required WalletId? currentWalletId,
  required AssetId initialCoinId,
  required AssetId currentCoinId,
  required bool Function() selectionIsCurrent,
}) {
  if (!isMounted ||
      initialWalletId == null ||
      currentWalletId == null ||
      currentWalletId != initialWalletId ||
      currentCoinId != initialCoinId) {
    return false;
  }

  return selectionIsCurrent();
}

/// A button that opens the Bitrefill widget in a new window or tab.
/// The Bitrefill widget is a web page that allows the user to purchase gift
/// cards and mobile top-ups with cryptocurrency.
///
/// The widget is disabled if the Bitrefill widget fails to load, if the coin
/// is not supported, or if the coin is suspended.
///
/// The widget returns a payment intent event when the user completes a purchase.
/// The event is passed to the [onPaymentRequested] callback.
///
/// Multi-address support: When the user has multiple addresses, an address
/// selector dialog will be shown allowing them to choose which address to use
/// as the refund address for the Bitrefill transaction.
class BitrefillButton extends StatefulWidget {
  const BitrefillButton({
    required this.coin,
    required this.onPaymentRequested,
    super.key,
    this.windowTitle = 'Bitrefill',
    this.tooltip,
  });

  final Coin coin;
  final String windowTitle;
  final String? tooltip;
  final void Function(BitrefillPaymentIntentEvent) onPaymentRequested;

  @override
  State<BitrefillButton> createState() => _BitrefillButtonState();
}

class _BitrefillButtonState extends State<BitrefillButton> {
  String? _selectedRefundAddress;

  @override
  void initState() {
    super.initState();
    _selectedRefundAddress = null;
    context.read<BitrefillBloc>().add(
      BitrefillLoadRequested(coin: widget.coin, refundAddress: null),
    );
  }

  @override
  void didUpdateWidget(covariant BitrefillButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coin.id == widget.coin.id) return;

    _selectedRefundAddress = _defaultRefundAddress(context);
    context.read<BitrefillBloc>().add(
      BitrefillLoadRequested(
        coin: widget.coin,
        refundAddress: _selectedRefundAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void handleMessage(String event) => _handleMessage(event, context);
    final KomodoDefiSdk sdk = GetIt.I<KomodoDefiSdk>();
    final addressesState = context.watch<CoinAddressesBloc>().state;
    final gaslessAccountStatus = addressesState.gaslessAccountStatus;
    final gaslessReceiveEnabled = _gaslessReceiveEnabled(
      context,
      sdk,
      addressesState: addressesState,
    );
    final isHdWallet = _isHdWallet(context);

    return BlocListener<CoinAddressesBloc, CoinAddressesState>(
      listenWhen: (previous, current) =>
          gaslessReceiveEnabled &&
          _selectedRefundAddress == null &&
          _firstGasfreeRefundAddress(
                previous.addresses,
                gaslessReceiveEnabled: true,
                isHdWallet: isHdWallet,
              ) ==
              null &&
          _firstGasfreeRefundAddress(
                current.addresses,
                gaslessReceiveEnabled: true,
                isHdWallet: isHdWallet,
              ) !=
              null,
      listener: (context, state) {
        final refundAddress = _firstGasfreeRefundAddress(
          state.addresses,
          gaslessReceiveEnabled: gaslessReceiveEnabled,
          isHdWallet: isHdWallet,
        );
        if (refundAddress != null) {
          _setRefundAddress(context, refundAddress);
        }
      },
      child: BlocConsumer<BitrefillBloc, BitrefillState>(
        listener: (BuildContext context, BitrefillState state) {
          if (state is BitrefillPaymentInProgress) {
            widget.onPaymentRequested(state.paymentIntent);
          }
        },
        builder: (BuildContext context, BitrefillState state) {
          final bool bitrefillLoadSuccess = state is BitrefillLoadSuccess;
          bool isCoinSupported = false;
          if (bitrefillLoadSuccess) {
            isCoinSupported = state.supportedCoins.contains(widget.coin.abbr);
          }

          final walletSpendable =
              sdk.balances.lastKnown(widget.coin.id)?.spendable ?? Decimal.zero;
          final custodySpendable =
              gaslessReceiveEnabled &&
                  gaslessAccountStatus?.availability ==
                      GaslessAccountAvailability.available
              ? gaslessAccountStatus?.spendableBalance ?? Decimal.zero
              : Decimal.zero;
          final bool hasNonZeroBalance =
              walletSpendable > Decimal.zero || custodySpendable > Decimal.zero;

          final isShown =
              bitrefillLoadSuccess &&
              isCoinSupported &&
              !widget.coin.isSuspended;

          final isEnabled = isShown && hasNonZeroBalance || kDebugMode;

          final String url = state is BitrefillLoadSuccess ? state.url : '';

          if (!isShown) {
            return const SizedBox.shrink();
          }

          return Column(
            children: [
              BitrefillInAppWebviewButton(
                windowTitle: widget.windowTitle,
                url: url,
                enabled: isEnabled,
                tooltip: _getTooltipMessage(
                  hasNonZeroBalance,
                  isEnabled,
                  isCoinSupported,
                ),
                onMessage: handleMessage,
                onBeforeOpen: () => _prepareLaunchUrl(
                  context,
                  hasNonZeroBalance: hasNonZeroBalance,
                  currentUrl: url,
                  gaslessReceiveEnabled: gaslessReceiveEnabled,
                  isHdWallet: isHdWallet,
                  gaslessAccountStatus: gaslessAccountStatus,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Gets the appropriate tooltip message based on balance and coin status
  String? _getTooltipMessage(
    bool hasNonZeroBalance,
    bool isEnabled,
    bool isCoinSupported,
  ) {
    if (widget.tooltip != null) {
      return widget.tooltip;
    }

    // Show tooltip when button is disabled to explain why
    if (!isEnabled) {
      if (widget.coin.isSuspended) {
        return '${widget.coin.abbr} is currently suspended';
      }

      if (!isCoinSupported) {
        return '${widget.coin.abbr} is not supported by Bitrefill';
      }

      if (!hasNonZeroBalance) {
        return 'No ${widget.coin.abbr} balance available for spending';
      }
    }

    return null;
  }

  bool _gaslessReceiveEnabled(
    BuildContext context,
    KomodoDefiSdk sdk, {
    CoinAddressesState? addressesState,
  }) {
    final walletType = context
        .read<AuthBloc>()
        .state
        .currentUser
        ?.wallet
        .config
        .type;
    if (walletType != WalletType.iguana && walletType != WalletType.hdwallet) {
      return false;
    }
    final state = addressesState ?? context.read<CoinAddressesBloc>().state;
    final currentWalletHash = context
        .read<AuthBloc>()
        .state
        .currentUser
        ?.walletId
        .pubkeyHash
        ?.trim();
    final verifiedWalletHash = state.gaslessReceiveWalletPubkeyHash?.trim();
    if (currentWalletHash == null ||
        currentWalletHash.isEmpty ||
        verifiedWalletHash == null ||
        verifiedWalletHash.isEmpty ||
        currentWalletHash != verifiedWalletHash) {
      return false;
    }
    try {
      final asset = widget.coin.toSdkAsset(sdk);
      return widget.coin.isGaslessReceiveAsset(sdk) &&
          state.addresses.any(
            (address) =>
                isCanonicalTronGaslessPubkey(
                  address,
                  isHdWallet: walletType == WalletType.hdwallet,
                ) &&
                isVerifiedTronGaslessReceive(
                  sdk,
                  asset,
                  capabilityReady:
                      state.gaslessReceiveStatus == GaslessReceiveStatus.ready,
                  accountStatus: state.gaslessAccountStatus,
                  accountStatusObservedAt: state.gaslessAccountStatusObservedAt,
                  verifiedAddress: state.verifiedGasfreeAddress,
                  custodyAddress: address.gasfreeAddress,
                  expiresAt: state.gaslessReceiveConfigExpiresAt,
                  expectedServiceProvider: tronGaslessServiceProvider,
                ),
          );
    } catch (_) {
      return false;
    }
  }

  bool _gasfreeSelectionIsCurrent(
    BuildContext context,
    KomodoDefiSdk sdk,
    CoinAddressesBloc addressesBloc,
    _RefundAddressOption selected,
  ) {
    if (!selected.isGasfree) return true;
    final state = addressesBloc.state;
    final walletEpoch = context
        .read<AuthBloc>()
        .state
        .currentUser
        ?.walletId
        .pubkeyHash
        ?.trim();
    final selectionMatches =
        selected.address == state.verifiedGasfreeAddress &&
        _gaslessReceiveEnabled(context, sdk, addressesState: state) &&
        state.addresses.any(
          (address) =>
              address.gasfreeAddress == selected.address &&
              isCanonicalTronGaslessPubkey(
                address,
                isHdWallet: _isHdWallet(context),
              ),
        );
    return selectionMatches &&
        walletEpoch != null &&
        walletEpoch.isNotEmpty &&
        addressesBloc.revalidateGaslessReceiveForAction(
          custodyAddress: selected.address,
          walletEpoch: walletEpoch,
        );
  }

  bool _usesGasfreeAddress(
    PubkeyInfo address, {
    required bool gaslessReceiveEnabled,
    required bool isHdWallet,
  }) =>
      gaslessReceiveEnabled &&
      widget.coin.id.subClass == CoinSubClass.trc20 &&
      isCanonicalTronGaslessPubkey(address, isHdWallet: isHdWallet) &&
      (address.gasfreeAddress?.isNotEmpty ?? false);

  bool _isHdWallet(BuildContext context) =>
      context.read<AuthBloc>().state.currentUser?.wallet.config.type ==
      WalletType.hdwallet;

  String? _defaultRefundAddress(BuildContext context) {
    return _firstGasfreeRefundAddress(
      context.read<CoinAddressesBloc>().state.addresses,
      gaslessReceiveEnabled: _gaslessReceiveEnabled(
        context,
        GetIt.I<KomodoDefiSdk>(),
      ),
      isHdWallet: _isHdWallet(context),
    );
  }

  String? _firstGasfreeRefundAddress(
    List<PubkeyInfo> addresses, {
    required bool gaslessReceiveEnabled,
    required bool isHdWallet,
  }) {
    for (final address in addresses) {
      if (_usesGasfreeAddress(
        address,
        gaslessReceiveEnabled: gaslessReceiveEnabled,
        isHdWallet: isHdWallet,
      )) {
        return address.gasfreeAddress;
      }
    }

    return null;
  }

  void _setRefundAddress(BuildContext context, String refundAddress) {
    _applyRefundAddress(context.read<BitrefillBloc>(), refundAddress);
  }

  void _applyRefundAddress(BitrefillBloc bloc, String refundAddress) {
    if (_selectedRefundAddress == refundAddress) {
      return;
    }

    setState(() {
      _selectedRefundAddress = refundAddress;
    });

    bloc.add(
      BitrefillLoadRequested(
        coin: widget.coin,
        refundAddress: _selectedRefundAddress,
      ),
    );
  }

  List<_RefundAddressOption> _refundOptions(
    List<PubkeyInfo> addresses, {
    required bool gaslessReceiveEnabled,
    required bool isHdWallet,
    required GaslessAccountStatusResponse? gaslessAccountStatus,
  }) {
    return [
      for (final address in addresses) ...[
        if (_usesGasfreeAddress(
          address,
          gaslessReceiveEnabled: gaslessReceiveEnabled,
          isHdWallet: isHdWallet,
        ))
          _RefundAddressOption(
            address: address.gasfreeAddress!,
            isGasfree: true,
            spendableBalance:
                gaslessAccountStatus?.gasfreeAddress == address.gasfreeAddress
                ? gaslessAccountStatus?.spendableBalance
                : null,
          ),
        _RefundAddressOption(
          address: address.address,
          isGasfree: false,
          spendableBalance: address.balance.spendable,
        ),
      ],
    ];
  }

  Future<_RefundAddressOption?> _selectRefundAddress(
    BuildContext context,
    List<_RefundAddressOption> options,
  ) async {
    if (options.isEmpty) return null;
    if (options.length == 1) return options.single;

    return showDialog<_RefundAddressOption>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(LocaleKeys.addresses.tr()),
        children: [
          for (final option in options)
            SimpleDialogOption(
              key: ValueKey('bitrefill-refund-${option.address}'),
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Icon(
                    option.isGasfree
                        ? Icons.bolt_rounded
                        : Icons.account_balance_wallet_outlined,
                    semanticLabel: option.isGasfree
                        ? LocaleKeys.addressRowGasfreeTag.tr()
                        : LocaleKeys.addressRowStandardTag.tr(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.isGasfree
                              ? LocaleKeys.addressRowGasfreeTag.tr()
                              : LocaleKeys.addressRowStandardTag.tr(),
                          style: Theme.of(dialogContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.address,
                          softWrap: true,
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.spendableBalance == null
                              ? LocaleKeys
                                    .bitrefillGasfreeRefundBalanceUnavailable
                                    .tr()
                              : option.isGasfree
                              ? LocaleKeys.bitrefillGasfreeRefundStatus.tr(
                                  args: [
                                    option.spendableBalance.toString(),
                                    widget.coin.abbr,
                                  ],
                                )
                              : LocaleKeys.addressBalanceAvailable.tr(
                                  args: [
                                    option.spendableBalance.toString(),
                                    widget.coin.abbr,
                                  ],
                                ),
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_selectedRefundAddress == option.address)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle_outline),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _prepareLaunchUrl(
    BuildContext context, {
    required bool hasNonZeroBalance,
    required String currentUrl,
    required bool gaslessReceiveEnabled,
    required bool isHdWallet,
    required GaslessAccountStatusResponse? gaslessAccountStatus,
  }) async {
    if (!hasNonZeroBalance) return null;
    final authBloc = context.read<AuthBloc>();
    final addressesBloc = context.read<CoinAddressesBloc>();
    final bitrefillBloc = context.read<BitrefillBloc>();
    final sdk = GetIt.I<KomodoDefiSdk>();
    final initialWalletId = authBloc.state.currentUser?.walletId;
    final initialCoinId = widget.coin.id;

    bool selectionContextIsCurrent([_RefundAddressOption? selected]) {
      if (!mounted) return false;
      return isBitrefillRefundSelectionContextCurrent(
        isMounted: true,
        initialWalletId: initialWalletId,
        currentWalletId: authBloc.state.currentUser?.walletId,
        initialCoinId: initialCoinId,
        currentCoinId: widget.coin.id,
        selectionIsCurrent: () =>
            selected == null ||
            _gasfreeSelectionIsCurrent(context, sdk, addressesBloc, selected),
      );
    }

    void showGasfreeSelectionUnavailable(_RefundAddressOption selected) {
      if (!mounted || !selected.isGasfree) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleKeys.bitrefillGasfreeRefundUnavailable.tr()),
        ),
      );
    }

    final options = _refundOptions(
      addressesBloc.state.addresses,
      gaslessReceiveEnabled: gaslessReceiveEnabled,
      isHdWallet: isHdWallet,
      gaslessAccountStatus: gaslessAccountStatus,
    );
    final selected = await _selectRefundAddress(context, options);
    if (!mounted) return null;
    if (selected == null) return null;
    if (!selectionContextIsCurrent(selected)) {
      showGasfreeSelectionUnavailable(selected);
      return null;
    }

    if (_urlUsesRefundAddress(currentUrl, selected.address)) {
      if (!selectionContextIsCurrent(selected)) {
        showGasfreeSelectionUnavailable(selected);
        return null;
      }
      _selectedRefundAddress = selected.address;
      return selectionContextIsCurrent(selected) ? currentUrl : null;
    }

    final matchingState = bitrefillBloc.stream.firstWhere(
      (state) =>
          state is BitrefillLoadSuccess &&
          _urlUsesRefundAddress(state.url, selected.address),
    );
    if (!selectionContextIsCurrent(selected)) {
      showGasfreeSelectionUnavailable(selected);
      return null;
    }
    _applyRefundAddress(bitrefillBloc, selected.address);

    try {
      final state = await matchingState.timeout(const Duration(seconds: 5));
      if (!mounted) return null;
      if (!selectionContextIsCurrent(selected)) {
        showGasfreeSelectionUnavailable(selected);
        return null;
      }
      return (state as BitrefillLoadSuccess).url;
    } on TimeoutException {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(LocaleKeys.somethingWrong.tr())));
      }
      return null;
    }
  }

  bool _urlUsesRefundAddress(String url, String refundAddress) =>
      Uri.tryParse(url)?.queryParameters['refund_address'] == refundAddress;

  /// Handles messages from the Bitrefill widget.
  /// The message is a JSON string that contains the event name and event data.
  /// The event name is used to create a [BitrefillWidgetEvent] object.
  void _handleMessage(String event, BuildContext context) {
    // Convert from JSON string to Map here to avoid library and
    // platform-specific javascript object conversion issues.
    final Map<String, dynamic> decodedEvent =
        jsonDecode(event) as Map<String, dynamic>;

    final BitrefillWidgetEvent bitrefillEvent =
        BitrefillEventFactory.createEvent(decodedEvent);
    if (bitrefillEvent is BitrefillPaymentIntentEvent) {
      context.read<BitrefillBloc>().add(
        BitrefillPaymentIntentReceived(bitrefillEvent),
      );
    }
  }
}
