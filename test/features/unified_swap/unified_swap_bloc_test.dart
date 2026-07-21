import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 12);

  test('wallet defaults seed intent without requesting a quote', () async {
    final repository = _ControlledQuoteRepository();
    final bloc = UnifiedSwapBloc(quoteRepository: repository, now: () => now);

    bloc.add(const UnifiedSwapWalletChanged('wallet-a'));
    await _waitFor(() => bloc.state.walletId == 'wallet-a');
    bloc.add(UnifiedSwapIntentSeeded(_intent(0, amount: '0')));
    await _waitFor(() => bloc.state.intent != null);

    expect(bloc.state.status, UnifiedSwapQuoteStatus.idle);
    expect(bloc.state.intent?.sourceAmount, '0');
    expect(repository.requests, isEmpty);
    await bloc.close();
  });

  test(
    'zero-amount selection revision invalidates quote without a request',
    () async {
      final repository = _ControlledQuoteRepository();
      final bloc = UnifiedSwapBloc(quoteRepository: repository, now: () => now);

      bloc.add(UnifiedSwapIntentChanged(_intent(1, amount: '10')));
      await repository.waitForRequests(1);
      repository.complete(0, _evaluation(1, candidateId: 'old', now: now));
      await _waitFor(() => bloc.state.status == UnifiedSwapQuoteStatus.ready);

      bloc.add(UnifiedSwapIntentChanged(_intent(2, amount: '0')));
      await _waitFor(() => bloc.state.intent?.revision == 2);

      expect(bloc.state.status, UnifiedSwapQuoteStatus.idle);
      expect(bloc.state.evaluation, isNull);
      expect(bloc.state.selectedCandidateId, isNull);
      expect(repository.requests, hasLength(1));
      await bloc.close();
    },
  );

  test('latest intent wins when an older response finishes last', () async {
    final repository = _ControlledQuoteRepository();
    final bloc = UnifiedSwapBloc(quoteRepository: repository, now: () => now);

    bloc.add(UnifiedSwapIntentChanged(_intent(1, amount: '10')));
    await repository.waitForRequests(1);
    bloc.add(UnifiedSwapIntentChanged(_intent(2, amount: '20')));
    await repository.waitForRequests(2);

    repository.complete(1, _evaluation(2, candidateId: 'new', now: now));
    await Future<void>.delayed(Duration.zero);
    repository.complete(0, _evaluation(1, candidateId: 'old', now: now));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.intent?.revision, 2);
    expect(bloc.state.candidates.single.candidateId, 'new');
    await bloc.close();
  });

  test('unknown or non-executable candidate cannot be selected', () async {
    final repository = _ImmediateQuoteRepository(
      _evaluation(
        1,
        candidateId: 'unknown',
        now: now,
        executable: false,
        topology: UnifiedSwapTopology.unknown,
      ),
    );
    final bloc = UnifiedSwapBloc(quoteRepository: repository, now: () => now);

    bloc.add(UnifiedSwapIntentChanged(_intent(1, amount: '10')));
    await _waitFor(() => bloc.state.status == UnifiedSwapQuoteStatus.ready);
    bloc.add(const UnifiedSwapCandidateSelected('unknown'));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.selectedCandidateId, isNull);
    await bloc.close();
  });

  test('wallet change immediately clears wallet-scoped quote state', () async {
    final repository = _ImmediateQuoteRepository(
      _evaluation(1, candidateId: 'candidate', now: now),
    );
    final bloc = UnifiedSwapBloc(quoteRepository: repository, now: () => now);

    bloc.add(UnifiedSwapIntentChanged(_intent(1, amount: '10')));
    await _waitFor(() => bloc.state.status == UnifiedSwapQuoteStatus.ready);
    bloc.add(const UnifiedSwapWalletChanged('wallet-b'));
    await _waitFor(() => bloc.state.walletId == 'wallet-b');

    expect(bloc.state.intent, isNull);
    expect(bloc.state.evaluation, isNull);
    expect(bloc.state.status, UnifiedSwapQuoteStatus.idle);
    await bloc.close();
  });

  test(
    'expiry prunes only expired candidates and keeps a live route',
    () async {
      var clock = now;
      final firstExpiry = now.add(const Duration(milliseconds: 20));
      final secondExpiry = now.add(const Duration(minutes: 1));
      final evaluation = UnifiedSwapQuoteEvaluation(
        evaluationId: 'evaluation-staggered-expiry',
        intentRevision: 1,
        candidates: [
          _candidate('short', expiresAt: firstExpiry, now: now),
          _candidate('long', expiresAt: secondExpiry, now: now),
        ],
      );
      final bloc = UnifiedSwapBloc(
        quoteRepository: _ImmediateQuoteRepository(evaluation),
        now: () => clock,
      );

      bloc.add(UnifiedSwapIntentChanged(_intent(1, amount: '10')));
      await _waitFor(() => bloc.state.status == UnifiedSwapQuoteStatus.ready);
      bloc.add(const UnifiedSwapCandidateSelected('short'));
      await _waitFor(() => bloc.state.selectedCandidateId == 'short');
      clock = firstExpiry;
      await _waitFor(() => bloc.state.candidates.length == 1);

      expect(bloc.state.status, UnifiedSwapQuoteStatus.ready);
      expect(bloc.state.candidates.single.candidateId, 'long');
      expect(bloc.state.selectedCandidateId, isNull);
      await bloc.close();
    },
  );
}

