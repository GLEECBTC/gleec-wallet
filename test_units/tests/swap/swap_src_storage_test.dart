import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers what the swap form remembers per wallet — the last pair, recent
/// assets, the zero-balance switch and acceptance of the routing provider's
/// terms — and that a record it cannot read counts as nothing remembered.
void main() {
  late MemoryStorage storage;
  late String? wallet;

  setUp(() {
    storage = MemoryStorage();
    wallet = 'w1';
  });

  SwapPreferences preferences() =>
      SwapPreferences(walletKey: () async => wallet, storage: storage);

  SwapTermsRepository terms({BaseStorage? store}) => SwapTermsRepository(
    walletKey: () async => wallet,
    storage: store ?? storage,
  );

  group('the last pair', () {
    test('is remembered per wallet', () async {
      await preferences().rememberPair(eth, usdc);

      expect(await preferences().lastPair(), (from: 'ETH', to: 'USDC-ERC20'));
      wallet = 'w2';
      expect(await preferences().lastPair(), isNull);
    });

    test('reads a record already decoded, and nothing malformed', () async {
      const key = 'swap_last_pair_v1:w1';
      Future<({String from, String to})?> read(Object value) async {
        storage.values[key] = value;
        return preferences().lastPair();
      }

      expect(await read({'from': 'BTC', 'to': 'ETH'}), (
        from: 'BTC',
        to: 'ETH',
      ));
      expect(await read(['BTC', 'ETH']), isNull);
      expect(await read({'from': 1, 'to': 'ETH'}), isNull);
      expect(await read('{not json'), isNull);
    });
  });

  group('recent assets', () {
    test('most recent first, never twice, eight at most', () async {
      final prefs = preferences();
      for (var i = 0; i < 10; i++) {
        await prefs.rememberAsset(assetOf('A$i'));
      }
      await prefs.rememberAsset(assetOf('A5'));

      expect(await prefs.recentAssets(), [
        'A5',
        'A9',
        'A8',
        'A7',
        'A6',
        'A4',
        'A3',
        'A2',
      ]);
      expect(SwapPreferences.maxRecent, 8);
    });

    test('keep only the tickers of whatever was stored', () async {
      const key = 'swap_recent_assets_v1:w1';
      Future<List<String>> read(Object value) async {
        storage.values[key] = value;
        return preferences().recentAssets();
      }

      expect(await read(['ETH', 3, null, 'BTC']), ['ETH', 'BTC']);
      expect(await read(jsonEncode(['GLEEC'])), ['GLEEC']);
      expect(await read({'ETH': true}), isEmpty);
      expect(await read('[broken'), isEmpty);
    });
  });

  group('hiding assets without a balance', () {
    test('is off until turned on, and stays as set', () async {
      final prefs = preferences();
      expect(await prefs.hideZeroBalances(), isFalse);

      await prefs.rememberHideZeroBalances(true);
      expect(await prefs.hideZeroBalances(), isTrue);

      await prefs.rememberHideZeroBalances(false);
      expect(await prefs.hideZeroBalances(), isFalse);
    });

    test('reads a decoded value, and a malformed one as off', () async {
      const key = 'swap_pay_hide_zero_v1:w1';

      storage.values[key] = true;
      expect(await preferences().hideZeroBalances(), isTrue);

      storage.values[key] = 'yes';
      expect(await preferences().hideZeroBalances(), isFalse);
    });
  });

  test('without a wallet, nothing is read or remembered', () async {
    wallet = null;
    final prefs = preferences();

    await prefs.rememberPair(eth, usdc);
    await prefs.rememberAsset(eth);
    await prefs.rememberHideZeroBalances(true);
    await terms().recordAcceptance();

    expect(storage.values, isEmpty);
    expect(await prefs.lastPair(), isNull);
    expect(await prefs.recentAssets(), isEmpty);
    expect(await prefs.hideZeroBalances(), isFalse);
    expect(await terms().hasAccepted(), isFalse);
  });

  test('the default store answers nothing readable in tests', () async {
    final prefs = SwapPreferences(walletKey: () async => 'w1');
    final defaultTerms = SwapTermsRepository(walletKey: () async => 'w1');

    expect(await prefs.lastPair(), isNull);
    expect(await prefs.recentAssets(), isEmpty);
    expect(await prefs.hideZeroBalances(), isFalse);
    expect(await defaultTerms.hasAccepted(), isFalse);
  });

  group('the routing provider\'s terms', () {
    test(
      'acceptance is recorded per wallet, with whose terms and when',
      () async {
        final at = DateTime.utc(2026, 9, 24, 12);

        await terms().recordAcceptance(at: at);

        expect(await terms().hasAccepted(), isTrue);
        final stored = jsonDecode(
          storage.values['routed_swap_terms_acceptance_v1:w1'] as String,
        );
        expect(stored, {
          'version': SwapTermsRepository.currentVersion,
          'accepted_at': '2026-09-24T12:00:00.000Z',
          'provider': 'LI.FI',
          'url': SwapTermsRepository.termsUrl,
        });
        wallet = 'w2';
        expect(await terms().hasAccepted(), isFalse);
      },
    );

    test('acceptance recorded without a time is stamped now', () async {
      final before = DateTime.now();
      await terms().recordAcceptance();
      final after = DateTime.now();

      final record = SwapTermsAcceptance.tryParse(
        storage.values['routed_swap_terms_acceptance_v1:w1'],
      )!;
      expect(record.acceptedAt.isBefore(before), isFalse);
      expect(record.acceptedAt.isAfter(after), isFalse);
    });

    test('terms accepted at an older version are asked again', () async {
      storage.values['routed_swap_terms_acceptance_v1:w1'] = {
        'version': 0,
        'accepted_at': '2026-01-01T00:00:00Z',
      };

      expect(await terms().hasAccepted(), isFalse);
    });

    test('a record that cannot be read counts as not accepted', () async {
      storage.values['routed_swap_terms_acceptance_v1:w1'] = 'garbage';
      expect(await terms().hasAccepted(), isFalse);

      expect(await terms(store: _FailingStorage()).hasAccepted(), isFalse);
    });

    test('a stored record parses leniently, never guessing a version', () {
      final lenient = SwapTermsAcceptance.tryParse({
        'version': 1,
        'accepted_at': '2026-09-24T12:00:00Z',
      })!;

      expect(lenient.version, 1);
      expect(lenient.acceptedAt, DateTime.utc(2026, 9, 24, 12));
      expect(lenient.provider, '');
      expect(lenient.url, '');
      expect(
        SwapTermsAcceptance.tryParse({'version': '1', 'accepted_at': ''}),
        isNull,
      );
      expect(
        SwapTermsAcceptance.tryParse({'version': 1, 'accepted_at': 'never'}),
        isNull,
      );
      expect(SwapTermsAcceptance.tryParse(42), isNull);
    });
  });
}

class _FailingStorage implements BaseStorage {
  @override
  Future<dynamic> read(String key) => Future.error(StateError('disk error'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
