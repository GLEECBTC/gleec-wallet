import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/nft_receive/bloc/nft_receive_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/nfts/nft_receive/common/nft_failure_page.dart';
import 'package:web_dex/views/nfts/nft_receive/common/nft_receive_card.dart';

class NftReceiveView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return Stack(
      children: [
        SizedBox(
          height: 50,
          width: double.maxFinite,
          child: PageHeader(
            title: '',
            backText: LocaleKeys.collectibles.tr(),
            onBackButtonPressed: routingState.nftsState.reset,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 50),
          child: DexScrollbar(
            scrollController: scrollController,
            child: SingleChildScrollView(
              controller: scrollController,
              child: BlocBuilder<NftReceiveBloc, NftReceiveState>(
                builder: (context, state) {
                  if (state is NftReceiveInitial) {
                    return const Center(child: UiSpinner());
                  } else if (state is NftReceiveLoadFailure) {
                    return NftReceiveFailurePage(
                      message:
                          state.message ??
                          LocaleKeys.pleaseTryActivateAssets.tr(),
                      onReload: () {
                        context.read<NftReceiveBloc>().add(
                          const NftReceiveRefreshRequested(),
                        );
                      },
                    );
                  } else if (state is NftReceiveLoadSuccess) {
                    return isMobile
                        ? SizedBox(
                            width: double.maxFinite,
                            child: NftReceiveCard(
                              onAddressChanged: (value) =>
                                  _onAddressChanged(value, context),
                              coin: state.asset,
                              pubkeys: state.pubkeys,
                              currentAddress: state.selectedAddress,
                              qrCodeSize: 260,
                              maxWidth: double.infinity,
                            ),
                          )
                        : Align(
                            alignment: Alignment.center,
                            child: NftReceiveCard(
                              currentAddress: state.selectedAddress,
                              pubkeys: state.pubkeys,
                              qrCodeSize: 200,
                              onAddressChanged: (value) =>
                                  _onAddressChanged(value, context),
                              coin: state.asset,
                            ),
                          );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onAddressChanged(PubkeyInfo? value, BuildContext context) {
    context.read<NftReceiveBloc>().add(
      NftReceiveAddressChanged(address: value),
    );
  }
}
