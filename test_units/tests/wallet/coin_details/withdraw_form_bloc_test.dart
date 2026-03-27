import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';

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
}) {
  return PubkeyInfo(
    address: address,
    derivationPath: "m/44'/141'/0'/0/0",
    chain: 'external',
    balance: _balance(balance),
    coinTicker: asset.id.id,
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

void main() {
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

        await _primeFillState(bloc, recipient: 'recipient-1', amount: '1');

        final sendingState = bloc.stream.firstWhere((state) => state.isSending);
        bloc.add(const WithdrawFormPreviewSubmitted());
        await sendingState;

        feeOptionsCompleter.complete(expectedFeeOptions);
        await bloc.stream.firstWhere(
          (state) =>
              state.feeOptions == expectedFeeOptions &&
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
  });
}
