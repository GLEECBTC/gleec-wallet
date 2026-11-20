part of 'unified_swap_repository.dart';

/// Progress of one eligible source, independently of its competitors.
enum SwapQuoteSourceStatus { pending, available, unavailable, skipped }

/// One immutable view of a quote attempt. Pricing completion means the
/// bounded enrichment attempts settled, not that every asset has a USD price.
class SwapQuoteUpdate extends Equatable {
  SwapQuoteUpdate({
    required this.quotes,
    required Map<SwapLiquiditySource, SwapQuoteSourceStatus> sources,
    required this.pricingComplete,
  }) : sources = Map.unmodifiable(sources);

  final UnifiedSwapQuotes quotes;
  final Map<SwapLiquiditySource, SwapQuoteSourceStatus> sources;
  final bool pricingComplete;

  Set<SwapLiquiditySource> get pendingSources => {
    for (final entry in sources.entries)
      if (entry.value == SwapQuoteSourceStatus.pending) entry.key,
  };

  bool get sourcesComplete => pendingSources.isEmpty;
  bool get complete => sourcesComplete && pricingComplete;

  @override
  List<Object?> get props => [quotes, sources, pricingComplete];
}

typedef _PreviewRequestKey = ({
  Object scope,
  SwapQuoteSource source,
  SwapQuoteRequest request,
});

class _PreviewRequest {
  _PreviewRequest(this.result);
  final Future<List<SwapQuoteResult>> result;
  int listeners = 0;
}

class _PreviewLease {
  _PreviewLease(this.result, this.release);
  final Future<List<SwapQuoteResult>> result;
  final void Function() release;
}

/// Owns the lifetime of one stream, including optional work and deadlines.
/// Closing the view releases interest; transport replies may still arrive,
/// but can never publish into the cancelled stream.
class _SwapQuoteRun {
  _SwapQuoteRun({
    required this.repository,
    required this.request,
    required this.timeout,
    required this.pricingTimeout,
    required this.scope,
  }) {
    _controller = StreamController<SwapQuoteUpdate>(
      onListen: () => unawaited(_run()),
      onCancel: _cancel,
    );
  }

  final UnifiedSwapRepository repository;
  final SwapQuoteRequest request;
  final Duration timeout;
  final Duration pricingTimeout;
  final Object? scope;
  late final StreamController<SwapQuoteUpdate> _controller;
  final _stop = Completer<void>();
  final _sources = <SwapLiquiditySource, SwapQuoteSourceStatus>{};
  final _quotes = <SwapQuote>[];
  final _failures = <SwapQuoteFailure>[];
  final _warming = <Future<void>>[];
  final _warmedAssets = <AssetId>{};
  final _leases = <_PreviewLease>[];
  final _priceDeadlines = <Timer, Completer<void>>{};
  Timer? _deadline;
  int _pricingPending = 0;
  bool _cancelled = false;

  Stream<SwapQuoteUpdate> get stream => _controller.stream;

  void _emit() {
    if (_cancelled || _controller.isClosed) return;
    _controller.add(
      SwapQuoteUpdate(
        quotes: UnifiedSwapRepository.rank(
          _quotes.map(repository.pricing.price).toList(),
          List.unmodifiable(_failures),
          comparisonComplete:
              !_sources.values.contains(SwapQuoteSourceStatus.pending) &&
              _pricingPending == 0,
        ),
        sources: _sources,
        pricingComplete: _pricingPending == 0,
      ),
    );
  }

