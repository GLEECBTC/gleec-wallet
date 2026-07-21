import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/trading_kind/trading_kind_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/dex/common/dex_text_button.dart';

class SectionSwitcher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final geometry = GleecGeometry.of(context);
    return Container(
      constraints: BoxConstraints(
        maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
      ),
      padding: EdgeInsets.only(bottom: geometry.space4),
      child: Row(
        children: [
          Expanded(child: _TakerBtn()),
          SizedBox(width: geometry.space8),
          Expanded(child: _MakerBtn()),
        ],
      ),
    );
  }
}

class _TakerBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TradingKindBloc bloc = context.read<TradingKindBloc>();
    final isActive = bloc.state.isTaker;
    final onTap = isActive ? null : () => bloc.setKind(TradingKind.taker);
    return DexTextButton(
      text: LocaleKeys.takerOrder.tr(),
      isActive: isActive,
      onTap: onTap,
      key: const Key('take-order-tab'),
    );
  }
}

class _MakerBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TradingKindBloc bloc = context.read<TradingKindBloc>();
    final isActive = bloc.state.isMaker;
    final onTap = isActive ? null : () => bloc.setKind(TradingKind.maker);
    return DexTextButton(
      text: LocaleKeys.makerOrder.tr(),
      isActive: isActive,
      onTap: onTap,
      key: const Key('make-order-tab'),
    );
  }
}
