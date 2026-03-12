import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_sort.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/information_popup.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_controls.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_list.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_list_header.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_selected_types_list.dart';

class CoinsManagerListWrapper extends StatefulWidget {
  const CoinsManagerListWrapper({super.key});

  @override
  State<CoinsManagerListWrapper> createState() =>
      _CoinsManagerListWrapperState();
}

class _CoinsManagerListWrapperState extends State<CoinsManagerListWrapper> {
  late InformationPopup _informationPopup;

  @override
  void initState() {
    _informationPopup = InformationPopup(context: context);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // The switching between add and remove assets was removed,
    // so we can simplify the listener logic to only handle disable
    // requests and confirmations.
    return MultiBlocListener(
      listeners: [
        BlocListener<CoinsManagerBloc, CoinsManagerState>(
          listenWhen: (previous, current) =>
              previous.removalState != current.removalState,
          listener: _onRemovalStateChanged,
        ),
        BlocListener<CoinsManagerBloc, CoinsManagerState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage &&
              current.errorMessage != null,
          listener: _onErrorMessageChanged,
        ),
      ],
      child: BlocBuilder<CoinsManagerBloc, CoinsManagerState>(
        builder: (BuildContext context, CoinsManagerState state) {
          final bool isAddAssets = state.action == CoinsManagerAction.add;
          final double bottomInset = isMobile
              ? MediaQuery.of(context).viewInsets.bottom
              : 0.0;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                CoinsManagerFilters(isMobile: isMobile),
                if (!isMobile)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: CoinsManagerListHeader(
                      sortData: state.sortData,
                      isAddAssets: isAddAssets,
                      onSortChange: _onSortChange,
                    ),
                  ),
                SizedBox(height: isMobile ? 4.0 : 14.0),
                const CoinsManagerSelectedTypesList(),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CoinsManagerList(
                          coinList: state.coins,
                          isAddAssets: isAddAssets,
                          onCoinSelect: _onCoinSelect,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onSortChange(CoinsManagerSortData sortData) {
    context.read<CoinsManagerBloc>().add(CoinsManagerSortChanged(sortData));
  }

  void _onRemovalStateChanged(BuildContext context, CoinsManagerState state) {
    final removalState = state.removalState;
    if (removalState == null) return;

    final bloc = context.read<CoinsManagerBloc>();
    final coin = removalState.coin;
    final childCoinTickers = removalState.childCoins
        .map((c) => c.abbr)
        .toList();
    final requiresParentConfirmation =
        coin.parentCoin == null && childCoinTickers.isNotEmpty;

    if (removalState.hasActiveSwap) {
      _informationPopup.text = LocaleKeys.coinDisableSpan1.tr(
        args: [removalState.coin.abbr],
      );
      _informationPopup.show();
      bloc.add(const CoinsManagerCoinRemovalCancelled());
      return;
    }

    if (removalState.hasOpenOrders) {
      confirmCoinDisableWithOrders(
        context,
        coin: removalState.coin.abbr,
        ordersCount: removalState.openOrdersCount,
      ).then((confirmed) {
        if (confirmed) {
          confirmParentCoinDisable(
            context,
            parent: coin.abbr,
            tokens: childCoinTickers,
          ).then((confirmed) {
            if (confirmed) {
              bloc.add(const CoinsManagerCoinRemoveConfirmed());
            } else {
              bloc.add(const CoinsManagerCoinRemovalCancelled());
            }
          });
        } else {
          bloc.add(const CoinsManagerCoinRemovalCancelled());
        }
      });
      return;
    }

    if (requiresParentConfirmation) {
      confirmParentCoinDisable(
        context,
        parent: coin.abbr,
        tokens: childCoinTickers,
      ).then((confirmed) {
        if (confirmed) {
          bloc.add(const CoinsManagerCoinRemoveConfirmed());
        } else {
          bloc.add(const CoinsManagerCoinRemovalCancelled());
        }
      });
    } else {
      // Direct removal without additional confirmation
      bloc.add(const CoinsManagerCoinRemoveConfirmed());
    }
  }

  void _onErrorMessageChanged(BuildContext context, CoinsManagerState state) {
    final errorMessage = state.errorMessage;
    if (errorMessage != null) {
      _informationPopup.text = errorMessage;
      _informationPopup.show();

      // Clear the error message after showing it
      context.read<CoinsManagerBloc>().add(const CoinsManagerErrorCleared());
    }
  }

  void _onCoinSelect(Coin coin) {
    final bloc = context.read<CoinsManagerBloc>();

    if (bloc.state.action == CoinsManagerAction.remove) {
      // Send request to bloc to check trading status
      bloc.add(CoinsManagerCoinRemoveRequested(coin: coin));
      return;
    }

    // For add mode, send the regular coin select event
    // The bloc will handle trading checks for deselection
    bloc.add(CoinsManagerCoinSelect(coin: coin));
  }
}
