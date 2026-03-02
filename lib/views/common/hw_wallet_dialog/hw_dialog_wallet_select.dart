import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/platform/platform_bloc.dart';
import 'package:web_dex/bloc/platform/platform_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/hw_wallet/hw_wallet.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/constants.dart';

class HwDialogWalletSelect extends StatefulWidget {
  const HwDialogWalletSelect({Key? key, required this.onSelect})
    : super(key: key);

  final void Function(WalletBrand) onSelect;

  @override
  State<HwDialogWalletSelect> createState() => _HwDialogWalletSelectState();
}

class _HwDialogWalletSelectState extends State<HwDialogWalletSelect> {
  WalletBrand? _selectedBrand;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlatformBloc, PlatformState>(
      builder: (context, platformState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              LocaleKeys.trezorSelectTitle.tr(),
              style: trezorDialogTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              LocaleKeys.trezorSelectSubTitle.tr(),
              style: trezorDialogSubtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              LocaleKeys.trezorWalletOnlyNotice.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _HwWalletTile(
              disabled: !platformState.isTrezorSupported,
              selected: _selectedBrand == WalletBrand.trezor,
              onSelect: () {
                setState(() => _selectedBrand = WalletBrand.trezor);
              },
              child: Center(
                child: SvgPicture.asset(
                  theme.mode == ThemeMode.light
                      ? '$assetsPath/others/trezor_logo_light.svg'
                      : '$assetsPath/others/trezor_logo.svg',
                ),
              ),
            ),
            if (!platformState.isTrezorSupported)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4.0),
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  LocaleKeys.trezorBrowserUnsupported.tr(),
                  style: theme.currentGlobal.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
            _HwWalletTile(
              disabled: true,
              selected: _selectedBrand == WalletBrand.ledger,
              onSelect: () {
                setState(() => _selectedBrand = WalletBrand.ledger);
              },
              child: Stack(
                children: [
                  Center(
                    child: SvgPicture.asset(
                      theme.mode == ThemeMode.light
                          ? '$assetsPath/others/ledger_logo_light.svg'
                          : '$assetsPath/others/ledger_logo.svg',
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          LocaleKeys.comingSoon.tr().toLowerCase(),
                          style: theme.currentGlobal.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            BlocSelector<AuthBloc, AuthBlocState, bool>(
              selector: (state) => state.isLoading,
              builder: (context, inProgress) {
                return UiPrimaryButton(
                  text: LocaleKeys.continueText.tr(),
                  prefix: inProgress ? const UiSpinner() : null,
                  onPressed: _selectedBrand == null || inProgress
                      ? null
                      : () {
                          widget.onSelect(_selectedBrand!);
                        },
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _HwWalletTile extends StatelessWidget {
  const _HwWalletTile({
    Key? key,
    required this.child,
    required this.onSelect,
    required this.selected,
    this.disabled = false,
  }) : super(key: key);

  final Widget child;
  final bool disabled;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        border: Border.all(
          width: 2,
          color: selected
              ? theme.currentGlobal.colorScheme.secondary
              : theme.custom.noColor,
        ),
        borderRadius: BorderRadius.circular(20),
        color: theme.currentGlobal.colorScheme.onSurface,
      ),
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: disabled ? null : () => onSelect(),
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
      ),
    );
  }
}
