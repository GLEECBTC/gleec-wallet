import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:web_dex/bloc/cex_market_data/cache_constants.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/generator.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/mock_transaction_history_repository.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss_cache.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';

class MockProfitLossRepository extends ProfitLossRepository {
  MockProfitLossRepository({
    required this.performanceMode,
    required super.transactionHistoryRepo,
    required super.profitLossCacheProvider,
    required super.profitLossCalculator,
    required super.sdk,
  });

  factory MockProfitLossRepository.withDefaults({
    required PerformanceMode performanceMode,
    required KomodoDefiSdk sdk,
    String cacheTableName = mockProfitLossCacheBoxName,
  }) {
    return MockProfitLossRepository(
      profitLossCacheProvider: HiveLazyBoxProvider<String, ProfitLossCache>(
        name: cacheTableName,
      ),
      performanceMode: performanceMode,
      transactionHistoryRepo: MockTransactionHistoryRepo(
        performanceMode: performanceMode,
        demoDataGenerator: DemoDataCache.withDefaults(sdk),
      ),
      profitLossCalculator: RealisedProfitLossCalculator(sdk),
      sdk: sdk,
    );
  }

  final PerformanceMode performanceMode;
}
