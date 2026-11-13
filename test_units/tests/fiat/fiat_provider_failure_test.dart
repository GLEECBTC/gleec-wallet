import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/banxa_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
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

void main() {
  group('Fiat provider response boundary', () {
    const blockPage = '<html>upstream block page</html>';
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
              isA<FormatException>().having(
                (error) => error.toString(),
                'safe message',
                allOf(
                  contains('Invalid fiat provider response'),
                  isNot(contains(blockPage)),
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
