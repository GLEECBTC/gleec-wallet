part of 'swap_accessibility_test.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Services implements SwapServices {
  _Services(this.registry, this._activated);

  @override
  final SwapExecutionRegistry registry;

  final Set<AssetId> _activated;
  Map<AssetId, Decimal> balances = {};
  Map<AssetId, Decimal> elsewhere = {};

  @override
  final Set<String> viewing = {};

  @override
  late final SwapPreferences preferences = SwapPreferences(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  @override
  SwapNetworks networks() => SwapNetworks([eth, usdc, btc]);

  @override
  Future<Set<AssetId>> activatedAssets() async => _activated;

  /// Never finishes, so a test sees the picker mid-activation.
  @override
  Future<void> activate(AssetId id) => Completer<void>().future;

  @override
  bool isTestnet(AssetId id) => false;

  @override
  AssetId? resolveAsset(String ticker) => null;

  @override
  Decimal? usdPrice(AssetId id) => id == eth ? d('3000') : null;

  @override
  Decimal? lastKnownBalance(AssetId id) => balances[id];

  @override
  Decimal? spendableElsewhere(AssetId id) => elsewhere[id];

  @override
  String? contractOf(AssetId id) => null;

  @override
  Uri? explorerTxUrl(AssetId? asset, String hash) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets the clipboard accept copies in the current test.
void _acceptClipboard(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}
