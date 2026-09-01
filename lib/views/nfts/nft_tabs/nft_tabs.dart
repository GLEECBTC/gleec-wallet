import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/shared/ui/fading_edge_scroll_view.dart';
import 'package:web_dex/views/nfts/nft_tabs/nft_tab.dart';

class NftTabs extends StatelessWidget {
  final List<NftBlockchains> tabs;
  const NftTabs({super.key, required this.tabs});

  @override
  Widget build(BuildContext context) {
    onTap(NftBlockchains chain) => _onTap(chain, context);
    return FadingEdgeScrollView.fromSingleChildScrollView(
        gradientFractionOnStart: 0.4,
        gradientFractionOnEnd: 0.4,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: tabs
                .map(
                  (NftBlockchains t) => NftTab(
                    chain: t,
                    key: Key('nft-tab-${t.name}'),
                    isFirst: tabs.first == t,
                    onTap: onTap,
                  ),
                )
                .toList(),
          ),
        ));
  }

  void _onTap(NftBlockchains chain, BuildContext context) {
    final bloc = context.read<NftMainBloc>();
    bloc.add(NftMainTabChanged(chain));
  }
}
