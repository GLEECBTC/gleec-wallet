import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/wallet.dart';

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
}) {
  return PubkeyInfo(
    address: address,
    derivationPath: "m/44'/141'/0'/0/0",
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
}) {
  return WithdrawResult(
    txJson: const {
      'relay_type': 'tron_gasfree',
      'chain_id': '728126428',
      'coin': 'USDT-TRC20',
      'from_address': 'source-address',
      'gasfree_address': 'gasfree-source-address',
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
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'gasfree-source-address',
      transferFee: Decimal.parse('1'),
      totalTokenFee: Decimal.parse('1'),
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
  bool providerAvailable = true,
  bool? active = true,
  String onChain = '100',
  String? maxWithdrawable = '98',
  String? transferFee = '1',
  String? activationFee,
}) {
  return GaslessAccountStatusResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'gasfree_address': 'gasfree-source-address',
      'on_chain_balance': onChain,
      'provider_available': providerAvailable,
      if (active != null) 'active': active,
      if (maxWithdrawable != null) 'max_withdrawable': maxWithdrawable,
      if (transferFee != null) 'transfer_fee': transferFee,
      if (activationFee != null) 'activation_fee': activationFee,
      'frozen_balance': '0',
      'spendable_balance': onChain,
    },
  });
}

/// Builds a TRC-20 bloc whose single source address carries a GasFree custody
/// address, mirroring the production gasless setup.
WithdrawFormBloc _buildTrc20Bloc({
  required Asset asset,
  required _FakeWithdrawalManager withdrawals,
  Map<AssetId, BalanceInfo>? balances,
  WalletType? walletType,
  String? initialRecipient,
  bool initialGaslessEnabled = true,
  bool initialIsMax = false,
  String pubkeyBalance = '5',
}) {
  final pubkeys = AssetPubkeys(
    assetId: asset.id,
    keys: [
      _pubkeyForAsset(
        asset,
        balance: pubkeyBalance,
        gasfreeAddress: 'gasfree-source-address',
      ),
    ],
    availableAddressesCount: 1,
    syncStatus: SyncStatusEnum.success,
  );
  return WithdrawFormBloc(
    asset: asset,
    sdk: _FakeSdk(
      addresses: _FakeAddressOperations(),
      withdrawals: withdrawals,
      pubkeys: _FakePubkeyManager({asset.id: pubkeys}),
      balances: _FakeBalanceManager(
        balances ?? {asset.id: _balance(pubkeyBalance)},
      ),
    ),
    mm2Api: _FakeMm2Api(),
    walletType: walletType,
    initialRecipient: initialRecipient,
    initialGaslessEnabled: initialGaslessEnabled,
    initialIsMax: initialIsMax,
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

WithdrawalResult _resultFromPreview(WithdrawalPreview preview) {
  return WithdrawalResult(
    txHash: preview.txHash,
    balanceChanges: preview.balanceChanges,
    coin: preview.coin,
    toAddress: preview.to.first,
    fee: preview.fee,
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _awaitSourceSelection(WithdrawFormBloc bloc) async {
  if (bloc.state.selectedSourceAddress != null) {
    return;
  }
  await bloc.stream.firstWhere((state) => state.selectedSourceAddress != null);
}

Future<void> _primeFillState(
  WithdrawFormBloc bloc, {
  required String recipient,
  required String amount,
}) async {
  await _awaitSourceSelection(bloc);

  final recipientState = bloc.stream.firstWhere(
    (state) => state.recipientAddress == recipient,
  );
  bloc.add(WithdrawFormRecipientChanged(recipient));
  await recipientState;

  final amountState = bloc.stream.firstWhere((state) => state.amount == amount);
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
  }) : _previewWithdrawalHandler = previewWithdrawalHandler,
       _getFeeOptionsHandler = getFeeOptionsHandler,
       _executeWithdrawalHandler = executeWithdrawalHandler;

  final Future<WithdrawalPreview> Function(WithdrawParameters params)
  _previewWithdrawalHandler;
  final Future<WithdrawalFeeOptions?> Function(String assetId)?
  _getFeeOptionsHandler;
  final Stream<WithdrawalProgress> Function(
    WithdrawalPreview preview,
    String assetId,
  )?
  _executeWithdrawalHandler;

  int previewCallCount = 0;
  int executeCallCount = 0;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this._pubkeysByAssetId);

  final Map<AssetId, AssetPubkeys> _pubkeysByAssetId;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) => _pubkeysByAssetId[assetId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBalanceManager implements BalanceManager {
  _FakeBalanceManager(this._balances);

  final Map<AssetId, BalanceInfo> _balances;

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _balances[assetId];

  @override
  Future<BalanceInfo> getBalance(AssetId assetId) async =>
      _balances[assetId] ?? BalanceInfo.zero();

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
  });

  @override
  final AddressOperations addresses;

  @override
  final WithdrawalManager withdrawals;

  @override
  final PubkeyManager pubkeys;

  @override
  final BalanceManager balances;

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

      final sendingState = bloc.stream.firstWhere((state) => state.isSending);
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

      final confirmState = await bloc.stream.firstWhere(
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

        final sendingState = bloc.stream.firstWhere((state) => state.isSending);
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

        final confirmState = await bloc.stream.firstWhere(
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

        final sendingState = bloc.stream.firstWhere((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        feeOptionsCompleter.complete(expectedFeeOptions);
        final feeDefaultedState = await bloc.stream.firstWhere(
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

        final confirmState = await bloc.stream.firstWhere(
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

        final sendingState = bloc.stream.firstWhere((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        pubkeysByAssetId[asset.id] = AssetPubkeys(
          assetId: asset.id,
          keys: [updatedPubkey],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        );
        bloc.add(const WithdrawFormSourcesLoadRequested());
        await bloc.stream.firstWhere(
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

        final settledState = await bloc.stream.firstWhere(
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

        final sendingState = bloc.stream.firstWhere((state) => state.isSending);
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

        await bloc.stream.firstWhere(
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
        await bloc.stream.firstWhere(
          (state) => state.recipientAddress == 'recipient-1',
        );

        bloc.add(const WithdrawFormRecipientChanged('recipient-2'));
        await bloc.stream.firstWhere(
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
        await bloc.stream.firstWhere(
          (state) =>
              state.step == WithdrawFormStep.confirm &&
              state.preview?.txHash == 'preview-1',
        );

        final refreshingState = bloc.stream.firstWhere(
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

        final refreshedState = await bloc.stream.firstWhere(
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
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'gasless-preview',
            toAddress: 'tron-recipient',
            timestamp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
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
                keys: [nativeOnlySource, gasfreeSource],
                availableAddressesCount: 2,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('5')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '1');

        expect(bloc.state.useGasless, isTrue);
        expect(bloc.state.pubkeys?.keys, [gasfreeSource]);
        expect(bloc.state.selectedSourceAddress, gasfreeSource);

        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhere(
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
      },
    );

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
        await bloc.stream.firstWhere(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        bloc.add(const WithdrawFormSubmitted());
        await bloc.stream.firstWhere((state) => state.isSending);

        progressController.add(
          const WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free transfer submitted...',
            gaslessState: GaslessTraceState.submitted,
          ),
        );
        final relaying = await bloc.stream.firstWhere(
          (state) => state.gaslessTraceState != null,
        );
        expect(relaying.gaslessTraceState, GaslessTraceState.submitted);
        expect(relaying.gaslessStatusMessage, isNotNull);

        progressController.add(
          WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Withdrawal complete',
            withdrawalResult: _resultFromPreview(preview),
          ),
        );
        final success = await bloc.stream.firstWhere(
          (state) => state.step == WithdrawFormStep.success,
        );
        expect(success.gaslessTraceState, isNull);
        expect(success.gaslessStatusMessage, isNull);
      },
    );

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
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => throw WithdrawalException(
            'Not enough USDT-TRC20 to withdraw and activate the destination: '
            'available 0, required at least 14, activation fee 1.5',
            WithdrawalErrorCode.insufficientFunds,
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
                keys: [gasfreeSource],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            }),
            balances: _FakeBalanceManager({asset.id: _balance('100')}),
          ),
          mm2Api: _FakeMm2Api(),
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '12');
        bloc.add(const WithdrawFormPreviewSubmitted());

        final errored = await bloc.stream.firstWhere(
          (state) => state.previewError != null,
        );

        expect(
          errored.previewError!.message,
          contains('withdrawGaslessInsufficientBalance'),
        );
        expect(
          errored.previewError!.message,
          isNot(contains('notEnoughBalanceForGasError')),
        );
      },
    );

    WithdrawalException custodyShortError({
      String available = '0',
      String required = '14',
      String activationFee = '1.5',
    }) => WithdrawalException(
      'Not enough USDT-TRC20 to withdraw and activate the destination: '
      'available $available, required at least $required, '
      'activation fee $activationFee',
      WithdrawalErrorCode.insufficientFunds,
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
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async =>
              throw custodyShortError(available: '0', required: '14'),
        );
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
        );
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'tron-recipient', amount: '12');
        bloc.add(const WithdrawFormPreviewSubmitted());

        final errored = await bloc.stream.firstWhere(
          (state) => state.previewError != null,
        );
        // Custody-aware, token-denominated message — never "insufficient TRX",
        // and no top-up offer (the custody address is the account).
        expect(
          errored.previewError!.message,
          contains('withdrawGaslessInsufficientBalance'),
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
        await bloc.stream.firstWhere(
          (state) => state.step == WithdrawFormStep.confirm,
        );

        final sendingState = bloc.stream.firstWhere(
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

        final successState = await bloc.stream.firstWhere(
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
      await bloc.stream.firstWhere(
        (state) =>
            state.step == WithdrawFormStep.confirm && state.isPreviewExpired,
      );

      bloc.add(const WithdrawFormSubmitted());
      await _flush();

      expect(withdrawals.executeCallCount, 0);
      expect(bloc.state.step, WithdrawFormStep.confirm);
      expect(bloc.state.confirmStepError, isNotNull);
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
      await bloc.stream.firstWhere(
        (state) => state.selectedSourceAddress?.address == 'source-one',
      );

      bloc.add(const WithdrawFormMaxAmountEnabled(true));
      await bloc.stream.firstWhere(
        (state) => state.isMaxAmount && state.amount == '5',
      );

      bloc.add(WithdrawFormSourceChanged(sourceTwo));
      final updated = await bloc.stream.firstWhere(
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
      await bloc.stream.firstWhere((state) => state.isPreviewExpired);

      final refreshing = bloc.stream.firstWhere(
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

      final refreshed = await bloc.stream.firstWhere(
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

      final errored = await bloc.stream.firstWhere(
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
        await bloc.stream.firstWhere(
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
      final previewBlocked = await bloc.stream.firstWhere(
        (state) => state.previewError != null,
      );

      expect(previewBlocked.previewError?.message, contains('SIA is not'));
      expect(withdrawals.previewCallCount, 0);

      bloc.add(const WithdrawFormSubmitted());
      final submitBlocked = await bloc.stream.firstWhere(
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
        final errored = await bloc.stream.firstWhere(
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
        final errored = await bloc.stream.firstWhere(
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
        final errored = await bloc.stream.firstWhere(
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
            ),
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          bloc.add(const WithdrawFormPreviewSubmitted());
          final errored = await bloc.stream.firstWhere(
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
        },
      );

      test(
        'new KDF shortfall phrasing still matches the string fallback',
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
          final errored = await bloc.stream.firstWhere(
            (s) => s.previewError != null,
          );

          // The new phrasing drops "at least"; the widened regex must still
          // extract the amounts and produce the token-denominated message.
          expect(
            errored.previewError!.message,
            'withdrawGaslessInsufficientBalance',
          );
        },
      );
    });

    group('gasless account status', () {
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

        await bloc.stream.firstWhere((s) => s.gaslessAccountStatus != null);
        expect(withdrawals.gaslessStatusCallCount, 1);

        bloc.add(const WithdrawFormGaslessStatusRequested());
        await _flush();
        expect(withdrawals.gaslessStatusCallCount, 1, reason: 'TTL cache hit');

        bloc.add(const WithdrawFormGaslessStatusRequested(force: true));
        await _flush();
        await _flush();
        expect(withdrawals.gaslessStatusCallCount, 2, reason: 'force refetch');
      });

      test('fetch failure degrades silently and preview still works', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async => _tronGaslessPreview(
            txHash: 'preview-1',
            toAddress: 'recipient-1',
            timestamp: 1,
          ),
        ); // no gaslessAccountStatusHandler → the call throws
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
        expect(bloc.state.gaslessAccountStatus, isNull);
        expect(bloc.state.previewError, isNull);
        expect(bloc.state.networkError, isNull);
        expect(bloc.state.amountError, isNull);

        bloc.add(const WithdrawFormPreviewSubmitted());
        await bloc.stream.firstWhere((s) => s.step == WithdrawFormStep.confirm);
        expect(withdrawals.previewCallCount, 1);
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
                    _gaslessStatus(maxWithdrawable: '98');
          final bloc = _buildTrc20Bloc(
            asset: asset,
            withdrawals: withdrawals,
            pubkeyBalance: '5',
          );
          addTearDown(bloc.close);

          await bloc.stream.firstWhere((s) => s.gaslessAccountStatus != null);
          await _awaitSourceSelection(bloc);

          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          final maxState = await bloc.stream.firstWhere(
            (s) => s.isMaxAmount && s.amount == '98',
          );

          // Display-only: the request still delegates the amount to KDF.
          final params = maxState.toWithdrawParameters();
          expect(params.isMax, isTrue);
          expect(params.amount, isNull);
        },
      );

      test('amount above the custody cap errors in token terms', () async {
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
                  _gaslessStatus(maxWithdrawable: '98');
        final bloc = _buildTrc20Bloc(
          asset: asset,
          withdrawals: withdrawals,
          pubkeyBalance: '500',
        );
        addTearDown(bloc.close);

        await bloc.stream.firstWhere((s) => s.gaslessAccountStatus != null);
        await _awaitSourceSelection(bloc);

        bloc.add(const WithdrawFormAmountChanged('99'));
        final errored = await bloc.stream.firstWhere(
          (s) => s.amountError != null,
        );
        expect(
          errored.amountError!.message,
          contains('withdrawGaslessAmountExceedsMax'),
        );

        bloc.add(const WithdrawFormAmountChanged('98'));
        final cleared = await bloc.stream.firstWhere((s) => s.amount == '98');
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
            providerAvailable: providerUp,
            active: providerUp ? true : null,
            maxWithdrawable: providerUp ? '98' : null,
            transferFee: providerUp ? '1' : null,
          );
          final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
          addTearDown(bloc.close);

          await bloc.stream.firstWhere((s) => s.isGaslessProviderUnavailable);
          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
          final callsBeforePreview = withdrawals.gaslessStatusCallCount;

          bloc.add(const WithdrawFormPreviewSubmitted());
          final blocked = await bloc.stream.firstWhere(
            (s) => s.previewError != null,
          );

          expect(
            blocked.previewError!.message,
            contains('withdrawGaslessProviderUnavailable'),
          );
          expect(withdrawals.previewCallCount, 0);

          // The block force-refreshes the status; with the provider back the
          // guard lifts without user action.
          providerUp = true;
          await bloc.stream.firstWhere((s) => !s.isGaslessProviderUnavailable);
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
                    _gaslessStatus(maxWithdrawable: '98');
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

          await bloc.stream.firstWhere((s) => s.gaslessAccountStatus != null);
          await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

          bloc.add(const WithdrawFormPreviewSubmitted());
          await bloc.stream.firstWhere((s) => s.previewError != null);

          bloc.add(const WithdrawFormMaxAmountEnabled(true));
          await bloc.stream.firstWhere((s) => s.isMaxAmount);

          bloc.add(const WithdrawFormGaslessToggled(false));
          final toggled = await bloc.stream.firstWhere(
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

      test('provider-outage preview errors are never diagnosed as insufficient '
          'balance', () async {
        final asset = _trc20Asset();
        final withdrawals = _FakeWithdrawalManager(
          previewWithdrawalHandler: (_) async =>
              throw Exception('GasFree authentication failed: 401'),
        )..gaslessAccountStatusHandler = (_) async => _gaslessStatus();
        final bloc = _buildTrc20Bloc(asset: asset, withdrawals: withdrawals);
        addTearDown(bloc.close);

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');
        bloc.add(const WithdrawFormPreviewSubmitted());

        final errored = await bloc.stream.firstWhere(
          (s) => s.previewError != null,
        );
        expect(
          errored.previewError!.message,
          contains('withdrawGaslessProviderUnavailable'),
        );
        expect(
          errored.previewError!.message,
          isNot(contains('withdrawGaslessInsufficientBalance')),
        );
      });

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

        final primed = await bloc.stream.firstWhere(
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
        await bloc.stream.firstWhere((s) => s.step == WithdrawFormStep.confirm);
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

        await bloc.stream.firstWhere(
          (s) => s.recipientAddress == 'gasfree-source-address',
        );

        bloc.add(const WithdrawFormReset());
        final restored = await bloc.stream.firstWhere(
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

          final blocked = await bloc.stream.firstWhere(
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
    });
  });
}

void main() {
  testWithdrawFormBloc();
}
