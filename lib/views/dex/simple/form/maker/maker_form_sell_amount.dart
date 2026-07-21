import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/dex/common/trading_amount_field.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class MakerFormSellAmount extends StatelessWidget {
  const MakerFormSellAmount(this.isEnabled, {Key? key}) : super(key: key);

  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 18, top: 1),
            child: _SellAmountInput(
              key: const Key('maker-sell-amount'),
              isEnabled: isEnabled,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 18),
            child: _SellAmountFiat(),
          ),
        ],
      ),
    );
  }
}

class _SellAmountFiat extends StatelessWidget {
  const _SellAmountFiat();

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    final TextStyle? textStyle = Theme.of(context).textTheme.bodySmall;
    return StreamBuilder<Rational?>(
      initialData: makerFormBloc.sellAmount,
      stream: makerFormBloc.outSellAmount,
      builder: (context, snapshot) {
        final amount = snapshot.data ?? Rational.zero;

        return StreamBuilder<Coin?>(
          initialData: makerFormBloc.sellCoin,
          stream: makerFormBloc.outSellCoin,
          builder: (context, snapshot) {
            final Coin? coin = snapshot.data;
            if (coin == null) return const SizedBox();

            return Text(
              getFormattedFiatAmount(context, coin.abbr, amount),
              style: textStyle,
            );
          },
        );
      },
    );
  }
}

class _SellAmountInput extends StatelessWidget {
  _SellAmountInput({Key? key, required this.isEnabled}) : super(key: key);

  final bool isEnabled;

  final _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return StreamBuilder<Rational?>(
      initialData: makerFormBloc.sellAmount,
      stream: makerFormBloc.outSellAmount,
      builder: (context, snapshot) {
        formatAmountInput(_textController, makerFormBloc.sellAmount);

        return TradingAmountField(
          inputKey: const Key('maker-sell-amount-input'),
          controller: _textController,
          enabled: isEnabled,
          onChanged: makerFormBloc.setSellAmount,
        );
      },
    );
  }
}
