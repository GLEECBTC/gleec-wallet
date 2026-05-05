import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_list_item.dart';

class WalletsList extends StatefulWidget {
  const WalletsList({
    super.key,
    required this.walletType,
    required this.onWalletClick,
  });

  final WalletType walletType;
  final void Function(Wallet, WalletsManagerExistWalletAction) onWalletClick;

  @override
  State<WalletsList> createState() => _WalletsListState();
}

class _WalletsListState extends State<WalletsList> {
  late final Stream<List<Wallet>> _walletsStream;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final walletsRepository = context.read<WalletsRepository>();
    _walletsStream = walletsRepository.watchWallets();
    unawaited(
      walletsRepository.refreshWallets().catchError((Object error) {
        debugPrint('Failed to refresh wallets list: $error');
        return <Wallet>[];
      }),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      initialData: const <Wallet>[],
      stream: _walletsStream,
      builder: (BuildContext context, AsyncSnapshot<List<Wallet>> snapshot) {
        final List<Wallet> wallets = snapshot.data ?? [];
        final List<Wallet> filteredWallets = wallets
            .where(
              (w) =>
                  w.config.type == widget.walletType ||
                  (widget.walletType == WalletType.iguana &&
                      w.config.type == WalletType.hdwallet),
            )
            .toList();
        if (wallets.isEmpty) {
          return const SizedBox(width: 0, height: 0);
        }
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface,
            borderRadius: BorderRadius.circular(18.0),
          ),
          child: DexScrollbar(
            isMobile: isMobile,
            scrollController: _scrollController,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: filteredWallets.length,
              shrinkWrap: true,
              itemBuilder: (BuildContext context, int i) {
                return WalletListItem(
                  wallet: filteredWallets[i],
                  onClick: widget.onWalletClick,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
