import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';

class CoinsManagerSelectAllButton extends StatelessWidget {
  const CoinsManagerSelectAllButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<CoinsManagerBloc>();
    final bool isSelectedAllEnabled = bloc.state.isSelectedAllCoinsEnabled;
    final ThemeData theme = Theme.of(context);
    return Checkbox(
      value: isSelectedAllEnabled,
      splashRadius: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: isSelectedAllEnabled
          ? null
          : WidgetStateBorderSide.resolveWith(
              (states) =>
                  BorderSide(width: 2.0, color: theme.colorScheme.primary),
            ),
      checkColor: isSelectedAllEnabled ? null : theme.colorScheme.primary,
      fillColor: isSelectedAllEnabled
          ? null
          : WidgetStateProperty.all<Color>(theme.colorScheme.surface),
      onChanged: (_) => bloc.add(const CoinsManagerSelectAllTap()),
    );
  }
}
