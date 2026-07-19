import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/simple/confirm/taker_order_confirmation.dart';
import 'package:web_dex/views/dex/simple/form/tables/coins_table/taker_sell_coins_table.dart';
import 'package:web_dex/views/dex/simple/form/tables/orders_table/taker_orders_table.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_form_content.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_order_book.dart';

class TakerFormLayout extends StatelessWidget {
  const TakerFormLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TakerBloc, TakerState, TakerStep>(
      selector: (state) => state.step,
      builder: (context, step) {
        if (step == TakerStep.confirm) {
          return const TakerOrderConfirmation();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final spec = DexResponsiveSpec.fromWidth(constraints.maxWidth);
            return spec.usesStackedTradingLayout
                ? const _TakerFormMobileLayout()
                : _TakerFormDesktopLayout();
          },
        );
      },
    );
  }
}

class _TakerFormDesktopLayout extends StatefulWidget {
  @override
  State<_TakerFormDesktopLayout> createState() =>
      _TakerFormDesktopLayoutState();
}

class _TakerFormDesktopLayoutState extends State<_TakerFormDesktopLayout> {
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
                        key: const Key('taker-form-layout-scroll'),
                        controller: _mainScrollController,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Theme.of(
                              context,
                            ).calmCoreCompatibility.dexFormWidth,
                          ),
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              const TakerFormContent(),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: TakerSellCoinsTable(),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: TakerOrdersTable(),
                              ),
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
                    child: const TakerOrderbook(),
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

class _TakerFormMobileLayout extends StatefulWidget {
  const _TakerFormMobileLayout();

  @override
  State<_TakerFormMobileLayout> createState() => _TakerFormMobileLayoutState();
}

class _TakerFormMobileLayoutState extends State<_TakerFormMobileLayout> {
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
      controller: _scrollController,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
        ),
        child: Stack(
          children: [
            const Column(
              children: [
                TakerFormContent(),
                SizedBox(height: 22),
                TakerOrderbook(),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TakerSellCoinsTable(),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TakerOrdersTable(),
            ),
          ],
        ),
      ),
    );
  }
}
