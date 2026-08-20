import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/cancel_order/cancel_order_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_response.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';

const String _uuidA = '11111111-2222-3333-4444-555555555555';
const String _uuidB = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const String _walletA = 'wallet-a';
const String _walletB = 'wallet-b';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

KdfUser _user(String name) => KdfUser(
  walletId: WalletId(
    name: name,
    authOptions: const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

MyOrder _order(String uuid, {bool cancelable = true}) => MyOrder(
  base: 'KMD',
  orderType: TradeSide.maker,
  rel: 'BTC',
  relAmount: Rational.one,
  uuid: uuid,
  baseAmount: Rational.one,
  createdAt: 1,
  cancelable: cancelable,
);

Swap _swap(String uuid, {bool recoverable = true}) => Swap(
  type: TradeSide.taker,
  uuid: uuid,
  myOrderUuid: uuid,
  events: const [],
  makerAmount: Rational.one,
  makerCoin: 'KMD',
  takerAmount: Rational.one,
  takerCoin: 'BTC',
  gui: 'test',
  mmVersion: '1',
  successEvents: const [],
  errorEvents: const [],
  recoverable: recoverable,
);

/// Bounded stream wait. A bare `firstWhere` on a bloc stream never completes
/// when the predicate is not met, which wedges the whole test runner instead
/// of failing this one test.
Future<T> firstWhereBounded<T>(
  Stream<T> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 5),
  String? description,
}) {
  return stream.firstWhere(test).timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      'No matching event within $timeout${description == null ? '' : ': $description'}',
    ),
  );
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this._activatedWallet);

  String? Function() _activatedWallet;
  set activatedWallet(String? Function() value) => _activatedWallet = value;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    return <String, dynamic>{
      'mmrpc': '2.0',
      'result': <String, dynamic>{
        'wallet_names': <String>[_walletA, _walletB],
        'activated_wallet': _activatedWallet(),
      },
    };
  }
}

class _FakeAuth implements KomodoDefiLocalAuth {
  _FakeAuth(this._userController);

  final StreamController<KdfUser?> _userController;
  KdfUser? user;

  @override
  Future<KdfUser?> get currentUser async => user;

