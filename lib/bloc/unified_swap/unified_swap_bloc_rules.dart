part of 'unified_swap_bloc.dart';

/// Form validation and the rules that decide when a change needs consent.
extension _UnifiedSwapRules on UnifiedSwapBloc {
  void _invalidate() {
    _evaluationVersion++;
    _debounce?.cancel();
    _refresh?.cancel();
    _expiry?.cancel();
  }

  /// Applies form validation to [next].
  UnifiedSwapState _validated(UnifiedSwapState next) {
    final issue = _issueFor(next);
    return issue == null
        ? next.copyWith(clearIssue: true)
        : next.copyWith(issue: issue);
  }

  SwapFormIssue? _issueFor(UnifiedSwapState next) {
    final pay = next.pay;
    if (pay != null && pay == next.receive) return SwapFormIssue.sameAsset;

    final text = next.inputText.trim();
    if (text.isEmpty) return SwapFormIssue.amountMissing;
    final typed = Decimal.tryParse(text);
    if (typed == null) return SwapFormIssue.amountMalformed;
    if (typed <= Decimal.zero) return SwapFormIssue.amountZero;

    final amount = amountOf(next);
    if (amount == null) {
      return next.amountMode == SwapAmountMode.fiat
          ? SwapFormIssue.fiatUnavailable
          : SwapFormIssue.amountMalformed;
    }
    final decimals = pay?.chainId.decimals;
    if (next.amountMode == SwapAmountMode.token &&
        decimals != null &&
        amount.scale > decimals) {
      return SwapFormIssue.tooManyDecimals;
    }

    final balance = next.balance;
    if (balance != null && amount > balance) return SwapFormIssue.insufficient;

    // With a priced option, check the network fees can be paid too.
    final quote = next.selectedQuote;
    if (quote != null && pay != null) {
      final fees = quote.fees.where(
        (fee) =>
            !fee.deductedFromReceive &&
            (fee.kind == SwapFeeKind.network ||
                fee.kind == SwapFeeKind.approvalNetwork),
      );
      final ownFees = fees
          .where((fee) => fee.asset == pay)
          .fold<Decimal>(Decimal.zero, (sum, fee) => sum + fee.amount);
      if (balance != null && amount + ownFees > balance) {
        return SwapFormIssue.insufficient;
      }
      final feeAsset = pay.parentId;
      final feeBalance = next.feeBalance;
      if (feeAsset != null && feeBalance != null) {
        final parentFees = fees
            .where((fee) => fee.asset == feeAsset)
            .fold<Decimal>(Decimal.zero, (sum, fee) => sum + fee.amount);
        if (parentFees > feeBalance) return SwapFormIssue.insufficientForFees;
      }
    }
    return null;
  }

  /// The pair to open on: the last one swapped, or the largest holding paired
  /// with a stablecoin.
  Future<({AssetId pay, AssetId receive})?> _defaultPair(
    Set<AssetId> tradable,
  ) async {
    try {
      final last = await _preferences.lastPair();
      if (last != null) {
        final pay = _resolveAsset(last.from);
        final receive = _resolveAsset(last.to);
        if (pay != null &&
            receive != null &&
            tradable.contains(pay) &&
            tradable.contains(receive)) {
          return (pay: pay, receive: receive);
        }
      }

      final holdings = await _holdings?.call() ?? const <SwapHolding>[];
      final ranked = holdings.where((h) => tradable.contains(h.asset)).toList()
        ..sort((a, b) => b.usdValue.compareTo(a.usdValue));
      if (ranked.isEmpty) return null;
      final pay = ranked.first.asset;
      final receive = _partnerFor(pay, tradable);
      return receive == null ? null : (pay: pay, receive: receive);
    } on Object {
      return null;
    }
  }
}

/// A price move may lower the minimum; costs may drift within this much
/// before the move counts as material.
final _costTolerance = Decimal.parse('0.10');
final _costToleranceUsd = Decimal.parse('0.50');

/// How long after a rate limit only the default route is priced.
const _alternativesCooldown = Duration(minutes: 5);

/// Whether the route's shape changed: a different kind, different steps, or
/// a different permission. Consent to the old shape does not carry over.
bool _isStructuralChange(SwapQuote accepted, SwapQuote fresh) {
  if (accepted.routeKind != fresh.routeKind) return true;
  if ((accepted.approval == null) != (fresh.approval == null)) return true;
  if ((accepted.approval?.resetsFirst ?? false) !=
      (fresh.approval?.resetsFirst ?? false)) {
    return true;
  }
  final before = accepted.stages.map((s) => (s.kind, s.network)).toList();
  final after = fresh.stages.map((s) => (s.kind, s.network)).toList();
  if (before.length != after.length) return true;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) return true;
  }
  return false;
}

/// Whether the numbers moved against the user by enough to ask again.
///
/// Any drop in the guaranteed minimum is material: a swap that silently
/// delivers less than the figure someone agreed to is the failure this flow
/// exists to prevent. Costs may drift a little, not a lot.
bool _isMaterialChange(SwapQuote accepted, SwapQuote fresh) {
  if (fresh.guaranteedReceive < accepted.guaranteedReceive) return true;
  final before = accepted.pricing.totalCostUsd;
  final after = fresh.pricing.totalCostUsd;
  if (before == null || after == null) return false;
  final increase = after - before;
  return increase > _costToleranceUsd && increase > before * _costTolerance;
}

const _stablecoins = {'USDT', 'USDC', 'DAI'};

bool _isStable(AssetId asset) =>
    _stablecoins.contains(asset.symbol.configSymbol.toUpperCase());

/// A stablecoin on the same network as [pay]; for a stablecoin, the
/// network's own coin.
AssetId? _partnerFor(AssetId pay, Set<AssetId> tradable) {
  final network = pay.parentId ?? pay;
  if (_isStable(pay)) {
    if (tradable.contains(network) && network != pay) return network;
    return tradable.where((a) => !_isStable(a) && a != pay).firstOrNull;
  }
  final sameNetwork = tradable.where(
    (a) => _isStable(a) && (a.parentId ?? a) == network,
  );
  return sameNetwork.firstOrNull ??
      tradable.where((a) => _isStable(a) && a != pay).firstOrNull;
}
