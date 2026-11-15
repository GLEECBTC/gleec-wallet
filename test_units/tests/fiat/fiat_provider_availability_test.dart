import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/banxa_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/views/fiat/fiat_payment_methods_grid.dart';

const _blocked =
    '<html><title>Attention Required! | Cloudflare</title>'
    '<body>Sorry, you have been blocked; PRIVATE_RESPONSE_CANARY</body></html>';

BanxaFiatProvider _provider(http.Response Function(http.Request) response) {
  final client = MockClient((request) async {
    expect(
      request.method,
      'GET',
      reason: 'This suite must never create orders',
    );
    expect(request.url.queryParameters['endpoint'], isNot('/api/orders'));
    return response(request);
  });
  addTearDown(client.close);
  return BanxaFiatProvider(client: client);
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

final _price = FiatPriceInfo(
  fiatAmount: Decimal.fromInt(50),
  coinAmount: Decimal.parse('0.001'),
  fiatCode: 'USD',
  coinCode: 'BTC',
  spotPriceIncludingFee: Decimal.fromInt(50000),
);
final _method = FiatPaymentMethod.none.copyWith(
  providerId: 'Banxa',
  id: '1',
  name: 'Card',
  priceInfo: _price,
);

http.Response _healthy(http.Request request) {
  switch (request.url.queryParameters['endpoint']) {
    case '/api/payment-methods':
      return _json({
        'data': {
          'payment_methods': [
            {'id': 1, 'name': 'Card'},
          ],
        },
      });
    case '/api/prices':
      return _json({
        'data': {
          'prices': [_price.toJson()],
        },
      });
    default:
      throw StateError('Unexpected fixture endpoint');
  }
}

void main() {
  group('Banxa availability boundary', () {
    for (final fixture in <String, String>{
      'JSON-string HTML': jsonEncode(_blocked),
      'raw HTML': _blocked,
      'null JSON': 'null',
      'array JSON': '[]',
      'missing data': '{}',
    }.entries) {
      test('${fixture.key} never becomes an empty successful quote', () async {
        final provider = _provider((_) => http.Response(fixture.value, 200));
        for (final operation in <Future<Object> Function()>[
          provider.getFiatList,
          provider.getCoinList,
          () => provider.getPaymentMethodsList(
            'USD',
            CryptoCurrency.bitcoin(),
            '50',
          ),
          () => provider.getPaymentMethodPrice(
            'USD',
            CryptoCurrency.bitcoin(),
            '50',
            _method,
          ),
        ]) {
          await expectLater(
            operation(),
            throwsA(
              isA<FiatProviderUnavailable>().having(
                (error) => error.toString(),
                'safe message',
                isNot(contains('PRIVATE_RESPONSE_CANARY')),
              ),
            ),
          );
        }
      });
    }

    test(
      'HTTP failure with HTML remains a typed availability failure',
      () async {
        final provider = _provider((_) => http.Response(_blocked, 503));
        await expectLater(
          provider.getFiatList(),
          throwsA(
            isA<FiatProviderUnavailable>().having(
              (e) => e.statusCode,
              'status',
              503,
            ),
          ),
        );
      },
    );

    for (final status in [200, 422]) {
      test(
        'HTTP $status preserves a structured provider business rejection',
        () async {
          final provider = _provider(
            (_) => _json({
              'errors': {
                'code': 123,
                'status': 422,
                'title': 'Minimum purchase is 100 USD',
              },
            }, status),
          );
          await expectLater(
            provider.getPaymentMethodsList(
              'USD',
              CryptoCurrency.bitcoin(),
              '50',
            ),
            throwsA(
              isA<FiatProviderRejected>().having(
                (e) => e.error.title,
                'provider error',
                'Minimum purchase is 100 USD',
              ),
            ),
          );
        },
      );
    }

    test(
      'empty methods stay a valid empty result and do not request prices',
      () async {
        var requests = 0;
        final provider = _provider((request) {
          requests++;
          expect(
            request.url.queryParameters['endpoint'],
            '/api/payment-methods',
          );
          return _json({
            'data': {'payment_methods': []},
          });
        });
        expect(
          await provider.getPaymentMethodsList(
            'USD',
            CryptoCurrency.bitcoin(),
            '50',
          ),
          isEmpty,
        );
        expect(requests, 1);
      },
    );

    test('malformed catalog entries fail at the provider boundary', () async {
      final provider = _provider(
        (_) => _json({
          'data': {
            'fiats': [42],
          },
        }),
      );
      await expectLater(
        provider.getFiatList(),
        throwsA(isA<FiatProviderUnavailable>()),
      );
    });

    test('blocked prices never become zero-valued payment methods', () async {
      final provider = _provider(
        (request) => request.url.queryParameters['endpoint'] == '/api/prices'
            ? _json(_blocked)
            : _healthy(request),
      );
      await expectLater(
        provider.getPaymentMethodsList('USD', CryptoCurrency.bitcoin(), '50'),
        throwsA(isA<FiatProviderUnavailable>()),
      );
    });

    test(
      'repository invalidates estimated quotes after provider outage',
      () async {
        var blocked = false;
        final provider = _provider(
          (request) => blocked ? _json(_blocked) : _healthy(request),
        );
        final repository = FiatRepository([provider], _Coins());
        final coin = CryptoCurrency.bitcoin();
        final first = await repository
            .getPaymentMethodsList('USD', coin, '50')
            .toList();
        expect(first.single.single.priceInfo.coinAmount, _price.coinAmount);
        blocked = true;
        final staleThenFailure = <List<FiatPaymentMethod>>[];
        Object? failure;
        try {
          await for (final methods in repository.getPaymentMethodsList(
            'USD',
            coin,
            '60',
          )) {
            staleThenFailure.add(methods);
          }
        } catch (error) {
          failure = error;
        }
        expect(staleThenFailure, hasLength(1));
        expect(failure, isA<FiatProviderUnavailable>());
        await expectLater(
          repository.getPaymentMethodsList('USD', coin, '60'),
          emitsError(isA<FiatProviderUnavailable>()),
        );
      },
    );

    test(
      'a healthy provider remains usable when another is unavailable',
      () async {
        final unavailable = _provider((_) => _json(_blocked));
        final healthy = _provider(_healthy);
        final repository = FiatRepository([unavailable, healthy], _Coins());
        final results = await repository
            .getPaymentMethodsList('USD', CryptoCurrency.bitcoin(), '50')
            .toList();
        expect(results.single, hasLength(1));
      },
    );
  });

  group('Fiat availability form', () {
    late _Repository repository;
    late FiatFormBloc bloc;
    setUp(() {
      repository = _Repository();
      bloc = FiatFormBloc(
        repository: repository,
        coinsRepo: _Coins(),
        sdk: _Sdk(),
        storage: _Storage(),
      );
      addTearDown(bloc.close);
    });

    Future<FiatFormState> fetchCurrencies() {
      final complete = bloc.stream.firstWhere(
        (state) =>
            state.currenciesStatus == FiatFormStatus.failure ||
            (state.currenciesStatus == FiatFormStatus.success &&
                state.status == FiatFormStatus.success),
      );
      bloc.add(const FiatFormCurrenciesRefreshRequested());
      return complete;
    }

    test('one currency per catalog finishes loading', () async {
      final state = await fetchCurrencies();
      expect(state.isLoading, isFalse);
      expect(state.fiatList, hasLength(1));
      expect(state.coinList, hasLength(1));
    });

    test('empty catalogs end the spinner and prohibit submission', () async {
      repository.emptyCatalog = true;
      final state = await fetchCurrencies();
      expect(state.currenciesStatus, FiatFormStatus.failure);
      expect(state.providerUnavailable, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.canSubmit, isFalse);
    });

    test(
      'empty methods produce a recoverable state without a bloc error',
      () async {
        await fetchCurrencies();
        repository.emptyMethods = true;
        final failed = bloc.stream.firstWhere(
          (state) => state.status == FiatFormStatus.failure,
        );
        bloc.add(const FiatFormPaymentMethodsRefreshRequested());
        final state = await failed;
        expect(state.isLoading, isFalse);
        expect(state.paymentMethods, isEmpty);
        expect(state.selectedPaymentMethod.isNone, isTrue);
        expect(state.canSubmit, isFalse);
      },
    );

    test(
      'quote outage clears the selected method and retry restores it',
      () async {
        await fetchCurrencies();
        repository.quoteFailure = const FiatProviderUnavailable();
        final failed = bloc.stream.firstWhere(
          (state) => state.providerUnavailable,
        );
        bloc.add(const FiatFormPaymentMethodsRefreshRequested());
        final state = await failed;
        expect(state.selectedPaymentMethod.isNone, isTrue);
        expect(state.isLoading, isFalse);
        repository.quoteFailure = null;
        final recovered = bloc.stream.firstWhere(
          (state) => state.status == FiatFormStatus.success,
        );
        bloc.add(const FiatFormPaymentMethodsRefreshRequested());
        expect((await recovered).providerUnavailable, isFalse);
      },
    );

    test('structured quote rejections keep their provider message', () async {
      await fetchCurrencies();
      repository.quoteFailure = const FiatProviderRejected(
        FiatBuyOrderError(
          code: 123,
          status: 422,
          title: 'Minimum purchase is 100 USD',
        ),
      );
      final failed = bloc.stream.firstWhere(
        (state) => state.status == FiatFormStatus.failure,
      );
      bloc.add(const FiatFormPaymentMethodsRefreshRequested());
      final state = await failed;
      expect(state.providerError, 'Minimum purchase is 100 USD');
      expect(state.providerUnavailable, isFalse);
    });

    testWidgets('catalog outage offers an explicit read-only retry', (
      tester,
    ) async {
      repository.emptyCatalog = true;
      final failure = await tester.runAsync(fetchCurrencies);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: bloc,
              child: FiatPaymentMethodsGrid(state: failure!),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('fiat-provider-retry')), findsOneWidget);
      expect(find.textContaining('PRIVATE_RESPONSE_CANARY'), findsNothing);
      repository.emptyCatalog = false;
      final recovered = bloc.stream.firstWhere(
        (state) => state.currenciesStatus == FiatFormStatus.success,
      );
      await tester.tap(find.byKey(const Key('fiat-provider-retry')));
      await tester.runAsync(() => recovered);
      await tester.pumpAndSettle();
      expect(repository.catalogRequests, 2);
      expect(bloc.state.currenciesStatus, FiatFormStatus.success);
    });
  });
}

class _Repository implements FiatRepository {
  bool emptyCatalog = false;
  bool emptyMethods = false;
  Object? quoteFailure;
  int catalogRequests = 0;

  @override
  Future<List<FiatCurrency>> getFiatList() async {
    catalogRequests++;
    return emptyCatalog ? [] : [FiatCurrency.usd()];
  }

  @override
  Future<List<CryptoCurrency>> getCoinList() async => [
    CryptoCurrency.bitcoin(),
  ];
  @override
  Stream<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    CryptoCurrency target,
    String amount,
  ) async* {
    if (quoteFailure != null) throw quoteFailure!;
    yield emptyMethods ? [] : [_method];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Coins implements CoinsRepo {
  @override
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) =>
      {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements BaseStorage {
  final values = <String, dynamic>{};
  @override
  Future<dynamic> read(String key) async => values[key];
  @override
  Future<bool> write(String key, dynamic data) async {
    values[key] = data;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}
