import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

class SettingsHideBalances extends StatelessWidget {
  const SettingsHideBalances({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: LocaleKeys.hideBalancesTitle.tr(),
      child: const _HideBalancesSwitcher(),
    );
  }
}

class _HideBalancesSwitcher extends StatelessWidget {
  const _HideBalancesSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) => Row(
        children: [
          UiSwitcher(
            key: const Key('hide-balances-switcher'),
            value: state.hideBalances,
            onChanged: (value) => _onSwitcherChanged(context, value),
          ),
          const SizedBox(width: 15),
          Expanded(child: Text(LocaleKeys.hideBalancesSubtitle.tr())),
        ],
      ),
    );
  }

  void _onSwitcherChanged(BuildContext context, bool value) {
    context.read<SettingsBloc>().add(HideBalancesChanged(hideBalances: value));
  }
}
