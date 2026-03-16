import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:web_dex/bloc/cex_market_data/cache_constants.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/generator.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/mock_transaction_history_repository.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';
import 'package:web_dex/bloc/cex_market_data/models/graph_cache.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';

class MockPortfolioGrowthRepository extends PortfolioGrowthRepository {
  MockPortfolioGrowthRepository({
    required super.transactionHistoryRepo,
    required super.cacheProvider,
    required this.performanceMode,
    required super.coinsRepository,
    required super.sdk,
  });

  MockPortfolioGrowthRepository.withDefaults({
    required this.performanceMode,
    required super.coinsRepository,
    required super.sdk,
  }) : super(
         transactionHistoryRepo: MockTransactionHistoryRepo(
           performanceMode: performanceMode,
           demoDataGenerator: DemoDataCache.withDefaults(sdk),
         ),
         cacheProvider: HiveLazyBoxProvider<String, GraphCache>(
           name: mockBalanceGrowthCacheBoxName,
         ),
       );

  final PerformanceMode performanceMode;
}
