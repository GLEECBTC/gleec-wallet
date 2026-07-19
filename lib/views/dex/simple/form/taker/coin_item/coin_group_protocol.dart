import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';

class CoinGroupProtocol extends StatelessWidget {
  const CoinGroupProtocol([this.coin]);

  final Coin? coin;

  @override
  Widget build(BuildContext context) {
    if (coin == null) return const SizedBox();
    return Row(
      children: [
        _CoinProtocol(coin!),
        if (coin?.mode == CoinMode.segwit)
          const Padding(
            padding: EdgeInsets.only(left: 4.0),
            child: SegwitIcon(height: 18),
          ),
      ],
    );
  }
}

class _CoinProtocol extends StatelessWidget {
  const _CoinProtocol(this.coin);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Text(
      coin.typeNameWithTestnet.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).calmCoreCompatibility.dexCoinProtocolColor,
      ),
    );
  }
}
