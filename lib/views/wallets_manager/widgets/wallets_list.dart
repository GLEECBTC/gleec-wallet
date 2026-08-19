import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_list_item.dart';

/// Renders the stored wallets. Purely presentational.
///
/// The wallets stream used to live here, which meant nothing knew whether any
/// wallets existed until this widget had already mounted and returned an empty
/// box. The entry screen owns the stream now, because it has to pick a layout
/// from that answer.
class WalletsList extends StatefulWidget {
  const WalletsList({
    super.key,
    required this.walletType,
    required this.wallets,
    required this.onWalletClick,
  });

  final WalletType walletType;
  final List<Wallet> wallets;
  final void Function(Wallet, WalletsManagerExistWalletAction) onWalletClick;

  @override
  State<WalletsList> createState() => _WalletsListState();
}

class _WalletsListState extends State<WalletsList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preserved verbatim from the stateful version, including the rule that
    // `iguana` also matches `hdwallet` - dropping that alias silently hides
    // every HD wallet from the list.
    final filteredWallets = widget.wallets
        .where(
          (w) =>
              w.config.type == widget.walletType ||
              (widget.walletType == WalletType.iguana &&
                  w.config.type == WalletType.hdwallet),
        )
        .toList();

    if (filteredWallets.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
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
  }
}
