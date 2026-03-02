import 'dart:math' as math;

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

class NftMainControls extends StatefulWidget {
  const NftMainControls({super.key});

  @override
  State<NftMainControls> createState() => _NftMainControlsState();
}

class _NftMainControlsState extends State<NftMainControls> {
  PopupDispatcher? _popupDispatcher;

  @override
  void dispose() {
    _popupDispatcher?.close();
    _popupDispatcher = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorSchemeExtension colorScheme = Theme.of(
      context,
    ).extension<ColorSchemeExtension>()!;
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        UiPrimaryButton(
          text: LocaleKeys.receiveNft.tr(),
          key: const Key('nft-receive-btn'),
          width: 140,
          height: 40,
          backgroundColor: colorScheme.surfContHighest,
          prefix: Transform.rotate(
            angle: math.pi / 4,
            child: Icon(Icons.arrow_forward, color: colorScheme.primary),
          ),
          onPressed: _onReceiveNft,
          textStyle: textTheme.bodySBold.copyWith(color: colorScheme.primary),
        ),
        const Spacer(),
        UiPrimaryButton(
          text: LocaleKeys.transactions.tr(),
          key: const Key('nft-transactions-btn'),
          onPressed: _onTransactionsNFT,
          width: 140,
          height: 40,
          backgroundColor: Colors.transparent,
          textStyle: textTheme.bodySBold.copyWith(color: colorScheme.primary),
        ),
      ],
    );
  }

  void _onReceiveNft() {
    final isSignedIn = context.read<AuthBloc>().state.isSignedIn;
    if (isSignedIn) {
      routingState.nftsState.setReceiveAction();
    } else {
      _popupDispatcher = _createPopupDispatcher();
      _popupDispatcher?.show();
    }
  }

  void _onTransactionsNFT() {
    routingState.nftsState.setTransactionsAction();
  }

  PopupDispatcher _createPopupDispatcher() {
    final NftMainBloc nftBloc = context.read<NftMainBloc>();

    return PopupDispatcher(
      borderColor: theme.custom.specificButtonBorderColor,
      barrierColor: isMobile ? Theme.of(context).colorScheme.onSurface : null,
      barrierDismissible: false,
      width: 320,
      context: scaffoldKey.currentContext ?? context,
      popupContent: WalletsManagerWrapper(
        eventType: WalletsManagerEventType.header,
        onSuccess: (_) async {
          nftBloc.add(const NftMainChainUpdateRequested());
          _popupDispatcher?.close();
        },
      ),
    );
  }
}
