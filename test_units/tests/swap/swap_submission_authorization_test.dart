import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';

import '../../support/legal_documents_fixture.dart';
import 'swap_src_sdk_fakes.dart';
import 'swap_test_fixtures.dart'
    show
        MemoryStorage,
        TestSwapAuth,
        completed,
        d,
        eth,
        quoteOf,
        snapshotOf,
        usdc;

const _wallet = KdfUser(
  walletId: WalletId(
    name: 'authorization-wallet',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
  isBip39Seed: false,
);

Matcher get _stale => throwsA(
  isA<SwapStartRejectedException>().having(
    (error) => error.reason,
    'reason',
    SwapStartRejection.quoteStale,
  ),
);

void main() {
  group('submission authorization', () {
    late AuthSessionTracker sessions;
    late AuthSessionContext? cachedSession;
    late _GuardedExecutor executor;
    late SwapExecutionRegistry registry;

    SwapExecutionRegistry registryFor(_GuardedExecutor executor) =>
        SwapExecutionRegistry(
          executors: [executor],
          inFlight: () async => const [],
          currentSession: () => cachedSession,
          isSessionCurrent: sessions.isCurrent,
        );

    setUp(() {
      sessions = AuthSessionTracker()..observe(_wallet);
      cachedSession = sessions.current;
      executor = _GuardedExecutor();
      registry = registryFor(executor);
    });

    tearDown(() async {
      await registry.dispose();
      await sessions.dispose();
    });

    test(
      'rejects a token from another registry at the same generation',
      () async {
        final otherExecutor = _GuardedExecutor();
        final otherRegistry = registryFor(otherExecutor);
        addTearDown(otherRegistry.dispose);
        final submission = registry.beginSubmission();

        expect(otherRegistry.isCurrent(submission), isFalse);
        await expectLater(otherRegistry.start(quoteOf(), submission), _stale);
        expect(otherExecutor.starts, 0);
        expect(otherExecutor.dispatches, 0);
      },
    );

    test('rejects a consumed token while its first start is pending', () async {
      executor.responseGate = Completer<void>();
      final submission = registry.beginSubmission();
      final first = registry.start(quoteOf(), submission);
      await executor.dispatched.future;

      await expectLater(registry.start(quoteOf(), submission), _stale);
      expect(executor.starts, 1);
      expect(executor.dispatches, 1);
      executor.responseGate!.complete();
      await first;

      await expectLater(registry.start(quoteOf(), submission), _stale);
      expect(executor.dispatches, 1);
    });

    test(
      'rejects stale cached auth before its change notification arrives',
      () {
        final staleSession = cachedSession;
        sessions.invalidate();

        // The application has not observed the session-change stream yet.
        expect(cachedSession, same(staleSession));
        expect(registry.beginSubmission, _stale);
        expect(executor.starts, 0);
        expect(executor.dispatches, 0);
      },
    );

    test('rejects without an authenticated session', () {
      cachedSession = null;

      expect(registry.beginSubmission, _stale);
      expect(executor.starts, 0);
    });

    test(
      'a same-wallet login cannot reuse the previous confirmation',
      () async {
        final submission = registry.beginSubmission();
        sessions
          ..invalidate()
          ..observe(_wallet);
        cachedSession = sessions.current;

        await expectLater(registry.start(quoteOf(), submission), _stale);
        expect(executor.starts, 0);
        expect(executor.dispatches, 0);
        final freshSubmission = registry.beginSubmission();
        await registry.start(quoteOf(), freshSubmission);
        expect(executor.dispatches, 1);
      },
    );

    test('captures the wallet key with the original confirmation', () {
      final submission = registry.beginSubmission();
      sessions.invalidate();
      cachedSession = null;

      expect(submission.walletKey, _wallet.walletId.compoundId);
      expect(registry.isCurrent(submission), isFalse);
    });

    test('rejects a registry reset before executor entry', () async {
      final submission = registry.beginSubmission();
      await registry.reset();

      await expectLater(registry.start(quoteOf(), submission), _stale);
      expect(executor.starts, 0);
      expect(executor.dispatches, 0);
    });

    test(
      'invalidates synchronously before asynchronous reset cleanup',
      () async {
        final submission = registry.beginSubmission();
        await registry.start(quoteOf(), submission);
        final tokenValidity = <bool>[];
        final subscription = registry.invalidations.listen(
          (_) => tokenValidity.add(registry.isCurrent(submission)),
        );
        addTearDown(subscription.cancel);

        final resetting = registry.reset();

        expect(tokenValidity, [false]);
        await resetting;
        expect(registry.current, isEmpty);
        expect(executor.handle!.closed, isTrue);
        expect(executor.handle!.cancelCalls, 0);
      },
    );

    test('disposing twice closes the invalidation stream only once', () async {
      var invalidations = 0;
      final ended = Completer<void>();
      final subscription = registry.invalidations.listen(
        (_) => invalidations++,
        onDone: ended.complete,
      );
      addTearDown(subscription.cancel);

      await registry.dispose();
      await ended.future;
      expect(invalidations, 1);

      await registry.dispose();
      expect(invalidations, 1);
    });

    for (final source in SwapLiquiditySource.values) {
      test(
        '$source refuses revoked intent after executor preparation',
        () async {
          executor.source = source;
          await registry.dispose();
          registry = registryFor(executor);
          executor.preparationGate = Completer<void>();
          var authorized = true;
          var dispatchNotifications = 0;
          final pending = registry.start(
            quoteOf(source: source),
            registry.beginSubmission(),
            stillCurrent: () => authorized,
            onDispatch: () => dispatchNotifications++,
          );
          final rejected = expectLater(pending, _stale);
          await executor.entered.future;

          authorized = false;
          executor.preparationGate!.complete();
          await rejected;

          expect(executor.dispatches, 0);
          expect(dispatchNotifications, 0);
          expect(registry.current, isEmpty);
        },
      );
    }

    test(
      'rechecks the registry generation after executor preparation',
      () async {
        executor.preparationGate = Completer<void>();
        final pending = registry.start(quoteOf(), registry.beginSubmission());
        final rejected = expectLater(pending, _stale);
        await executor.entered.future;

        await registry.reset();
        executor.preparationGate!.complete();
        await rejected;

        expect(executor.dispatches, 0);
        expect(registry.current, isEmpty);
      },
    );

    test('rechecks the SDK session after executor preparation', () async {
      executor.preparationGate = Completer<void>();
      final pending = registry.start(quoteOf(), registry.beginSubmission());
      final rejected = expectLater(pending, _stale);
      await executor.entered.future;

      sessions.invalidate();
      executor.preparationGate!.complete();
      await rejected;

      expect(executor.dispatches, 0);
      expect(registry.current, isEmpty);
    });

    test('notifies once at dispatch and passes the original session', () async {
      final originalSession = cachedSession;
      var notifications = 0;
      final result = await registry.start(
        quoteOf(),
        registry.beginSubmission(),
        onDispatch: () {
          expect(executor.dispatches, 0);
          notifications++;
        },
      );

      expect(executor.authorization!.session, same(originalSession));
      expect(executor.dispatches, 1);
      expect(notifications, 1);
      expect(registry.snapshotOf(result.id), result);
    });

    test('continues tracking when the form closes after dispatch', () async {
      executor.responseGate = Completer<void>();
      var formOpen = true;
      final pending = registry.start(
        quoteOf(),
        registry.beginSubmission(),
        stillCurrent: () => formOpen,
      );
      await executor.dispatched.future;

      formOpen = false;
      executor.responseGate!.complete();
      final result = await pending;
      expect(registry.snapshotOf(result.id), result);

      executor.handle!.push(snapshotOf(outcome: completed()));
      await pumpEventQueue();
      expect(registry.snapshotOf(result.id)!.isTerminal, isTrue);
      expect(executor.dispatches, 1);
      expect(executor.handle!.closed, isFalse);
    });

    test(
      'retains a late execution id without following it in a new session',
      () async {
        executor.responseGate = Completer<void>();
        final pending = registry.start(quoteOf(), registry.beginSubmission());
        final unconfirmed = expectLater(
          pending,
          throwsA(
            isA<SwapStartUnconfirmedException>().having(
              (error) => error.executionId,
              'executionId',
              'swap-1',
            ),
          ),
        );
        await executor.dispatched.future;

        sessions
          ..invalidate()
          ..observe(_wallet);
        cachedSession = sessions.current;
        executor.responseGate!.complete();
        await unconfirmed;

        expect(registry.current, isEmpty);
        expect(executor.handle!.closed, isTrue);
        expect(executor.handle!.cancelCalls, 0);
        expect(executor.dispatches, 1);
      },
    );
  });

  group('atomic submission authorization', () {
    late _LeasedAuth auth;
    late _AtomicDex dex;
    late AtomicSwapExecutor executor;
    late SwapExecutionAuthorization authorization;

    SwapQuote quote() => quoteOf(
      source: SwapLiquiditySource.atomic,
      payload: AtomicSwapPlan(
        base: eth,
        rel: usdc,
        volume: d('1'),
        price: d('3000'),
        orderPrice: Rational.fromInt(3000),
      ),
    );

    setUp(() {
      auth = _LeasedAuth();
      dex = _AtomicDex(auth);
      executor = AtomicSwapExecutor(
        auth: auth,
        dexRepository: dex,
        orders: _UnusedOrders(),
        networks: () => SwapNetworks([eth, usdc]),
        resolveAsset: (ticker) => ticker == eth.id ? eth : usdc,
      );
      authorization = SwapExecutionAuthorization(
        session: auth.currentSession!,
        beforeDispatch: () {},
      );
    });

    tearDown(() => auth.sessions.dispose());

    test(
      'passes the original session and sells only inside its lease',
      () async {
        final handle = await executor.start(
          quote(),
          authorization: authorization,
        );
        await handle.close();

        expect(auth.requestedContexts, [same(authorization.session)]);
        expect(dex.sells, hasLength(1));
        expect(dex.leaseActiveAtSell, isTrue);
        expect(auth.insideLease, isFalse);
        expect(handle.id, 'atomic-authorization');
      },
    );

    test('rejects a session revoked while waiting for the lease', () async {
      auth.acquisitionGate = Completer<void>();
      final pending = executor.start(quote(), authorization: authorization);
      final rejected = expectLater(pending, _stale);
      await auth.requested.future;

      auth.sessions.invalidate();
      auth.acquisitionGate!.complete();
      await rejected;

      expect(dex.sells, isEmpty);
      expect(auth.insideLease, isFalse);
    });

    test('does not recapture a same-wallet replacement session', () async {
      auth.acquisitionGate = Completer<void>();
      final pending = executor.start(quote(), authorization: authorization);
      final rejected = expectLater(pending, _stale);
      await auth.requested.future;

      auth.sessions
        ..invalidate()
        ..observe(
          KdfUser(walletId: authorization.session.walletId, isBip39Seed: true),
        );
      auth.acquisitionGate!.complete();
      await rejected;

      expect(auth.currentSession, isNot(authorization.session));
      expect(auth.requestedContexts, [same(authorization.session)]);
      expect(dex.sells, isEmpty);
    });

    test('rejects a cancelled intent after waiting for the lease', () async {
      auth.acquisitionGate = Completer<void>();
      var confirmed = true;
      final pending = executor.start(
        quote(),
        authorization: SwapExecutionAuthorization(
          session: authorization.session,
          beforeDispatch: () {
            expect(auth.insideLease, isTrue);
            if (!confirmed) {
              throw const SwapStartRejectedException(
                SwapStartRejection.quoteStale,
              );
            }
          },
        ),
      );
      final rejected = expectLater(pending, _stale);
      await auth.requested.future;

      confirmed = false;
      auth.acquisitionGate!.complete();
      await rejected;

      expect(dex.sells, isEmpty);
      expect(auth.insideLease, isFalse);
    });

    test(
      'keeps a session change during sell unconfirmed without retry',
      () async {
        dex.responseGate = Completer<void>();
        final pending = executor.start(quote(), authorization: authorization);
        final unconfirmed = expectLater(
          pending,
          throwsA(
            isA<SwapStartUnconfirmedException>().having(
              (error) => error.executionId,
              'executionId',
              'atomic-authorization',
            ),
          ),
        );
        await dex.entered.future;
        expect(auth.insideLease, isTrue);

        auth.sessions.invalidate();
        dex.responseGate!.complete();
        await unconfirmed;

        expect(dex.sells, hasLength(1));
        expect(auth.insideLease, isFalse);
      },
    );

    test(
      'preserves an explicit engine rejection after session revocation',
      () async {
        dex
          ..responseGate = Completer<void>()
          ..response = SellResponse(
            error: TextError(error: 'insufficient balance'),
          );
        final pending = executor.start(quote(), authorization: authorization);
        final rejected = expectLater(
          pending,
          throwsA(
            isA<SwapStartRejectedException>().having(
              (error) => error.reason,
              'reason',
              SwapStartRejection.unknown,
            ),
          ),
        );
        await dex.entered.future;

        auth.sessions.invalidate();
        dex.responseGate!.complete();
        await rejected;

        expect(dex.sells, hasLength(1));
        expect(auth.insideLease, isFalse);
      },
    );

    test(
      'keeps a lost sell response unconfirmed and releases the lease',
      () async {
        final failure = StateError('connection closed');
        dex.error = failure;

        await expectLater(
          executor.start(quote(), authorization: authorization),
          throwsA(
            isA<SwapStartUnconfirmedException>().having(
              (error) => error.cause,
              'cause',
              same(failure),
            ),
          ),
        );
        expect(dex.sells, hasLength(1));
        expect(auth.insideLease, isFalse);
      },
    );
  });
  test(
    'consent lookup uses the captured wallet instead of a stale user',
    () async {
      final legalDocuments = legalFixtureRepository();
      addTearDown(legalDocuments.dispose);
      var walletReads = 0;
      final terms = SwapTermsRepository(
        walletKey: () async {
          walletReads++;
          return 'accepted-wallet-A';
        },
        legalDocuments: legalDocuments,
        storage: MemoryStorage(),
      );
      final snapshot = legalFixtureSnapshot();
      await terms.recordAcceptance(
        snapshot: snapshot,
        walletKey: 'accepted-wallet-A',
      );
      expect(walletReads, 0);
      expect(await terms.hasAccepted(snapshot: snapshot), isTrue);
      expect(walletReads, 1);

      expect(
        await terms.hasAccepted(
          snapshot: snapshot,
          walletKey: 'replacement-wallet-B',
        ),
        isFalse,
      );
      expect(
        await terms.hasAccepted(
          snapshot: snapshot,
          walletKey: 'accepted-wallet-A',
        ),
        isTrue,
      );
      expect(walletReads, 1);
    },
  );

  group('service consent ownership', () {
    late SrcSdk sdk;
    late SwapServices services;
    late MemoryStorage storage;
    final snapshot = legalFixtureSnapshot();
    final userA = userOf('consent-session-A');
    final userB = userOf('consent-session-B');

    setUp(() {
      sdk = SrcSdk();
      storage = MemoryStorage();
      final legalDocuments = legalFixtureRepository();
      addTearDown(legalDocuments.dispose);
      services = SwapServices(
        sdk: sdk,
        legalDocuments: legalDocuments,
        coinsRepo: SrcCoinsRepo(),
        dexRepository: SrcDex(),
        orders: SrcOrders(),
        mm2Api: SrcMm2Api(),
        storage: storage,
        logAnalytics: (_) {},
      );
    });

    tearDown(() async {
      await services.dispose();
      await sdk.auth.users.close();
    });

    Future<void> acceptAsA() async {
      sdk.auth.users.add(userA);
      await pumpEventQueue();
      await services.terms.recordAcceptance(snapshot: snapshot);
      expect(await services.terms.hasAccepted(snapshot: snapshot), isTrue);
      expect(
        storage.values.keys,
        contains(
          'routed_swap_terms_acceptance_v1:${userA.walletId.compoundId}',
        ),
      );
    }

    test(
      'uses the SDK session while current-user data still belongs to A',
      () async {
        await acceptAsA();
        final reads = sdk.auth.currentUserReads;

        sdk.auth.sessions
          ..invalidate()
          ..observe(userB);
        await pumpEventQueue();

        expect(sdk.auth.current, same(userA));
        expect(sdk.auth.sessions.current!.walletId, userB.walletId);
        expect(await services.terms.hasAccepted(snapshot: snapshot), isFalse);
        expect(sdk.auth.currentUserReads, reads);
        expect(
          storage.values.keys,
          isNot(
            contains(
              'routed_swap_terms_acceptance_v1:${userB.walletId.compoundId}',
            ),
          ),
        );
      },
    );

    test(
      'rejects revoked consent ownership before its notification arrives',
      () async {
        await acceptAsA();
        final reads = sdk.auth.currentUserReads;

        sdk.auth.sessions.invalidate();
        final accepted = services.terms.hasAccepted(snapshot: snapshot);

        expect(await accepted, isFalse);
        expect(sdk.auth.current, same(userA));
        expect(sdk.auth.currentUserReads, reads);
      },
    );

    test('does not recover a missing session by reading currentUser', () async {
      expect(await services.terms.hasAccepted(snapshot: snapshot), isFalse);
      expect(sdk.auth.currentUserReads, 0);
    });
  });
}

class _GuardedExecutor implements SwapExecutor {
  @override
  SwapLiquiditySource source = SwapLiquiditySource.routed;

  Completer<void>? preparationGate;
  Completer<void>? responseGate;
  final entered = Completer<void>();
  final dispatched = Completer<void>();
  int starts = 0;
  int dispatches = 0;
  SwapExecutionAuthorization? authorization;
  _Handle? handle;

  @override
  Future<SwapExecutionHandle> start(
    SwapQuote quote, {
    required SwapExecutionAuthorization authorization,
  }) async {
    starts++;
    this.authorization = authorization;
    if (!entered.isCompleted) entered.complete();
    if (preparationGate != null) await preparationGate!.future;
    authorization.beforeDispatch();
    dispatches++;
    if (!dispatched.isCompleted) dispatched.complete();
    if (responseGate != null) await responseGate!.future;
    return handle = _Handle(snapshotOf(source: source));
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => null;
}

class _Handle implements SwapExecutionHandle {
  _Handle(this.latest);

  @override
  SwapExecutionSnapshot latest;

  final _updates = StreamController<SwapExecutionSnapshot>.broadcast();
  bool closed = false;
  int cancelCalls = 0;

  void push(SwapExecutionSnapshot snapshot) {
    latest = snapshot;
    _updates.add(snapshot);
  }

  @override
  String get id => latest.id;

  @override
  DateTime? get checkedAt => null;

  @override
  Stream<DateTime> get checks => const Stream.empty();

  @override
  Stream<SwapExecutionSnapshot> get updates => _updates.stream;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> close() async {
    closed = true;
    await _updates.close();
  }
}

/// Controls lease acquisition; the real mutex is covered by local-auth tests.
class _LeasedAuth extends TestSwapAuth {
  Completer<void>? acquisitionGate;
  final requested = Completer<void>();
  final requestedContexts = <AuthSessionContext>[];
  bool insideLease = false;

  @override
  Future<T> runWithSession<T>(
    AuthSessionContext expected,
    Future<T> Function() dispatch,
  ) async {
    requestedContexts.add(expected);
    if (!requested.isCompleted) requested.complete();
    ensureSessionContextCurrent(expected);
    if (acquisitionGate != null) await acquisitionGate!.future;
    ensureSessionContextCurrent(expected);
    insideLease = true;
    try {
      return await dispatch();
    } finally {
      insideLease = false;
    }
  }
}

class _AtomicDex implements DexRepository {
  _AtomicDex(this.auth);

  final _LeasedAuth auth;
  final sells = <SellRequest>[];
  final entered = Completer<void>();
  Completer<void>? responseGate;
  SellResponse response = SellResponse(
    result: SellResponseResult(uuid: 'atomic-authorization'),
  );
  Object? error;
  bool? leaseActiveAtSell;

  @override
  Future<SellResponse> sellOrThrow(SellRequest request) async {
    sells.add(request);
    leaseActiveAtSell = auth.insideLease;
    if (!entered.isCompleted) entered.complete();
    if (responseGate != null) await responseGate!.future;
    if (error case final error?) throw error;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedOrders implements MyOrdersService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
