import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

class KdfWalletIdentitySource implements GnosisWalletIdentitySource {
  const KdfWalletIdentitySource(this._sdk);

  final KomodoDefiSdk _sdk;

  @override
  Future<String?> currentWalletId() async =>
      (await _sdk.auth.currentUser)?.walletId.compoundId;

  @override
  Stream<String?> watchWalletId() => _sdk.auth
      .watchCurrentUser()
      .map((user) => user?.walletId.compoundId)
      .distinct();
}
