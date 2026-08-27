import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/gasless/tron_gasless_consolidation_gate.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_reward_claim_success.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_rewards_info.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/gasless_consolidation_wizard.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

class CoinDetails extends StatefulWidget {
  const CoinDetails({
    super.key,
    required this.coin,
    required this.onBackButtonPressed,
  });

  final Coin coin;
  final VoidCallback onBackButtonPressed;

  @override
  State<CoinDetails> createState() => _CoinDetailsState();
}

class _CoinDetailsState extends State<CoinDetails> {
  CoinPageType _selectedPageType = CoinPageType.info;

  String _rewardValue = '';
  String _formattedUsdPrice = '';

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final walletType =
          context.read<AuthBloc>().state.currentUser?.wallet.config.type.name ??
          '';
      context.read<AnalyticsBloc>().logEvent(
        AssetViewedEventData(
          asset: widget.coin.abbr,
          network: widget.coin.protocolType,
          hdType: walletType,
        ),
      );
    });
    super.initState();
  }

  @override
  void dispose() {
    // _txHistoryBloc.add(TransactionHistoryUnsubscribe(coin: widget.coin));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TransactionHistoryBloc>(
      create: (ctx) {
        final bloc = TransactionHistoryBloc(sdk: ctx.read<KomodoDefiSdk>());
        if (hasTxHistorySupport(widget.coin)) {
          bloc.add(TransactionHistorySubscribe(coin: widget.coin));
        }
        return bloc;
      },
      // No BlocBuilder<CoinsBloc, CoinsState> here.
      //
      // There used to be one, and its builder ignored `state` entirely - it
      // only wrapped this GestureDetector. The effect was that every
      // `CoinsState` emission (a balance change, an activation transition, the
      // 3-minute price tick, each wave of the balance sweep) rebuilt the whole
      // coin-details page, including the transaction list's eagerly-built rows.
      // Descendants that need coin state subscribe to it themselves.
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Detect swipe-back gesture (swipe from left to right)
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 0) {
            // Only trigger back navigation if we're on the info page
            if (_selectedPageType == CoinPageType.info) {
              widget.onBackButtonPressed();
            }
          }
        },
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedPageType) {
      case CoinPageType.info:
        return CoinDetailsInfo(
          coin: widget.coin,
          setPageType: _setPageType,
          onBackButtonPressed: widget.onBackButtonPressed,
        );

      case CoinPageType.send:
        return WithdrawForm(
          asset: widget.coin.toSdkAsset(context.read<KomodoDefiSdk>()),
          onSuccess: _openInfo,
          onBackButtonPressed: _openInfo,
        );

      case CoinPageType.sendConsolidate:
        final sdk = context.read<KomodoDefiSdk>();
        final asset = widget.coin.toSdkAsset(sdk);
        final currentUser = context.read<AuthBloc>().state.currentUser;
        final walletType = currentUser?.wallet.config.type;
        final gasfreeAddress = cachedCanonicalTronGaslessCustodyAddress(
          sdk,
          asset,
          walletType: walletType,
          currentWalletId: currentUser?.walletId,
        );

        // The info-page receive BLoC is intentionally page-scoped. Start a
        // fresh gate evaluation for the wizard so remote expiry, SDK binding,
        // and the canonical cache are revalidated after navigation as well.
        return BlocProvider<CoinAddressesBloc>(
          create: (context) =>
              CoinAddressesBloc(sdk, asset.id.id, context.read<AnalyticsBloc>())
                ..add(const CoinAddressesStarted()),
          child: GaslessConsolidationWizard(
            asset: asset,
            custodyAddress: gasfreeAddress ?? '',
            expectedWalletId: currentUser?.walletId,
            onDone: _openInfo,
          ),
        );
      case CoinPageType.claim:
        return KmdRewardsInfo(
          coin: widget.coin,
          onBackButtonPressed: _openInfo,
          onSuccess: (String reward, String formattedUsd) {
            _rewardValue = reward;
            _formattedUsdPrice = formattedUsd;
            _setPageType(CoinPageType.claimSuccess);
          },
        );

      case CoinPageType.claimSuccess:
        return KmdRewardClaimSuccess(
          reward: _rewardValue,
          formattedUsd: _formattedUsdPrice,
          onBackButtonPressed: _openInfo,
        );
    }
  }

  void _openInfo() => _setPageType(CoinPageType.info);

  void _setPageType(CoinPageType pageType) {
    setState(() => _selectedPageType = pageType);
  }
}
