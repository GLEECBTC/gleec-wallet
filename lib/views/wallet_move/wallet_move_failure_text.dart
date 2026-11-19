import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';

/// What went wrong with a scanned move code and what to do next, worded for
/// the phone that scanned it: the new phone reads replies, the old one offers.
String walletMoveFailureText(
  WalletMoveFailure failure, {
  required bool onNewPhone,
}) {
  final key = switch (failure) {
    WalletMoveFailure.notAMoveCode =>
      onNewPhone
          ? 'walletMoveFailureNotMoveCodeNew'
          : 'walletMoveFailureNotMoveCodeOld',
    WalletMoveFailure.wrongStep =>
      onNewPhone
          ? 'walletMoveFailureWrongStepNew'
          : 'walletMoveFailureWrongStepOld',
    WalletMoveFailure.unsupportedVersion => 'walletMoveFailureVersion',
    WalletMoveFailure.damaged => 'walletMoveFailureDamaged',
    // Only an offer can expire or belong to another device; the old phone
    // hears of either only through a stale code.
    WalletMoveFailure.expired =>
      onNewPhone ? 'walletMoveFailureExpired' : 'walletMoveFailureStaleOffer',
    WalletMoveFailure.notForThisDevice =>
      onNewPhone
          ? 'walletMoveFailureNotForThisPhone'
          : 'walletMoveFailureStaleOffer',
  };
  return key.tr();
}
