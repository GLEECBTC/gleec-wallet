import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_wrapper.dart';
import 'package:web_dex/views/dex/common/form_plate.dart';
import 'package:web_dex/views/dex/common/front_plate.dart';
import 'package:web_dex/views/dex/common/section_switcher.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_flip_button_overlapper.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_form_group_header.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_info_container.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_buy_item.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_compare_to_cex.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_error_list.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_exchange_rate.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_price_item.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_sell_item.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_total_fees.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_trade_button.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

class MakerFormContent extends StatelessWidget {
  const MakerFormContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);

    return FormPlate(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
        child: Column(
          children: [
            SectionSwitcher(),
            const SizedBox(height: 6),
            DexFlipButtonOverlapper(
              onTap: () async {
                final tmp = makerFormBloc.sellCoin;
                makerFormBloc.sellCoin = makerFormBloc.buyCoin;
                makerFormBloc.buyCoin = tmp;
                return true;
              },
              topWidget: const MakerFormSellItem(),
              bottomWidget: const FrontPlate(
                child: Column(
                  children: [
                    _BuyItemHeader(),
                    MakerFormBuyItem(),
                    MakerFormPriceItem(),
                  ],
                ),
              ),
            ),
            const _FormControls(),
          ],
        ),
      ),
    );
  }
}

class _FormControls extends StatelessWidget {
  const _FormControls({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        MakerFormErrorList(),
        SizedBox(height: 24),
        DexInfoContainer(
          children: [
            MakerFormExchangeRate(),
            SizedBox(height: 8),
            MakerFormCompareToCex(),
            SizedBox(height: 8),
            MakerFormTotalFees(),
          ],
        ),
        SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(flex: 3, child: _ClearButton()),
            SizedBox(width: 12),
            Flexible(
              flex: 7,
              child: ConnectWalletWrapper(
                key: Key('connect-wallet-maker-form'),
                eventType: WalletsManagerEventType.dex,
                child: MakerFormTradeButton(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return UiLightButton(
      text: LocaleKeys.clear.tr(),
      onPressed: () {
        makerFormBloc.clear();
      },
      height: 48,
    );
  }
}

class _BuyItemHeader extends StatelessWidget {
  const _BuyItemHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DexFormGroupHeader(title: LocaleKeys.buy.tr());
  }
}