  @override
  Stream<KdfUser?> watchCurrentUser() => _userController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.auth, required this.client});

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final ApiClient client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMm2Api implements Mm2Api {
  final List<String> cancelCalls = [];
  final List<String> recoverCalls = [];
  List<Swap> swaps = const [];

  /// Returned by `recoverFundsOfSwap`; `null` models an unobservable outcome.
  RecoverFundsOfSwapResponse? recoverResponse;

  /// Runs after `beforeMutation` succeeds, to model state changing mid-RPC.
  void Function()? onCancelAccepted;
  void Function()? onRecoverAccepted;

  @override
  Future<Map<String, dynamic>> cancelOrder(
    CancelOrderRequest request, {
    Future<void> Function()? beforeMutation,
  }) async {
    await beforeMutation?.call();
    cancelCalls.add(request.uuid);
    onCancelAccepted?.call();
    return <String, dynamic>{'result': 'success'};
  }

  @override
  Future<RecoverFundsOfSwapResponse?> recoverFundsOfSwap(
    RecoverFundsOfSwapRequest request, {
    Future<void> Function()? beforeMutation,
  }) async {
    await beforeMutation?.call();
    recoverCalls.add(request.uuid);
    onRecoverAccepted?.call();
    return recoverResponse;
  }

  @override
  Future<MyRecentSwapsResponse?> getMyRecentSwaps(
    MyRecentSwapsRequest request,
  ) async {
    return MyRecentSwapsResponse(
      result: MyRecentSwapsResponseResult(
        fromUuid: null,
        skipped: 0,
        limit: request.limit ?? 0,
        total: swaps.length,
        pageNumber: 1,
        totalPages: 1,
        foundRecords: swaps.length,
        swaps: List<Swap>.of(swaps),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrdersService implements MyOrdersService {
  List<MyOrder> orders = const [];

  @override
  Future<List<MyOrder>?> getOrders() async => List<MyOrder>.of(orders);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Everything a test needs to drive one wallet-bound bloc.
class _Harness {
  _Harness._(
    this.bloc,
    this.auth,
    this.client,
    this.mm2Api,
    this.ordersService,
    this._userController,
  );

  final TradingEntitiesBloc bloc;
  final _FakeAuth auth;
  final _FakeApiClient client;
  final _FakeMm2Api mm2Api;
  final _FakeOrdersService ordersService;
  final StreamController<KdfUser?> _userController;

  static Future<_Harness> create({
    List<MyOrder> orders = const [],
    List<Swap> swaps = const [],
    String wallet = _walletA,
  }) async {
    final userController = StreamController<KdfUser?>.broadcast();
    final auth = _FakeAuth(userController)..user = _user(wallet);
    final client = _FakeApiClient(() => wallet);
    final mm2Api = _FakeMm2Api()..swaps = swaps;
    final ordersService = _FakeOrdersService()..orders = orders;
    final bloc = TradingEntitiesBloc(
      _FakeSdk(auth: auth, client: client),
      mm2Api,
      ordersService,
    );
    final harness = _Harness._(
      bloc,
      auth,
      client,
      mm2Api,
      ordersService,
      userController,
    );
    // Populate the wallet binding and the order/swap snapshots the guards
    // read, the same way the app's polling loop does.
    await bloc.fetch();
    return harness;
  }

  /// Models the live KDF wallet changing out from under an in-flight mutation.
  void switchWallet(String wallet) {
    auth.user = _user(wallet);
    client.activatedWallet = () => wallet;
  }

  Future<void> dispose() async {
    bloc.dispose();
    await _userController.close();
  }
}

// ---------------------------------------------------------------------------

void testTradingEntitiesGuards() {
  group('canCancelOrder', () {
    test('is false for unknown, malformed and non-cancelable orders', () async {
      final harness = await _Harness.create(
        orders: [_order(_uuidA), _order(_uuidB, cancelable: false)],
      );
      addTearDown(harness.dispose);

      expect(harness.bloc.canCancelOrder(_uuidA), isTrue);
      expect(
        harness.bloc.canCancelOrder(_uuidB),
        isFalse,
        reason: 'the order is not cancelable',
      );
      expect(
        harness.bloc.canCancelOrder('00000000-0000-0000-0000-000000000000'),
        isFalse,
        reason: 'no such order',
      );
      expect(
        harness.bloc.canCancelOrder('not-a-uuid'),
        isFalse,
        reason: 'malformed identity must never match a real order',
      );
    });

    test('accepts a differently-cased spelling of the same uuid', () async {
      final harness = await _Harness.create(orders: [_order(_uuidB)]);
      addTearDown(harness.dispose);

      expect(harness.bloc.canCancelOrder(_uuidB.toUpperCase()), isTrue);
    });
  });

  group('cancelOrder exactly-once', () {
    test('refuses a non-cancelable order without issuing the RPC', () async {
      final harness = await _Harness.create(
        orders: [_order(_uuidA, cancelable: false)],
      );
      addTearDown(harness.dispose);

      final error = await harness.bloc.cancelOrder(_uuidA);

      expect(error, isNotNull);
      expect(harness.mm2Api.cancelCalls, isEmpty);
    });

    test('concurrent submissions share one in-flight RPC', () async {
      final harness = await _Harness.create(orders: [_order(_uuidA)]);
      addTearDown(harness.dispose);

      final results = await Future.wait([
        harness.bloc.cancelOrder(_uuidA),
        harness.bloc.cancelOrder(_uuidA),
        harness.bloc.cancelOrder(_uuidA),
      ]);

      expect(
        harness.mm2Api.cancelCalls,
        [_uuidA],
        reason: 'three taps must produce exactly one cancellation',
      );
      expect(results.every((error) => error == null), isTrue);
    });

    test('a wallet switch before the RPC aborts the cancellation', () async {
      final harness = await _Harness.create(orders: [_order(_uuidA)]);
      addTearDown(harness.dispose);

      harness.switchWallet(_walletB);
      final error = await harness.bloc.cancelOrder(_uuidA);

      expect(error, isNotNull);
      expect(
        harness.mm2Api.cancelCalls,
        isEmpty,
        reason: 'the order belongs to a wallet that is no longer live',
      );
      expect(
        harness.bloc.canCancelOrder(_uuidA),
        isFalse,
        reason: 'the bloc must rebind to the new wallet and drop stale orders',
      );
    });

    test('cancelAllOrders skips orders that are not cancelable', () async {
      final harness = await _Harness.create(
        orders: [_order(_uuidA), _order(_uuidB, cancelable: false)],
      );
      addTearDown(harness.dispose);

      await harness.bloc.cancelAllOrders();

      expect(harness.mm2Api.cancelCalls, [_uuidA]);
    });
  });

  group('canRecoverSwap', () {
    test('is false for unknown, malformed and settled swaps', () async {
      final harness = await _Harness.create(
        swaps: [_swap(_uuidA), _swap(_uuidB, recoverable: false)],
      );
      addTearDown(harness.dispose);

      expect(harness.bloc.canRecoverSwap(_uuidA), isTrue);
      expect(harness.bloc.canRecoverSwap(_uuidB), isFalse);
      expect(harness.bloc.canRecoverSwap('not-a-uuid'), isFalse);
    });
  });

  group('recoverFundsOfSwap exactly-once', () {
    test('refuses a non-recoverable swap without issuing the RPC', () async {
      final harness = await _Harness.create(
        swaps: [_swap(_uuidA, recoverable: false)],
      );
      addTearDown(harness.dispose);

      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNull);
      expect(harness.mm2Api.recoverCalls, isEmpty);
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.idle,
      );
    });

    test('concurrent submissions share one in-flight RPC', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);

      await Future.wait([
        harness.bloc.recoverFundsOfSwap(_uuidA),
        harness.bloc.recoverFundsOfSwap(_uuidA),
        harness.bloc.recoverFundsOfSwap(_uuidA),
      ]);

      expect(
        harness.mm2Api.recoverCalls,
        [_uuidA],
        reason: 'three taps must produce exactly one recovery submission',
      );
    });

    test('an unobservable outcome parks the swap in uncertain, and a '
        'later submission is refused', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);

      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNull);
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.uncertain,
        reason: 'a missing reply is not proof the recovery did not happen',
      );

      // The swap is still reported as recoverable, so the only thing stopping
      // a double submission is the uncertain status itself.
      expect(harness.bloc.canRecoverSwap(_uuidA), isTrue);
      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNull);
      expect(
        harness.mm2Api.recoverCalls,
        [_uuidA],
        reason: 'an uncertain submission must never be retried automatically',
      );
    });

    test('uncertain is promoted to accepted once KDF stops reporting the '
        'swap as recoverable', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);

      await harness.bloc.recoverFundsOfSwap(_uuidA);
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.uncertain,
      );

      harness.mm2Api.swaps = [_swap(_uuidA, recoverable: false)];
      final promoted = firstWhereBounded(
        harness.bloc.outRecoveryStatuses,
        (statuses) => statuses[_uuidA] == RecoverySubmissionStatus.accepted,
        description: 'uncertain -> accepted after an authoritative snapshot',
      );
      await harness.bloc.fetch();

      await promoted;
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.accepted,
      );
    });

    test('a successful submission is not repeatable', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);
      harness.mm2Api.recoverResponse = RecoverFundsOfSwapResponse(
        result: RecoverFundsOfSwapResponseResult(
          action: 'SpentOtherPayment',
          coin: 'KMD',
          txHash: 'hash',
          txHex: 'hex',
        ),
      );

      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNotNull);
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.accepted,
      );

      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNull);
      expect(harness.mm2Api.recoverCalls, [_uuidA]);
    });

    test('a wallet switch before the RPC aborts the recovery', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);

      harness.switchWallet(_walletB);
      expect(await harness.bloc.recoverFundsOfSwap(_uuidA), isNull);

      expect(
        harness.mm2Api.recoverCalls,
        isEmpty,
        reason: 'the swap belongs to a wallet that is no longer live',
      );
    });

    test('a submission left in flight across a wallet change is recorded as '
        'uncertain for the wallet that started it', () async {
      final harness = await _Harness.create(swaps: [_swap(_uuidA)]);
      addTearDown(harness.dispose);

      // Change the wallet from inside the RPC, after the pre-flight checks
      // have already passed: the submission has left, and its outcome for
      // wallet A can no longer be observed.
      harness.mm2Api.onRecoverAccepted = () {
        harness.switchWallet(_walletB);
        harness.auth.user = _user(_walletB);
      };

      await harness.bloc.recoverFundsOfSwap(_uuidA);
      await harness.bloc.fetch();

      // Back on wallet A, the earlier submission must still read as uncertain
      // rather than idle, so the button stays locked.
      harness.switchWallet(_walletA);
      await harness.bloc.fetch();
      expect(
        harness.bloc.recoveryStatusFor(_uuidA),
        RecoverySubmissionStatus.uncertain,
      );
      expect(harness.mm2Api.recoverCalls, [_uuidA]);
    });
  });
}
