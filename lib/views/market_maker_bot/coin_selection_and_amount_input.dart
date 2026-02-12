import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_body.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/shared/widgets/coin_select_item_widget.dart';
import 'package:web_dex/views/dex/common/front_plate.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_form_group_header.dart';
import 'package:web_dex/views/dex/simple/form/tables/table_utils.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/coin_name_and_protocol.dart';
import 'package:web_dex/views/market_maker_bot/coin_search_dropdown.dart';

class CoinSelectionAndAmountInput extends StatefulWidget {
  const CoinSelectionAndAmountInput({
    super.key,
    required this.coins,
    this.selectedCoin,
    required this.title,
    this.trailing,
    this.onItemSelected,
    this.useFrontPlate = true,
    this.refine,
  });

  final Coin? selectedCoin;
  final List<Coin> coins;
  final String title;
  final Widget? trailing;
  final Function(Coin?)? onItemSelected;
  final bool useFrontPlate;
  /// Optional refiner applied after default filtering/sorting to customize
  /// ordering (e.g., activation/balance grouping for buy list).
  final List<Coin> Function(List<Coin>)? refine;

  @override
  State<CoinSelectionAndAmountInput> createState() =>
      _CoinSelectionAndAmountInputState();
}

class _CoinSelectionAndAmountInputState
    extends State<CoinSelectionAndAmountInput> {
  // TECH DEBT: This widget uses StatefulWidget with local state (_items)
  // which is an anti-pattern when the data depends on Bloc state.
  // Following BLoC best practices, this should be refactored to use BlocBuilder
  // and compute the items in the build method based on bloc state changes.
  // Currently, we work around this by wrapping the widget in BlocBuilder below.
  late List<DropdownMenuItem<String>> _items;

  @override
  void initState() {
    super.initState();
    _prepareItems();
  }

  @override
  void didUpdateWidget(CoinSelectionAndAmountInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coins != oldWidget.coins) {
      _prepareItems();
    }
  }

  late final _sdk = context.read<KomodoDefiSdk>();
  void _prepareItems() {
    List<Coin> list = prepareCoinsForTable(
      context,
      widget.coins,
      null,
      testCoinsEnabled:
          context.read<SettingsBloc>().state.testCoinsEnabled,
    );

    if (widget.refine != null) {
      list = widget.refine!(list);
    }

    _items = list
        .map(
          (coin) => DropdownMenuItem<String>(
            value: coin.abbr,
            child: CoinSelectItemWidget(
              name: coin.displayName,
              coinId: coin.abbr,
              trailing: AssetBalanceText(
                coin.toSdkAsset(_sdk).id,
                activateIfNeeded: false,
              ),
              title: CoinItemBody(coin: coin, size: CoinItemSize.large),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Using BlocBuilder to listen to TradingStatusBloc changes
    // This ensures _prepareItems is called when geo-blocking status changes.
    // Following BLoC best practices: widgets should rebuild when dependent bloc states change.
    return BlocBuilder<TradingStatusBloc, TradingStatusState>(
      builder: (context, tradingStatus) {
        // Rebuild items when trading status changes
        _prepareItems();

        Widget content = Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DexFormGroupHeader(title: widget.title),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 8, 0, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.selectedCoin == null
                          ? AssetLogo.placeholder(isBlank: true)
                          : AssetLogo.ofId(widget.selectedCoin!.id),
                      const SizedBox(width: 9),
                      CoinNameAndProtocol(widget.selectedCoin, true),
                      const SizedBox(width: 9),
                    ],
                  ),
                  const SizedBox(width: 5),
                  Expanded(child: widget.trailing ?? const SizedBox.shrink()),
                ],
              ),
            ),
          ],
        );

        if (widget.useFrontPlate) {
          content = FrontPlate(child: content);
        }

        final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
        return CoinDropdown(
          items: _items,
          onItemSelected: (item) =>
              widget.onItemSelected?.call(coinsRepository.getCoin(item)),
          child: content,
        );
      },
    );
  }
}
