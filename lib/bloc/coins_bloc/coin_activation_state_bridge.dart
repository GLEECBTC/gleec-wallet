import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';

/// Single ordered channel for "what activation state is this coin in".
///
/// Merges two sources, neither of which can answer alone:
///
/// * **the SDK's activation-state stream** — authoritative for "KDF has this
///   enabled", and the only source that sees activations the SDK performs on
///   its own behalf (pubkey, balance, withdrawal and transaction-history
///   managers all activate assets without telling the app);
/// * **app-authored states** the SDK has no vocabulary for — see
///   [publishAppState].
///
/// Replayable: a late subscriber receives the current state of every known
/// asset before any delta. That is what lets [CoinsRepo] drop the
/// listener-count drop guard it used to need, and it is the property whose
/// absence left wallet rows stuck on `activating` for a whole session.
class CoinActivationStateBridge {
  /// Creates a bridge over [sdkStates], falling back to [sdkSnapshot] when the
  /// mirror has to be rebuilt.
  CoinActivationStateBridge({
    required Stream<Coin> sdkStates,
    required Iterable<Coin> Function() sdkSnapshot,
  }) : _sdkSnapshot = sdkSnapshot {
    _subscription = sdkStates.listen(_onSdkState);
  }

  final Iterable<Coin> Function() _sdkSnapshot;
  StreamSubscription<Coin>? _subscription;

  final StreamController<Coin> _controller = StreamController<Coin>.broadcast();

  /// Last published state per asset, so [watch] can replay.
  final Map<AssetId, Coin> _lastKnown = {};

  /// Assets whose SDK events are currently ignored. See [suppress].
  final Set<AssetId> _suppressed = <AssetId>{};

  /// Current state of every known asset, then every subsequent change.
  Stream<Coin> watch() {
    late final StreamController<Coin> out;
    StreamSubscription<Coin>? subscription;

    out = StreamController<Coin>(
      onListen: () {
        // Subscribe first, replay second. A `yield current; yield* stream`
        // prologue looks equivalent but is not: the `yield*` only attaches
        // after the replay drains, and anything published in that window is
        // dropped by the unbuffered broadcast controller underneath. That is
        // the very class of loss this bridge exists to prevent.
        subscription = _controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        for (final coin in List<Coin>.of(_lastKnown.values)) {
          if (_suppressed.contains(coin.id)) continue;
          out.add(coin);
        }
      },
      onCancel: () => subscription?.cancel(),
    );

    return out.stream;
  }

  /// Last published state for [assetId], or null if it has never been seen.
  Coin? lastKnownFor(AssetId assetId) => _lastKnown[assetId];

  /// Publishes a state the SDK cannot know about.
  ///
  /// Wins immediately. A later SDK event for the same asset supersedes it,
  /// deliberately: if KDF really did enable the coin after the app gave up,
  /// the row must come back.
  void publishAppState(Coin coin) => _publish(coin);

  /// Stops SDK events for [assetIds] reaching subscribers.
  ///
  /// Two flows need this, and both would otherwise regress:
  ///
  /// * **local deactivation** — `deactivateCoinsSync` deliberately does *not*
  ///   disable the coin in KDF, so the SDK keeps reporting it active and would
  ///   put the row straight back;
  /// * **custom-token import preview** — the token is activated only so its
  ///   balance can be read, and must not appear in the user's wallet.
  void suppress(Iterable<AssetId> assetIds) => _suppressed.addAll(assetIds);

  /// Lifts suppression and republishes each asset's current SDK state.
  ///
  /// The republish is not optional. The SDK emits no event for an asset that
  /// is *already* active, so re-enabling a locally-deactivated coin, or
  /// confirming a previewed custom token, would otherwise never produce a row.
  void release(Iterable<AssetId> assetIds) {
    _suppressed.removeAll(assetIds);
    republish(assetIds);
  }

  /// Re-emits the SDK's current state for [assetIds].
  void republish(Iterable<AssetId> assetIds) {
    final wanted = assetIds.toSet();
    if (wanted.isEmpty) return;
    for (final coin in _sdkSnapshot()) {
      if (!wanted.contains(coin.id)) continue;
      // The UI may have removed the coin without publishing an inactive
      // state (deactivateCoinsSync with notify: false). An explicit replay
      // must reach that UI even when the retained SDK state is unchanged.
      _publish(coin, force: true);
    }
  }

  /// Wallet change: forget everything and re-prime from the SDK.
  ///
  /// A plain clear is not enough. This bridge holds one long-lived
  /// subscription and will never receive a second replay prologue, so without
  /// re-priming the app would forget whatever KDF already has enabled for the
  /// incoming wallet.
  void reset() {
    _lastKnown.clear();
    _suppressed.clear();
    for (final coin in _sdkSnapshot()) {
      _publish(coin);
    }
  }

  void _onSdkState(Coin coin) {
    if (_suppressed.contains(coin.id)) return;
    _publish(coin);
  }

  void _publish(Coin coin, {bool force = false}) {
    if (!force && _lastKnown[coin.id] == coin) return;
    _lastKnown[coin.id] = coin;
    if (!_controller.isClosed) _controller.add(coin);
  }

  /// Releases the SDK subscription and closes the outbound stream.
  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _controller.close();
  }
}
