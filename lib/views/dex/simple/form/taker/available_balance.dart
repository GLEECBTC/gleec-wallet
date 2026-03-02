import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class AvailableBalance extends StatelessWidget {
  const AvailableBalance(this.availableBalance, this.state, [Key? key])
    : super(key: key);

  final Rational? availableBalance;
  final AvailableBalanceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurfaceVariant,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isMobile
              ? LocaleKeys.available.tr()
              : LocaleKeys.availableForSwaps.tr(),
          style: labelStyle,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 38),
            child: _Balance(availableBalance: availableBalance, state: state),
          ),
        ),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.availableBalance, required this.state});
  final Rational? availableBalance;
  final AvailableBalanceState state;

  @override
  Widget build(BuildContext context) {
    final Rational balance = availableBalance ?? Rational.zero;
    String value = formatAmt(balance.toDouble());
    switch (state) {
      case AvailableBalanceState.loading:
      case AvailableBalanceState.initial:
        if (availableBalance == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13),
            child: UiSpinner(height: 12, width: 12, strokeWidth: 1.5),
          );
        }
        break;
      case AvailableBalanceState.unavailable:
        value = formatAmt(0.0);
        break;
      case AvailableBalanceState.success:
      case AvailableBalanceState.failure:
        break;
    }

    return AutoScrollText(
      text: value,
      style:
          Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ) ??
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
      textAlign: TextAlign.end,
    );
  }
}
