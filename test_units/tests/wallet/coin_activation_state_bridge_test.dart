import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coin_activation_state_bridge.dart';
import 'package:web_dex/model/coin.dart';

Map<String, dynamic> _utxoConfig({String coin = 'KMD'}) => {
  'coin': coin,
  'type': 'UTXO',
  'name': coin,
  'fname': coin,
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'",
  'protocol': {'type': 'UTXO'},
};

Coin _coin(String id, CoinState state) => Asset.fromJson(
  _utxoConfig(coin: id),
  knownIds: const {},
).toCoin().copyWith(state: state);

/// The bridge merges the SDK's authoritative activation state with the app-only
/// states the SDK has no vocabulary for.
///
/// Three app flows would regress without suppression and republish, because
/// `deactivateCoinsSync` deliberately leaves the coin *enabled in KDF* and the
/// SDK emits nothing at all for an asset that is already active.
void testCoinActivationStateBridge() {
  group('CoinActivationStateBridge', () {
    late StreamController<Coin> sdk;
    late List<Coin> snapshot;
    late CoinActivationStateBridge bridge;

    setUp(() {
      sdk = StreamController<Coin>.broadcast();
      snapshot = <Coin>[];
      bridge = CoinActivationStateBridge(
        sdkStates: sdk.stream,
        sdkSnapshot: () => snapshot,
      );
      addTearDown(bridge.dispose);
    });

    test('replays current state to a late subscriber', () async {
      sdk.add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.abbr, 'KMD');
      expect(seen.single.isActive, isTrue);
    });

    test('does not drop a state published while a listener attaches', () async {
      // A `yield current; yield* stream` prologue would lose this one.
      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      sdk.add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
    });

    test('suppress hides SDK events for a locally deactivated coin', () async {
      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      bridge.suppress([_coin('KMD', CoinState.active).id]);
      sdk.add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });

    test('suppress hides retained state from a late subscriber', () async {
      final kmd = _coin('KMD', CoinState.active);
      sdk.add(kmd);
      await Future<void>.delayed(Duration.zero);
      bridge.suppress([kmd.id]);

      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });

    test('release republishes, so re-enabling produces a row', () async {
      // The SDK emits no delta for an already-active asset, so without the
      // republish the coins manager could never bring the row back.
      final kmd = _coin('KMD', CoinState.active);
      snapshot = [kmd];
      bridge.suppress([kmd.id]);

      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);

      bridge.release([kmd.id]);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.isActive, isTrue);
    });

    test('an app state is superseded by a later SDK event', () async {
      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      bridge.publishAppState(_coin('KMD', CoinState.suspended));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.isSuspended, isTrue);

      // KDF turned out to have enabled it after the app gave up.
      sdk.add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.isActive, isTrue);
    });

    test('identical states are not republished', () async {
      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      sdk
        ..add(_coin('KMD', CoinState.active))
        ..add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
    });

    test('reset forgets everything and re-primes from the SDK', () async {
      sdk.add(_coin('KMD', CoinState.active));
      await Future<void>.delayed(Duration.zero);

      // The incoming wallet has a different coin enabled.
      snapshot = [_coin('BTC', CoinState.active)];
      bridge.reset();

      final seen = <Coin>[];
      final sub = bridge.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((coin) => coin.abbr), ['BTC']);
    });
  });
}

void main() {
  testCoinActivationStateBridge();
}
