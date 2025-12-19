import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/misc_events.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/gleec_dex_logo.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

class SettingsThemeSwitcher extends StatelessWidget {
  const SettingsThemeSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: LocaleKeys.changeTheme.tr(),
      child: Container(
        padding: const EdgeInsets.all(10.0),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 6.0),
                child: _SettingsModeSelector(mode: ThemeMode.light),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 6.0),
                child: _SettingsModeSelector(mode: ThemeMode.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsModeSelector extends StatelessWidget {
  const _SettingsModeSelector({required this.mode});
  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = _getColor(mode, context);
    final bool isSelected =
        mode == context.select((SettingsBloc bloc) => bloc.state.themeMode);
    const double size = 16.0;
    return InkWell(
      onTap: () {
        context.read<SettingsBloc>().add(ThemeModeChanged(mode: mode));
        context.read<AnalyticsBloc>().logEvent(
          ThemeSelectedEventData(themeName: _analyticsName),
        );
      },
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        key: Key('theme-settings-switcher-$_themeName'),
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.0),
          color: backgroundColor,
        ),
        child: Stack(
          children: [
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(child: GleecDexLogo(height: 20, themeMode: mode)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Container(
                    width: size,
                    height: size,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).primaryColor,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: backgroundColor,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : theme.custom.noColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 2),
                      child: Text(
                        _themeName,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                          color: _getTextColor(mode, context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _themeName {
    switch (mode) {
      case ThemeMode.dark:
        return LocaleKeys.dark.tr();
      case ThemeMode.light:
        return LocaleKeys.light.tr();
      case ThemeMode.system:
        return LocaleKeys.defaultText.tr();
    }
  }

  String get _analyticsName {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'auto';
    }
  }

  Color _getColor(ThemeMode mode, BuildContext context) {
    switch (mode) {
      case ThemeMode.dark:
        return const Color.fromRGBO(14, 16, 27, 1);
      case ThemeMode.light:
        return const Color.fromRGBO(255, 255, 255, 1);
      case ThemeMode.system:
        return const Color.fromRGBO(0, 0, 0, 0);
    }
  }

  Color _getTextColor(ThemeMode mode, BuildContext context) {
    switch (mode) {
      case ThemeMode.dark:
        return const Color.fromRGBO(255, 255, 255, 1);
      case ThemeMode.light:
        return const Color.fromRGBO(125, 144, 161, 1);
      case ThemeMode.system:
        return const Color.fromRGBO(0, 0, 0, 0);
    }
  }
}
