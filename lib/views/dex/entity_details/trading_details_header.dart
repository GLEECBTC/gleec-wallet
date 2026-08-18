import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/market_maker_bot_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';

class TradingDetailsHeader extends StatelessWidget {
  const TradingDetailsHeader({
    Key? key,
    required this.title,
  }) : super(key: key);
  final String title;

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      title: title,
      backText: _backButtonText,
      onBackButtonPressed: () {
        if (routingState.dexState.action != DexAction.none) {
          routingState.dexState.action = DexAction.none;
          routingState.dexState.uuid = '';
        } else if (routingState.marketMakerState.action !=
            MarketMakerBotAction.none) {
          routingState.marketMakerState.action = MarketMakerBotAction.none;
          routingState.marketMakerState.uuid = '';
        }
      },
    );
  }

  String get _backButtonText {
    String text;

    switch (routingState.selectedMenu) {
      case MainMenuValue.dex:
        text = LocaleKeys.backToDex.tr();
        break;
      default:
        text = LocaleKeys.back.tr();
    }

    return text;
  }
}
