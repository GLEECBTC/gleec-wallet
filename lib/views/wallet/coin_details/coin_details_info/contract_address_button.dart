import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/truncate_middle_text.dart';

class ContractAddressButton extends StatelessWidget {
  const ContractAddressButton(this.coin, {Key? key}) : super(key: key);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final contractAddress = coin.protocolData?.contractAddress ?? '';
    final url = getAddressExplorerUrl(coin, contractAddress);

    return Material(
      color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(5),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: url.isEmpty ? null : () => launchURLString(url),
        child: isMobile
            ? _ContractAddressMobile(coin)
            : _ContractAddressDesktop(coin),
      ),
    );
  }
}

class _ContractAddressMobile extends StatelessWidget {
  const _ContractAddressMobile(this.coin, {Key? key}) : super(key: key);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ContractAddressTitle(),
                const SizedBox(height: 4),
                _ContractAddressValue(coin),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 32,
            height: 32,
            child: _ContractAddressCopyButton(coin),
          ),
        ],
      ),
    );
  }
}

class _ContractAddressDesktop extends StatelessWidget {
  const _ContractAddressDesktop(this.coin, {Key? key}) : super(key: key);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 13.0, right: 6.0, top: 4),
          child: Stack(
            children: [
              const _ContractAddressTitle(),
              Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 24,
                  height: 16,
                  child: _ContractAddressCopyButton(coin),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 13.0, right: 13.0, bottom: 5),
          child: _ContractAddressValue(coin),
        ),
      ],
    );
  }
}

class _ContractAddressValue extends StatelessWidget {
  const _ContractAddressValue(this.coin, {Key? key}) : super(key: key);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        AssetIcon.ofTicker(coin.protocolData?.platform ?? '', size: 12),
        const SizedBox(width: 3),
        Text(
          '${coin.protocolData?.platform ?? ''} ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
        ),
        Flexible(
          child: TruncatedMiddleText(
            coin.protocolData?.contractAddress ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContractAddressCopyButton extends StatelessWidget {
  const _ContractAddressCopyButton(this.coin, {Key? key}) : super(key: key);

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        copyToClipBoard(context, coin.protocolData?.contractAddress ?? '');
      },
      child: Icon(
        Icons.copy,
        size: isMobile ? 14 : 10,
        color: theme.currentGlobal.textTheme.bodyLarge?.color,
      ),
    );
  }
}

class _ContractAddressTitle extends StatelessWidget {
  const _ContractAddressTitle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.contractAddress.tr(),
      style: Theme.of(context).textTheme.titleSmall!.copyWith(
        fontSize: 9,
        fontWeight: FontWeight.w500,
        color: Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: .45),
      ),
    );
  }
}
