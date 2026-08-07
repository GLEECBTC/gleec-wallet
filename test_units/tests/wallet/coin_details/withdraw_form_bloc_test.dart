import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/wallet.dart';

/// [Stream.firstWhere] with a deadline.
///
/// A bare `firstWhere` never completes when the predicate is never satisfied,
/// and `flutter test`'s own per-test timeout does not rescue it here: killing
/// the tester device at that point throws during finalization
/// (`PathNotFoundException` on the listener temp dir) and wedges the *entire*
/// runner. One stuck expectation in this file therefore took the whole app
/// suite down with it, which is why `testWithdrawFormBloc()` had to be
/// commented out of `test_units/main.dart` to get any run at all.
///
/// Failing fast inside the test turns that into an ordinary, readable failure.
extension _BoundedStateWait<T> on Stream<T> {
  Future<T> firstWhereBounded(
    bool Function(T element) test, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return firstWhere(test).timeout(timeout);
  }
}

Map<String, dynamic> _utxoConfig({
  String coin = 'KMD',
  String name = 'Komodo',
}) => {
  'coin': coin,
  'type': 'UTXO',
  'name': name,
  'fname': name,
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
};

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'gasless': {'enabled': true},
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _siaConfig() => {
  'coin': 'SC',
  'type': 'SIA',
  'name': 'Siacoin',
  'fname': 'Siacoin',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 2024,
  'decimals': 24,
  'required_confirmations': 1,
  'nodes': const [
    {'url': 'https://api.siascan.com/wallet/api'},
  ],
};

BalanceInfo _balance(String amount) {
  final value = Decimal.parse(amount);
  return BalanceInfo(total: value, spendable: value, unspendable: Decimal.zero);
}

Asset _assetFromConfig(Map<String, dynamic> config) =>
    Asset.fromJson(config, knownIds: const {});

PubkeyInfo _pubkeyForAsset(
  Asset asset, {
  String address = 'source-address',
  String balance = '5',
  String? gasfreeAddress,
  String? derivationPath,
}) {
  final effectiveDerivationPath =
      derivationPath ??
      (asset.protocol is TrxProtocol || asset.protocol is Trc20Protocol
          ? "m/44'/195'/0'/0/0"
          : "m/44'/141'/0'/0/0");
  return PubkeyInfo(
    address: address,
    derivationPath: effectiveDerivationPath,
    chain: 'external',
    balance: _balance(balance),
    coinTicker: asset.id.id,
    gasfreeAddress: gasfreeAddress,
  );
}

AssetPubkeys _assetPubkeys(
  Asset asset, {
  String address = 'source-address',
  String balance = '5',
}) {
  return AssetPubkeys(
    assetId: asset.id,
    keys: [_pubkeyForAsset(asset, address: address, balance: balance)],
    availableAddressesCount: 1,
    syncStatus: SyncStatusEnum.success,
  );
}

WithdrawalPreview _utxoPreview({
  required String assetId,
  required String txHash,
  required String toAddress,
  required int timestamp,
}) {
  return WithdrawResult(
    txHex: 'signed-$txHash',
    txHash: txHash,
    from: const ['source-address'],
    to: [toAddress],
    balanceChanges: BalanceChanges(
      netChange: Decimal.fromInt(-1),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.one,
      totalAmount: Decimal.one,
    ),
    blockHeight: 1,
    timestamp: timestamp,
    fee: FeeInfo.utxoFixed(coin: assetId, amount: Decimal.parse('0.0001')),
    coin: assetId,
  );
}

WithdrawalPreview _tronPreview({
  required String txHash,
  required String toAddress,
  required int timestamp,
}) {
  return WithdrawResult(
    txHex: 'signed-$txHash',
    txHash: txHash,
    from: const ['source-address'],
    to: [toAddress],
    balanceChanges: BalanceChanges(
      netChange: Decimal.fromInt(-1),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.one,
      totalAmount: Decimal.one,
    ),
    blockHeight: 1,
    timestamp: timestamp,
    fee: FeeInfo.tron(
      coin: 'TRX',
      bandwidthUsed: 1,
      energyUsed: 1,
      bandwidthFee: Decimal.zero,
      energyFee: Decimal.parse('0.1'),
      totalFeeAmount: Decimal.parse('0.1'),
    ),
    coin: 'TRX',
  );
}

WithdrawalPreview _tronGaslessPreview({
  required String txHash,
  required String toAddress,
  required int timestamp,
  int? authorizationDeadline,
  Object? signedAuthorizationDeadline,
  bool includeAuthorizationDeadline = true,
  FeeInfo? fee,
}) {
  final resolvedDeadline =
      authorizationDeadline ??
      DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
  return WithdrawResult(
    txJson: {
      'relay_type': 'tron_gasfree',
      'chain_id': '728126428',
      'coin': 'USDT-TRC20',
      'from_address': 'source-address',
      'gasfree_address': 'gasfree-source-address',
      'verifying_contract': 'TGasFreeVerifyingContract',
      'signed_authorization': {
        'token': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'service_provider': 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
        'user': 'gasfree-source-address',
        'receiver': toAddress,
        'value': '1000000',
        'max_fee': '1000000',
        if (includeAuthorizationDeadline)
          'deadline': signedAuthorizationDeadline ?? '$resolvedDeadline',
        'version': '1',
        'nonce': '1',
        'sig': List<String>.filled(130, 'a').join(),
      },
      'created_at': DateTime.fromMillisecondsSinceEpoch(
        timestamp * Duration.millisecondsPerSecond,
        isUtc: true,
      ).toIso8601String(),
    },
    txHash: txHash,
    from: const ['source-address'],
    to: [toAddress],
    balanceChanges: BalanceChanges(
      netChange: Decimal.fromInt(-1),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.one,
      totalAmount: Decimal.one,
    ),
    blockHeight: 1,
    timestamp: timestamp,
    fee:
        fee ??
        FeeInfo.tronGasless(
          coin: 'USDT-TRC20',
          feeMethod: 'gasless',
          providerName: 'gasfree',
          gasfreeAddress: 'gasfree-source-address',
          transferFee: Decimal.parse('1'),
          totalTokenFee: Decimal.parse('1'),
          signedMaxFee: Decimal.parse('1'),
        ),
    coin: 'USDT-TRC20',
  );
}

/// TRC-20 assets need their parent (TRX) in `knownIds` to resolve `parentId`.
Asset _trc20Asset() {
  final parent = _assetFromConfig(_trxConfig());
  return Asset.fromJson(_trc20Config(), knownIds: {parent.id});
}

GaslessAccountStatusResponse _gaslessStatus({
  GaslessAccountAvailability availability =
      GaslessAccountAvailability.available,
  bool active = true,
  String onChain = '100',
  String maxWithdrawable = '99',
  String transferFee = '1',
  String? activationFee,
  String frozen = '0',
  String? spendable,
  String gasfreeAddress = 'gasfree-source-address',
}) {
  const serviceProvider = 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird';
  return GaslessAccountStatusResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'gasfree_address': gasfreeAddress,
      'on_chain_balance': onChain,
      'availability': availability.wireValue,
      'service_provider':
          availability == GaslessAccountAvailability.providerUnreachable
          ? null
          : serviceProvider,
      'active':
          availability == GaslessAccountAvailability.available ||
              availability == GaslessAccountAvailability.pendingTransfer
          ? active
          : null,
      'transfer_fee':
          availability == GaslessAccountAvailability.available ||
              availability == GaslessAccountAvailability.pendingTransfer
          ? transferFee
          : null,
      'activation_fee':
          availability == GaslessAccountAvailability.available ||
              availability == GaslessAccountAvailability.pendingTransfer
          ? activationFee
          : null,
      'frozen_balance':
          availability == GaslessAccountAvailability.available ||
              availability == GaslessAccountAvailability.pendingTransfer
          ? frozen
          : null,
      'spendable_balance':
          availability == GaslessAccountAvailability.available ||
              availability == GaslessAccountAvailability.pendingTransfer
          ? spendable ?? onChain
          : null,
      'max_withdrawable': availability == GaslessAccountAvailability.available
          ? maxWithdrawable
          : null,
    },
  });
}

PendingGaslessTransfer _pendingGaslessTransfer({
  String? traceId = 'trace-pending',
  GaslessTransferState state = GaslessTransferState.submittedUnknown,
}) {
  final now = DateTime.utc(2026, 7, 10, 12);
  return PendingGaslessTransfer(
    traceId: traceId,
    journalId: 'journal-pending',
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: 'source-address',
    custodyAddress: 'gasfree-source-address',
    destinationAddress: 'recipient-address',
    requestedAmount: Decimal.parse('4'),
    signedMaxFee: Decimal.one,
    authorizationDeadline: BigInt.from(
      now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
    ),
    balanceChanges: BalanceChanges(
      netChange: Decimal.fromInt(-5),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.fromInt(5),
      totalAmount: Decimal.fromInt(4),
    ),
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'gasfree-source-address',
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.one,
    ),
    acceptedAt: now,
    updatedAt: now,
    state: state,
  );
}

/// Builds a TRC-20 bloc whose single source address carries a GasFree custody
/// address, mirroring the production gasless setup.
WithdrawFormBloc _buildTrc20Bloc({
  required Asset asset,
  required _FakeWithdrawalManager withdrawals,
  Map<AssetId, BalanceInfo>? balances,
  WalletType? walletType = WalletType.hdwallet,
  String? initialRecipient,
  bool initialGaslessEnabled = true,
  bool initialIsMax = false,
  bool lockSourceSelection = false,
  String pubkeyBalance = '5',
  bool stubAvailableGaslessStatus = true,
  WithdrawalAuthorizationGuard? authorizationGuard,
  String? authorizationFailureMessage,
}) {
  if (stubAvailableGaslessStatus) {
    withdrawals.gaslessAccountStatusHandler ??= (_) async => _gaslessStatus();
  }
  final parentId = asset.id.parentId;
  final parentAsset = parentId == null
      ? null
      : _assetFromConfig(
          asset.protocol.isTestnet ? _trxConfig() : _trxConfig(),
        );
  final parentBalance = parentId == null
      ? null
      : balances?[parentId] ?? BalanceInfo.zero();
  final tokenSource = _pubkeyForAsset(
    asset,
    balance: pubkeyBalance,
    gasfreeAddress: 'gasfree-source-address',
  );
  final pubkeys = AssetPubkeys(
    assetId: asset.id,
    keys: [tokenSource],
    availableAddressesCount: 1,
    syncStatus: SyncStatusEnum.success,
  );
  final pubkeysByAssetId = <AssetId, AssetPubkeys>{asset.id: pubkeys};
  if (parentAsset != null && parentId != null) {
    pubkeysByAssetId[parentId] = AssetPubkeys(
      assetId: parentId,
      keys: [
        _pubkeyForAsset(
          parentAsset,
          address: 'source-address',
          balance: parentBalance!.spendable.toString(),
        ),
      ],
      availableAddressesCount: 1,
      syncStatus: SyncStatusEnum.success,
    );
  }
  return WithdrawFormBloc(
    asset: asset,
    sdk: _FakeSdk(
      addresses: _FakeAddressOperations(),
      withdrawals: withdrawals,
      pubkeys: _FakePubkeyManager(pubkeysByAssetId),
      balances: _FakeBalanceManager(
        balances ?? {asset.id: _balance(pubkeyBalance)},
      ),
      assets: _FakeAssetManager({
        if (parentAsset != null) parentAsset.id: parentAsset,
      }),
    ),
    mm2Api: _FakeMm2Api(),
    walletType: walletType,
    initialRecipient: initialRecipient,
    initialSourceAddress: lockSourceSelection ? tokenSource : null,
    initialGaslessEnabled: initialGaslessEnabled,
    initialIsMax: initialIsMax,
    lockSourceSelection: lockSourceSelection,
    gaslessFeatureConfigured: true,
    authorizationGuard: authorizationGuard,
    authorizationFailureMessage: authorizationFailureMessage,
  );
}

WithdrawalFeeOptions _utxoFeeOptions(String assetId) {
  WithdrawalFeeOption option(WithdrawalFeeLevel priority, String amount) {
    return WithdrawalFeeOption(
      priority: priority,
      feeInfo: FeeInfo.utxoFixed(coin: assetId, amount: Decimal.parse(amount)),
    );
  }

  return WithdrawalFeeOptions(
    coin: assetId,
    low: option(WithdrawalFeeLevel.low, '0.00001'),
    medium: option(WithdrawalFeeLevel.medium, '0.00002'),
    high: option(WithdrawalFeeLevel.high, '0.00003'),
  );
}

