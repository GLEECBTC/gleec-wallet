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

class SwapRecoverButton extends StatefulWidget {
  const SwapRecoverButton({super.key, required this.uuid});

  final String uuid;

  @override
  State<SwapRecoverButton> createState() => _SwapRecoverButtonState();
}

class _SwapRecoverButtonState extends State<SwapRecoverButton> {
  bool _isLoading = false;
  bool _isFailedRecover = false;
  String _message = '';
  RecoverFundsOfSwapResponse? _recoverResponse;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    // The bloc owns recovery state so the lock survives this widget being
    // rebuilt, scrolled out of the list, or opened from a second entry point.
    return StreamBuilder<Map<String, RecoverySubmissionStatus>>(
      initialData: const {},
      stream: tradingEntitiesBloc.outRecoveryStatuses,
      builder: (context, snapshot) {
        final status = tradingEntitiesBloc.recoveryStatusFor(widget.uuid);
        final isSubmitting =
            _isLoading || status == RecoverySubmissionStatus.submitting;
        final isLocked =
            status != RecoverySubmissionStatus.idle ||
            !tradingEntitiesBloc.canRecoverSwap(widget.uuid);
        final message = _message.isNotEmpty
            ? _message
            : switch (status) {
                RecoverySubmissionStatus.accepted =>
                  LocaleKeys.swapRecoverButtonSuccessMessage.tr(),
                RecoverySubmissionStatus.uncertain =>
                  LocaleKeys.swapRecoverButtonUncertainMessage.tr(),
                RecoverySubmissionStatus.submitting =>
                  LocaleKeys.swapRecoverButtonSubmittingMessage.tr(),
                RecoverySubmissionStatus.idle => '',
              };

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(LocaleKeys.swapRecoverButtonTitle.tr()),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: isSubmitting
                  ? const Center(child: UiSpinner(width: 48, height: 48))
                  : UiPrimaryButton(
                      key: const Key('swap-recover-button'),
                      text: LocaleKeys.swapRecoverButtonText.tr(),
                      onPressed: isLocked ? null : _recoverFunds,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5.0),
              child: message.isNotEmpty
                  ? _buildMessage(
                      message,
                      isUncertain: status == RecoverySubmissionStatus.uncertain,
                    )
                  : const SizedBox(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recoverFunds() async {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    // Re-check rather than trusting the enabled state we were built with: the
    // swap may have stopped being recoverable since the last frame.
    if (_isLoading ||
        tradingEntitiesBloc.recoveryStatusFor(widget.uuid) !=
            RecoverySubmissionStatus.idle ||
        !tradingEntitiesBloc.canRecoverSwap(widget.uuid)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isFailedRecover = false;
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
        _message = LocaleKeys.swapRecoverButtonUncertainMessage.tr();
        _isFailedRecover = false;
      } else if (status == RecoverySubmissionStatus.accepted ||
          response != null) {
        _message = LocaleKeys.swapRecoverButtonSuccessMessage.tr();
        _recoverResponse = response;
        _isFailedRecover = false;
      } else {
        _message = LocaleKeys.swapRecoverButtonErrorMessage.tr();
        _isFailedRecover = true;
      }
      _isLoading = false;
    });
  }

  Widget _buildMessage(String message, {required bool isUncertain}) {
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
            color: isUncertain
                ? theme.custom.warningColor
                : theme.custom.successColor,
          ),
        ),
        if (url != null && response != null)
          Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: InkWell(
              child: Text(
                '${LocaleKeys.transactionHash.tr()}: ${response.result.txHash}',
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
