import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/simple/confirm/maker_order_confirmation.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_buy_coin_table.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_content.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_orderbook.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_sell_coin_table.dart';

class MakerFormLayout extends StatefulWidget {
  const MakerFormLayout();

  @override
  State<MakerFormLayout> createState() => _MakerFormLayoutState();
}

class _MakerFormLayoutState extends State<MakerFormLayout> {
  @override
  void initState() {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    makerFormBloc.setDefaultSellCoin();
    _consumeRouteParameters();

    super.initState();
  }

  void _consumeRouteParameters() {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);

    if (routingState.dexState.orderType != 'taker') {
      if (routingState.dexState.fromCurrency.isNotEmpty) {
        final Coin? sellCoin = coinsRepository.getCoin(
          routingState.dexState.fromCurrency,
        );

        if (sellCoin != null) {
          makerFormBloc.sellCoin = sellCoin;

          if (routingState.dexState.fromAmount.isNotEmpty) {
            makerFormBloc.setSellAmount(routingState.dexState.fromAmount);
          }
        }
      }

      if (routingState.dexState.toCurrency.isNotEmpty) {
        final Coin? buyCoin = coinsRepository.getCoin(
          routingState.dexState.toCurrency,
        );

        if (buyCoin != null) {
          makerFormBloc.buyCoin = buyCoin;

          if (routingState.dexState.toAmount.isNotEmpty) {
            makerFormBloc.setBuyAmount(routingState.dexState.toAmount);
          }
        }
      }

      routingState.dexState.clearDexParams();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DexTabBarBloc bloc = context.read<DexTabBarBloc>();
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);

    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        if (state.mode == AuthorizeMode.noLogin) {
          makerFormBloc.showConfirmation = false;
        }
      },
      child: StreamBuilder<bool>(
        initialData: makerFormBloc.showConfirmation,
        stream: makerFormBloc.outShowConfirmation,
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return MakerOrderConfirmation(
              onCreateOrder: () => bloc.add(const TabChanged(2)),
              onCancel: () {
                makerFormBloc.showConfirmation = false;
              },
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final spec = DexResponsiveSpec.fromWidth(constraints.maxWidth);
              return spec.usesStackedTradingLayout
                  ? const _MakerFormMobileLayout()
                  : const _MakerFormDesktopLayout();
            },
          );
        },
      ),
    );
  }
}

class _MakerFormDesktopLayout extends StatefulWidget {
  const _MakerFormDesktopLayout();

  @override
  State<_MakerFormDesktopLayout> createState() =>
      _MakerFormDesktopLayoutState();
}

class _MakerFormDesktopLayoutState extends State<_MakerFormDesktopLayout> {
  late final ScrollController _mainScrollController;
  late final ScrollController _orderbookScrollController;

  @override
  void initState() {
    super.initState();
    _mainScrollController = ScrollController();
    _orderbookScrollController = ScrollController();
    _mainScrollController.addListener(_onScroll);
    _orderbookScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _mainScrollController.removeListener(_onScroll);
    _orderbookScrollController.removeListener(_onScroll);
    _mainScrollController.dispose();
    _orderbookScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Dismiss keyboard when user starts scrolling
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spec = DexResponsiveSpec.fromWidth(constraints.maxWidth);
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: spec.maxContentWidth),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: DexScrollbar(
                      scrollController: _mainScrollController,
                      isMobile: false,
                      child: SingleChildScrollView(
                        key: const Key('maker-form-layout-scroll'),
                        controller: _mainScrollController,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Theme.of(
                              context,
                            ).calmCoreCompatibility.dexFormWidth,
                          ),
                          child: const Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              MakerFormContent(),
                              MakerFormSellCoinTable(),
                              MakerFormBuyCoinTable(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spec.gutter),
                SizedBox(
                  width: spec.orderbookWidth,
                  child: SingleChildScrollView(
                    controller: _orderbookScrollController,
                    child: const MakerFormOrderbook(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MakerFormMobileLayout extends StatefulWidget {
  const _MakerFormMobileLayout();

  @override
  State<_MakerFormMobileLayout> createState() => _MakerFormMobileLayoutState();
}

class _MakerFormMobileLayoutState extends State<_MakerFormMobileLayout> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Dismiss keyboard when user starts scrolling
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('maker-form-layout-scroll'),
      controller: _scrollController,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
        ),
        child: const Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MakerFormContent(),
                SizedBox(height: 22),
                MakerFormOrderbook(),
              ],
            ),
            MakerFormSellCoinTable(),
            MakerFormBuyCoinTable(),
          ],
        ),
      ),
    );
  }
}