UnifiedSwapIntent _intent(int revision, {required String amount}) =>
    UnifiedSwapIntent(
      revision: revision,
      source: const UnifiedSwapAssetIdentity(
        ticker: 'ETH',
        chainFamily: UnifiedSwapChainFamily.evm,
        chainId: '1',
        kind: UnifiedSwapAssetKind.native,
        decimals: 18,
      ),
      destination: const UnifiedSwapAssetIdentity(
        ticker: 'USDC',
        chainFamily: UnifiedSwapChainFamily.evm,
        chainId: '137',
        kind: UnifiedSwapAssetKind.token,
        decimals: 6,
        contractAddress: '0x1111111111111111111111111111111111111111',
      ),
      sourceAmount: amount,
      sourceSelection: const UnifiedSwapActiveSourceSelection(),
      recipient: '0x2222222222222222222222222222222222222222',
      sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
      destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
    );

UnifiedSwapQuoteEvaluation _evaluation(
  int revision, {
  required String candidateId,
  required DateTime now,
  bool executable = true,
  UnifiedSwapTopology topology = UnifiedSwapTopology.external,
}) => UnifiedSwapQuoteEvaluation(
  evaluationId: 'evaluation-$revision-$candidateId',
  intentRevision: revision,
  candidates: [
    _candidate(
      candidateId,
      expiresAt: now.add(const Duration(minutes: 1)),
      now: now,
      executable: executable,
      topology: topology,
    ),
  ],
);

UnifiedSwapQuoteCandidate _candidate(
  String candidateId, {
  required DateTime expiresAt,
  required DateTime now,
  bool executable = true,
  UnifiedSwapTopology topology = UnifiedSwapTopology.external,
}) => UnifiedSwapQuoteCandidate(
  candidateId: candidateId,
  candidateDigest: 'digest-$candidateId',
  topology: topology,
  expectedReceive: '100',
  minimumReceive: '99',
  fees: const [],
  expiresAt: expiresAt,
  rankable: true,
  rank: 1,
  valuation: UnifiedSwapValuationProof(
    currency: 'USD',
    observedAt: now,
    validUntil: expiresAt,
    netMinimumReceive: '99',
  ),
  isExecutable: executable,
  rawUnknownDiscriminator: topology == UnifiedSwapTopology.unknown
      ? 'future'
      : null,
);

class _ControlledQuoteRepository implements UnifiedSwapQuoteRepository {
  final requests = <Completer<UnifiedSwapQuoteEvaluation>>[];

  @override
  Future<UnifiedSwapQuoteEvaluation> evaluate(UnifiedSwapIntent intent) {
    final completer = Completer<UnifiedSwapQuoteEvaluation>();
    requests.add(completer);
    return completer.future;
  }

  void complete(int index, UnifiedSwapQuoteEvaluation evaluation) =>
      requests[index].complete(evaluation);

  Future<void> waitForRequests(int count) =>
      _waitFor(() => requests.length >= count);
}

class _ImmediateQuoteRepository implements UnifiedSwapQuoteRepository {
  const _ImmediateQuoteRepository(this.evaluation);

  final UnifiedSwapQuoteEvaluation evaluation;

  @override
  Future<UnifiedSwapQuoteEvaluation> evaluate(UnifiedSwapIntent intent) async =>
      evaluation;
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 100; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TimeoutException('Condition was not reached');
}
