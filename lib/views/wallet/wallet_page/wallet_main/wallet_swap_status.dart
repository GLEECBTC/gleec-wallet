import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_presentation.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_display.dart';

/// A view of the existing execution registry, with no independent polling.
class WalletSwapStatus extends StatelessWidget {
  const WalletSwapStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.read<SwapServices?>();
    if (services == null) return const SizedBox.shrink();
    final session = services.presentation;
    return StreamBuilder<List<SwapExecutionSnapshot>>(
      stream: services.registry.executions,
      builder: (context, _) => StreamBuilder<int>(
        stream: session.changes,
        builder: (context, _) {
          final entries = session.walletEntries;
          if (entries.isEmpty) return const SizedBox.shrink();
          final snapshot = entries.first;
          final display = SwapExecutionDisplay(snapshot, services.networks());
          final palette = SwapPalette.of(context);
          final multiple = entries.length > 1;
          final balanceUpdating =
              snapshot.isSuccess &&
              session.balanceStatus(snapshot.id) ==
                  SwapReceiptBalanceStatus.updating;
          final title = multiple
              ? 'swapWalletCount'.tr(args: ['${entries.length}'])
              : display.statusLine;
          final detail = multiple
              ? 'swapWalletOpenActivity'.tr()
              : '${display.pairLine}${balanceUpdating ? ' · ${'swapUpdatingBalance'.tr()}' : ''}';
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: palette.controlBorder),
              ),
              child: InkWell(
                key: const Key('wallet-swap-status'),
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (multiple) {
                    services.requestActivity();
                  } else {
                    services.requestOpen((
                      id: snapshot.id,
                      source: snapshot.source,
                    ));
                  }
                  routingState.selectedMenu = MainMenuValue.dex;
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SwapTokenIcon(
                        asset: snapshot.isSuccess
                            ? display.presentation.receivedAsset
                            : snapshot.from,
                        ticker: snapshot.isSuccess
                            ? display.receivedTicker
                            : display.fromTicker,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: SwapText.strong(context)),
                            const SizedBox(height: 3),
                            Text(detail, style: SwapText.small(context)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