  Future<void> _run() async {
    _deadline = Timer(timeout, () {
      if (!_stop.isCompleted) _stop.complete();
    });
    try {
      if (request.amount <= Decimal.zero) return;
      final local = repository._localFailures(
        request.from,
        request.to,
        signedOut: request.signedOut,
      );
      if (local != null) {
        _failures.addAll(local);
        return;
      }
      final able = repository._sourcesFor(request.from, request.to);
      final asked = <SwapQuoteSource>[];
      for (final source in able) {
        if (!request.signedOut || source.pricesSignedOut) {
          asked.add(source);
          _sources[source.source] = SwapQuoteSourceStatus.pending;
        } else {
          _sources[source.source] = SwapQuoteSourceStatus.skipped;
          _failures.add(
            SwapQuoteFailure(
              source: source.source,
              kind: SwapQuoteFailureKind.signedOut,
            ),
          );
        }
      }
      if (asked.isEmpty) return;

      _warm([request.from, request.to, ?request.from.parentId]);
      _emit();
      var comparison = request;
      if (request.maxSource case final maxSource?) {
        final controlling = asked
            .where((source) => source.source == maxSource)
            .firstOrNull;
        if (controlling == null) {
          _failures.add(
            SwapQuoteFailure(
              source: maxSource,
              kind: SwapQuoteFailureKind.pairUnsupported,
            ),
          );
          _skipPending();
          return;
        }
        final maximum = await _ask(controlling, request);
        final priced = maximum.whereType<SwapQuoteAvailable>().firstOrNull;
        if (priced == null || _cancelled) {
          _skipPending();
          return;
        }
        comparison = request.atAmount(priced.quote.sellAmount);
      }
      if (!_cancelled) {
        await Future.wait([
          for (final source in asked)
            if (source.source != request.maxSource) _ask(source, comparison),
        ]);
      }
    } finally {
      // New fee currencies are discovered only when a source replies. Wait
      // for those bounded reads too, while earlier snapshots remain usable.
      await Future.wait(_warming);
      _emit();
      _release();
      if (!_controller.isClosed) unawaited(_controller.close());
    }
  }

  Future<List<SwapQuoteResult>> _ask(
    SwapQuoteSource source,
    SwapQuoteRequest input,
  ) async {
    List<SwapQuoteResult> timedOut() => [
      SwapQuoteRejected(
        SwapQuoteFailure(
          source: source.source,
          kind: SwapQuoteFailureKind.timeout,
        ),
      ),
    ];
    final List<SwapQuoteResult> results;
    if (_stop.isCompleted) {
      results = timedOut();
    } else {
      final lease = repository._preview(source, input, scope);
      _leases.add(lease);
      results = await Future.any([
        lease.result,
        _stop.future.then((_) => timedOut()),
      ]);
    }
    if (_cancelled) return const [];
    var available = false;
    for (final result in results) {
      switch (result) {
        case SwapQuoteAvailable(:final quote):
          available = true;
          _quotes.add(quote);
          _warm([
            for (final fee in quote.fees)
              if (fee.asset != null) fee.asset!,
          ]);
        case SwapQuoteRejected(:final failure):
          _failures.add(failure);
      }
    }
    _sources[source.source] = available
        ? SwapQuoteSourceStatus.available
        : SwapQuoteSourceStatus.unavailable;
    _emit();
    return results;
  }

  void _skipPending() {
    for (final source in _sources.keys.toList()) {
      if (_sources[source] == SwapQuoteSourceStatus.pending) {
        _sources[source] = SwapQuoteSourceStatus.skipped;
      }
    }
  }

  void _warm(Iterable<AssetId> assets) {
    final fresh = assets.where(_warmedAssets.add).toSet();
    if (fresh.isEmpty || _cancelled || _stop.isCompleted) return;
    _pricingPending++;
    final expired = Completer<void>();
    final timer = Timer(pricingTimeout, expired.complete);
    _priceDeadlines[timer] = expired;
    final warming = Future.sync(() => repository.pricing.prices.warm(fresh))
        .catchError((Object _) {});
    _warming.add(
      Future.any([warming, expired.future, _stop.future]).whenComplete(() {
        timer.cancel();
        _priceDeadlines.remove(timer);
        _pricingPending--;
        _emit();
      }),
    );
  }

  void _cancel() {
    _cancelled = true;
    if (!_stop.isCompleted) _stop.complete();
    _release();
  }

  void _release() {
    _deadline?.cancel();
    for (final entry in _priceDeadlines.entries.toList()) {
      entry.key.cancel();
      if (!entry.value.isCompleted) entry.value.complete();
    }
    _priceDeadlines.clear();
    for (final lease in _leases) {
      lease.release();
    }
    _leases.clear();
  }
}
