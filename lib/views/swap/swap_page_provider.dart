import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/swap_page.dart';

/// Builds the swap screen with its real dependencies.
///
/// Kept separate from [SwapPage] so the page itself stays testable against a
/// stubbed bloc, and so mounting the feature at a route is a one-liner rather
/// than a spread of wiring.
class SwapPageProvider extends StatelessWidget {
  const SwapPageProvider({super.key});

  @override
  Widget build(BuildContext context) {
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final coinsRepo = RepositoryProvider.of<CoinsRepo>(context);

    return BlocProvider(
      create: (_) => UnifiedSwapBloc(
        repository: UnifiedSwapRepository(
          sources: [
            RoutedSwapQuoteSource(sdk.routedSwaps),
            AtomicSwapQuoteSource(
              trading: sdk.trading,
              activatedAssets: () async =>
                  (await coinsRepo.getActivatedAssetIds()).toSet(),
            ),
          ],
        ),
        executors: [
          RoutedSwapExecutor(sdk.routedSwaps),
          AtomicSwapExecutor(
            dexRepository: RepositoryProvider.of<DexRepository>(context),
            trading: sdk.trading,
          ),
        ],
        spendableBalance: (asset) => _spendable(coinsRepo, asset),
      )..add(const UnifiedSwapStarted()),
      child: const SwapPage(),
    );
  }

  /// What the user can actually put into a swap.
  ///
  /// Returns null rather than zero when the balance cannot be read: zero would
  /// make the form reject every amount as exceeding the balance, which reads
  /// as "you have no funds" when the truth is "we could not check".
  static Future<Decimal?> _spendable(CoinsRepo repo, AssetId asset) async {
    try {
      final balance = await repo.balance(asset);
      if (balance == null) return null;
      return Decimal.tryParse(balance.spendable.toString());
    } on Object {
      return null;
    }
  }
}
