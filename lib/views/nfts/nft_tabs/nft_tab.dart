import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
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

    return BlocSelector<NftMainBloc, NftMainState, NftBlockchains>(
      selector: (state) {
        return state.selectedChain;
      },
      builder: (context, selectedChain) {
        final bool isSelected = selectedChain == chain;
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
                    color: isSelected ? chainColor : colorScheme.s40,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      '$assetsPath/blockchain_icons/svg/32px/${chain.toApiRequest().toLowerCase()}.svg',
                      width: 16,
                      height: 16,
                      key: Key('nft-tab-btn-icon-$chain'),
                      colorFilter: ColorFilter.mode(
                        isSelected ? colorScheme.surf : chainColor,
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
                        color: isSelected ? chainColor : colorScheme.s50,
                      ),
                    ),
                    _NftCount(chain: chain),
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

class _NftCount extends StatelessWidget {
  //ignore: unused_element_parameter
  const _NftCount({super.key, required this.chain});

  final NftBlockchains chain;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NftMainBloc, NftMainState, Map<NftBlockchains, int?>>(
      selector: (state) {
        return state.nftCount;
      },
      builder: (context, nftCount) {
        final int? count = nftCount[chain];
        final ColorSchemeExtension colorScheme = Theme.of(
          context,
        ).extension<ColorSchemeExtension>()!;
        final TextThemeExtension textTheme = Theme.of(
          context,
        ).extension<TextThemeExtension>()!;
        return Text(
          count != null ? LocaleKeys.nItems.tr(args: [count.toString()]) : '',
          style: textTheme.bodyXXSBold.copyWith(color: colorScheme.s40),
          key: Key('ntf-tab-count-$chain'),
        );
      },
    );
  }
}