WithdrawalResult _resultFromPreview(
  WithdrawalPreview preview, {
  Decimal? gaslessFinalFee,
  String? gaslessTraceId,
}) {
  return WithdrawalResult(
    txHash: preview.txHash,
    balanceChanges: preview.balanceChanges,
    coin: preview.coin,
    toAddress: preview.to.first,
    fee: preview.fee,
    gaslessFinalFee: gaslessFinalFee,
    gaslessTraceId: gaslessTraceId,
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _awaitSourceSelection(WithdrawFormBloc bloc) async {
  if (bloc.state.selectedSourceAddress != null) {
    return;
  }
  await bloc.stream.firstWhereBounded((state) => state.selectedSourceAddress != null);
}

Future<void> _primeFillState(
  WithdrawFormBloc bloc, {
  required String recipient,
  required String amount,
}) async {
  await _awaitSourceSelection(bloc);

  final recipientState = bloc.stream.firstWhereBounded(
    (state) => state.recipientAddress == recipient,
  );
  bloc.add(WithdrawFormRecipientChanged(recipient));
  await recipientState;

  final amountState = bloc.stream.firstWhereBounded((state) => state.amount == amount);
  bloc.add(WithdrawFormAmountChanged(amount));
  await amountState;
}

class _FakeAddressOperations implements AddressOperations {
  _FakeAddressOperations({this.validateAddressHandler});

  final Future<AddressValidation> Function({
    required Asset asset,
    required String address,
  })?
  validateAddressHandler;

  @override
  Future<AddressValidation> validateAddress({
    required Asset asset,
    required String address,
  }) {
    return validateAddressHandler?.call(asset: asset, address: address) ??
        Future<AddressValidation>.value(
          AddressValidation(isValid: true, address: address, asset: asset),
        );
  }

  @override
  Future<AddressConversionResult> convertFormat({
    required Asset asset,
    required String address,
    required AddressFormat format,
  }) {
    return Future<AddressConversionResult>.value(
      AddressConversionResult(
        originalAddress: address,
        convertedAddress: address,
        asset: asset,
        format: format,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWithdrawalManager implements WithdrawalManager {
  _FakeWithdrawalManager({
    required Future<WithdrawalPreview> Function(WithdrawParameters params)
    previewWithdrawalHandler,
    Future<WithdrawalFeeOptions?> Function(String assetId)?
    getFeeOptionsHandler,
    Stream<WithdrawalProgress> Function(
      WithdrawalPreview preview,
      String assetId,
    )?
    executeWithdrawalHandler,
    Future<List<PendingGaslessTransfer>> Function()?
    listPendingGaslessTransfersHandler,
    Stream<WithdrawalProgress> Function(String traceId)?
    resumePendingGaslessTransferHandler,
  }) : _previewWithdrawalHandler = previewWithdrawalHandler,
       _getFeeOptionsHandler = getFeeOptionsHandler,
       _executeWithdrawalHandler = executeWithdrawalHandler,
       _listPendingGaslessTransfersHandler = listPendingGaslessTransfersHandler,
       _resumePendingGaslessTransferHandler =
           resumePendingGaslessTransferHandler;

  final Future<WithdrawalPreview> Function(WithdrawParameters params)
  _previewWithdrawalHandler;
  final Future<WithdrawalFeeOptions?> Function(String assetId)?
  _getFeeOptionsHandler;
  final Stream<WithdrawalProgress> Function(
    WithdrawalPreview preview,
    String assetId,
  )?
  _executeWithdrawalHandler;
  final Future<List<PendingGaslessTransfer>> Function()?
  _listPendingGaslessTransfersHandler;
  final Stream<WithdrawalProgress> Function(String traceId)?
  _resumePendingGaslessTransferHandler;

  int previewCallCount = 0;
  int executeCallCount = 0;
  int pendingListCallCount = 0;
  int pendingResumeCallCount = 0;
  final List<WithdrawParameters> previewRequests = <WithdrawParameters>[];

  /// Stub for `gasless::account_status`. When null the call throws, which the
  /// bloc must swallow (fetch failure degrades silently).
  Future<GaslessAccountStatusResponse> Function(AssetId assetId)?
  gaslessAccountStatusHandler;
  int gaslessStatusCallCount = 0;

  @override
  Future<GaslessAccountStatusResponse> gaslessAccountStatus(
    AssetId assetId,
  ) async {
    gaslessStatusCallCount += 1;
    final handler = gaslessAccountStatusHandler;
    if (handler == null) {
      throw StateError('gasless::account_status not stubbed');
    }
    return handler(assetId);
  }

  @override
  Future<WithdrawalPreview> previewWithdrawal(WithdrawParameters params) async {
    previewCallCount += 1;
    previewRequests.add(params);
    return _previewWithdrawalHandler(params);
  }

  @override
  Future<WithdrawalFeeOptions?> getFeeOptions(String assetId) async {
    return _getFeeOptionsHandler?.call(assetId);
  }

  @override
  Stream<WithdrawalProgress> executeWithdrawal(
    WithdrawalPreview preview,
    String assetId,
  ) {
    executeCallCount += 1;
    return _executeWithdrawalHandler?.call(preview, assetId) ??
        const Stream<WithdrawalProgress>.empty();
  }

  @override
  Future<List<PendingGaslessTransfer>> listPendingGaslessTransfers() async {
    pendingListCallCount += 1;
    return _listPendingGaslessTransfersHandler?.call() ??
        const <PendingGaslessTransfer>[];
  }

  @override
  Stream<WithdrawalProgress> resumePendingGaslessTransfer(String traceId) {
    pendingResumeCallCount += 1;
    return _resumePendingGaslessTransferHandler?.call(traceId) ??
        const Stream<WithdrawalProgress>.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this._pubkeysByAssetId);

  final Map<AssetId, AssetPubkeys> _pubkeysByAssetId;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) => _pubkeysByAssetId[assetId];

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async =>
      _pubkeysByAssetId[asset.id] ??
      AssetPubkeys(
        assetId: asset.id,
        keys: const [],
        availableAddressesCount: 0,
        syncStatus: SyncStatusEnum.success,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBalanceManager implements BalanceManager {
  _FakeBalanceManager(this._balances);

  final Map<AssetId, BalanceInfo> _balances;

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _balances[assetId];

  @override
  Future<BalanceInfo> getBalance(
    AssetId assetId, {
    // This fake serves a fixed map, so a forced refresh has nothing to go back
    // to; the flag exists on the real manager to bypass its pubkey cache.
    bool forceRefresh = false,
  }) async => _balances[assetId] ?? BalanceInfo.zero();

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) async* {
    final balance = _balances[assetId];
    if (balance != null) {
      yield balance;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({
    required this.addresses,
    required this.withdrawals,
    required this.pubkeys,
    required this.balances,
    AssetManager? assets,
  }) : assets = assets ?? _FakeAssetManager(const <AssetId, Asset>{});

  @override
  final AddressOperations addresses;

  @override
  final WithdrawalManager withdrawals;

  @override
  final PubkeyManager pubkeys;

  @override
  final BalanceManager balances;

  @override
  final AssetManager assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._assets);

  final Map<AssetId, Asset> _assets;

  @override
  Asset? fromId(AssetId id) => _assets[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMm2Api implements Mm2Api {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void testWithdrawFormBloc() {
  group('WithdrawFormBloc', () {
    test('preview completion uses the original request snapshot', () async {
      final asset = _assetFromConfig(_utxoConfig());
      final previewCompleter = Completer<WithdrawalPreview>();
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) => previewCompleter.future,
      );
      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

      final sendingState = bloc.stream.firstWhereBounded((state) => state.isSending);
      bloc.add(const WithdrawFormPreviewSubmitted());
      await sendingState;

      bloc.add(const WithdrawFormAmountChanged('2'));
      await _flush();

      previewCompleter.complete(
        _utxoPreview(
          assetId: asset.id.id,
          txHash: 'preview-1',
          toAddress: 'recipient-1',
          timestamp: 1,
        ),
      );

      final confirmState = await bloc.stream.firstWhereBounded(
        (state) =>
            state.step == WithdrawFormStep.confirm &&
            state.preview?.txHash == 'preview-1',
      );

      expect(withdrawals.previewCallCount, 1);
      expect(withdrawals.previewRequests.single.amount, Decimal.one);
      expect(confirmState.amount, '1');
      expect(confirmState.recipientAddress, 'recipient-1');
    });

    test(
      'preview completion preserves concurrent fee option updates',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final feeOptionsCompleter = Completer<WithdrawalFeeOptions?>();
        final previewCompleter = Completer<WithdrawalPreview>();
        final expectedFeeOptions = _utxoFeeOptions(asset.id.id);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) => previewCompleter.future,
          getFeeOptionsHandler: (_) => feeOptionsCompleter.future,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        feeOptionsCompleter.complete(expectedFeeOptions);
        await _flush();

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        final sendingState = bloc.stream.firstWhereBounded((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        previewCompleter.complete(
          _utxoPreview(
            assetId: asset.id.id,
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );

        final confirmState = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'preview-1',
        );

        expect(confirmState.feeOptions, expectedFeeOptions);
      },
    );

    test(
      'preview completion survives fee priority defaulting during request',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final feeOptionsCompleter = Completer<WithdrawalFeeOptions?>();
        final previewCompleter = Completer<WithdrawalPreview>();
        final expectedFeeOptions = _utxoFeeOptions(asset.id.id);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) => previewCompleter.future,
          getFeeOptionsHandler: (_) => feeOptionsCompleter.future,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        final sendingState = bloc.stream.firstWhereBounded((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        feeOptionsCompleter.complete(expectedFeeOptions);
        final feeDefaultedState = await bloc.stream.firstWhereBounded(
          (state) =>
              state.isSending &&
              state.selectedFeePriority == WithdrawalFeeLevel.medium,
        );

        previewCompleter.complete(
          _utxoPreview(
            assetId: asset.id.id,
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );

        final confirmState = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'preview-1',
        );

        expect(withdrawals.previewRequests.single.feePriority, isNull);
        expect(feeDefaultedState.feeOptions, expectedFeeOptions);
        expect(confirmState.feeOptions, expectedFeeOptions);
        expect(confirmState.selectedFeePriority, WithdrawalFeeLevel.medium);
      },
    );

    test(
      'stale preview results are discarded after request inputs change',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final previewCompleter = Completer<WithdrawalPreview>();
        final initialPubkey = PubkeyInfo(
          address: 'source-address-1',
          derivationPath: "m/44'/141'/0'/0/0",
          chain: 'external',
          balance: _balance('5'),
          coinTicker: asset.id.id,
        );
        final updatedPubkey = PubkeyInfo(
          address: 'source-address-2',
          derivationPath: "m/44'/141'/0'/0/1",
          chain: 'external',
          balance: _balance('5'),
          coinTicker: asset.id.id,
        );
        final pubkeysByAssetId = <AssetId, AssetPubkeys>{
          asset.id: AssetPubkeys(
            assetId: asset.id,
            keys: [initialPubkey],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        };
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) => previewCompleter.future,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager(pubkeysByAssetId),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        final sendingState = bloc.stream.firstWhereBounded((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        pubkeysByAssetId[asset.id] = AssetPubkeys(
          assetId: asset.id,
          keys: [updatedPubkey],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        );
        bloc.add(const WithdrawFormSourcesLoadRequested());
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.selectedSourceAddress?.derivationPath ==
              updatedPubkey.derivationPath,
        );

        previewCompleter.complete(
          _utxoPreview(
            assetId: asset.id.id,
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );

        final settledState = await bloc.stream.firstWhereBounded(
          (state) =>
              !state.isSending &&
              state.selectedSourceAddress?.derivationPath ==
                  updatedPubkey.derivationPath,
        );

        expect(
          withdrawals.previewRequests.single.from,
          WithdrawalSource.hdDerivationPath(initialPubkey.derivationPath!),
        );
        expect(settledState.step, WithdrawFormStep.fill);
        expect(settledState.preview, isNull);
        expect(
          settledState.selectedSourceAddress?.derivationPath,
          updatedPubkey.derivationPath,
        );
      },
    );

    test(
      'duplicate preview submissions are dropped while one is running',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final previewCompleter = Completer<WithdrawalPreview>();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) => previewCompleter.future,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        final sendingState = bloc.stream.firstWhereBounded((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;
        await _flush();

        expect(withdrawals.previewCallCount, 1);

        previewCompleter.complete(
          _utxoPreview(
            assetId: asset.id.id,
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );

        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
      },
    );

    test(
      'recipient validation keeps the latest input when async checks overlap',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final validations = <String, Completer<AddressValidation>>{
          'recipient-1': Completer<AddressValidation>(),
          'recipient-2': Completer<AddressValidation>(),
        };
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(
              validateAddressHandler:
                  ({required Asset asset, required String address}) =>
                      validations[address]!.future,
            ),
            withdrawals: _FakeWithdrawalManager(
              previewWithdrawalHandler: (_) async => _utxoPreview(
                assetId: asset.id.id,
                txHash: 'unused',
                toAddress: 'recipient-2',
                timestamp: 1,
              ),
            ),
            pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormRecipientChanged('recipient-1'));
        await bloc.stream.firstWhereBounded(
          (state) => state.recipientAddress == 'recipient-1',
        );

        bloc.add(const WithdrawFormRecipientChanged('recipient-2'));
        await bloc.stream.firstWhereBounded(
          (state) => state.recipientAddress == 'recipient-2',
        );

        validations['recipient-1']!.complete(
          AddressValidation(
            isValid: false,
            address: 'recipient-1',
            asset: asset,
            invalidReason: 'invalid recipient-1',
          ),
        );
        await _flush();

        expect(bloc.state.recipientAddress, 'recipient-2');
        expect(bloc.state.recipientAddressError, isNull);

        validations['recipient-2']!.complete(
          AddressValidation(
            isValid: true,
            address: 'recipient-2',
            asset: asset,
          ),
        );
        await _flush();

        expect(bloc.state.recipientAddress, 'recipient-2');
        expect(bloc.state.recipientAddressError, isNull);
      },
    );

    test(
      'TRON preview refresh drops duplicate requests and preserves confirm state',
      () async {
        final asset = _assetFromConfig(_trxConfig());
        final refreshCompleter = Completer<WithdrawalPreview>();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        var previewInvocation = 0;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async {
            previewInvocation += 1;
            if (previewInvocation == 1) {
              return _tronPreview(
                txHash: 'preview-1',
                toAddress: 'tron-recipient',
                timestamp: now,
              );
            }

            return refreshCompleter.future;
          },
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: _assetPubkeys(asset, balance: '5'),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');

        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'preview-1',
        );

        final refreshingState = bloc.stream.firstWhereBounded(
          (state) => state.isPreviewRefreshing,
        );
        bloc.add(const WithdrawFormTronPreviewRefreshRequested());
        bloc.add(const WithdrawFormTronPreviewRefreshRequested());
        await refreshingState;
        await _flush();

        expect(withdrawals.previewCallCount, 2);

        refreshCompleter.complete(
          _tronPreview(
            txHash: 'preview-2',
            toAddress: 'tron-recipient',
            timestamp: now + 5,
          ),
        );

        final refreshedState = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              !state.isPreviewRefreshing &&
              state.preview?.txHash == 'preview-2',
        );

        expect(withdrawals.previewCallCount, 2);
        expect(refreshedState.amount, '1');
        expect(refreshedState.recipientAddress, 'tron-recipient');
        expect(refreshedState.previewSecondsRemaining, isNotNull);
      },
    );

    test(
      'gasless TRC20 preview uses GasFree source and forbids native fallback',
      () async {
        final parent = _assetFromConfig(_trxConfig());
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final gasfreeSource = _pubkeyForAsset(
          asset,
          address: 'source-gasfree',
          balance: '0',
          gasfreeAddress: 'gasfree-source-address',
        );
        final nativeOnlySource = _pubkeyForAsset(
          asset,
          address: 'source-native-only',
          balance: '5',
        );
        final secondaryGasfreeSource = _pubkeyForAsset(
          asset,
          address: 'source-secondary',
          balance: '7',
          gasfreeAddress: 'secondary-must-not-be-custody',
          derivationPath: "m/44'/195'/1'/0/0",
        );
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'gasless-preview',
            toAddress: 'tron-recipient',
            timestamp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ),
        )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();

        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: AssetPubkeys(
                assetId: asset.id,
                keys: [secondaryGasfreeSource, nativeOnlySource, gasfreeSource],
                availableAddressesCount: 3,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
          walletType: WalletType.hdwallet,
          gaslessFeatureConfigured: true,
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');

        expect(bloc.state.useGasless, isTrue);
        expect(bloc.state.pubkeys?.keys, [
          secondaryGasfreeSource,
          nativeOnlySource,
          gasfreeSource,
        ]);
        expect(bloc.state.selectedSourceAddress, gasfreeSource);

        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'gasless-preview',
        );

        final request = withdrawals.previewRequests.single;
        expect(request.feeMethod, WithdrawalFeeMethod.gasless);
        expect(request.gaslessOptions?.fallbackToNative, isFalse);
        expect(
          request.from,
          WithdrawalSource.hdDerivationPath(gasfreeSource.derivationPath!),
        );

        final resetFuture = bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.fill &&
              state.recipientAddress.isEmpty &&
              state.selectedSourceAddress == gasfreeSource,
        );
        bloc.add(const WithdrawFormReset());
        final reset = await resetFuture;
        expect(reset.selectedSourceAddress, gasfreeSource);
      },
    );

    test('Standard TRC20 rejects an unexpected GasFree preview rail', () async {
      final asset = _trc20Asset();
      final now =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronGaslessPreview(
          txHash: 'unexpected-gasless-preview',
          toAddress: 'standard-recipient',
          timestamp: now,
        ),
      );
      final bloc = _buildTrc20Bloc(
        asset: asset,
        withdrawals: withdrawals,
        initialGaslessEnabled: false,
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'standard-recipient', amount: '1');
      expect(bloc.state.useGasless, isFalse);

      bloc.add(const WithdrawFormPreviewSubmitted());
      final blocked = await bloc.stream.firstWhereBounded(
        (state) =>
            state.previewError != null &&
            state.gaslessQuoteFailure?.failureClass ==
                GaslessQuoteFailureClass.securityMismatch &&
            !state.isSending &&
            state.step == WithdrawFormStep.fill,
      );

      expect(withdrawals.previewRequests.single.feeMethod, isNull);
      expect(blocked.preview, isNull);
      expect(
        blocked.gaslessQuoteFailure?.failureClass,
        GaslessQuoteFailureClass.securityMismatch,
      );
      expect(withdrawals.executeCallCount, 0);
    });

    test('raw relay_type without the typed GasFree fee is rejected as an '
        'inconsistent preview', () async {
      final asset = _trc20Asset();
      final now =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronGaslessPreview(
          txHash: 'inconsistent-preview',
          toAddress: 'standard-recipient',
          timestamp: now,
          fee: FeeInfo.tron(
            coin: 'TRX',
            bandwidthUsed: 1,
            energyUsed: 1,
            bandwidthFee: Decimal.zero,
            energyFee: Decimal.parse('0.1'),
            totalFeeAmount: Decimal.parse('0.1'),
          ),
        ),
      );
      final bloc = _buildTrc20Bloc(
        asset: asset,
        withdrawals: withdrawals,
        initialGaslessEnabled: false,
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'standard-recipient', amount: '1');
      expect(bloc.state.useGasless, isFalse);

      bloc.add(const WithdrawFormPreviewSubmitted());
      final blocked = await bloc.stream.firstWhereBounded(
        (state) =>
            state.previewError != null &&
            state.gaslessQuoteFailure?.failureClass ==
                GaslessQuoteFailureClass.securityMismatch &&
            !state.isSending &&
            state.step == WithdrawFormStep.fill,
      );

      expect(withdrawals.previewRequests.single.feeMethod, isNull);
      expect(blocked.preview, isNull);
      expect(
        blocked.gaslessQuoteFailure?.failureClass,
        GaslessQuoteFailureClass.securityMismatch,
      );
      expect(withdrawals.executeCallCount, 0);
    });

    test('duplicate canonical GasFree sources hard-block GasFree but keep '
        'funded Standard sources usable', () async {
      final asset = _trc20Asset();
      final firstCanonical = _pubkeyForAsset(
        asset,
        address: 'duplicate-canonical-one',
        balance: '5',
        gasfreeAddress: 'gasfree-custody-one',
      );
      final secondCanonical = _pubkeyForAsset(
        asset,
        address: 'duplicate-canonical-two',
        balance: '3',
        gasfreeAddress: 'gasfree-custody-two',
      );
      final fundedSecondary = _pubkeyForAsset(
        asset,
        address: 'funded-standard-secondary',
        balance: '2',
        derivationPath: "m/44'/195'/0'/0/1",
      );
      final now =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronPreview(
          txHash: 'standard-with-ambiguous-gasfree',
          toAddress: 'standard-recipient',
          timestamp: now,
        ),
      )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({
            asset.id: AssetPubkeys(
              assetId: asset.id,
              keys: [firstCanonical, fundedSecondary, secondCanonical],
              availableAddressesCount: 3,
              syncStatus: SyncStatusEnum.success,
            ),
          }),
          balances: _FakeBalanceManager({asset.id: _balance('10')}),
        ),
        mm2Api: _FakeMm2Api(),
        walletType: WalletType.hdwallet,
        initialSourceAddress: secondCanonical,
        gaslessFeatureConfigured: true,
      );
      addTearDown(bloc.close);

      final blocked = await bloc.stream.firstWhereBounded(
        (state) =>
            state.hasAmbiguousGaslessSources &&
            state.gaslessAvailability == GaslessAvailability.securityMismatch,
      );
      expect(blocked.canonicalGaslessSource, isNull);
      expect(blocked.canonicalGaslessSourceCandidates, hasLength(2));
      expect(blocked.isGaslessEnabled, isFalse);
      expect(blocked.useGasless, isFalse);
      expect(blocked.selectedSourceAddress, secondCanonical);
      expect(blocked.pubkeys?.keys, contains(fundedSecondary));
      expect(withdrawals.gaslessStatusCallCount, 0);

      bloc.add(const WithdrawFormGaslessToggled(true));
      await _flush();
      expect(bloc.state.isGaslessEnabled, isFalse);
      expect(
        bloc.state.gaslessAvailability,
        GaslessAvailability.securityMismatch,
      );

      await _primeFillState(bloc, recipient: 'standard-recipient', amount: '1');
      bloc.add(const WithdrawFormPreviewSubmitted());
      await bloc.stream.firstWhereBounded(
        (state) =>
            state.step == WithdrawFormStep.confirm &&
            state.preview?.txHash == 'standard-with-ambiguous-gasfree',
      );
      expect(withdrawals.previewRequests.single.feeMethod, isNull);

      bloc.add(const WithdrawFormReset());
      final reset = await bloc.stream.firstWhereBounded(
        (state) =>
            state.step == WithdrawFormStep.fill &&
            state.recipientAddress.isEmpty,
      );
      expect(reset.selectedSourceAddress, secondCanonical);
      expect(reset.isGaslessEnabled, isFalse);
      expect(reset.gaslessAvailability, GaslessAvailability.securityMismatch);
    });

    test(
      'gasless submit surfaces the typed relay state and clears it on success',
      () async {
        final asset = _trc20Asset();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final preview = _tronGaslessPreview(
          txHash: 'gasless-preview',
          toAddress: 'tron-recipient',
          timestamp: now,
        );
        final progressController = StreamController<WithdrawalProgress>();
        addTearDown(progressController.close);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => progressController.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        progressController.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free transfer submitted...',
            gaslessState: GaslessTraceState.submitted,
            taskId: 'trace-1',
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: 'trace-1',
              journalId: 'journal-1',
            ),
          ),
        );
        final relaying = await bloc.stream.firstWhereBounded(
          (state) => state.gaslessTraceState != null,
        );
        expect(relaying.gaslessTraceState, GaslessTraceState.submitted);
        expect(relaying.gaslessTraceId, 'trace-1');
        expect(relaying.gaslessJournalId, 'journal-1');
        expect(
          relaying.gaslessTransferState,
          GaslessTransferState.submittedPending,
        );
        expect(relaying.gaslessStatusMessage, isNotNull);

        progressController.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Withdrawal complete',
            withdrawalResult: _resultFromPreview(
              preview,
              gaslessFinalFee: Decimal.parse('0.75'),
              gaslessTraceId: 'trace-1',
            ),
          ),
        );
        final success = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );
        expect(success.gaslessTraceState, GaslessTraceState.confirmed);
        expect(success.gaslessStatusMessage, isNull);
        expect(success.gaslessTransferState, GaslessTransferState.confirmed);
        expect(success.result?.gaslessFinalFee, Decimal.parse('0.75'));
        expect(success.result?.gaslessTraceId, 'trace-1');
      },
    );

    test(
      'post-acceptance relay error becomes non-retryable pending unknown',
      () async {
        final asset = _trc20Asset();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final preview = _tronGaslessPreview(
          txHash: 'gasless-preview',
          toAddress: 'tron-recipient',
          timestamp: now,
        );
        final progressController = StreamController<WithdrawalProgress>();
        addTearDown(progressController.close);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => progressController.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        progressController.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free transfer accepted',
            gaslessState: GaslessTraceState.pending,
            taskId: 'trace-accepted',
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: 'trace-accepted',
              journalId: 'journal-accepted',
            ),
          ),
        );
        await bloc.stream.firstWhereBounded(
          (state) => state.gaslessTraceId == 'trace-accepted',
        );
        final pendingFuture = bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.pending,
        );
        progressController.addError(StateError('trace service offline'));

        final pending = await pendingFuture;
        expect(pending.gaslessJournalId, 'journal-accepted');
        expect(
          pending.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(pending.transactionError, isNull);
        expect(pending.preview, isNull);
        expect(pending.canRetryGaslessTransfer, isFalse);
      },
    );

    test(
      'journal-only relay ambiguity remains non-retryable when stream closes',
      () async {
        final asset = _trc20Asset();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final preview = _tronGaslessPreview(
          txHash: 'gasless-preview',
          toAddress: 'tron-recipient',
          timestamp: now,
        );
        final progressController = StreamController<WithdrawalProgress>();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => progressController.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        progressController.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free submission outcome is unknown',
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: WithdrawalSubmission.gaslessUnknown(
              journalId: 'journal-only-ambiguity',
            ),
          ),
        );
        final pendingFuture = bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.pending,
        );
        await progressController.close();

        final pending = await pendingFuture;
        expect(pending.gaslessJournalId, 'journal-only-ambiguity');
        expect(pending.gaslessTraceId, isNull);
        expect(pending.gaslessSubmittedAt, isNotNull);
        expect(
          pending.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(pending.canRetryGaslessTransfer, isFalse);
        expect(pending.transactionError, isNull);
      },
    );

    test(
      'journal-only relay ambiguity remains non-retryable on stream error',
      () async {
        final asset = _trc20Asset();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final preview = _tronGaslessPreview(
          txHash: 'gasless-preview',
          toAddress: 'tron-recipient',
          timestamp: now,
        );
        final progressController = StreamController<WithdrawalProgress>();
        addTearDown(progressController.close);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => progressController.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        progressController.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free submission outcome is unknown',
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: WithdrawalSubmission.gaslessUnknown(
              journalId: 'journal-only-error',
            ),
          ),
        );
        await bloc.stream.firstWhereBounded(
          (state) => state.gaslessJournalId == 'journal-only-error',
        );
        progressController.addError(StateError('relay response lost'));

        final pending = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.pending,
        );
        expect(pending.gaslessJournalId, 'journal-only-error');
        expect(pending.gaslessTraceId, isNull);
        expect(pending.gaslessSubmittedAt, isNotNull);
        expect(
          pending.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(pending.canRetryGaslessTransfer, isFalse);
        expect(pending.transactionError, isNull);
      },
    );

    test(
      'restart restores and reconciles an accepted trace while new sends are disabled',
      () async {
        final asset = _trc20Asset();
        final pending = _pendingGaslessTransfer();
        final reconciliation = StreamController<WithdrawalProgress>();
        addTearDown(reconciliation.close);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: pending.destinationAddress,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          listPendingGaslessTransfersHandler: () async => [pending],
          resumePendingGaslessTransferHandler: (traceId) {
            expect(traceId, pending.traceId);
            return reconciliation.stream;
          },
        );
        final pubkeys = AssetPubkeys(
          assetId: asset.id,
          keys: [
            _pubkeyForAsset(asset, gasfreeAddress: pending.custodyAddress),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({asset.id: pubkeys}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
          // Simulates the production kill switch being off after acceptance.
          gaslessFeatureConfigured: false,
        );
        addTearDown(bloc.close);

        final restored = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.pending &&
              state.gaslessTraceId == pending.traceId &&
              state.isSending,
        );
        expect(restored.isGaslessFeatureConfigured, isFalse);
        expect(restored.authorizedRecipientAmount, pending.requestedAmount);
        expect(restored.gaslessJournalId, pending.journalId);
        expect(restored.canRetryGaslessTransfer, isFalse);
        expect(withdrawals.pendingResumeCallCount, 1);

        reconciliation.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Withdrawal complete',
            taskId: pending.traceId,
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: pending.traceId!,
              journalId: pending.journalId,
            ),
            gaslessTransferState: GaslessTransferState.confirmed,
            withdrawalResult: WithdrawalResult(
              txHash: 'on-chain-hash',
              balanceChanges: pending.balanceChanges,
              coin: pending.assetId,
              toAddress: pending.destinationAddress,
              fee: pending.fee,
              gaslessFinalFee: Decimal.parse('0.75'),
              gaslessTraceId: pending.traceId,
            ),
          ),
        );

        final success = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );
        expect(success.result?.txHash, 'on-chain-hash');
        expect(success.result?.gaslessFinalFee, Decimal.parse('0.75'));
        expect(success.result?.gaslessTraceId, pending.traceId);
        expect(success.gaslessTransferState, GaslessTransferState.confirmed);
      },
    );

    test(
      'finite trace recovery retains confirming on-chain lifecycle',
      () async {
        final asset = _trc20Asset();
        final pending = _pendingGaslessTransfer(
          state: GaslessTransferState.submittedPending,
        );
        final reconciliation = StreamController<WithdrawalProgress>();
        addTearDown(() async {
          if (!reconciliation.isClosed) await reconciliation.close();
        });
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: pending.destinationAddress,
            timestamp:
                DateTime.now().millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond,
          ),
          listPendingGaslessTransfersHandler: () async => [pending],
          resumePendingGaslessTransferHandler: (_) => reconciliation.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.pending && state.isSending,
        );
        reconciliation.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Waiting for on-chain confirmation',
            gaslessState: GaslessTraceState.onChain,
            gaslessTransferState: GaslessTransferState.confirming,
          ),
        );
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.gaslessTransferState == GaslessTransferState.confirming &&
              state.gaslessTraceState == GaslessTraceState.onChain,
        );

        final pausedFuture = bloc.stream.firstWhereBounded(
          (state) =>
              !state.isSending &&
              state.gaslessTransferState == GaslessTransferState.confirming,
        );
        await reconciliation.close();
        final paused = await pausedFuture;

        expect(paused.step, WithdrawFormStep.pending);
        expect(paused.gaslessTraceState, GaslessTraceState.onChain);
        expect(
          paused.gaslessStatusMessage,
          'Waiting for on-chain confirmation',
        );
        expect(paused.canRetryGaslessTransfer, isFalse);
      },
    );

    test(
      'trace transport error after confirming preserves on-chain lifecycle',
      () async {
        final asset = _trc20Asset();
        final pending = _pendingGaslessTransfer(
          state: GaslessTransferState.submittedPending,
        );
        final reconciliation = StreamController<WithdrawalProgress>();
        addTearDown(() async {
          if (!reconciliation.isClosed) await reconciliation.close();
        });
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: pending.destinationAddress,
            timestamp:
                DateTime.now().millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond,
          ),
          listPendingGaslessTransfersHandler: () async => [pending],
          resumePendingGaslessTransferHandler: (_) => reconciliation.stream,
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.pending && state.isSending,
        );
        reconciliation.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Waiting for on-chain confirmation',
            gaslessState: GaslessTraceState.onChain,
            gaslessTransferState: GaslessTransferState.confirming,
          ),
        );
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.gaslessTransferState == GaslessTransferState.confirming &&
              state.gaslessTraceState == GaslessTraceState.onChain,
        );

        final pausedFuture = bloc.stream.firstWhereBounded(
          (state) =>
              !state.isSending &&
              state.gaslessTransferState == GaslessTransferState.confirming,
        );
        reconciliation.addError(StateError('trace transport disconnected'));
        final paused = await pausedFuture;

        expect(paused.step, WithdrawFormStep.pending);
        expect(paused.gaslessTraceState, GaslessTraceState.onChain);
        expect(
          paused.gaslessStatusMessage,
          'Waiting for on-chain confirmation',
        );
        expect(paused.canRetryGaslessTransfer, isFalse);
      },
    );

    test(
      'restart keeps journal-only ambiguity locked without reconciliation',
      () async {
        final asset = _trc20Asset();
        final pending = _pendingGaslessTransfer(traceId: null);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: pending.destinationAddress,
            timestamp:
                DateTime.now().millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond,
          ),
          listPendingGaslessTransfersHandler: () async => [pending],
          resumePendingGaslessTransferHandler: (_) =>
              throw StateError('A local journal ID is not a provider trace'),
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: _assetPubkeys(asset, balance: '5'),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
          gaslessFeatureConfigured: false,
        );
        addTearDown(bloc.close);

        final unresolved = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.pending &&
              state.gaslessJournalId == pending.journalId,
        );
        expect(unresolved.gaslessTraceId, isNull);
        expect(unresolved.isSending, isFalse);
        expect(unresolved.canRetryGaslessTransfer, isFalse);
        bloc.add(const WithdrawFormGaslessTraceCheckRequested());
        await _flush();
        expect(withdrawals.pendingResumeCallCount, 0);
      },
    );

    for (final pendingCase in <({String name, String? traceId})>[
      (name: 'trace-backed', traceId: 'trace-standard-escape'),
      (name: 'journal-only', traceId: null),
    ]) {
      test('${pendingCase.name} unresolved transfer can use Standard without '
          'unlocking GasFree', () async {
        final asset = _trc20Asset();
        final pending = _pendingGaslessTransfer(traceId: pendingCase.traceId);
        final reconciliation = pendingCase.traceId == null
            ? null
            : StreamController<WithdrawalProgress>();
        if (reconciliation != null) {
          addTearDown(reconciliation.close);
        }
        final now =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'standard-after-pending',
            toAddress: 'new-standard-recipient',
            timestamp: now,
          ),
          executeWithdrawalHandler: (preview, _) => Stream.value(
            WithdrawalProgress(
              status: WithdrawalStatus.complete,
              message: 'Standard withdrawal complete',
              withdrawalResult: _resultFromPreview(preview),
            ),
          ),
          listPendingGaslessTransfersHandler: () async => [pending],
          resumePendingGaslessTransferHandler: (_) => reconciliation!.stream,
        )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
        final source = _pubkeyForAsset(
          asset,
          balance: '5',
          gasfreeAddress: pending.custodyAddress,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: AssetPubkeys(
                assetId: asset.id,
                keys: [source],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
          walletType: WalletType.hdwallet,
          gaslessFeatureConfigured: true,
        );
        addTearDown(bloc.close);

        final unresolved = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.pending &&
              state.gaslessJournalId == pending.journalId &&
              (pendingCase.traceId == null || state.isSending),
        );
        expect(unresolved.canRetryGaslessTransfer, isFalse);

        bloc.add(const WithdrawFormPendingUseStandardRequested());
        final standardFill = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.fill &&
              !state.isGaslessEnabled &&
              state.gaslessJournalId == pending.journalId,
        );
        expect(standardFill.gaslessTraceId, pendingCase.traceId);
        expect(
          standardFill.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(standardFill.canRetryGaslessTransfer, isFalse);
        expect(standardFill.recipientAddress, isEmpty);
        expect(standardFill.amount, '0');

        if (pendingCase.traceId != null) {
          reconciliation!.add(
            const WithdrawalProgress(
              status: WithdrawalStatus.inProgress,
              message: 'Late trace update',
              gaslessState: GaslessTraceState.onChain,
            ),
          );
          await _flush();
          expect(bloc.state.step, WithdrawFormStep.fill);
        }

        bloc.add(const WithdrawFormGaslessToggled(true));
        await _flush();
        expect(bloc.state.isGaslessEnabled, isFalse);
        expect(bloc.state.canRetryGaslessTransfer, isFalse);

        await _primeFillState(
          bloc,
          recipient: 'new-standard-recipient',
          amount: '1',
        );
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'standard-after-pending',
        );
        expect(withdrawals.previewRequests.single.feeMethod, isNull);

        bloc.add(const WithdrawFormSubmitted());
        final success = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );
        expect(success.gaslessJournalId, pending.journalId);
        expect(success.gaslessTraceId, pendingCase.traceId);
        expect(
          success.gaslessTransferState,
          GaslessTransferState.submittedUnknown,
        );
        expect(success.canRetryGaslessTransfer, isFalse);

        bloc.add(const WithdrawFormReset());
        final reset = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.fill &&
              state.result == null &&
              state.gaslessJournalId == pending.journalId,
        );
        expect(reset.isGaslessEnabled, isFalse);
        expect(reset.canRetryGaslessTransfer, isFalse);
        expect(reset.gaslessAvailability, GaslessAvailability.pendingTransfer);
      });
    }

    test(
      'unreadable pending journal fails closed for new GasFree sends',
      () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => throw StateError(
            'GasFree preview must not run while the journal is unreadable',
          ),
          listPendingGaslessTransfersHandler: () async =>
              throw const FormatException('corrupt encrypted journal'),
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        final blocked = await bloc.stream.firstWhereBounded(
          (state) => !state.gaslessPendingStoreHealthy,
        );
        expect(blocked.isGaslessSupported, isFalse);
        expect(blocked.useGasless, isFalse);
        expect(
          blocked.gaslessAvailability,
          GaslessAvailability.securityMismatch,
        );
        expect(blocked.gaslessPendingStoreReady, isTrue);
        expect(blocked.isGaslessEnabled, isFalse);
        expect(
          blocked.selectedSourceAddress?.balance.total,
          greaterThan(Decimal.zero),
        );
        expect(blocked.previewError, isNull);

        bloc.add(const WithdrawFormReset());
        final reset = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.fill && state.previewError == null,
        );
        expect(reset.gaslessPendingStoreHealthy, isFalse);
        expect(reset.isGaslessSupported, isFalse);
        expect(reset.gaslessAvailability, GaslessAvailability.securityMismatch);
      },
    );

    for (final failureCase in <(String, Object)>[
      (
        'missing wallet identity',
        StateError('GasFree requires an authenticated wallet'),
      ),
      (
        'typed unverified wallet identity',
        GaslessTransferException(
          kind: GaslessTransferErrorKind.capabilityNotReady,
          code: GaslessTransferErrorCode.capabilityNotReady,
          stage: GaslessTransferStage.recovery,
          message: 'GasFree requires a verified wallet identity',
          retryable: true,
          terminal: false,
        ),
      ),
      (
        'wallet switch',
        const WalletChangedDisconnectException(
          'Wallet changed while loading the GasFree journal',
        ),
      ),
    ]) {
      test(
        '${failureCase.$1} pauses journal readiness without claiming storage '
        'corruption',
        () async {
          final asset = _trc20Asset();
          final firstLoad = Completer<List<PendingGaslessTransfer>>();
          var attempts = 0;
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronPreview(
              txHash: 'standard-preview',
              toAddress: 'recipient',
              timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ),
            listPendingGaslessTransfersHandler: () {
              attempts += 1;
              return attempts == 1
                  ? firstLoad.future
                  : Future.value(const <PendingGaslessTransfer>[]);
            },
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          final pausedFuture = bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessPendingStoreHealthy &&
                !state.gaslessPendingStoreReady &&
                !state.isGaslessEnabled,
          );
          while (attempts == 0) {
            await _flush();
          }
          firstLoad.completeError(failureCase.$2);
          final paused = await pausedFuture;

          expect(paused.gaslessPendingStoreHealthy, isTrue);
          expect(paused.gaslessPendingStoreReady, isFalse);
          expect(paused.useGasless, isFalse);
          expect(paused.gaslessAvailability, GaslessAvailability.initial);
          if (failureCase.$1 != 'wallet switch') {
            expect(
              paused.selectedSourceAddress?.balance.total,
              greaterThan(Decimal.zero),
            );
          }

          bloc.add(const WithdrawFormPendingGaslessLoadRequested());
          final recovered = await bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessPendingStoreHealthy &&
                state.gaslessPendingStoreReady &&
                attempts == 2,
          );

          expect(recovered.gaslessAvailability, GaslessAvailability.initial);
          expect(withdrawals.pendingListCallCount, 2);
        },
      );
    }

    test(
      'legacy journal ownership resolution failure shows storage recovery',
      () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: 'recipient',
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          listPendingGaslessTransfersHandler: () async =>
              throw const GaslessTransferLegacyResolutionException(),
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        final blocked = await bloc.stream.firstWhereBounded(
          (state) =>
              !state.gaslessPendingStoreHealthy &&
              state.gaslessPendingStoreReady,
        );

        expect(
          blocked.gaslessAvailability,
          GaslessAvailability.securityMismatch,
        );
        expect(blocked.isGaslessEnabled, isFalse);
        expect(blocked.useGasless, isFalse);
      },
    );

    test(
      'journal retry restores GasFree readiness after a transient failure',
      () async {
        final asset = _trc20Asset();
        var attempts = 0;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused-preview',
            toAddress: 'recipient',
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          listPendingGaslessTransfersHandler: () async {
            attempts += 1;
            if (attempts == 1) {
              throw const GaslessTransferStorageReadException();
            }
            return const <PendingGaslessTransfer>[];
          },
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) =>
              !state.gaslessPendingStoreHealthy &&
              state.gaslessPendingStoreReady,
        );

        bloc.add(const WithdrawFormPendingGaslessLoadRequested());
        final recovered = await bloc.stream.firstWhereBounded(
          (state) =>
              state.gaslessPendingStoreHealthy &&
              state.gaslessPendingStoreReady &&
              attempts == 2,
        );

        expect(recovered.gaslessAvailability, GaslessAvailability.initial);
        expect(recovered.previewError, isNull);
        expect(withdrawals.pendingListCallCount, 2);
      },
    );

    test(
      'late pending journal preserves an executing Standard withdrawal',
      () async {
        final asset = _trc20Asset();
        final journalLoad = Completer<List<PendingGaslessTransfer>>();
        final execution = StreamController<WithdrawalProgress>();
        addTearDown(execution.close);
        final now =
            DateTime.now().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'standard-preview',
            toAddress: 'standard-recipient',
            timestamp: now,
          ),
          executeWithdrawalHandler: (_, __) => execution.stream,
          listPendingGaslessTransfersHandler: () => journalLoad.future,
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          initialGaslessEnabled: false,
        );
        addTearDown(bloc.close);

        await _primeFillState(
          bloc,
          recipient: 'standard-recipient',
          amount: '1',
        );
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        final pending = _pendingGaslessTransfer();
        journalLoad.complete([pending]);
        final discovered = await bloc.stream.firstWhereBounded(
          (state) => state.gaslessJournalId == pending.journalId,
        );
        expect(discovered.step, WithdrawFormStep.confirm);
        expect(discovered.isSending, isTrue);

        execution.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Standard withdrawal complete',
            withdrawalResult: _resultFromPreview(
              _tronPreview(
                txHash: 'standard-preview',
                toAddress: 'standard-recipient',
                timestamp: now,
              ),
            ),
          ),
        );
        final success = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );

        expect(success.result?.txHash, 'standard-preview');
        expect(success.gaslessJournalId, pending.journalId);
        expect(success.gaslessTransferState, pending.state);
      },
    );

    test(
      'late journal error preserves an executing Standard withdrawal',
      () async {
        final asset = _trc20Asset();
        final journalLoad = Completer<List<PendingGaslessTransfer>>();
        final execution = StreamController<WithdrawalProgress>();
        addTearDown(execution.close);
        final now =
            DateTime.now().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        final preview = _tronPreview(
          txHash: 'standard-after-journal-error',
          toAddress: 'standard-recipient',
          timestamp: now,
        );
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => execution.stream,
          listPendingGaslessTransfersHandler: () => journalLoad.future,
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          initialGaslessEnabled: false,
        );
        addTearDown(bloc.close);

        await _primeFillState(
          bloc,
          recipient: 'standard-recipient',
          amount: '1',
        );
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );
        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhereBounded((state) => state.isSending);

        journalLoad.completeError(const GaslessTransferStorageReadException());
        final degraded = await bloc.stream.firstWhereBounded(
          (state) => !state.gaslessPendingStoreHealthy,
        );
        expect(degraded.step, WithdrawFormStep.confirm);
        expect(degraded.isSending, isTrue);
        expect(degraded.preview, preview);

        execution.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Standard withdrawal complete',
            withdrawalResult: _resultFromPreview(preview),
          ),
        );
        final success = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );

        expect(success.result?.txHash, 'standard-after-journal-error');
        expect(success.gaslessPendingStoreHealthy, isFalse);
        expect(success.gaslessTransferState, isNull);
      },
    );

    test('authoritative terminal relay failure is safely retryable', () async {
      final asset = _trc20Asset();
      final pending = _pendingGaslessTransfer();
      final reconciliation = StreamController<WithdrawalProgress>();
      addTearDown(reconciliation.close);
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronGaslessPreview(
          txHash: 'unused-preview',
          toAddress: pending.destinationAddress,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        listPendingGaslessTransfersHandler: () async => [pending],
        resumePendingGaslessTransferHandler: (_) => reconciliation.stream,
      );
      final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
      addTearDown(bloc.close);

      await bloc.stream.firstWhereBounded(
        (state) => state.step == WithdrawFormStep.pending && state.isSending,
      );
      reconciliation.addError(
        SdkError(
          code: SdkErrorCode.general,
          category: SdkErrorCategory.unknown,
          messageKey: 'withdrawGaslessFinalFailure',
          fallbackMessage: 'Provider reported a final failure',
          source: GaslessTransferException(
            kind: GaslessTransferErrorKind.finalFailure,
            message: 'Provider reported a final failure',
            retryable: false,
            terminal: true,
            traceId: 'trace-pending',
          ),
        ),
      );

      final failed = await bloc.stream.firstWhereBounded(
        (state) => state.step == WithdrawFormStep.failed,
      );
      expect(failed.gaslessTransferState, GaslessTransferState.failedFinal);
      expect(failed.canRetryGaslessTransfer, isTrue);
      expect(failed.transactionError?.message, contains('final failure'));
    });

    test(
      'gasless TRC20 activation-balance error is mapped to custody guidance',
      () async {
        final parent = _assetFromConfig(_trxConfig());
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final gasfreeSource = _pubkeyForAsset(
          asset,
          address: 'source-with-regular-balance',
          balance: '100',
          gasfreeAddress: 'gasfree-source-address',
        );
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => throw SdkError(
                  code: SdkErrorCode.insufficientFunds,
                  category: SdkErrorCategory.funds,
                  messageKey:
                      'withdrawGaslessInsufficientGasFreeBalanceForActivation',
                  fallbackMessage:
                      'The GasFree custody balance has 0 USDT-TRC20, but this '
                      'send needs 14 USDT-TRC20, including a one-time 1.5 '
                      'USDT-TRC20 activation fee.',
                  messageArgs: const [
                    '',
                    '0',
                    'USDT-TRC20',
                    '14',
                    'USDT-TRC20',
                    '1.5',
                    'USDT-TRC20',
                    'USDT-TRC20',
                  ],
                  retryable: false,
                  source: GaslessTransferException(
                    kind: GaslessTransferErrorKind.providerResponse,
                    code: GaslessTransferErrorCode.relayRejected,
                    stage: GaslessTransferStage.preview,
                    message: 'GasFree custody balance is insufficient',
                    retryable: false,
                    terminal: true,
                  ),
                ),
              )
              ..gaslessAccountStatusHandler = (_) async =>
                  _gaslessStatus(onChain: '100');

        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: AssetPubkeys(
                assetId: asset.id,
                keys: [gasfreeSource],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('100')}),
          ),
          mm2Api: _FakeMm2Api(),
          walletType: WalletType.hdwallet,
          gaslessFeatureConfigured: true,
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '12');
        bloc.add(const WithdrawFormPreviewSubmitted());

        final errored = await bloc.stream.firstWhereBounded(
          (state) => state.previewError != null,
        );

        expect(
          errored.previewError!.message,
          contains('withdrawGaslessInsufficientGasFreeBalanceForActivation'),
        );
        expect(
          errored.previewError!.message,
          isNot(contains('notEnoughBalanceForGasError')),
        );
      },
    );

    test(
      'gas-free custody shortfall surfaces a USDT insufficient-balance error '
      '(no TRX top-up)',
      () async {
        final parent = _assetFromConfig(_trxConfig());
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final gasfreeSource = _pubkeyForAsset(
          asset,
          address: 'source-main',
          balance: '100',
          gasfreeAddress: 'gasfree-source-address',
        );
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => throw SdkError(
                  code: SdkErrorCode.insufficientFunds,
                  category: SdkErrorCategory.funds,
                  messageKey: 'withdrawGaslessInsufficientGasFreeBalance',
                  fallbackMessage:
                      'The GasFree custody balance has 0 USDT-TRC20, but this '
                      'send needs 14 USDT-TRC20.',
                  messageArgs: const [
                    '',
                    '0',
                    'USDT-TRC20',
                    '14',
                    'USDT-TRC20',
                    'USDT-TRC20',
                  ],
                  retryable: false,
                  source: GaslessTransferException(
                    kind: GaslessTransferErrorKind.providerResponse,
                    code: GaslessTransferErrorCode.relayRejected,
                    stage: GaslessTransferStage.preview,
                    message: 'GasFree custody balance is insufficient',
                    retryable: false,
                    terminal: true,
                  ),
                ),
              )
              ..gaslessAccountStatusHandler = (_) async =>
                  _gaslessStatus(onChain: '100');
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: AssetPubkeys(
                assetId: asset.id,
                keys: [gasfreeSource],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({
              asset.id: _balance('100'),
              parent.id: _balance('50'),
            }),
          ),
          mm2Api: _FakeMm2Api(),
          walletType: WalletType.hdwallet,
          gaslessFeatureConfigured: true,
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '12');
        bloc.add(const WithdrawFormPreviewSubmitted());

        final errored = await bloc.stream.firstWhereBounded(
          (state) => state.previewError != null,
        );
        // Custody-aware, token-denominated message — never "insufficient TRX",
        // and no top-up offer (the custody address is the account).
        expect(
          errored.previewError!.message,
          contains('withdrawGaslessInsufficientGasFreeBalance'),
        );
      },
    );

    test(
      'duplicate submit events are dropped while broadcast is running',
      () async {
        final asset = _assetFromConfig(_utxoConfig());
        final preview = _utxoPreview(
          assetId: asset.id.id,
          txHash: 'preview-1',
          toAddress: 'recipient-1',
          timestamp: 1,
        );
        final progressController = StreamController<WithdrawalProgress>();
        addTearDown(progressController.close);
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => preview,
          executeWithdrawalHandler: (_, __) => progressController.stream,
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        final sendingState = bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm && state.isSending,
        );
        bloc.add(const WithdrawFormSubmitted());
        bloc.add(const WithdrawFormSubmitted());
        await sendingState;
        await _flush();

        expect(withdrawals.executeCallCount, 1);

        progressController.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'done',
            withdrawalResult: _resultFromPreview(preview),
          ),
        );

        final successState = await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.success,
        );

        expect(withdrawals.executeCallCount, 1);
        expect(successState.result?.txHash, 'preview-1');
      },
    );

    test('submit ignores expired TRON preview until refresh', () async {
      final asset = _assetFromConfig(_trxConfig());
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronPreview(
          txHash: 'expired-preview',
          toAddress: 'tron-recipient',
          timestamp: now - 120,
        ),
        executeWithdrawalHandler: (_, __) async* {},
      );

      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({
            asset.id: _assetPubkeys(asset, balance: '5'),
          }),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');

      bloc.add(const WithdrawFormPreviewSubmitted());
      await bloc.stream.firstWhereBounded(
        (state) =>
            state.step == WithdrawFormStep.confirm && state.isPreviewExpired,
      );

      bloc.add(const WithdrawFormSubmitted());
      await _flush();

      expect(withdrawals.executeCallCount, 0);
      expect(bloc.state.step, WithdrawFormStep.confirm);
      expect(bloc.state.confirmStepError, isNotNull);
    });

    test(
      'gasless preview expires at the signed authorization deadline',
      () async {
        final asset = _trc20Asset();
        final now =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        final authorizationDeadline = now - 1;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'expired-gasless-preview',
            toAddress: 'tron-recipient',
            // A future result timestamp proves it cannot extend the signed
            // relay authorization.
            timestamp: now + 3600,
            authorizationDeadline: authorizationDeadline,
          ),
          executeWithdrawalHandler: (_, __) async* {},
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        final expired = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm && state.isPreviewExpired,
        );

        expect(
          expired.previewExpiresAt,
          DateTime.fromMillisecondsSinceEpoch(
            authorizationDeadline * Duration.millisecondsPerSecond,
            isUtc: true,
          ),
        );
        bloc.add(const WithdrawFormSubmitted());
        await _flush();
        expect(withdrawals.executeCallCount, 0);
      },
    );

    test(
      'gasless preview accepts a fresh signed authorization deadline',
      () async {
        final asset = _trc20Asset();
        final now =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        final authorizationDeadline = now + 120;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'fresh-gasless-preview',
            toAddress: 'tron-recipient',
            // Relay previews can have an absent/old result timestamp; freshness
            // comes from the typed signed_authorization.deadline.
            timestamp: now - 3600,
            authorizationDeadline: authorizationDeadline,
          ),
        );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        final ready = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'fresh-gasless-preview',
        );

        expect(ready.isPreviewExpired, isFalse);
        expect(
          ready.previewExpiresAt,
          DateTime.fromMillisecondsSinceEpoch(
            authorizationDeadline * Duration.millisecondsPerSecond,
            isUtc: true,
          ),
        );
      },
    );

    for (final malformedDeadline in <Object?>[null, 'not-an-epoch']) {
      test(
        'gasless preview fails closed for '
        '${malformedDeadline == null ? 'missing' : 'malformed'} deadline',
        () async {
          final asset = _trc20Asset();
          final now =
              DateTime.now().toUtc().millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond;
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronGaslessPreview(
              txHash: 'invalid-deadline-preview',
              toAddress: 'tron-recipient',
              timestamp: now,
              includeAuthorizationDeadline: malformedDeadline != null,
              signedAuthorizationDeadline: malformedDeadline,
            ),
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final rejected = await bloc.stream.firstWhereBounded(
            (state) =>
                state.step == WithdrawFormStep.fill &&
                state.previewError != null &&
                state.gaslessQuoteFailure?.failureClass ==
                    GaslessQuoteFailureClass.securityMismatch,
          );

          expect(rejected.preview, isNull);
          expect(rejected.isPreviewExpired, isFalse);
          expect(rejected.confirmStepError, isNull);
          expect(withdrawals.executeCallCount, 0);
        },
      );
    }

    test('gasless preview fails closed when the U256 deadline is outside '
        'Dart DateTime range', () async {
      final asset = _trc20Asset();
      final now =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _tronGaslessPreview(
          txHash: 'unrepresentable-deadline-preview',
          toAddress: 'tron-recipient',
          timestamp: now,
          signedAuthorizationDeadline: ((BigInt.one << 256) - BigInt.one)
              .toString(),
        ),
      );
      final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
      bloc.add(const WithdrawFormPreviewSubmitted());
      final expired = await bloc.stream.firstWhereBounded(
        (state) =>
            state.step == WithdrawFormStep.confirm && state.isPreviewExpired,
      );

      expect(expired.previewSecondsRemaining, 0);
      expect(expired.confirmStepError, isNotNull);
    });

    test('send max recomputes amount when source address changes', () async {
      final asset = _assetFromConfig(_utxoConfig());
      final sourceOne = _pubkeyForAsset(
        asset,
        address: 'source-one',
        balance: '5',
      );
      final sourceTwo = _pubkeyForAsset(
        asset,
        address: 'source-two',
        balance: '2',
      );

      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _utxoPreview(
              assetId: asset.id.id,
              txHash: 'unused',
              toAddress: 'recipient',
              timestamp: 1,
            ),
          ),
          pubkeys: _FakePubkeyManager({
            asset.id: AssetPubkeys(
              assetId: asset.id,
              keys: [sourceOne, sourceTwo],
              availableAddressesCount: 2,
              syncStatus: SyncStatusEnum.success,
            ),
          }),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
      );
      addTearDown(bloc.close);

      bloc.add(WithdrawFormSourceChanged(sourceOne));
      await bloc.stream.firstWhereBounded(
        (state) => state.selectedSourceAddress?.address == 'source-one',
      );

      bloc.add(const WithdrawFormMaxAmountEnabled(true));
      await bloc.stream.firstWhereBounded(
        (state) => state.isMaxAmount && state.amount == '5',
      );

      bloc.add(WithdrawFormSourceChanged(sourceTwo));
      final updated = await bloc.stream.firstWhereBounded(
        (state) =>
            state.selectedSourceAddress?.address == 'source-two' &&
            state.amount == '2',
      );

      expect(updated.isMaxAmount, isTrue);
    });

    test('preview refresh recovers after expired quote', () async {
      final asset = _assetFromConfig(_trxConfig());
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var previewCalls = 0;
      final refreshedCompleter = Completer<WithdrawalPreview>();

      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async {
          previewCalls += 1;
          if (previewCalls == 1) {
            return _tronPreview(
              txHash: 'expired-preview',
              toAddress: 'tron-recipient',
              timestamp: now - 120,
            );
          }

          return refreshedCompleter.future;
        },
      );

      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({
            asset.id: _assetPubkeys(asset, balance: '5'),
          }),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');
      bloc.add(const WithdrawFormPreviewSubmitted());
      await bloc.stream.firstWhereBounded((state) => state.isPreviewExpired);

      final refreshing = bloc.stream.firstWhereBounded(
        (state) => state.isPreviewRefreshing,
      );
      bloc.add(const WithdrawFormTronPreviewRefreshRequested());
      await refreshing;

      refreshedCompleter.complete(
        _tronPreview(
          txHash: 'fresh-preview',
          toAddress: 'tron-recipient',
          timestamp: now + 10,
        ),
      );

      final refreshed = await bloc.stream.firstWhereBounded(
        (state) =>
            !state.isPreviewRefreshing &&
            !state.isPreviewExpired &&
            state.preview?.txHash == 'fresh-preview',
      );

      expect(withdrawals.previewCallCount, 2);
      expect(refreshed.confirmStepError, isNull);
    });

    test('validation maps known sdk errors to user-facing state', () async {
      final asset = _assetFromConfig(_utxoConfig());
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async =>
            throw Exception('insufficient gas for transaction'),
      );

      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({asset.id: _assetPubkeys(asset)}),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
      bloc.add(const WithdrawFormPreviewSubmitted());

      final errored = await bloc.stream.firstWhereBounded(
        (state) => state.previewError != null,
      );

      expect(
        errored.previewError!.message,
        contains('notEnoughBalanceForGasError'),
      );
    });

    test(
      'SIA preview omits source derivation path in request params',
      () async {
        final asset = _assetFromConfig(_siaConfig());
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _utxoPreview(
            assetId: asset.id.id,
            txHash: 'preview-sia',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );

        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: _assetPubkeys(asset, balance: '5'),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        expect(withdrawals.previewRequests.single.from, isNull);
      },
    );

    test('Trezor blocks SIA preview and submit', () async {
      final asset = _assetFromConfig(_siaConfig());
      final withdrawals = _FakeWithdrawalManager(
        previewWithdrawalHandler: (_) async => _utxoPreview(
          assetId: asset.id.id,
          txHash: 'preview-sia',
          toAddress: 'recipient-1',
          timestamp: 1,
        ),
      );

      final bloc = WithdrawFormBloc(
        asset: asset,
        sdk: _FakeSdk(
          addresses: _FakeAddressOperations(),
          withdrawals: withdrawals,
          pubkeys: _FakePubkeyManager({
            asset.id: _assetPubkeys(asset, balance: '5'),
          }),
          balances: _FakeBalanceManager({asset.id: _balance('5')}),
        ),
        mm2Api: _FakeMm2Api(),
        walletType: WalletType.trezor,
      );
      addTearDown(bloc.close);

      await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

      bloc.add(const WithdrawFormPreviewSubmitted());
      final previewBlocked = await bloc.stream.firstWhereBounded(
        (state) => state.previewError != null,
      );

      expect(previewBlocked.previewError?.message, contains('SIA is not'));
      expect(withdrawals.previewCallCount, 0);

      bloc.add(const WithdrawFormSubmitted());
      final submitBlocked = await bloc.stream.firstWhereBounded(
        (state) => state.transactionError != null,
      );

      expect(submitBlocked.transactionError?.message, contains('SIA is not'));
      expect(withdrawals.executeCallCount, 0);
    });

    group('localized amount errors', () {
      // Without EasyLocalization initialized, .tr() echoes the key — the
      // assertions pin each branch to its LocaleKeys entry.
      test('native-rail amount above balance uses the localized key', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          initialGaslessEnabled: false,
          pubkeyBalance: '5',
        );
        addTearDown(bloc.close);
        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormAmountChanged('10'));
        final errored = await bloc.stream.firstWhereBounded(
          (s) => s.amountError != null,
        );
        expect(
          errored.amountError!.message,
          contains('withdrawNotSufficientBalanceError'),
        );
      });

      test('zero amount uses the localized too-low key', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          initialGaslessEnabled: false,
        );
        addTearDown(bloc.close);
        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormAmountChanged('0'));
        final errored = await bloc.stream.firstWhereBounded(
          (s) => s.amountError != null,
        );
        expect(
          errored.amountError!.message,
          contains('withdrawAmountTooLowError'),
        );
      });

      test('unparseable amount uses the localized invalid key', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          initialGaslessEnabled: false,
        );
        addTearDown(bloc.close);
        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormAmountChanged('abc'));
        final errored = await bloc.stream.firstWhereBounded(
          (s) => s.amountError != null,
        );
        expect(
          errored.amountError!.message,
          contains('withdrawInvalidAmountError'),
        );
      });
    });

    group('structured GasFree shortfall errors', () {
      test(
        'structured SdkError renders via its own key, not the generic text',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => throw SdkError(
              code: SdkErrorCode.insufficientFunds,
              category: SdkErrorCategory.funds,
              messageKey: 'withdrawGaslessInsufficientGasFreeBalance',
              fallbackMessage:
                  'Your GasFree address has 0 USDT-TRC20, but this send '
                  'needs 8 USDT-TRC20.',
              messageArgs: const [
                '',
                '0',
                'USDT-TRC20',
                '8',
                'USDT-TRC20',
                'USDT-TRC20',
              ],
              retryable: false,
              source: GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                code: GaslessTransferErrorCode.relayRejected,
                stage: GaslessTransferStage.preview,
                message: 'GasFree custody balance is insufficient',
                retryable: false,
                terminal: true,
              ),
            ),
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final errored = await bloc.stream.firstWhereBounded(
            (s) => s.previewError != null,
          );

          // The short-circuit renders the structured key directly (echoed in
          // tests) — the string normalizers must not collapse it back into
          // the generic gasless-balance text.
          expect(
            errored.previewError!.message,
            contains('withdrawGaslessInsufficientGasFreeBalance'),
          );
          expect(
            errored.previewError!.message,
            isNot(contains('withdrawGaslessInsufficientBalanceGeneric')),
          );
          expect(
            errored.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.insufficientFunds,
              retryable: false,
            ),
          );
        },
      );

      test(
        'typed quote classification is independent of localized copy',
        () async {
          final asset = _trc20Asset();
          final typedFailure = GaslessTransferException(
            kind: GaslessTransferErrorKind.traceUnavailable,
            code: GaslessTransferErrorCode.providerTimeout,
            stage: GaslessTransferStage.preview,
            message: 'Le fournisseur ne répond pas',
            retryable: true,
            terminal: false,
          );
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => throw SdkError(
              code: SdkErrorCode.timeout,
              category: SdkErrorCategory.network,
              messageKey: 'sdk_errors.gasless_status_unavailable',
              fallbackMessage: 'Le fournisseur ne répond pas',
              retryable: true,
              source: typedFailure,
            ),
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final errored = await bloc.stream.firstWhereBounded(
            (state) => state.gaslessQuoteFailure != null,
          );

          expect(
            errored.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.timeout,
              retryable: true,
            ),
          );
        },
      );

      test(
        'untyped shortfall-like text does not invent a KDF lifecycle state',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => throw Exception(
              'Not enough USDT-TRC20 in your GasFree deposit address: '
              'available 0, required 8. Deposit USDT-TRC20 into your GasFree '
              'address.',
            ),
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final errored = await bloc.stream.firstWhereBounded(
            (s) => s.previewError != null,
          );

          expect(errored.previewError!.message, 'somethingWrong');
          expect(
            errored.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.unknown,
              retryable: false,
            ),
          );
        },
      );
    });

    group('gasless account status', () {
      test('source switch disables GasFree and cannot apply an older custody '
          'observation', () async {
        final asset = _trc20Asset();
        final firstStatus = Completer<GaslessAccountStatusResponse>();
        var statusCalls = 0;
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'unused',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) {
                statusCalls += 1;
                return statusCalls == 1
                    ? firstStatus.future
                    : Future.value(
                        _gaslessStatus(
                          gasfreeAddress: 'gasfree-source-address-2',
                        ),
                      );
              };
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        while (statusCalls == 0) {
          await _flush();
        }
        final replacement = _pubkeyForAsset(asset, address: 'source-address-2');
        final replacementReady = bloc.stream.firstWhereBounded(
          (state) =>
              state.selectedSourceAddress?.address == 'source-address-2' &&
              !state.isGaslessEnabled,
        );
        bloc.add(WithdrawFormSourceChanged(replacement));
        await replacementReady;

        firstStatus.complete(_gaslessStatus());
        await _flush();
        expect(bloc.state.gaslessAccountStatus, isNull);
        expect(withdrawals.gaslessStatusCallCount, greaterThanOrEqualTo(1));
      });

      test(
        'rail switch invalidates an in-flight custody observation',
        () async {
          final asset = _trc20Asset();
          final pendingStatus = Completer<GaslessAccountStatusResponse>();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronGaslessPreview(
              txHash: 'unused',
              toAddress: 'recipient-1',
              timestamp: 1,
            ),
          )..gaslessAccountStatusHandler = (_) => pendingStatus.future;
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          while (withdrawals.gaslessStatusCallCount == 0) {
            await _flush();
          }
          bloc.add(const WithdrawFormGaslessToggled(false));
          await bloc.stream.firstWhereBounded((state) => !state.isGaslessEnabled);

          pendingStatus.complete(_gaslessStatus());
          await _flush();

          expect(bloc.state.isGaslessEnabled, isFalse);
          expect(bloc.state.gaslessAccountStatus, isNull);
          expect(bloc.state.isGaslessStatusLoading, isFalse);
        },
      );

      test('fetched once on open and cached within TTL', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'unused',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        final ready = await bloc.stream.firstWhereBounded(
          (s) => s.gaslessAccountStatus != null,
        );
        expect(
          ready.gaslessAccountStatus?.availability,
          GaslessAccountAvailability.available,
        );
        expect(
          ready.gaslessAccountStatus?.maxWithdrawable,
          Decimal.fromInt(99),
        );
        expect(ready.gaslessAccountStatus?.serviceProvider, isNotEmpty);
        expect(withdrawals.gaslessStatusCallCount, 1);

        bloc.add(const WithdrawFormGaslessStatusRequested());
        await _flush();
        expect(withdrawals.gaslessStatusCallCount, 1, reason: 'TTL cache hit');

        bloc.add(const WithdrawFormGaslessStatusRequested(force: true));
        await _flush();
        await _flush();
        expect(withdrawals.gaslessStatusCallCount, 2, reason: 'force refetch');
      });

      test('fetch failure pauses GasFree before preview', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        ); // no gaslessAccountStatusHandler → the call throws
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          stubAvailableGaslessStatus: false,
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
        if (bloc.state.gaslessAvailability !=
            GaslessAvailability.temporarilyUnavailable) {
          await bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessAvailability ==
                GaslessAvailability.temporarilyUnavailable,
          );
        }
        expect(bloc.state.gaslessAccountStatus, isNull);
        expect(bloc.state.previewError, isNull);
        expect(bloc.state.networkError, isNull);
        expect(bloc.state.amountError, isNull);
        expect(
          bloc.state.gaslessAvailability,
          GaslessAvailability.temporarilyUnavailable,
        );

        bloc.add(const WithdrawFormPreviewSubmitted());
        await _flush();
        await _flush();
        expect(bloc.state.step, WithdrawFormStep.fill);
        expect(
          bloc.state.gaslessAvailability,
          GaslessAvailability.temporarilyUnavailable,
        );
        expect(withdrawals.previewCallCount, 0);
      });

      test('failed refresh marks an existing snapshot stale', () async {
        final asset = _trc20Asset();
        var shouldFail = false;
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'preview-1',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) async {
                if (shouldFail) throw StateError('provider offline');
                return _gaslessStatus();
              };
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) => state.gaslessAvailability == GaslessAvailability.ready,
        );
        shouldFail = true;
        bloc.add(const WithdrawFormGaslessStatusRequested(force: true));
        final stale = await bloc.stream.firstWhereBounded(
          (state) => state.gaslessAvailability == GaslessAvailability.stale,
        );

        expect(stale.gaslessAccountStatus, isNotNull);
        expect(stale.isGaslessAvailabilityNeutral, isTrue);
      });

      test(
        'GaslessNotConfigured disables GasFree until controlled reactivation',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'must-not-preview',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async =>
                    throw GaslessTransferException(
                      kind: GaslessTransferErrorKind.configuration,
                      code: GaslessTransferErrorCode.gaslessNotConfigured,
                      stage: GaslessTransferStage.status,
                      message:
                          'GasFree requires controlled reactivation with provider '
                          'settings',
                      retryable: false,
                      terminal: true,
                    );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          final disabled = await bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessAvailability == GaslessAvailability.disabled,
          );
          expect(disabled.gaslessAccountStatus, isNull);
          expect(disabled.isGaslessSendBlocked, isTrue);
          expect(disabled.isGaslessAvailabilityNeutral, isFalse);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final blocked = await bloc.stream.firstWhereBounded(
            (state) => state.gaslessQuoteFailure != null,
          );

          expect(withdrawals.previewCallCount, 0);
          expect(
            blocked.previewError?.message,
            contains('withdrawGaslessUnavailableBlocked'),
          );
          expect(
            blocked.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.capabilityNotReady,
              retryable: false,
            ),
          );
        },
      );

      test(
        'retryable capabilityNotReady remains temporary on the send path',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'must-not-preview',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async =>
                    throw GaslessTransferException(
                      kind: GaslessTransferErrorKind.capabilityNotReady,
                      code: GaslessTransferErrorCode.capabilityNotReady,
                      stage: GaslessTransferStage.status,
                      message:
                          'A newer account-status probe superseded this one',
                      retryable: true,
                      terminal: false,
                    );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          final temporary = await bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessAvailability ==
                    GaslessAvailability.temporarilyUnavailable &&
                state.gaslessStatusMessage != null,
          );

          expect(temporary.gaslessAccountStatus, isNull);
          expect(temporary.isGaslessAvailabilityNeutral, isTrue);
          expect(temporary.isGaslessSendBlocked, isTrue);
        },
      );

      for (final testCase
          in <(String, GaslessTransferErrorCode, GaslessAvailability)>[
            (
              'CoinNotSupported',
              GaslessTransferErrorCode.coinNotSupported,
              GaslessAvailability.unsupported,
            ),
            (
              'NotEthCoin',
              GaslessTransferErrorCode.notEthCoin,
              GaslessAvailability.unsupported,
            ),
            (
              'GaslessNotConfigured',
              GaslessTransferErrorCode.gaslessNotConfigured,
              GaslessAvailability.disabled,
            ),
            (
              'CoinNotFound',
              GaslessTransferErrorCode.coinNotFound,
              GaslessAvailability.disabled,
            ),
          ]) {
        test(
          '${testCase.$1} retains its exact KDF send classification',
          () async {
            final asset = _trc20Asset();
            final withdrawals =
                _FakeWithdrawalManager(
                    previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                      txHash: 'must-not-preview',
                      toAddress: 'recipient-1',
                      timestamp: 1,
                    ),
                  )
                  ..gaslessAccountStatusHandler = (_) async =>
                      throw GaslessTransferException(
                        kind: GaslessTransferErrorKind.configuration,
                        code: testCase.$2,
                        stage: GaslessTransferStage.status,
                        message: testCase.$1,
                        retryable: false,
                        terminal: true,
                      );
            final bloc = _buildTrc20Bloc(
              asset: asset,
              withdrawals: withdrawals,
            );
            addTearDown(bloc.close);

            final mapped = await bloc.stream.firstWhereBounded(
              (state) => state.gaslessAvailability == testCase.$3,
            );

            expect(mapped.gaslessAccountStatus, isNull);
            expect(mapped.gaslessMaxWithdrawable, isNull);
            expect(mapped.gaslessTransferFee, isNull);
            expect(mapped.isGaslessSendBlocked, isTrue);
          },
        );
      }

      for (final testCase
          in <(GaslessAccountAvailability, GaslessAvailability, bool)>[
            (
              GaslessAccountAvailability.available,
              GaslessAvailability.ready,
              false,
            ),
            (
              GaslessAccountAvailability.pendingTransfer,
              GaslessAvailability.pendingTransfer,
              true,
            ),
            (
              GaslessAccountAvailability.tokenUnsupported,
              GaslessAvailability.unsupported,
              true,
            ),
            (
              GaslessAccountAvailability.providerUnreachable,
              GaslessAvailability.providerUnavailable,
              true,
            ),
          ]) {
        test(
          '${testCase.$1.wireValue} maps from the exact KDF status shape',
          () async {
            final asset = _trc20Asset();
            final withdrawals =
                _FakeWithdrawalManager(
                    previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                      txHash: 'must-not-preview',
                      toAddress: 'recipient-1',
                      timestamp: 1,
                    ),
                  )
                  ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                    availability: testCase.$1,
                    onChain: '42',
                    maxWithdrawable: '41',
                    frozen:
                        testCase.$1 ==
                            GaslessAccountAvailability.pendingTransfer
                        ? '42'
                        : '0',
                    spendable:
                        testCase.$1 ==
                            GaslessAccountAvailability.pendingTransfer
                        ? '0'
                        : '42',
                  );
            final bloc = _buildTrc20Bloc(
              asset: asset,
              withdrawals: withdrawals,
            );
            addTearDown(bloc.close);

            final mapped = await bloc.stream.firstWhereBounded(
              (state) => state.gaslessAvailability == testCase.$2,
            );

            expect(
              mapped.gaslessAccountStatus?.onChainBalance,
              Decimal.fromInt(42),
            );
            expect(mapped.isGaslessSendBlocked, testCase.$3);
          },
        );
      }

      for (final hardFailure in <(String, Object)>[
        (
          'token decimal mismatch',
          GaslessTransferException(
            kind: GaslessTransferErrorKind.providerResponse,
            code: GaslessTransferErrorCode.tokenDecimalMismatch,
            stage: GaslessTransferStage.status,
            message: 'account token decimals do not match the selected asset',
            retryable: false,
            terminal: true,
          ),
        ),
        (
          'custody mismatch',
          GaslessTransferException(
            kind: GaslessTransferErrorKind.providerResponse,
            code: GaslessTransferErrorCode.custodyAddressMismatch,
            stage: GaslessTransferStage.status,
            message: 'account custody does not match the selected source',
            retryable: false,
            terminal: true,
          ),
        ),
        (
          'provider identity mismatch',
          GaslessTransferException(
            kind: GaslessTransferErrorKind.providerResponse,
            code: GaslessTransferErrorCode.serviceProviderMismatch,
            stage: GaslessTransferStage.status,
            message: 'account provider does not match the production pin',
            retryable: false,
            terminal: true,
          ),
        ),
        (
          'SDK response mismatch',
          GaslessTransferException(
            kind: GaslessTransferErrorKind.providerResponse,
            code: GaslessTransferErrorCode.responseMismatch,
            stage: GaslessTransferStage.status,
            message: 'invalid account status',
            retryable: false,
            terminal: true,
          ),
        ),
      ]) {
        test('${hardFailure.$1} clears stale fees and fails closed', () async {
          final asset = _trc20Asset();
          var failure = false;
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'must-not-preview',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async {
                  if (failure) throw hardFailure.$2;
                  return _gaslessStatus(maxWithdrawable: '99');
                };
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded(
            (state) => state.gaslessAvailability == GaslessAvailability.ready,
          );
          expect(bloc.state.gaslessMaxWithdrawable, Decimal.fromInt(99));

          failure = true;
          bloc.add(const WithdrawFormGaslessStatusRequested(force: true));
          final blocked = await bloc.stream.firstWhereBounded(
            (state) =>
                state.gaslessAvailability ==
                GaslessAvailability.securityMismatch,
          );

          expect(blocked.gaslessAccountStatus, isNotNull);
          expect(blocked.gaslessMaxWithdrawable, isNull);
          expect(blocked.gaslessTransferFee, isNull);
          expect(blocked.gaslessActivationFee, isNull);
          expect(blocked.isGaslessSendBlocked, isTrue);
        });
      }

      test('typed pending transfer has truthful blocked state', () async {
        final asset = _trc20Asset();
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'must-not-preview',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                availability: GaslessAccountAvailability.pendingTransfer,
                onChain: '42',
                frozen: '42',
                spendable: '0',
              );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        final pending = await bloc.stream.firstWhereBounded(
          (state) =>
              state.gaslessAvailability == GaslessAvailability.pendingTransfer,
        );
        expect(pending.isGaslessSendBlocked, isTrue);
        expect(pending.gaslessMaxWithdrawable, isNull);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());
        await _flush();

        expect(withdrawals.previewCallCount, 0);
        expect(
          bloc.state.gaslessAvailability,
          GaslessAvailability.pendingTransfer,
        );
        expect(bloc.state.previewError, isNull);
      });

      test('typed unsupported status never exposes send fees', () async {
        final asset = _trc20Asset();
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'must-not-preview',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                availability: GaslessAccountAvailability.tokenUnsupported,
              );
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        final blocked = await bloc.stream.firstWhereBounded(
          (state) =>
              state.gaslessAvailability == GaslessAvailability.unsupported,
        );
        expect(blocked.gaslessMaxWithdrawable, isNull);
        expect(blocked.gaslessTransferFee, isNull);
        expect(blocked.isGaslessSendBlocked, isTrue);
      });

      test(
        'gasless max displays max_withdrawable, not EOA spendable',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'unused',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async =>
                    _gaslessStatus(maxWithdrawable: '99');
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
          await _awaitSourceSelection(bloc);

          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          final maxState = await bloc.stream.firstWhereBounded(
            (s) => s.isMaxAmount && s.amount == '99',
          );

          // Display-only: the request still delegates the amount to KDF.
          final params = maxState.toWithdrawParameters();
          expect(params.isMax, isTrue);
          expect(params.amount, isNull);
        },
      );

      test('status fee floor stays advisory for max preview', () async {
        final asset = _trc20Asset();
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'unused',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                active: false,
                onChain: '3',
                maxWithdrawable: '0',
                transferFee: '1.5',
                activationFee: '1.5',
              );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '5',
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
        await _awaitSourceSelection(bloc);

        final maxStateFuture = bloc.stream.firstWhereBounded((s) => s.isMaxAmount);
        bloc.add(const WithdrawFormMaxAmountEnabled(true));
        final maxState = await maxStateFuture;

        expect(maxState.amountError, isNull);
        expect(maxState.toWithdrawParameters().isMax, isTrue);
        expect(maxState.toWithdrawParameters().amount, isNull);
      });

      test(
        'max with a genuinely empty custody does not raise the below-fees error',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'unused',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                  active: false,
                  onChain: '0',
                  maxWithdrawable: '0',
                  transferFee: '1.5',
                  activationFee: '1.5',
                );
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
          await _awaitSourceSelection(bloc);

          final maxStateFuture = bloc.stream.firstWhereBounded(
            (s) => s.isMaxAmount && s.amount == '0',
          );
          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          final maxState = await maxStateFuture;
          expect(maxState.amountError, isNull);
        },
      );

      test(
        'fully frozen custody is pending, not below the fee floor',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                    txHash: 'unused',
                    toAddress: 'recipient-1',
                    timestamp: 1,
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async => _gaslessStatus(
                  availability: GaslessAccountAvailability.pendingTransfer,
                  onChain: '10',
                  spendable: '0',
                  frozen: '10',
                );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
          await _awaitSourceSelection(bloc);
          final maxStateFuture = bloc.stream.firstWhereBounded(
            (s) => s.isMaxAmount && s.amount.isEmpty,
          );
          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          final maxState = await maxStateFuture;

          expect(maxState.isGaslessSendBlocked, isTrue);
          expect(maxState.amountError, isNull);
        },
      );

      test('status custody cap stays advisory for explicit amount', () async {
        final asset = _trc20Asset();
        final withdrawals =
            _FakeWithdrawalManager(
                previewWithdrawalHandler: (_) async => _tronGaslessPreview(
                  txHash: 'unused',
                  toAddress: 'recipient-1',
                  timestamp: 1,
                ),
              )
              ..gaslessAccountStatusHandler = (_) async =>
                  _gaslessStatus(maxWithdrawable: '99');
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '500',
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormAmountChanged('100'));
        final acceptedForPreview = await bloc.stream.firstWhereBounded(
          (s) => s.amount == '100',
        );
        expect(acceptedForPreview.amountError, isNull);

        bloc.add(const WithdrawFormAmountChanged('99'));
        final cleared = await bloc.stream.firstWhereBounded((s) => s.amount == '99');
        expect(cleared.amountError, isNull);
      });

      test(
        'provider unavailable blocks preview honestly and self-heals',
        () async {
          final asset = _trc20Asset();
          var providerUp = false;
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronGaslessPreview(
              txHash: 'unused',
              toAddress: 'recipient-1',
              timestamp: 1,
            ),
          );
          withdrawals.gaslessAccountStatusHandler = (_) async => _gaslessStatus(
            availability: providerUp
                ? GaslessAccountAvailability.available
                : GaslessAccountAvailability.providerUnreachable,
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded((s) => s.isGaslessProviderUnavailable);
          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          final callsBeforePreview = withdrawals.gaslessStatusCallCount;

          bloc.add(const WithdrawFormPreviewSubmitted());
          final blocked = await bloc.stream.firstWhereBounded(
            (s) => s.previewError != null,
          );

          expect(
            blocked.previewError!.message,
            contains('withdrawGaslessProviderUnavailable'),
          );
          expect(
            blocked.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.serviceUnavailable,
              retryable: true,
            ),
          );
          expect(withdrawals.previewCallCount, 0);

          // The block force-refreshes the status; with the provider back the
          // guard lifts without user action.
          providerUp = true;
          await bloc.stream.firstWhereBounded((s) => !s.isGaslessProviderUnavailable);
          expect(
            withdrawals.gaslessStatusCallCount,
            greaterThan(callsBeforePreview),
          );
        },
      );

      test(
        'gasless params carry the 300s permit deadline and 60s preview TTL',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronGaslessPreview(
              txHash: 'unused',
              toAddress: 'recipient-1',
              timestamp: 1,
            ),
          )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          final params = bloc.state.toWithdrawParameters();

          expect(params.gaslessOptions?.deadlineSeconds, 300);
          expect(params.gaslessOptions?.fallbackToNative, isFalse);
          expect(params.expirationSeconds, 60);
        },
      );

      test(
        'toggling gasless off clears stale errors and recomputes max',
        () async {
          final asset = _trc20Asset();
          final withdrawals =
              _FakeWithdrawalManager(
                  previewWithdrawalHandler: (_) async => throw Exception(
                    'gasfree balance not enough, available 1, '
                    'required at least 2',
                  ),
                )
                ..gaslessAccountStatusHandler = (_) async =>
                    _gaslessStatus(maxWithdrawable: '99');
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
            balances: {
              asset.id: _balance('5'),
              // Parent TRX funded so the native max guard passes after toggle.
              asset.id.parentId!: _balance('10'),
            },
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded((s) => s.gaslessAccountStatus != null);
          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

          bloc.add(const WithdrawFormPreviewSubmitted());
          await bloc.stream.firstWhereBounded((s) => s.previewError != null);

          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          await bloc.stream.firstWhereBounded((s) => s.isMaxAmount);

          bloc.add(const WithdrawFormGaslessToggled(false));
          final toggled = await bloc.stream.firstWhereBounded(
            (s) => !s.isGaslessEnabled && s.amount == '5',
          );

          expect(toggled.previewError, isNull);
          expect(toggled.networkError, isNull);
          expect(toggled.transactionError, isNull);
          expect(toggled.confirmStepError, isNull);
          expect(toggled.gaslessStatusMessage, isNull);
          // Max recomputed on the native rail from the EOA spendable balance.
          expect(toggled.isMaxAmount, isTrue);
        },
      );

      test(
        'untyped provider-looking preview errors remain safely generic',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async =>
                throw Exception('GasFree authentication failed: 401'),
          )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());

          final errored = await bloc.stream.firstWhereBounded(
            (s) => s.previewError != null,
          );
          expect(errored.previewError!.message, 'somethingWrong');
          expect(
            errored.previewError!.message,
            isNot(contains('withdrawGaslessInsufficientBalance')),
          );
          expect(
            errored.gaslessQuoteFailure,
            const GaslessQuoteFailure(
              failureClass: GaslessQuoteFailureClass.unknown,
              retryable: false,
            ),
          );
        },
      );

      test(
        'Trezor TRC-20 is gasless-blocked with the honest notice flag',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronPreview(
              txHash: 'unused',
              toAddress: 'recipient-1',
              timestamp: 1,
            ),
          );
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            walletType: WalletType.trezor,
          );
          addTearDown(bloc.close);

          expect(bloc.state.isGaslessSupported, isFalse);
          expect(bloc.state.isGaslessTrezorBlocked, isTrue);
          expect(withdrawals.gaslessStatusCallCount, 0);
        },
      );
    });

    group('consolidation prefill', () {
      test(
        'locked consolidation cannot change source, rail, recipient, or Max',
        () async {
          final asset = _trc20Asset();
          final parentId = asset.id.parentId!;
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronPreview(
              txHash: 'preview-consolidate',
              toAddress: 'gasfree-source-address',
              timestamp: 1,
            ),
          );
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
            balances: {asset.id: _balance('5'), parentId: _balance('10')},
            initialRecipient: 'gasfree-source-address',
            initialGaslessEnabled: false,
            initialIsMax: true,
            lockSourceSelection: true,
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded(
            (state) =>
                state.recipientAddress == 'gasfree-source-address' &&
                state.selectedSourceAddress?.address == 'source-address' &&
                state.isMaxAmount &&
                state.amount == '5',
          );

          bloc
            ..add(const WithdrawFormGaslessToggled(true))
            ..add(const WithdrawFormRecipientChanged('other-recipient'))
            ..add(const WithdrawFormMaxAmountEnabled(false))
            ..add(const WithdrawFormAmountChanged('1'))
            ..add(
              WithdrawFormSourceChanged(
                _pubkeyForAsset(asset, address: 'other-source', balance: '5'),
              ),
            );
          await _flush();

          expect(bloc.state.selectedSourceAddress?.address, 'source-address');
          expect(bloc.state.isGaslessEnabled, isFalse);
          expect(bloc.state.useGasless, isFalse);
          expect(bloc.state.recipientAddress, 'gasfree-source-address');
          expect(bloc.state.isMaxAmount, isTrue);
          expect(bloc.state.amount, '5');

          bloc.add(const WithdrawFormPreviewSubmitted());
          await bloc.stream.firstWhereBounded(
            (state) => state.step == WithdrawFormStep.confirm,
          );
          final request = withdrawals.previewRequests.single;
          expect(
            request.from,
            WithdrawalSource.hdDerivationPath(
              bloc.state.selectedSourceAddress!.derivationPath!,
            ),
          );
          expect(request.feeMethod, isNull);
          expect(request.toAddress, 'gasfree-source-address');
          expect(request.isMax, isTrue);
          expect(request.amount, isNull);
        },
      );

      test(
        'locked consolidation does not fall back when its source disappears',
        () async {
          final asset = _trc20Asset();
          final parent = _assetFromConfig(_trxConfig());
          final source = _pubkeyForAsset(
            asset,
            address: 'locked-source',
            balance: '5',
            gasfreeAddress: 'gasfree-source-address',
          );
          final otherSource = _pubkeyForAsset(
            asset,
            address: 'other-source',
            balance: '7',
            derivationPath: "m/44'/195'/0'/0/1",
          );
          final pubkeysByAssetId = <AssetId, AssetPubkeys>{
            asset.id: AssetPubkeys(
              assetId: asset.id,
              keys: [source, otherSource],
              availableAddressesCount: 2,
              syncStatus: SyncStatusEnum.success,
            ),
            parent.id: AssetPubkeys(
              assetId: parent.id,
              keys: [
                _pubkeyForAsset(parent, address: source.address, balance: '10'),
              ],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          };
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronPreview(
              txHash: 'must-not-preview',
              toAddress: 'gasfree-source-address',
              timestamp: 1,
            ),
          );
          final bloc = WithdrawFormBloc(
            asset: asset,
            sdk: _FakeSdk(
              addresses: _FakeAddressOperations(),
              withdrawals: withdrawals,
              pubkeys: _FakePubkeyManager(pubkeysByAssetId),
              balances: _FakeBalanceManager({
                asset.id: _balance('12'),
                parent.id: _balance('10'),
              }),
              assets: _FakeAssetManager({parent.id: parent}),
            ),
            mm2Api: _FakeMm2Api(),
            walletType: WalletType.hdwallet,
            initialRecipient: 'gasfree-source-address',
            initialSourceAddress: source,
            initialGaslessEnabled: false,
            initialIsMax: true,
            lockSourceSelection: true,
            gaslessFeatureConfigured: true,
            authorizationFailureMessage: 'GasFree consolidation paused',
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhereBounded(
            (state) =>
                state.selectedSourceAddress?.address == source.address &&
                state.recipientAddress == 'gasfree-source-address' &&
                state.isMaxAmount,
          );

          pubkeysByAssetId[asset.id] = AssetPubkeys(
            assetId: asset.id,
            keys: [otherSource],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          );
          bloc.add(const WithdrawFormSourcesLoadRequested());
          await bloc.stream.firstWhereBounded(
            (state) => state.selectedSourceAddress == null,
          );

          bloc.add(const WithdrawFormPreviewSubmitted());
          final blocked = await bloc.stream.firstWhereBounded(
            (state) =>
                state.previewError?.message == 'GasFree consolidation paused',
          );

          expect(blocked.selectedSourceAddress, isNull);
          expect(withdrawals.previewCallCount, 0);
        },
      );

      test('authorization loss blocks the source preview', () async {
        final asset = _trc20Asset();
        final parentId = asset.id.parentId!;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'must-not-preview',
            toAddress: 'gasfree-source-address',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '5',
          balances: {asset.id: _balance('5'), parentId: _balance('10')},
          initialRecipient: 'gasfree-source-address',
          initialGaslessEnabled: false,
          initialIsMax: true,
          authorizationGuard: () async => false,
          authorizationFailureMessage: 'GasFree consolidation paused',
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) =>
              state.recipientAddress == 'gasfree-source-address' &&
              state.amount == '5',
        );
        bloc.add(const WithdrawFormPreviewSubmitted());
        final blocked = await bloc.stream.firstWhereBounded(
          (state) =>
              state.previewError?.message == 'GasFree consolidation paused',
        );

        expect(blocked.step, WithdrawFormStep.fill);
        expect(blocked.preview, isNull);
        expect(withdrawals.previewCallCount, 0);
      });

      test('authorization loss blocks execution after preview', () async {
        var authorized = true;
        final asset = _trc20Asset();
        final parentId = asset.id.parentId!;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'preview-consolidate',
            toAddress: 'gasfree-source-address',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '5',
          balances: {asset.id: _balance('5'), parentId: _balance('10')},
          initialRecipient: 'gasfree-source-address',
          initialGaslessEnabled: false,
          initialIsMax: true,
          authorizationGuard: () => authorized,
          authorizationFailureMessage: 'GasFree consolidation paused',
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (state) =>
              state.recipientAddress == 'gasfree-source-address' &&
              state.amount == '5',
        );
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        authorized = false;
        bloc.add(const WithdrawFormSubmitted());
        final blocked = await bloc.stream.firstWhereBounded(
          (state) =>
              state.step == WithdrawFormStep.fill &&
              state.previewError?.message == 'GasFree consolidation paused',
        );

        expect(blocked.preview, isNull);
        expect(withdrawals.previewCallCount, 1);
        expect(withdrawals.executeCallCount, 0);
      });

      test('prefills custody recipient, native rail, and max', () async {
        final asset = _trc20Asset();
        final parentId = asset.id.parentId!;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'preview-consolidate',
            toAddress: 'gasfree-source-address',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '5',
          balances: {asset.id: _balance('5'), parentId: _balance('10')},
          initialRecipient: 'gasfree-source-address',
          initialGaslessEnabled: false,
          initialIsMax: true,
        );
        addTearDown(bloc.close);

        final primed = await bloc.stream.firstWhereBounded(
          (s) =>
              s.recipientAddress == 'gasfree-source-address' &&
              s.isMaxAmount &&
              s.amount == '5',
        );
        expect(primed.isGaslessEnabled, isFalse);
        expect(primed.useGasless, isFalse);

        // The native self-transfer guard must not block sending to the
        // user's own custody address.
        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhereBounded((s) => s.step == WithdrawFormStep.confirm);
        expect(withdrawals.previewCallCount, 1);
      });

      test('reset preserves the consolidation prefill and tolerates empty '
          'sources', () async {
        final asset = _trc20Asset();
        final parentId = asset.id.parentId!;
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'unused',
            toAddress: 'gasfree-source-address',
            timestamp: 1,
          ),
        );
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '5',
          balances: {asset.id: _balance('5'), parentId: _balance('10')},
          initialRecipient: 'gasfree-source-address',
          initialGaslessEnabled: false,
          initialIsMax: true,
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhereBounded(
          (s) => s.recipientAddress == 'gasfree-source-address',
        );

        bloc.add(const WithdrawFormReset());
        final restored = await bloc.stream.firstWhereBounded(
          (s) =>
              s.recipientAddress == 'gasfree-source-address' && s.isMaxAmount,
        );
        // The prefilled rail survives a reset — a "try again" keeps the
        // native consolidation instead of degrading to a gasless form.
        expect(restored.isGaslessEnabled, isFalse);
      });

      test(
        'zero parent TRX blocks the native consolidation honestly',
        () async {
          final asset = _trc20Asset();
          final withdrawals = _FakeWithdrawalManager(
            previewWithdrawalHandler: (_) async => _tronPreview(
              txHash: 'unused',
              toAddress: 'gasfree-source-address',
              timestamp: 1,
            ),
          );
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
            balances: {asset.id: _balance('5')}, // parent TRX missing → zero
            initialRecipient: 'gasfree-source-address',
            initialGaslessEnabled: false,
            initialIsMax: true,
          );
          addTearDown(bloc.close);

          final blocked = await bloc.stream.firstWhereBounded(
            (s) => s.amountError != null,
          );
          // TRON's native-rail guard names TRX and the standard address —
          // the one flow honestly allowed to require TRX.
          expect(
            blocked.amountError!.message,
            contains('withdrawTronNativeNeedsTrx'),
          );
          expect(blocked.isMaxAmount, isFalse);
        },
      );

      test('TRX on a different derivation cannot fund consolidation', () async {
        final asset = _trc20Asset();
        final parent = _assetFromConfig(_trxConfig());
        final tokenSource = _pubkeyForAsset(
          asset,
          balance: '5',
          gasfreeAddress: 'gasfree-source-address',
          derivationPath: "m/44'/195'/0'/0/0",
        );
        final otherTrxSource = _pubkeyForAsset(
          parent,
          address: 'other-source-address',
          balance: '10',
          derivationPath: "m/44'/195'/0'/0/1",
        );
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronPreview(
            txHash: 'unused',
            toAddress: 'gasfree-source-address',
            timestamp: 1,
          ),
        );
        final bloc = WithdrawFormBloc(
          asset: asset,
          sdk: _FakeSdk(
            addresses: _FakeAddressOperations(),
            withdrawals: withdrawals,
            pubkeys: _FakePubkeyManager({
              asset.id: AssetPubkeys(
                assetId: asset.id,
                keys: [tokenSource],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
              parent.id: AssetPubkeys(
                assetId: parent.id,
                keys: [otherTrxSource],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            // A wallet-wide lookup sees TRX, but it is not on tokenSource.
            balances: _FakeBalanceManager({parent.id: _balance('10')}),
            assets: _FakeAssetManager({parent.id: parent}),
          ),
          mm2Api: _FakeMm2Api(),
          initialRecipient: 'gasfree-source-address',
          initialGaslessEnabled: false,
          gaslessFeatureConfigured: true,
        );
        addTearDown(bloc.close);

        await _awaitSourceSelection(bloc);
        bloc.add(const WithdrawFormMaxAmountEnabled(true));
        final blocked = await bloc.stream.firstWhereBounded(
          (state) => state.amountError != null,
        );
        expect(blocked.isMaxAmount, isFalse);
        expect(
          blocked.amountError!.message,
          contains('withdrawTronNativeNeedsTrx'),
        );
      });
    });
  });
}

void main() {
  testWithdrawFormBloc();
}
