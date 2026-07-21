import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

/// Adapter around the existing KDF EIP-191 and smart-account RPCs.
/// There is deliberately no synthetic signature fallback.
class KdfSmartAccountSigner
    implements SmartAccountSigner, GnosisWalletReadiness {
  KdfSmartAccountSigner(
    this._sdk, {
    required CoinsRepo coinsRepository,
    this.coin = const String.fromEnvironment(
      'GNOSIS_CARD_COIN',
      defaultValue: 'GNO-GNO',
    ),
  }) : _coinsRepository = coinsRepository;

  final KomodoDefiSdk _sdk;
  final CoinsRepo _coinsRepository;
  final String coin;

  Asset? _asset;
  PubkeyInfo? _ownerKey;
  SmartAccountOwner? _readyOwner;
  Future<SmartAccountOwner>? _readinessFlight;
  var _readinessGeneration = 0;

  @override
  void invalidate() {
    _readinessGeneration += 1;
    _readinessFlight = null;
    _asset = null;
    _ownerKey = null;
    _readyOwner = null;
  }

  @override
  Future<SmartAccountOwner> ensureReady() {
    final ready = _readyOwner;
    if (ready != null) return Future.value(ready);
    final active = _readinessFlight;
    if (active != null) return active;
    late final Future<SmartAccountOwner> flight;
    final generation = _readinessGeneration;
    flight = _ensureReady(generation).whenComplete(() {
      if (identical(_readinessFlight, flight)) _readinessFlight = null;
    });
    _readinessFlight = flight;
    return flight;
  }

  Future<SmartAccountOwner> _ensureReady(int generation) async {
    final asset = _sdk.assets.available.values
        .where((candidate) => candidate.id.id == coin)
        .firstOrNull;
    if (asset == null) {
      throw GnosisCardUnavailable(
        'The Gnosis Chain signer is unavailable in this wallet.',
      );
    }
    if (asset.id.chainId.formattedChainId != '100') {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.wrongChain,
        message: 'The configured card signer is not on Gnosis Chain.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    final parentId = asset.id.parentId;
    final parent = parentId == null ? null : _sdk.assets.available[parentId];
    if (parentId?.id != 'XDAI' ||
        parent == null ||
        parent.id.chainId.formattedChainId != '100') {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.wrongChain,
        message: 'The Gnosis Chain parent asset is missing or invalid.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    await _coinsRepository.activateAssetsSync(
      [parent, asset],
      maxRetryAttempts: 5,
      initialRetryDelay: const Duration(milliseconds: 500),
      maxRetryDelay: const Duration(seconds: 4),
    );
    final activationChecks = await Future.wait([
      _coinsRepository.isAssetActivated(parent.id, forceRefresh: true),
      _coinsRepository.isAssetActivated(asset.id, forceRefresh: true),
    ]);
    if (activationChecks.any((isActivated) => !isActivated)) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.activationFailed,
        message: 'Gnosis Chain could not be prepared for card signing.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final pubkeys = await _sdk.pubkeys.getPubkeys(asset);
    if (pubkeys.keys.isEmpty) {
      throw const GnosisCardUnavailable(
        'KDF did not return an owner address for card signing.',
      );
    }
    final key =
        pubkeys.keys.where((value) => value.isActiveForSwap).firstOrNull ??
        pubkeys.keys.first;
    if (generation != _readinessGeneration) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed while preparing Gnosis Chain.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    _asset = asset;
    _ownerKey = key;
    return _readyOwner = SmartAccountOwner(
      address: key.address,
      coin: asset.id.id,
      derivationPath: key.derivationPath,
    );
  }

  @override
  Future<SmartAccountOwner> owner() => ensureReady();

  @override
  Future<String> signPersonalMessage(
    String message, {
    required SmartAccountOwner expectedOwner,
  }) async {
    final identity = await owner();
    final asset = _asset;
    final key = _ownerKey;
    if (asset == null ||
        key == null ||
        identity.address.toLowerCase() != key.address.toLowerCase() ||
        identity.address.toLowerCase() != expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable('KDF signer identity changed.');
    }
    final signature = await _sdk.messageSigning.signMessage(
      asset: asset,
      addressInfo: key,
      message: message,
    );
    final currentOwner = await owner();
    if (currentOwner.address.toLowerCase() !=
        expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF signer identity changed during approval.',
      );
    }
    return signature;
  }

  @override
  Future<void> registerSafe(
    String safeAddress, {
    required SmartAccountOwner expectedOwner,
  }) async {
    final identity = await owner();
    if (identity.address.toLowerCase() != expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF signer identity changed before card account registration.',
      );
    }
    final response = await _sdk.client.rpc.smartAccount.register(
      coin: identity.coin,
      safeAddress: safeAddress,
      from: _addressPath(identity),
    );
    if (response.smartAccountAddress.toLowerCase() !=
            safeAddress.toLowerCase() ||
        response.ownerAddress.toLowerCase() !=
            expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF registered a different Safe or owner than requested.',
      );
    }
    final currentOwner = await owner();
    if (currentOwner.address.toLowerCase() !=
        expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF signer identity changed during card account registration.',
      );
    }
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent, {
    required SmartAccountOwner expectedOwner,
  }) async {
    final identity = await owner();
    if (identity.address.toLowerCase() != expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF signer identity changed before card approval.',
      );
    }
    final response = await _sdk.client.rpc.smartAccount.signTypedData(
      coin: identity.coin,
      intent: intent,
      from: _addressPath(identity),
    );
    if (response.verifyingContract.toLowerCase() !=
            intent.delayModule.toLowerCase() ||
        response.ownerAddress.toLowerCase() !=
            expectedOwner.address.toLowerCase() ||
        !response.typedDataHash.startsWith('0x') ||
        response.signature.isEmpty) {
      throw const GnosisCardUnavailable(
        'KDF signed response did not match the reviewed intent.',
      );
    }
    final currentOwner = await owner();
    if (currentOwner.address.toLowerCase() !=
        expectedOwner.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF signer identity changed during card approval.',
      );
    }
    return SmartAccountSignature(
      signature: response.signature,
      typedDataHash: response.typedDataHash,
      ownerAddress: response.ownerAddress,
    );
  }

  AddressPath? _addressPath(SmartAccountOwner identity) =>
      identity.derivationPath == null
      ? null
      : AddressPath.derivationPath(identity.derivationPath!);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
