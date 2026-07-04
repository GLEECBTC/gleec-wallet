import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/app_button.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';

class SendConfirmButtons extends StatelessWidget {
  const SendConfirmButtons({
    super.key,
    required this.hasSendError,
    required this.onBackTap,
  });
  final bool hasSendError;
  final VoidCallback onBackTap;
  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return _MobileButtons(hasError: hasSendError, onBackTap: onBackTap);
    }
    return _DesktopButtons(hasError: hasSendError, onBackTap: onBackTap);
  }
}

class _MobileButtons extends StatelessWidget {
  const _MobileButtons({required this.hasError, required this.onBackTap});
  final bool hasError;
  final VoidCallback onBackTap;
  @override
  Widget build(BuildContext context) {
    const height = 52.0;

    return Row(
      children: [
        Expanded(
          child: AppDefaultButton(
            key: const Key('confirm-back-button'),
            height: height + 6,
            padding: const EdgeInsets.symmetric(vertical: 0),
            onPressed: onBackTap,
            text: LocaleKeys.back.tr(),
          ),
        ),
        if (!hasError)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: UiPrimaryButton(
                key: const Key('confirm-agree-button'),
                height: height,
                onPressed: () => context.read<WithdrawFormBloc>().add(
                  const WithdrawFormSubmitted(),
                ),
                text: LocaleKeys.confirm.tr(),
              ),
            ),
          ),
      ],
    );
  }
}

class _DesktopButtons extends StatelessWidget {
  const _DesktopButtons({required this.hasError, required this.onBackTap});
  final bool hasError;
  final VoidCallback onBackTap;
  @override
  Widget build(BuildContext context) {
    const double height = 40.0;
    const double space = 16.0;

    final width = hasError ? withdrawWidth : (withdrawWidth - space) / 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppDefaultButton(
          key: const Key('confirm-back-button'),
          width: width,
          height: height + 6,
          padding: const EdgeInsets.symmetric(vertical: 0),
          onPressed: onBackTap,
          text: LocaleKeys.back.tr(),
        ),
        if (!hasError)
          Padding(
            padding: const EdgeInsets.only(left: space),
            child: UiPrimaryButton(
              key: const Key('confirm-agree-button'),
              width: width,
              height: height,
              onPressed: () => context.read<WithdrawFormBloc>().add(
                const WithdrawFormSubmitted(),
              ),
              text: LocaleKeys.confirm.tr(),
            ),
          ),
      ],
    );
  }
}
