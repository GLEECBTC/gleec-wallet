import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/views/nfts/common/widgets/nft_failure.dart';

/// What the gallery shows in place of a list when the selected chain is not up.
///
/// Tabs now exist for chains the user has never enabled, so selecting one has
/// to explain itself rather than render an empty gallery that reads as
/// "you own nothing here".
class NftChainActivationPanel extends StatelessWidget {
  const NftChainActivationPanel({
    super.key,
    required this.chain,
    required this.status,
    this.error,
  });

  final NftBlockchains chain;
  final NftChainStatus status;
  final BaseError? error;

  @override
  Widget build(BuildContext context) {
    // coinAbbr() rather than a display name, matching every other user-facing
    // chain reference in this view tree (refreshList, tryReceiveNft, ...).
    final String ticker = chain.coinAbbr();

    switch (status) {
      case NftChainStatus.failed:
        return NftFailure(
          key: const Key('nft-chain-activation-failed'),
          title: LocaleKeys.nftEnableChainFailedTitle.tr(args: [ticker]),
          subtitle: LocaleKeys.nftEnableChainFailedBody.tr(args: [ticker]),
          message: error?.message ?? '',
          onTryAgain: () => _activate(context),
        );
      case NftChainStatus.activating:
        return _Centered(
          key: const Key('nft-chain-activating'),
          children: [
            const UiSpinner(width: 32, height: 32),
            const SizedBox(height: 24),
            _Title(LocaleKeys.nftEnablingChainTitle.tr(args: [ticker])),
            const SizedBox(height: 8),
            _Body(LocaleKeys.nftEnablingChainBody.tr(args: [ticker])),
          ],
        );
      case NftChainStatus.inactive:
      // `active` never reaches here; NftMain routes it to the gallery.
      case NftChainStatus.active:
        return _Centered(
          key: const Key('nft-chain-inactive'),
          children: [
            _Title(LocaleKeys.nftEnableChainTitle.tr(args: [ticker])),
            const SizedBox(height: 8),
            _Body(LocaleKeys.nftEnableChainBody.tr(args: [ticker])),
            const SizedBox(height: 24),
            UiPrimaryButton(
              key: const Key('nft-chain-activate-btn'),
              width: 260,
              height: 40,
              text: LocaleKeys.nftEnableChainAction.tr(args: [ticker]),
              onPressed: () => _activate(context),
            ),
          ],
        );
    }
  }

  void _activate(BuildContext context) =>
      context.read<NftMainBloc>().add(NftMainChainActivationRequested(chain));
}

class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;
    return Text(text, style: textTheme.heading1, textAlign: TextAlign.center);
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).extension<ColorSchemeExtension>()!;
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;
    return Text(
      text,
      style: textTheme.bodyM.copyWith(color: colorScheme.s70),
      textAlign: TextAlign.center,
    );
  }
}
