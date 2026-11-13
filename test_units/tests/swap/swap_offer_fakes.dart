import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Order-book offers a test scripts. Unscripted, every answer is unknown.
mixin ScriptedOffers implements SwapOfferSource {
  /// Offers per `(from, to)`; a pair left out is unknown.
  Map<(AssetId, AssetId), SwapOrderBookOffers> pairOffers = {};

  /// Whether anyone trades each asset, per anchor; an anchor left out is
  /// unknown.
  Map<AssetId, Map<AssetId, bool>> offeredBy = {};

  Completer<void>? offersGate;
  Completer<void>? offeredGate;
  Object? offersError;
  final List<(AssetId, AssetId)> offersCalls = [];
  final List<({AssetId anchor, List<AssetId> candidates, bool anchorPays})>
  offeredCalls = [];

  @override
  Future<SwapOrderBookOffers?> offers(AssetId from, AssetId to) async {
    offersCalls.add((from, to));
    if (offersGate != null) await offersGate!.future;
    final error = offersError;
    if (error != null) throw error;
    return pairOffers[(from, to)];
  }

  @override
  Future<Map<AssetId, bool>?> offered(
    AssetId anchor,
    Iterable<AssetId> candidates, {
    required bool anchorPays,
  }) async {
    offeredCalls.add((
      anchor: anchor,
      candidates: candidates.toList(),
      anchorPays: anchorPays,
    ));
    if (offeredGate != null) await offeredGate!.future;
    final answer = offeredBy[anchor];
    if (answer == null) return null;
    return {
      for (final id in candidates)
        if (answer[id] case final bool offered) id: offered,
    };
  }
}

/// An order-book source whose offers the test scripts.
class FakeOfferSource extends FakeQuoteSource with ScriptedOffers {
  FakeOfferSource({super.tradable, super.results})
    : super(SwapLiquiditySource.atomic);
}
