enum CoinPageType {
  send,

  /// Per-source native transfer wizard moving funded Standard EOAs into the
  /// user's canonical GasFree custody address. Every source is previewed and
  /// confirmed independently because its TRX balance pays its own network fee.
  sendConsolidate,
  claim,
  info,
  claimSuccess,
}
