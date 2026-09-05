import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/views/nfts/common/widgets/nft_connect_wallet.dart';
import 'package:web_dex/views/nfts/common/widgets/nft_no_chains_enabled.dart';
import 'package:web_dex/views/nfts/nft_list/nft_list.dart';
import 'package:web_dex/views/nfts/nft_main/nft_chain_activation_panel.dart';
import 'package:web_dex/views/nfts/nft_main/nft_main_controls.dart';
import 'package:web_dex/views/nfts/nft_main/nft_main_failure.dart';
import 'package:web_dex/views/nfts/nft_main/nft_main_loading.dart';
import 'package:web_dex/views/nfts/nft_tabs/nft_tabs.dart';

class NftMain extends StatelessWidget {
  const NftMain({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = context.select<AuthBloc, bool>(
        (bloc) => bloc.state.mode == AuthorizeMode.logIn);
    final bool isInitial =
        context.select<NftMainBloc, bool>((bloc) => !bloc.state.isInitialized);
    // Every chain this build supports earns a tab, activated or not - tapping
    // one is how the user enables it.
    final List<NftBlockchains> tabs =
        context.select<NftMainBloc, List<NftBlockchains>>(
            (bloc) => bloc.state.availableChains);
    final bool hasTabs = tabs.isNotEmpty;
    final NftChainStatus selectedStatus =
        context.select<NftMainBloc, NftChainStatus>(
            (bloc) => bloc.state.statusOf(bloc.state.selectedChain));
    final bool isSelectedActive = selectedStatus == NftChainStatus.active;

    // The chain list is only known after the first update completes, so it
    // cannot gate the loading screen: requiring it here made NftMainLoading
    // unreachable and painted the "enable NFT assets" placeholder for the
    // whole of the first fetch.
    if (isLoggedIn && isInitial) {
      return const NftMainLoading();
    }
    final ColorSchemeExtension colorScheme =
        Theme.of(context).extension<ColorSchemeExtension>()!;
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile)
          Container(
            padding: const EdgeInsets.only(top: 50, bottom: 15),
            alignment: Alignment.center,
            child: Text(
              LocaleKeys.yourCollectibles.tr(),
              textAlign: TextAlign.center,
              style: textTheme.bodyMBold.copyWith(color: colorScheme.secondary),
            ),
          ),
        if (hasTabs)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.surfContHighest,
                ),
              ),
            ),
            child: NftTabs(tabs: tabs),
          ),
        const SizedBox(height: 20),
        // The row stays whenever there are tabs - "Transactions" is chain
        // independent - but "Receive NFT" needs an enabled chain. See
        // [NftMainControls.canReceive].
        if (hasTabs) NftMainControls(canReceive: isSelectedActive),
        if (hasTabs) const SizedBox(height: 20),
        Flexible(
          child: Builder(builder: (context) {
            final mode = context
                .select<AuthBloc, AuthorizeMode>((bloc) => bloc.state.mode);
            if (mode != AuthorizeMode.logIn) {
              return isMobile
                  ? const Center(child: NftConnectWallet())
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      key: Key('msg-connect-wallet'),
                      children: [NftConnectWallet()],
                    );
            }

            // Read the error before the placeholder branch. A failed fetch
            // also leaves sortedChains empty, so checking the chain list first
            // reported a genuine failure as "enable NFT protocol assets" and
            // hid the only retry affordance reachable in that state.
            final BaseError? error = context
                .select<NftMainBloc, BaseError?>((bloc) => bloc.state.error);
            if (error != null) {
              return NftMainFailure(error: error);
            }

            // Only reachable now when the whole catalogue is missing or
            // geo-blocked, since an un-enabled chain still gets a tab.
            if (!hasTabs) {
              return isMobile
                  ? const Center(child: NftNoChainsEnabled())
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      key: Key('msg-no-chains-enabled'),
                      children: [NftNoChainsEnabled()],
                    );
            }

            final selectedChain = context.select<NftMainBloc, NftBlockchains>(
                (bloc) => bloc.state.selectedChain);
            final BaseError? chainError =
                context.select<NftMainBloc, BaseError?>(
                    (bloc) => bloc.state.chainErrors[bloc.state.selectedChain]);

            // Explain the chain before the gallery renders an empty grid, which
            // reads as "you own nothing here".
            if (!isSelectedActive) {
              return NftChainActivationPanel(
                chain: selectedChain,
                status: selectedStatus,
                error: chainError,
              );
            }

            // Scoped to this chain, so one flaky chain does not hide the tabs
            // that work - which a page-level error would.
            if (chainError != null) {
              return NftMainFailure(error: chainError);
            }

            return const NftList();
          }),
        ),
      ],
    );
  }
}
