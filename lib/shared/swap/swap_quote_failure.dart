import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Why a source could not price a swap.
///
/// Each kind maps to one of the swap entry's states, with its own copy and
/// its own next step — a pair no source supports steers the user to another
/// asset, a rate limit asks them to wait, a service error offers a retry.
enum SwapQuoteFailureKind {
  /// An asset in the pair is not activated in the wallet.
  assetInactive,

  /// This source cannot trade the pair at all.
  pairUnsupported,

  /// The amount is below what the source accepts.
  belowMinimum,

  /// The amount is above what the source accepts.
  aboveMaximum,

  /// Supported, but no route or counterparty exists at this size right now.
  noRoute,

  /// The provider's quota is exhausted. Slow down and retry after a pause.
  rateLimited,

  /// The service answered with an error. A retry may work.
  serviceError,

  /// Pricing took too long.
  timeout,

  /// The amount is malformed for this asset — too many decimals, say.
  invalidAmount,

  /// The wallet cannot cover the swap and its network fees: [asset] is short
  /// by what [minimum] requires.
  insufficientFunds,

  /// The selected address cannot sign every step this source requires.
  unsupportedSigner,

  /// The node is not configured for this source. Operator-side.
  notConfigured,

  /// Trading this asset is unavailable here.
  tradingBlocked,

  /// The device clock is off, which peer-to-peer swaps cannot tolerate.
  clockInvalid,

  /// Something else.
  unknown,
}

/// A source that could not price a swap, and why.
class SwapQuoteFailure extends Equatable {
  const SwapQuoteFailure({
    required this.source,
    required this.kind,
    this.asset,
    this.minimum,
    this.maximum,
    this.reasons = const [],
    this.providerRequestId,
    this.detail,
    this.retryAt,
  });

  /// Which source could not price it.
  final SwapLiquiditySource source;

  /// Why.
  final SwapQuoteFailureKind kind;

  /// The asset concerned, for [SwapQuoteFailureKind.assetInactive],
  /// [SwapQuoteFailureKind.tradingBlocked] and
  /// [SwapQuoteFailureKind.insufficientFunds].
  final AssetId? asset;

  /// The lower bound, for [SwapQuoteFailureKind.belowMinimum]; the amount
  /// required, for [SwapQuoteFailureKind.insufficientFunds].
  final Decimal? minimum;

  /// The upper bound, for [SwapQuoteFailureKind.aboveMaximum].
  final Decimal? maximum;

  /// Display strings from the provider explaining a missing route. No stable
  /// format — never parse them.
  final List<String> reasons;

  /// The provider's support-correlation id, for escalation.
  final String? providerRequestId;

  /// A diagnostic message. Not localised; never primary copy.
  final String? detail;

  /// For [SwapQuoteFailureKind.rateLimited]: when asking again is worth it.
  final DateTime? retryAt;

  /// Whether retrying the same request later may succeed.
  bool get isTransient => switch (kind) {
    SwapQuoteFailureKind.rateLimited ||
    SwapQuoteFailureKind.serviceError ||
    SwapQuoteFailureKind.timeout ||
    SwapQuoteFailureKind.unknown => true,
    _ => false,
  };

  /// Whether the pair can never be priced by this source, whatever the
  /// amount.
  bool get isPermanent => switch (kind) {
    SwapQuoteFailureKind.pairUnsupported ||
    SwapQuoteFailureKind.notConfigured ||
    SwapQuoteFailureKind.tradingBlocked => true,
    _ => false,
  };

  @override
  List<Object?> get props => [
    source,
    kind,
    asset,
    minimum,
    maximum,
    reasons,
    providerRequestId,
    detail,
    retryAt,
  ];
}

/// The outcome of asking one source for a price.
sealed class SwapQuoteResult {
  const SwapQuoteResult();
}

/// A source produced a price.
final class SwapQuoteAvailable extends SwapQuoteResult {
  const SwapQuoteAvailable(this.quote);

  /// The priced swap.
  final SwapQuote quote;
}

/// A source could not produce a price.
final class SwapQuoteRejected extends SwapQuoteResult {
  const SwapQuoteRejected(this.failure);

  /// Why not.
  final SwapQuoteFailure failure;
}

/// One place the app can get a swap price from.
abstract interface class SwapQuoteSource {
  /// Which source this is.
  SwapLiquiditySource get source;

  /// What this source can trade among the wallet's [known] assets, of which
  /// [activated] are active.
  ///
  /// Used to gate quoting and the pickers. Membership does not promise a
  /// route exists — only [quote] can answer that. Must not throw: a source
  /// that cannot refresh its list says so in [SwapSourceAssets.status] and
  /// reports what it last knew.
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  });

  /// Prices a swap — possibly several routes — or explains why it cannot.
  ///
  /// Must not throw for an ordinary "no price" outcome: one venue being unable
  /// to fill an order is not an error, and a source that throws takes the
  /// whole aggregation down with it.
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request);

  /// Prices [quote] again on the same route, for revalidation before start.
  Future<SwapQuoteResult> requote(SwapQuote quote);

  /// The largest amount of [from] this source can sell for [to] from
  /// [balance], keeping what its fees need. Null when it cannot tell.
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  });

  /// The smallest amount of [from] this source accepts, when it has a fixed
  /// one. Null when only a quote can tell.
  Future<Decimal?> minimumAmount({required AssetId from});
}
