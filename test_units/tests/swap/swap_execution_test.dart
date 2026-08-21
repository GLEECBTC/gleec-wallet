import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Covers placing an atomic order from a quoted swap.
void main() {
  AssetId assetOf(String id) => AssetId(
    id: id,
    name: id,
    symbol: AssetSymbol(assetConfigId: id),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  final gleec = assetOf('GLEEC');
  final kmd = assetOf('KMD');

  SwapQuote atomicQuote() => SwapQuote(
    source: SwapLiquiditySource.atomic,
    from: gleec,
    to: kmd,
    sellAmount: Decimal.parse('100'),
    expectedReceive: Decimal.parse('250'),
    guaranteedReceive: Decimal.parse('250'),
    costs: const [],
    quotedAt: DateTime(2026),
    hasUndisclosedCosts: false,
    payload: AtomicSwapPlan(
      base: gleec,
      rel: kmd,
      volume: Decimal.parse('100'),
      price: Decimal.parse('2.5'),
    ),
  );

  test('places a fill-or-kill order at the quoted size and price', () async {
    final dex = _FakeDex();
    final executor = AtomicSwapExecutor(
      dexRepository: dex,
      trading: _FakeTrading(),
    );

    await executor.start(atomicQuote());

    final request = dex.requests.single;
    // Fill-or-kill is the point. A resting or partially filled order is a
    // different trade from the one the user was quoted and accepted.
    expect(request.orderType, SellBuyOrderType.fillOrKill);
    expect(request.base, 'GLEEC');
    expect(request.rel, 'KMD');
    expect(request.volume, Rational.parse('100'));
    expect(request.price, Rational.parse('2.5'));
  });

  test(
    'surfaces a rejected order instead of reporting a running swap',
    () async {
      final executor = AtomicSwapExecutor(
        dexRepository: _FakeDex(error: 'Not enough balance'),
        trading: _FakeTrading(),
      );

      await expectLater(executor.start(atomicQuote()), throwsStateError);
    },
  );

  test('refuses a quote whose plan has gone missing', () async {
    final executor = AtomicSwapExecutor(
      dexRepository: _FakeDex(),
      trading: _FakeTrading(),
    );

    await expectLater(
      executor.start(
        SwapQuote(
          source: SwapLiquiditySource.atomic,
          from: gleec,
          to: kmd,
          sellAmount: Decimal.one,
          expectedReceive: Decimal.one,
          guaranteedReceive: Decimal.one,
          costs: const [],
          quotedAt: DateTime(2026),
          hasUndisclosedCosts: false,
        ),
      ),
      throwsStateError,
    );
  });

  test('cannot be cancelled once placed', () async {
    final executor = AtomicSwapExecutor(
      dexRepository: _FakeDex(),
      trading: _FakeTrading(),
    );

    final handle = await executor.start(atomicQuote());

    // KDF exposes no cancel for an in-flight atomic swap, and a fill-or-kill
    // never becomes a resting order that could be withdrawn. Offering cancel
    // would be a button that cannot work.
    await expectLater(handle.cancel(), throwsStateError);
  });
}

class _FakeDex implements DexRepository {
  _FakeDex({this.error});

  final String? error;
  final List<SellRequest> requests = [];

  @override
  Future<SellResponse> sell(SellRequest request) async {
    requests.add(request);
    if (error != null) {
      return SellResponse(error: TextError(error: error!));
    }
    return SellResponse.fromJson({
      'result': {
        'uuid': 'swap-uuid',
        'base': request.base,
        'rel': request.rel,
        'base_amount': request.volume.toString(),
        'rel_amount': request.price.toString(),
        'action': 'Taker',
        'sender_pubkey': '',
        'dest_pub_key': '',
        'method': 'sell',
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTrading implements TradingManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
