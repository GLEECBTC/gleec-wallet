import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/banxa_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/fiat/ramp/ramp_fiat_provider.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/dex/entities_list/history/history_list.dart';
import 'package:web_dex/views/dex/entities_list/in_progress/in_progress_list.dart';
import 'package:web_dex/views/dex/entity_details/trading_details.dart';
import 'package:web_dex/views/fiat/fiat_form.dart';

class FiatPage extends StatefulWidget {
  const FiatPage() : super(key: const Key('fiat-page'));

  @override
  State<StatefulWidget> createState() => _FiatPageState();
}

class _FiatPageState extends State<FiatPage> with TickerProviderStateMixin {
  int _activeTabIndex = 0;
  bool _showSwap = false;

  @override
  void initState() {
    routingState.fiatState.addListener(_onRouteChange);
    super.initState();
  }

  @override
  void dispose() {
    routingState.fiatState.removeListener(_onRouteChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final fiatRepository = FiatRepository(
      // Ramp API keys unavailable for the time being
      // TODO(takenagain): re-enable when API keys are available
      // [BanxaFiatProvider(), RampFiatProvider()],
      [BanxaFiatProvider()],
      coinsRepository,
    );
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    return AppPaletteScope(
      child: BlocProvider(
        create: (_) => FiatFormBloc(
          repository: fiatRepository,
          coinsRepo: coinsRepository,
          sdk: sdk,
        ),
        child: MultiBlocListener(
          listeners: [
            BlocListener<AuthBloc, AuthBlocState>(
              listener: _handleAuthStateChange,
            ),
            BlocListener<FiatFormBloc, FiatFormState>(
              listenWhen: (previous, current) =>
                  previous.fiatOrderStatus != current.fiatOrderStatus,
              listener: _handleOrderStatusChange,
            ),
          ],
          child: _showSwap
              ? TradingDetails(uuid: routingState.fiatState.uuid)
              : FiatPageLayout(activeTabIndex: _activeTabIndex),
        ),
      ),
    );
  }

  void _handleOrderStatusChange(BuildContext context, FiatFormState state) {
    if (state.fiatOrderStatus == FiatOrderStatus.success) {
      _onCheckoutComplete(isSuccess: true);
    }
  }

  void _handleAuthStateChange(BuildContext context, AuthBlocState state) {
    if (state.mode == AuthorizeMode.noLogin) {
      setState(() {
        _activeTabIndex = 0;
      });
    }
  }

  // Will be used in the future for switching between tabs when we implement
  // the purchase history tab.
  // void _setActiveTab(int i) {
  //   setState(() {
  //     _activeTabIndex = i;
  //   });
  // }

  void _onRouteChange() {
    setState(() {
      _showSwap = routingState.fiatState.action == FiatAction.tradingDetails;
    });
  }

  void _onCheckoutComplete({required bool isSuccess}) {
    if (isSuccess) {
      // In the future, we will navigate to the purchase history tab when the
      // purchase is complete.
      // _setActiveTab(1);
    }
  }
}

class FiatPageLayout extends StatelessWidget {
  const FiatPageLayout({
    required this.activeTabIndex,
    super.key,
  });

  final int activeTabIndex;

  @override
  Widget build(BuildContext context) {
    return PageLayout(
      content: Expanded(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650),
          margin: isMobile ? const EdgeInsets.only(top: 14) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // TODO: Future feature to show fiat purchase history. Until then,
              // we'll hide the tabs since only the first one is used.
              // ConstrainedBox(
              //   constraints:
              //       BoxConstraints(maxWidth: theme.custom.dexFormWidth),
              //   child: HiddenWithoutWallet(
              //     child: FiatTabBar(
              //       currentTabIndex: _activeTabIndex,
              //       onTabClick: _setActiveTab,
              //     ),
              //   ),
              // ),
              Flexible(
                child: _TabContent(
                  activeTabIndex: activeTabIndex,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required int activeTabIndex,
    // ignore: unused_element_parameter
    super.key,
  }) : _activeTabIndex = activeTabIndex;

  final int _activeTabIndex;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabContents = [
      const FiatForm(),
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: InProgressList(
          filter: _fiatSwapsFilter,
          onItemClick: _onSwapItemClick,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: HistoryList(
          filter: _fiatSwapsFilter,
          onItemClick: _onSwapItemClick,
        ),
      ),
    ];

    return tabContents[_activeTabIndex];
  }

  void _onSwapItemClick(Swap swap) {
    routingState.fiatState.setDetailsAction(swap.uuid);
  }

  bool _fiatSwapsFilter(Swap swap) {
    return abbr2Ticker(swap.sellCoin) == abbr2Ticker(swap.buyCoin);
  }
}
