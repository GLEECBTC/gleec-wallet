// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_test_fixtures.dart';

class EnglishAssetLoader extends AssetLoader {
  const EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Pumps [home] in an English app at [size], with the app-wide screen type
/// (which `isMobile` and friends read) matched to it.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 844),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(resetScreenType);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const EnglishAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: theme,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Builder(
            builder: (context) {
              updateScreenType(context);
              return home;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

KdfUser softwareUser() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'wallet-a',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'wallet-a-pubkey-hash',
  ),
  isBip39Seed: true,
  metadata: const {'has_backup': true},
);

KdfUser trezorUser() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'trezor',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'trezor-pubkey-hash',
  ),
  isBip39Seed: false,
  metadata: const {'type': 'trezor', 'has_backup': true},
);

class FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  FakeAuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  FakeSettingsBloc()
    : super(SettingsState.fromStored(StoredSettings.initial()));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTradingStatusBloc extends Cubit<TradingStatusState>
    implements TradingStatusBloc {
  FakeTradingStatusBloc([TradingStatusState? state])
    : super(state ?? TradingStatusLoadSuccess());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A registry following one swap that is waiting on the user.
///
/// Call [SwapExecutionRegistry.resumeInFlight] to pick the swap up.
SwapExecutionRegistry attentionRegistry({String id = 'swap-1'}) {
  final executor = FakeExecutor(SwapLiquiditySource.routed);
  executor.resumable[id] = FakeHandle(
    snapshotOf(id: id, stage: SwapProgressStage.actionRequired),
  );
  return SwapExecutionRegistry(
    executors: [executor],
    inFlight: () async => [(id: id, source: SwapLiquiditySource.routed)],
  );
}

/// The swap services the app provides, over a real registry.
class FakeSwapServices implements SwapServices {
  FakeSwapServices(this.registry);

  @override
  final SwapExecutionRegistry registry;

  @override
  final Set<String> viewing = {};

  final List<SwapIntent> requestedIntents = [];
  final List<SwapExecutionRef> requestedOpens = [];

  @override
  void requestIntent(SwapIntent intent) => requestedIntents.add(intent);

  @override
  void requestOpen(SwapExecutionRef ref) => requestedOpens.add(ref);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// KDF's legacy API: raw swap data and the recent-swaps page.
class FakeMm2Api implements Mm2Api {
  FakeMm2Api({this.rawSwapData = '{"result":{"swaps":[]}}'});

  String rawSwapData;
  Object? rawSwapError;
  final List<MyRecentSwapsRequest> rawRequests = [];
  final List<MyRecentSwapsRequest> recentRequests = [];

  @override
  Future<String> getRawSwapData(MyRecentSwapsRequest request) async {
    rawRequests.add(request);
    final error = rawSwapError;
    if (error != null) throw error;
    return rawSwapData;
  }

  @override
  Future<MyRecentSwapsResponse?> getMyRecentSwaps(
    MyRecentSwapsRequest request,
  ) async {
    recentRequests.add(request);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Routed-swap history served page by page.
class FakeRoutedSwaps implements RoutedSwapManager {
  FakeRoutedSwaps({this.pages = const [], this.error});

  List<RoutedSwapHistoryPage> pages;
  Object? error;
  final List<({int page, int limit})> historyCalls = [];
  int inFlightCalls = 0;

  @override
  Future<RoutedSwapHistoryPage> history({
    int pageNumber = 1,
    int limit = 20,
    rpc.RoutedSwapHistoryFilter? filter,
    AssetId? from,
    AssetId? to,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    historyCalls.add((page: pageNumber, limit: limit));
    final failure = error;
    if (failure != null) throw failure;
    return pages[pageNumber - 1];
  }

  @override
  Future<List<RoutedSwapProgress>> inFlight({int pageSize = 50}) async {
    inFlightCalls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sign-in state the test drives through [users].
class FakeAuth implements KomodoDefiLocalAuth {
  late final StreamController<KdfUser?> users =
      StreamController<KdfUser?>.broadcast();

  @override
  Stream<KdfUser?> watchCurrentUser() => users.stream;

  @override
  Future<KdfUser?> get currentUser async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMarketData implements MarketDataManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdk implements KomodoDefiSdk {
  FakeSdk({FakeRoutedSwaps? routedSwaps, FakeAuth? auth})
    : routedSwaps = routedSwaps ?? FakeRoutedSwaps(),
      auth = auth ?? FakeAuth();

  @override
  final FakeRoutedSwaps routedSwaps;

  @override
  final FakeAuth auth;

  @override
  final MarketDataManager marketData = FakeMarketData();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCoinsRepo implements CoinsRepo {
  FakeCoinsRepo([Set<AssetId>? activated]) : activated = activated ?? {};

  final Set<AssetId> activated;

  @override
  Future<Set<AssetId>> getActivatedAssetIds({
    bool forceRefresh = false,
  }) async => activated;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
