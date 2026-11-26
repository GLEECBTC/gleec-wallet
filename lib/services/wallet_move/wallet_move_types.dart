import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

/// Why a move code was refused. Each maps to one message and one next step.
enum WalletMoveFailure {
  /// A QR code from something else: an address, a link, another app.
  notAMoveCode,

  /// A move code for the other device: the new phone scanned its own kind.
  wrongStep,

  /// Made by a newer app version.
  unsupportedVersion,

  /// The new device's code timed out; it shows a fresh one.
  expired,

  /// Truncated or altered on the way.
  damaged,

  /// Sealed for a different new device or an earlier code.
  notForThisDevice,
}

final class WalletMoveException implements Exception {
  const WalletMoveException(this.failure);

  final WalletMoveFailure failure;

  @override
  String toString() => 'WalletMoveException(${failure.name})';
}

/// The new device's half of a move: [code] is shown for the old device to
/// scan, then [open] reads the old device's reply. Single use; [dispose]
/// forgets its key after success, cancellation or expiry.
abstract interface class WalletMoveOffer {
  String get code;
  DateTime get expiresAt;

  /// Throws [WalletMoveException]; never returns a partial secret.
  WalletTransferSecret open(String replyCode);

  void dispose();
}

/// Moves a wallet by two QR scans with no network: the new device shows a
/// one-time public key, the old device scans it and shows the wallet sealed
/// to that key, and the new device scans that.
abstract interface class WalletMoveProtocol {
  WalletMoveOffer createOffer();

  /// Throws [WalletMoveException] unless [offerCode] is a well-formed offer,
  /// so the old phone can refuse a code before it asks for the wallet's lock.
  /// Does no cryptography and seals nothing.
  void checkOffer(String offerCode);

  /// Seals [secret] for the device that showed [offerCode]. Throws
  /// [WalletMoveException] when [offerCode] is not a current offer.
  String seal({
    required String offerCode,
    required WalletTransferSecret secret,
  });

  /// Eight digits derived from [replyCode], shown beside it on the old phone
  /// and on the new phone's review. Anyone who saw the new phone's code can
  /// seal a wallet of their own to it; matching digits prove the reply the
  /// new phone read is the one the user's old phone made. Deliberately slow
  /// (memory-hard, off the UI thread) so nobody can try replies until one
  /// matches. Throws [WalletMoveException] for anything but a well-formed
  /// reply, before any work.
  Future<String> checkCode(String replyCode);
}
