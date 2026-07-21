import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_response.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';

class SwapRecoverButton extends StatefulWidget {
  const SwapRecoverButton({super.key, required this.uuid});

  final String uuid;

  @override
  State<SwapRecoverButton> createState() => _SwapRecoverButtonState();
}

class _SwapRecoverButtonState extends State<SwapRecoverButton> {
  bool _isLoading = false;
  bool _isFailedRecover = false;
  bool _isUncertainRecover = false;
  String _message = '';
  RecoverFundsOfSwapResponse? _recoverResponse;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return StreamBuilder<Map<String, RecoverySubmissionStatus>>(
      initialData: const {},
      stream: tradingEntitiesBloc.outRecoveryStatuses,
      builder: (context, snapshot) {
        final status =
            snapshot.data?[widget.uuid] ??
            tradingEntitiesBloc.recoveryStatusFor(widget.uuid);
        final loading =
            _isLoading || status == RecoverySubmissionStatus.submitting;
        final locked =
            status != RecoverySubmissionStatus.idle ||
            !tradingEntitiesBloc.canRecoverSwap(widget.uuid);
        final message = _message.isNotEmpty
            ? _message
            : switch (status) {
                RecoverySubmissionStatus.accepted =>
                  'advancedRecoverySubmitted'.tr(),
                RecoverySubmissionStatus.uncertain =>
                  'advancedRecoveryUncertain'.tr(),
                RecoverySubmissionStatus.submitting =>
                  'advancedRecoverySubmitting'.tr(),
                RecoverySubmissionStatus.idle => '',
              };
        final uncertain =
            _isUncertainRecover || status == RecoverySubmissionStatus.uncertain;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(LocaleKeys.swapRecoverButtonTitle.tr()),
            const SizedBox(height: 10),
            if (loading)
              const Center(child: UiSpinner(width: 48, height: 48))
            else
              UiPrimaryButton(
                text: LocaleKeys.swapRecoverButtonText.tr(),
                onPressed: locked ? null : _recoverFunds,
              ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5.0),
                child: _buildMessage(message, uncertain: uncertain),
              ),
          ],
        );
      },
    );
  }

  Future<void> _recoverFunds() async {
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.recover.tr(),
      targetDescription: 'Swap\n${widget.uuid}',
      confirmButtonKey: const Key('dex-details-recover-confirm'),
    );
    if (!confirmed || !mounted || _isLoading) return;
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    if (tradingEntitiesBloc.recoveryStatusFor(widget.uuid) !=
            RecoverySubmissionStatus.idle ||
        !tradingEntitiesBloc.canRecoverSwap(widget.uuid)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isFailedRecover = false;
      _isUncertainRecover = false;
      _recoverResponse = null;
      _message = '';
    });
    RecoverFundsOfSwapResponse? response;
    try {
      response = await tradingEntitiesBloc.recoverFundsOfSwap(widget.uuid);
    } on Object {
      response = null;
    }
    await Future<dynamic>.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final status = tradingEntitiesBloc.recoveryStatusFor(widget.uuid);
    setState(() {
      if (status == RecoverySubmissionStatus.uncertain) {
        _message = 'advancedRecoveryUncertain'.tr();
        _isFailedRecover = false;
        _isUncertainRecover = true;
      } else if (status == RecoverySubmissionStatus.accepted ||
          response != null) {
        _message = LocaleKeys.swapRecoverButtonSuccessMessage.tr();
        _recoverResponse = response;
        _isFailedRecover = false;
        _isUncertainRecover = false;
      } else {
        _message = LocaleKeys.swapRecoverButtonErrorMessage.tr();
        _isFailedRecover = true;
        _isUncertainRecover = false;
      }
      _isLoading = false;
    });
  }

  Widget _buildMessage(String message, {required bool uncertain}) {
    final ThemeData themeData = Theme.of(context);
    final RecoverFundsOfSwapResponse? response = _recoverResponse;
    if (_isFailedRecover) {
      return SelectableText(
        message,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: themeData.colorScheme.error,
        ),
      );
    }
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final Coin? coin = coinsRepository.getCoin(response?.result.coin ?? '');
    final String? url = coin == null || response == null
        ? null
        : getTxExplorerUrl(coin, response.result.txHash);

    return Column(
      children: [
        SelectableText(
          message,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: uncertain
                ? GleecColorTokens.of(context).warning
                : GleecColorTokens.of(context).success,
          ),
        ),
        if (url != null && response != null)
          Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: InkWell(
              child: Text(
                '${LocaleKeys.transactionHash.tr()}: '
                '${response.result.txHash}',
              ),
              onTap: () {
                launchURLString(url);
              },
            ),
          ),
      ],
    );
  }
}
