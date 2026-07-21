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
  const SwapRecoverButton({Key? key, required this.uuid}) : super(key: key);

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: SelectableText(LocaleKeys.swapRecoverButtonTitle.tr())),
        const SizedBox(height: 10),
        Flexible(
          child: _isLoading
              ? const Center(child: UiSpinner(width: 48, height: 48))
              : UiPrimaryButton(
                  text: LocaleKeys.swapRecoverButtonText.tr(),
                  onPressed: _isLoading ? null : _recoverFunds,
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5.0),
          child: _message.isNotEmpty ? _buildMessage() : const SizedBox(),
        ),
      ],
    );
  }

  Future<void> _recoverFunds() async {
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.recover.tr(),
      confirmButtonKey: const Key('dex-details-recover-confirm'),
    );
    if (!confirmed || !mounted || _isLoading) return;

    setState(() {
      _isLoading = true;
      _isFailedRecover = false;
      _recoverResponse = null;
      _message = '';
    });
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final response = await tradingEntitiesBloc.recoverFundsOfSwap(widget.uuid);
    await Future<dynamic>.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      if (response == null) {
        _message = LocaleKeys.swapRecoverButtonErrorMessage.tr();
        _isFailedRecover = true;
      } else {
        _message = LocaleKeys.swapRecoverButtonSuccessMessage.tr();
        _recoverResponse = response;
        _isFailedRecover = false;
      }
      _isLoading = false;
    });
  }

  Widget _buildMessage() {
    final ThemeData themeData = Theme.of(context);
    final RecoverFundsOfSwapResponse? response = _recoverResponse;
    if (_isFailedRecover) {
      return SelectableText(
        _message,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: themeData.colorScheme.error,
        ),
      );
    }
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final Coin? coin = coinsRepository.getCoin(response?.result.coin ?? '');
    if (coin == null || response == null) {
      return const SizedBox();
    }
    final String url = getTxExplorerUrl(coin, response.result.txHash);

    return Column(
      children: [
        SelectableText(
          _message,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: GleecColorTokens.of(context).success,
          ),
        ),
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
