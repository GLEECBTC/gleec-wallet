import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/fiat/models/i_currency.dart' as fiat_models;
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

void main() {
  group('Fiat default preference', () {
    test('hydrates the fiat form from the persisted default fiat', () async {
      final storage = _FakeStorage(
        initialData: <String, dynamic>{defaultFiatPreferenceKey: 'EUR'},
      );
      final bloc = FiatFormBloc(
        repository: _UnusedFiatRepository(),
        coinsRepo: _UnusedCoinsRepo(),
        sdk: _UnusedSdk(),
        storage: storage,
      );
      addTearDown(bloc.close);

      await _flush();

      expect(bloc.state.selectedFiat.value?.getAbbr(), 'EUR');
    });

    test(
      'falls back to USD when the persisted default fiat is missing',
      () async {
        final bloc = FiatFormBloc(
          repository: _UnusedFiatRepository(),
          coinsRepo: _UnusedCoinsRepo(),
          sdk: _UnusedSdk(),
          storage: _FakeStorage(),
        );
        addTearDown(bloc.close);

        await _flush();

        expect(bloc.state.selectedFiat.value?.getAbbr(), 'USD');
      },
    );

    test(
      'falls back to USD when the persisted default fiat is unsupported',
      () async {
        final bloc = FiatFormBloc(
          repository: _UnusedFiatRepository(),
          coinsRepo: _UnusedCoinsRepo(),
          sdk: _UnusedSdk(),
          storage: _FakeStorage(
            initialData: <String, dynamic>{defaultFiatPreferenceKey: 'XYZ'},
          ),
        );
        addTearDown(bloc.close);

        await _flush();

        expect(bloc.state.selectedFiat.value?.getAbbr(), 'USD');
      },
    );

    test('persists new fiat selections from the current app flow', () async {
      final storage = _FakeStorage();
      final bloc = FiatFormBloc(
        repository: _UnusedFiatRepository(),
        coinsRepo: _UnusedCoinsRepo(),
        sdk: _UnusedSdk(),
        storage: storage,
      );
      addTearDown(bloc.close);

      await _flush();

      final selectedStateFuture = bloc.stream.firstWhere(
        (state) =>
            state.selectedFiat.value?.getAbbr() == 'EUR' &&
            state.status == FiatFormStatus.loading,
      );
      bloc.add(
        FiatFormFiatSelected(
          fiat_models.FiatCurrency(
            symbol: 'EUR',
            name: 'Euro',
            minPurchaseAmount: Decimal.zero,
          ),
        ),
      );
      final selectedState = await selectedStateFuture;

      expect(selectedState.selectedFiat.value?.getAbbr(), 'EUR');
      expect(await storage.read(defaultFiatPreferenceKey), 'EUR');
    });
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeStorage implements BaseStorage {
  _FakeStorage({Map<String, dynamic>? initialData})
    : _values = initialData ?? <String, dynamic>{};

  final Map<String, dynamic> _values;

  @override
  Future<bool> delete(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<dynamic> read(String key) async => _values[key];

  @override
  Future<bool> write(String key, dynamic data) async {
    _values[key] = data;
    return true;
  }
}

class _UnusedFiatRepository implements FiatRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCoinsRepo implements CoinsRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSdk implements KomodoDefiSdk {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
