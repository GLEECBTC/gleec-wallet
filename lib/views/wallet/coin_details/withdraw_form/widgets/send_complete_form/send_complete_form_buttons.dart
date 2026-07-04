import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/app_button.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';

class SendCompleteFormButtons extends StatelessWidget {
  const SendCompleteFormButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isMobile) return const _MobileButtons();
    return const _DesktopButtons();
  }
}

class _MobileButtons extends StatelessWidget {
  const _MobileButtons();

  @override
  Widget build(BuildContext context) {
    const height = 52.0;
    final WithdrawFormBloc withdrawFormBloc = context.read<WithdrawFormBloc>();
    final WithdrawFormState state = withdrawFormBloc.state;

    final txHash = state.result?.txHash;

    final explorerUrl = txHash == null
        ? null
        : state.asset.protocol.explorerTxUrl(txHash);

    return Row(
      children: [
        if (explorerUrl != null)
          Expanded(
            child: AppDefaultButton(
              key: const Key('send-complete-view-on-explorer'),
              height: height + 6,
              padding: const EdgeInsets.symmetric(vertical: 0),
              onPressed: () => launchUrl(explorerUrl),
              text: LocaleKeys.viewOnExplorer.tr(),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: UiPrimaryButton(
              key: const Key('send-complete-done'),
              height: height,
              onPressed: () => withdrawFormBloc.add(const WithdrawFormReset()),
              text: LocaleKeys.done.tr(),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopButtons extends StatelessWidget {
  const _DesktopButtons();

  @override
  Widget build(BuildContext context) {
    const height = 40.0;
    const space = 16.0;
    final WithdrawFormBloc withdrawFormBloc = context.read<WithdrawFormBloc>();
    final WithdrawFormState state = withdrawFormBloc.state;
    const width = (withdrawWidth - space) / 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (state.result?.txHash != null)
          AppDefaultButton(
            key: const Key('send-complete-view-on-explorer'),
            width: width,
            height: height + 6,
            padding: const EdgeInsets.symmetric(vertical: 0),
            onPressed: () =>
                openUrl(state.asset.txExplorerUrl(state.result?.txHash)!),
            text: LocaleKeys.viewOnExplorer.tr(),
          ),
        Padding(
          padding: const EdgeInsets.only(left: space),
          child: UiPrimaryButton(
            key: const Key('send-complete-done'),
            width: width,
            height: height,
            onPressed: () => _sendCompleteDone(context),
            text: LocaleKeys.done.tr(),
          ),
        ),
      ],
    );
  }

  void _sendCompleteDone(BuildContext context) {
    context.read<WithdrawFormBloc>().add(const WithdrawFormReset());
    if (isBitrefillIntegrationEnabled) {
      context.read<BitrefillBloc>().add(const BitrefillPaymentCompleted());
    }
  }
}
