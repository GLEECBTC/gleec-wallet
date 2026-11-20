import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/banxa_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/services/storage/base_storage.dart';

class _Repository implements FiatRepository {
  Stream<List<FiatPaymentMethod>> Function() respond = () => Stream.value([]);

  @override
  Future<List<FiatCurrency>> getFiatList() async => [
    FiatCurrency.usd(),
    FiatCurrency.usd().copyWith(symbol: 'EUR', name: 'Euro'),
  ];

  @override
  Future<List<CryptoCurrency>> getCoinList() async => [
    CryptoCurrency.bitcoin(),
    CryptoCurrency.bitcoin().copyWith(symbol: 'LTC', name: 'Litecoin'),
  ];

  @override
  Stream<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    CryptoCurrency target,
    String sourceAmount,
  ) => respond();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoinsRepo implements CoinsRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements BaseStorage {
  @override
  Future<dynamic> read(String key) async => null;

  @override
  Future<bool> write(String key, dynamic data) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

http.Response _price(String coinAmount) => _json({
  'data': {
    'prices': [
      {
        'fiat_amount': '50',
        'coin_amount': coinAmount,
        'fiat_code': 'USD',
        'coin_code': 'BTC',
        'spot_price_including_fee': '50000',
      },
    ],
  },
});

final _rejection = _json({
  'errors': {
    'code': 123,
    'status': 422,
    'title': 'Minimum purchase is 100 USD',
  },
}, 422);

/// Three payment methods whose prices are answered by [price], keyed by the
/// payment method id.
BanxaFiatProvider _quotes(http.Response Function(String methodId) price) {
  final client = MockClient((request) async {
    final query = request.url.queryParameters;
    if (query['endpoint'] == '/api/payment-methods') {
      return _json({
        'data': {
          'payment_methods': [
            {'id': 1, 'name': 'Card'},
            {'id': 2, 'name': 'Bank transfer'},
            {'id': 3, 'name': 'Wallet'},
          ],
        },
      });
    }
    return price(query['payment_method_id']!);
  });
  addTearDown(client.close);
  return BanxaFiatProvider(client: client);
}

Future<List<FiatPaymentMethod>> _methods(BanxaFiatProvider provider) =>
    provider.getPaymentMethodsList('USD', CryptoCurrency.bitcoin(), '50');

/// Everything `watchOrderStatus` produced while [elapse] of fake time passed.
({List<FiatOrderStatus> statuses, Object? error, bool done, int polls})
_watchOrder(
  List<http.Response> responses, {
  Duration elapse = const Duration(minutes: 10),
}) {
  final statuses = <FiatOrderStatus>[];
  Object? error;
  var done = false;
  var polls = 0;
  fakeAsync((async) {
    final client = MockClient((request) async {
      final response =
          responses[polls < responses.length ? polls : responses.length - 1];
      polls++;
      return response;
    });
    BanxaFiatProvider(client: client)
        .watchOrderStatus('order-1')
        .listen(
          statuses.add,
          onError: (Object e) => error = e,
          onDone: () => done = true,
        );
    async.elapse(elapse);
    client.close();
  });
  return (statuses: statuses, error: error, done: done, polls: polls);
}

http.Response _order(String status) => _json({
  'data': {
    'order': {'status': status},
  },
});

final _outage = http.Response('<html>bad gateway</html>', 502);

void main() {
  group('Banxa payment method prices', () {
    test('a method whose price fails is dropped, the others stay', () async {
      final methods = await _methods(
        _quotes(
          (id) => switch (id) {
            '1' => _price('0.001'),
            '2' => _outage,
            _ => _json({
              'data': {'prices': <Object>[]},
            }),
          },
        ),
      );
      expect(methods.map((method) => method.id), ['1']);
      expect(methods.single.priceInfo.coinAmount.toString(), '0.001');
    });

    test('a zero-valued quote is dropped rather than offered', () async {
      final methods = await _methods(
        _quotes((id) => _price(id == '2' ? '0' : '0.001')),
      );
      expect(methods.map((method) => method.id), ['1', '3']);
    });

    test('no priced method at all is a provider outage', () async {
      await expectLater(
        _methods(_quotes((_) => _outage)),
        throwsA(isA<FiatProviderUnavailable>()),
      );
    });

    test('a rejection of every price keeps the provider message', () async {
      await expectLater(
        _methods(_quotes((id) => id == '3' ? _outage : _rejection)),
        throwsA(
          isA<FiatProviderRejected>().having(
            (e) => e.error.title,
            'provider error',
            'Minimum purchase is 100 USD',
          ),
        ),
      );
    });
  });

  group('Banxa order status polling', () {
    test('one failed poll does not end the watch', () {
      final watch = _watchOrder([
        _order('waitingPayment'),
        _outage,
        _order('complete'),
      ]);
      expect(watch.statuses, [
        FiatOrderStatus.pendingPayment,
        FiatOrderStatus.success,
      ]);
      expect(watch.error, isNull);
      expect(watch.done, isTrue);
    });

    test('a good poll restarts the count of tolerated failures', () {
      final watch = _watchOrder([
        for (var i = 0; i < 5; i++) _outage,
        _order('waitingPayment'),
        for (var i = 0; i < 5; i++) _outage,
        _order('complete'),
      ]);
      expect(watch.statuses, [
        FiatOrderStatus.pendingPayment,
        FiatOrderStatus.success,
      ]);
      expect(watch.error, isNull);
    });

    test('a sustained outage ends the watch with the provider error', () {
      final watch = _watchOrder([_order('waitingPayment'), _outage]);
      expect(watch.statuses, [FiatOrderStatus.pendingPayment]);
      expect(watch.error, isA<FiatProviderUnavailable>());
      expect(watch.done, isTrue);
      // The first status, five tolerated failures, and the sixth that ends it.
      expect(watch.polls, 7);
    });

    test('a provider rejection is not retried', () {
      final watch = _watchOrder([_rejection]);
      expect(watch.error, isA<FiatProviderRejected>());
      expect(watch.polls, 1);
    });
  });

  group('Fiat provider response boundary', () {
    const blockPage =
        '<html>upstream block page PRIVATE_RESPONSE_CANARY</html>';
    for (final entry in {
      'JSON-wrapped block page': jsonEncode(blockPage),
      'HTML block page': blockPage,
      'JSON array': '[]',
      'JSON null': 'null',
    }.entries) {
      test('rejects ${entry.key} even with HTTP 200', () async {
        await http.runWithClient(() async {
          await expectLater(
            BanxaFiatProvider().getFiatList(),
            throwsA(
              isA<FiatProviderUnavailable>().having(
                (error) => error.toString(),
                'safe message',
                allOf(
                  contains('Fiat provider is temporarily unavailable'),
                  isNot(contains(blockPage)),
                  isNot(contains('<html>')),
                  isNot(contains('PRIVATE_RESPONSE_CANARY')),
                ),
              ),
            ),
          );
        }, () => MockClient((_) async => http.Response(entry.value, 200)));
      });
    }

    test('accepts a valid provider currency response', () async {
      final currencies = await http.runWithClient(
        () => BanxaFiatProvider().getFiatList(),
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'fiats': [
                  {'fiat_code': 'USD', 'fiat_name': 'US Dollar'},
                ],
              },
            }),
            200,
          ),
        ),
      );
      expect(currencies.single.getAbbr(), 'USD');
    });
  });

  group('Fiat payment method failures', () {
    late _Repository repository;
    late FiatFormBloc bloc;
    final oldMethod = defaultFiatPaymentMethods.first;

    setUp(() {
      repository = _Repository();
      bloc = FiatFormBloc(
        repository: repository,
        coinsRepo: _CoinsRepo(),
        sdk: _Sdk(),
        storage: _Storage(),
      );
      addTearDown(bloc.close);
    });

    Future<FiatFormState> refresh(FiatFormStatus status) {
      final result = bloc.stream
          .firstWhere((state) => state.status == status)
          .timeout(const Duration(seconds: 5));
      bloc.add(const FiatFormPaymentMethodsRefreshRequested());
      return result;
    }

    void expectUnavailable(FiatFormState state) {
      expect(state.paymentMethods, isEmpty);
      expect(state.selectedPaymentMethod.isNone, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.canSubmit, isFalse);
    }

    test(
      'initial empty response clears placeholders and ends loading',
      () async {
        expectUnavailable(await refresh(FiatFormStatus.failure));
      },
    );

    for (final failsWithException in [false, true]) {
      test('clears a stale selection on '
          '${failsWithException ? 'provider exception' : 'empty methods'} '
          'and recovers on explicit refresh', () async {
        final currenciesLoaded = bloc.stream
            .firstWhere((state) => !state.isLoadingCurrencies)
            .timeout(const Duration(seconds: 5));
        bloc.add(const FiatFormCurrenciesRefreshRequested());
        await currenciesLoaded;
        final amountUpdated = bloc.stream
            .firstWhere((state) => state.fiatAmount.value == '50')
            .timeout(const Duration(seconds: 5));
        bloc.add(const FiatFormAmountUpdated('50'));
        await amountUpdated;
        repository.respond = () => Stream.value([oldMethod]);
        final ready = await refresh(FiatFormStatus.success);
        expect(ready.selectedPaymentMethod, oldMethod);

        repository.respond = () => failsWithException
            ? Stream.error(const FormatException('Provider unavailable'))
            : Stream.value([]);
        expectUnavailable(await refresh(FiatFormStatus.failure));

        repository.respond = () => Stream.value([oldMethod]);
        final recovered = await refresh(FiatFormStatus.success);
        expect(recovered.selectedPaymentMethod, oldMethod);
        expect(recovered.paymentMethods, [oldMethod]);
        expect(recovered.isLoading, isFalse);
      });
    }
  });
}
