import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/nft.dart';

class NftTab extends StatelessWidget {
  const NftTab({
    super.key,
    required this.chain,
    required this.isFirst,
    required this.onTap,
  });
  final NftBlockchains chain;
  final bool isFirst;
  final void Function(NftBlockchains) onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final ColorSchemeExtension colorScheme = themeData
        .extension<ColorSchemeExtension>()!;
    final TextThemeExtension textTheme = themeData
        .extension<TextThemeExtension>()!;

    // Records compare structurally, so widening the selector from a bare
    // NftBlockchains still dedupes rebuilds.
    return BlocSelector<
      NftMainBloc,
      NftMainState,
      (NftBlockchains, NftChainStatus)
    >(
      selector: (state) {
        return (state.selectedChain, state.statusOf(chain));
      },
      builder: (context, value) {
        final (selectedChain, status) = value;
        final bool isSelected = selectedChain == chain;
        final bool isActive = status == NftChainStatus.active;
        final chainColor = _getChainColor(chain);
        return InkWell(
          key: Key('nft-tab-bnt-$chain'),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            onTap(chain);
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeIn,
            );
          },
          child: Container(
            padding: EdgeInsets.only(left: isFirst ? 0 : 20, bottom: 8),
            decoration: isSelected
                ? BoxDecoration(
                    border: Border(bottom: BorderSide(color: chainColor)),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected && isActive
                        ? chainColor
                        : colorScheme.s40,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      '$assetsPath/blockchain_icons/svg/32px/${chain.toApiRequest().toLowerCase()}.svg',
                      width: 16,
                      height: 16,
                      key: Key('nft-tab-btn-icon-$chain'),
                      colorFilter: ColorFilter.mode(
                        isSelected && isActive
                            ? colorScheme.surf
                            : isActive
                            ? chainColor
                            : colorScheme.s50,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      key: Key('nft-tab-btn-text-$chain'),
                      style: textTheme.bodySBold.copyWith(
                        color: isSelected && isActive
                            ? chainColor
                            : colorScheme.s50,
                      ),
                    ),
                    _NftTabSubtitle(chain: chain, status: status),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String get _title {
    switch (chain) {
      case NftBlockchains.eth:
        return 'Ethereum';
      case NftBlockchains.bsc:
        return 'BNB Smart Chain';
      case NftBlockchains.avalanche:
        return 'Avalanche C-Chain';
      case NftBlockchains.polygon:
        return 'Polygon';
      case NftBlockchains.fantom:
        return 'Fantom';
    }
  }

  Color _getChainColor(NftBlockchains chain) {
    switch (chain) {
      case NftBlockchains.eth:
        return const Color(0xFF3D77E9);
      case NftBlockchains.bsc:
        return const Color(0xFFE6BC41);
      case NftBlockchains.avalanche:
        return const Color(0xFFD54F49);
      case NftBlockchains.polygon:
        return const Color(0xFF7B49DD);
      case NftBlockchains.fantom:
        return const Color(0xFF3267F6);
    }
  }
}

/// The line under the chain name.
///
/// Only an active chain that has answered shows a count. Every other state says
/// what it is rather than going blank, since a blank line reads as "you own
/// nothing here" about a chain nobody queried.
class _NftTabSubtitle extends StatelessWidget {
  const _NftTabSubtitle({required this.chain, required this.status});

  final NftBlockchains chain;
  final NftChainStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorSchemeExtension colorScheme = Theme.of(
      context,
    ).extension<ColorSchemeExtension>()!;
    final TextThemeExtension textTheme = Theme.of(
      context,
    ).extension<TextThemeExtension>()!;
    final TextStyle style = textTheme.bodyXXSBold.copyWith(
      color: colorScheme.s40,
    );

    switch (status) {
      case NftChainStatus.inactive:
        return Text(
          LocaleKeys.nftChainNotEnabled.tr(),
          style: style,
          key: Key('nft-tab-status-$chain'),
        );
      case NftChainStatus.activating:
        return Row(
          mainAxisSize: MainAxisSize.min,
          key: Key('nft-tab-activating-$chain'),
          children: [
            UiSpinner(
              width: 10,
              height: 10,
              strokeWidth: 1.5,
              color: colorScheme.s40,
            ),
            const SizedBox(width: 4),
            Text(LocaleKeys.nftChainEnabling.tr(), style: style),
          ],
        );
      case NftChainStatus.failed:
        return Text(
          LocaleKeys.nftChainEnableFailed.tr(),
          style: style.copyWith(color: colorScheme.error),
          key: Key('nft-tab-failed-$chain'),
        );
      case NftChainStatus.active:
        return BlocSelector<NftMainBloc, NftMainState, int?>(
          selector: (state) => state.nftCount[chain],
          builder: (context, count) => Text(
            count != null ? LocaleKeys.nItems.tr(args: [count.toString()]) : '',
            style: style,
            // Typo retained: existing tests and tooling target this key.
            key: Key('ntf-tab-count-$chain'),
          ),
        );
    }
  }
}
