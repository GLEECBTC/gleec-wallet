/// Legacy coin "type" used as a compatibility layer while migrating the app
/// to the SDK's `CoinSubClass`/`AssetId.subClass` protocol model.
///
/// New features and UI should avoid depending on [CoinType] directly and
/// instead use SDK metadata. This enum exists only to keep older code paths
/// working until they can be refactored.
// anchor: protocols support
enum CoinType {
  utxo,
  trx,
  trc20,
  smartChain,
  etc,
  erc20,
  bep20,
  qrc20,
  ftm20,
  arb20,
  base20,
  avx20,
  hrc20,
  mvr20,
  hco20,
  plg20,
  sbch,
  ubiq,
  krc20,
  grc20,
  tendermintToken,
  tendermint,
  slp,
  zhtlc,

  /// Legacy glue for the Sia protocol (`CoinSubClass.sia`).
  sia,
}
