// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';

/// Failure diagnostics deliberately exclude wallet names, identities, addresses,
/// secrets, raw RPC payloads and unstructured error messages.
Future<void> printMartyBalanceDiagnostics(
  WidgetTester tester,
  Finder receiveButton,
) async {
  final context = tester.element(receiveButton);
  final sdk = context.read<KomodoDefiSdk>();
  final coins = context.read<CoinsBloc>().state;
  final coin = coins.walletCoins['MARTY'] ?? coins.coins['MARTY'];
  final addresses = context.read<CoinAddressesBloc>().state;
  final balanceWidget = tester.widget(
    find.byKey(const Key('coin-details-balance')),
  );
  final content = tester.widget<CoinDetailsBalanceContent>(
    find.byType(CoinDetailsBalanceContent),
  );
  final activation = coin == null ? null : sdk.activationStates[coin.id];
  final policy = sdk.activationPolicy.current;
  final diagnostics = {
    'balanceWidgetType': balanceWidget.runtimeType.toString(),
    'isLoadingSkeleton': balanceWidget is Container,
    'balanceText': balanceWidget is AutoScrollText ? balanceWidget.text : null,
    'confirmed': content.isConfirmed,
    'hidden': content.hideBalances,
    'displaySpendable': content.latestBalance?.spendable.toString(),
    'coinState': coin?.state.name,
    'coinConfigId': coin?.id.id,
    'activationStatus': activation?.status.name,
    'activationErrorCode': activation?.sdkError?.code.name,
    'activationErrorIndicators': _errorIndicators(activation?.errorMessage),
    'policyCredentialConfigured': const String.fromEnvironment(
      'FEEDBACK_API_KEY',
    ).isNotEmpty,
    'geoPolicyExplicitlyDisabled':
        const String.fromEnvironment('GEO_BLOCK') == 'disabled',
    'policyStatus': policy.status.name,
    'policyCanActivate': coin != null && policy.canActivate(coin.id),
    'policyBlocked': coin != null && policy.isBlocked(coin.id),
    'activationStateSummaries': [
      for (final entry in sdk.activationStates.entries)
        {
          'configId': entry.key.id,
          'equalsMartyId': entry.key == coin?.id,
          'status': entry.value.status.name,
        },
    ],
    'addressStatus': addresses.status.name,
    'addressCount': addresses.addresses.length,
    'addressSpendable': addresses.addresses
        .map((a) => a.balance.spendable.toString())
        .toList(),
    'addressErrorIndicators': _errorIndicators(addresses.errorMessage),
    'addressErrorIsPolicyPending':
        coin != null &&
        addresses.errorMessage ==
            ActivationPolicyException(
              coin.id,
              ActivationPolicyStatus.loading,
            ).toString(),
    'addressErrorIsPolicyRestricted':
        coin != null &&
        addresses.errorMessage ==
            ActivationPolicyException(
              coin.id,
              ActivationPolicyStatus.ready,
            ).toString(),
    'cachedPubkeyCount': coins.pubkeys['MARTY']?.keys.length,
    'cachedSpendable': coin == null
        ? null
        : sdk.balances.lastKnown(coin.id)?.spendable.toString(),
    'balanceWatcherActive':
        coin != null && sdk.balances.hasActiveWatcher(coin.id),
    'receiveEnabled':
        tester.widget<UiPrimaryButton>(receiveButton).onPressed != null,
  };
  print('WITHDRAW BALANCE DIAGNOSTICS: $diagnostics');
  await _printMartyCoreDiagnostics(sdk);
}

Future<void> printMartyActivationDiagnostics(BuildContext context) async {
  final sdk = context.read<KomodoDefiSdk>();
  final coins = context.read<CoinsBloc>().state;
  final coin = coins.walletCoins['MARTY'] ?? coins.coins['MARTY'];
  final policy = sdk.activationPolicy.current;
  final activation = coin == null ? null : sdk.activationStates[coin.id];
  print(
    'WITHDRAW ACTIVATION DIAGNOSTICS: ${{
      'walletListContainsMarty': coins.walletCoins.containsKey('MARTY'),
      'coinState': coin?.state.name,
      'coinConfigId': coin?.id.id,
      'policyCredentialConfigured': const String.fromEnvironment('FEEDBACK_API_KEY').isNotEmpty,
      'geoPolicyExplicitlyDisabled': const String.fromEnvironment('GEO_BLOCK') == 'disabled',
      'policyStatus': policy.status.name,
      'policyCanActivate': coin != null && policy.canActivate(coin.id),
      'policyBlocked': coin != null && policy.isBlocked(coin.id),
      'activationStatus': activation?.status.name,
      'activationErrorCode': activation?.sdkError?.code.name,
      'activationErrorIndicators': _errorIndicators(activation?.errorMessage),
      'activationStateSummaries': [
        for (final entry in sdk.activationStates.entries) {'configId': entry.key.id, 'equalsMartyId': entry.key == coin?.id, 'status': entry.value.status.name},
      ],
      'cachedPubkeyCount': coins.pubkeys['MARTY']?.keys.length,
      'cachedSpendable': coin == null ? null : sdk.balances.lastKnown(coin.id)?.spendable.toString(),
      'balanceWatcherActive': coin != null && sdk.balances.hasActiveWatcher(coin.id),
    }}',
  );
  await _printMartyCoreDiagnostics(sdk);
}

Future<void> _printMartyCoreDiagnostics(KomodoDefiSdk sdk) async {
  // These read-only core RPCs do not pass through automatic activation, so they
  // distinguish SDK dispatch/publication from KDF state without repairing it.
  try {
    final enabled = await sdk.client.rpc.generalActivation
        .getEnabledCoins()
        .timeout(const Duration(seconds: 15));
    print(
      'WITHDRAW CORE ACTIVATION: '
      'martyEnabled=${enabled.result.any((c) => c.ticker == 'MARTY')}; '
      'enabledCoins=${enabled.result.map((c) => c.ticker).toList()}',
    );
    final balance = await sdk.client.rpc.wallet
        .myBalance(coin: 'MARTY')
        .timeout(const Duration(seconds: 15));
    print(
      'WITHDRAW CORE BALANCE: spendable=${balance.balance.spendable}; '
      'addressAvailable=${balance.address.isNotEmpty}',
    );
  } catch (error) {
    print(
      'WITHDRAW CORE READ FAILED: '
      'type=${error is MmRpcException ? 'MmRpcException' : error.runtimeType}; '
      'rpcErrorType=${error is MmRpcException ? error.errorType : null}; '
      'indicators=${_errorIndicators(error.toString())}',
    );
  }
}

List<String> _errorIndicators(String? message) {
  final normalized = message?.toLowerCase() ?? '';
  return [
    for (final token in [
      'timeout',
      'timed out',
      'electrum',
      'network',
      'connection',
      'all servers',
      'session',
      'wallet',
      'not enabled',
      'not found',
      'rpc',
      'balance',
      'protocol',
      'activation',
      'policy',
      'verification',
      'restricted',
    ])
      if (normalized.contains(token)) token,
  ];
}
