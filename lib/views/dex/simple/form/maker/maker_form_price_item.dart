import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/dex/simple/form/amount_input_field.dart';

class MakerFormPriceItem extends StatefulWidget {
  const MakerFormPriceItem({Key? key}) : super(key: key);

  @override
  State<MakerFormPriceItem> createState() => _MakerFormPriceItemState();
}

class _MakerFormPriceItemState extends State<MakerFormPriceItem> {
  final List<StreamSubscription> _listeners = [];
  Coin? _sellCoin;
  Coin? _buyCoin;

  @override
  void initState() {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);

    _sellCoin = makerFormBloc.sellCoin;
    _buyCoin = makerFormBloc.buyCoin;

    _listeners.add(makerFormBloc.outSellCoin.listen(_onFormStateChange));
    _listeners.add(makerFormBloc.outBuyCoin.listen(_onFormStateChange));
    super.initState();
  }

  @override
  void dispose() {
    _listeners.map((listener) => listener.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(width: 1, color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          _buildLabel(),
          const SizedBox(width: 24),
          Expanded(child: _buildPriceField()),
        ],
      ),
    );
  }

  Widget _buildLabel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 6),
      child: Text(
        '${LocaleKeys.price.tr()}:',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildPriceField() {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return AmountInputField(
      hint: '',
      stream: makerFormBloc.outPrice,
      initialData: makerFormBloc.price,
      isEnabled: _sellCoin != null && _buyCoin != null,
      suffix: _buildSuffix(),
      onChanged: (String value) {
        makerFormBloc.setPriceValue(value);
      },
      height: 18,
      background: Theme.of(context).calmCoreCompatibility.noColor,
      textAlign: TextAlign.right,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.all(0),
    );
  }

  Widget _buildSuffix() {
    final Coin? buyCoin = _buyCoin;
    if (buyCoin == null) return const SizedBox.shrink();

    return Text(
      Coin.normalizeAbbr(buyCoin.abbr),
      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      textAlign: TextAlign.right,
    );
  }

  void _onFormStateChange(dynamic _) {
    if (!mounted) return;

    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    setState(() {
      _sellCoin = makerFormBloc.sellCoin;
      _buyCoin = makerFormBloc.buyCoin;
    });
  }
}
