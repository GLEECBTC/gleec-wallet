import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/model/dex_list_type.dart';

class DexTabBar extends StatelessWidget {
  const DexTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    const values = DexListType.values;
    return BlocBuilder<DexTabBarBloc, DexTabBarState>(
      builder: (context, state) {
        final DexTabBarBloc bloc = context.read<DexTabBarBloc>();
        final colors = GleecColorTokens.of(context);
        final geometry = GleecGeometry.of(context);
        return Container(
          constraints: BoxConstraints(
            maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
          ),
          padding: EdgeInsets.all(geometry.space4),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            border: Border.all(color: colors.border),
            borderRadius: geometry.borderRadius16,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / values.length;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(values.length, (index) {
                    final tab = values[index];
                    return SizedBox(
                      width: tabWidth < 112 ? 112 : tabWidth,
                      child: _DexTab(
                        key: Key(tab.key),
                        text: tab.name(state),
                        isSelected: state.tabIndex == index,
                        onPressed: () => bloc.add(TabChanged(index)),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DexTab extends StatelessWidget {
  const _DexTab({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onPressed,
  });

  final String text;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? colors.selected : Colors.transparent,
        borderRadius: geometry.borderRadius12,
        child: InkWell(
          onTap: onPressed,
          borderRadius: geometry.borderRadius12,
          child: Container(
            constraints: BoxConstraints(minHeight: geometry.minimumTapTarget),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: geometry.space12,
              vertical: geometry.space8,
            ),
            child: Text(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: typography.labelLarge.copyWith(
                color: isSelected ? colors.brand : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
