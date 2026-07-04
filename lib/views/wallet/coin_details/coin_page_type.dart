enum CoinPageType {
  send,

  /// One-time native transfer moving stranded standard-address (EOA) funds of
  /// a gasless asset into the user's own GasFree custody address. Opens the
  /// send form prefilled: recipient = custody address, native rail, max.
  sendConsolidate,
  claim,
  info,
  claimSuccess,
}
