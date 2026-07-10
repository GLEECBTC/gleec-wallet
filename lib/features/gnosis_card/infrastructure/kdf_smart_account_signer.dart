import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

/// Adapter around the existing KDF EIP-191 and smart-account RPCs.
/// There is deliberately no synthetic signature fallback.
class KdfSmartAccountSigner implements SmartAccountSigner {
  KdfSmartAccountSigner(
    this._sdk, {
    this.coin = const String.fromEnvironment(
      'GNOSIS_CARD_COIN',
      defaultValue: 'GNO',
    ),
  });

  final KomodoDefiSdk _sdk;
  final String coin;

  Asset? _asset;
  PubkeyInfo? _ownerKey;

  @override
  Future<SmartAccountOwner> owner() async {
    final asset = _sdk.assets.available.values
        .where((candidate) => candidate.id.id == coin)
        .firstOrNull;
    if (asset == null) {
      throw GnosisCardUnavailable(
        '$coin must be available and activated before using card signing.',
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
    _asset = asset;
    _ownerKey = key;
    return SmartAccountOwner(
      address: key.address,
      coin: asset.id.id,
      derivationPath: key.derivationPath,
    );
  }

  @override
  Future<String> signPersonalMessage(String message) async {
    final identity = await owner();
    final asset = _asset;
    final key = _ownerKey;
    if (asset == null || key == null || identity.address != key.address) {
      throw const GnosisCardUnavailable('KDF signer identity changed.');
    }
    return _sdk.messageSigning.signMessage(
      asset: asset,
      addressInfo: key,
      message: message,
    );
  }

  @override
  Future<void> registerSafe(String safeAddress) async {
    final identity = await owner();
    final response = await _sdk.client.rpc.smartAccount.register(
      coin: identity.coin,
      safeAddress: safeAddress,
      from: _addressPath(identity),
    );
    if (response.smartAccountAddress.toLowerCase() !=
            safeAddress.toLowerCase() ||
        response.ownerAddress.toLowerCase() != identity.address.toLowerCase()) {
      throw const GnosisCardUnavailable(
        'KDF registered a different Safe or owner than requested.',
      );
    }
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent,
  ) async {
    final identity = await owner();
    final response = await _sdk.client.rpc.smartAccount.signTypedData(
      coin: identity.coin,
      intent: intent,
      from: _addressPath(identity),
    );
    if (response.verifyingContract.toLowerCase() !=
            intent.delayModule.toLowerCase() ||
        response.ownerAddress.toLowerCase() != identity.address.toLowerCase() ||
        !response.typedDataHash.startsWith('0x') ||
        response.signature.isEmpty) {
      throw const GnosisCardUnavailable(
        'KDF signed response did not match the reviewed intent.',
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
