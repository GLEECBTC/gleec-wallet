// Read-only live diagnostic for the frozen LiFi candidate.
// Only activates assets and quotes; never initializes or executes a swap.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/main.dart' as app;
import '../../common/report_failure.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Pinned WASM KDF reaches the live LiFi proxy',
    (tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      await acceptAlphaWarning(tester);
      await restoreWalletToTest(tester);
      await reportingFailure(binding, 'lifi_proxy_wasm', () async {
        final sdk = tester
            .element(find.byKey(const Key('main-menu-fiat')))
            .read<KomodoDefiSdk>();
        Future<Map<String, dynamic>> rpc(
          String method,
          Map<String, dynamic> params,
        ) async {
          if (!{
            'version',
            'enable_eth_with_tokens',
            'routed_swap::quote',
          }.contains(method)) {
            throw StateError(
              'Read-only diagnostic RPC allowlist rejected $method',
            );
          }
          return await sdk.client.executeRpc({
            'method': method,
            if (method != 'version') 'mmrpc': '2.0',
            if (method != 'version') 'params': params,
          });
        }

        final version = await rpc('version', {});
        expect(version['result'], contains('35f0bde'));
        final coins =
            jsonDecode(
                  await rootBundle.loadString(
                    'packages/komodo_defi_framework/assets/config/coins_config.json',
                  ),
                )
                as Map<String, dynamic>;
        final coin = coins['ETH-ARB20'] as Map<String, dynamic>;
        final urls = coin['nodes'] as List;
        final activation = await rpc('enable_eth_with_tokens', {
          'ticker': 'ETH-ARB20',
          'nodes': urls
              .map(
                (node) => {
                  'url': node['url'],
                  'komodo_proxy':
                      node['komodo_proxy'] ?? node['gui_auth'] ?? false,
                },
              )
              .toList(),
          'erc20_tokens_requests': [
            {'ticker': 'USDC-ARB20', 'required_confirmations': 3},
          ],
          'priv_key_policy': {'type': 'ContextPrivKey'},
          'tx_history': false,
          'get_balances': true,
          if (coin['swap_contract_address'] != null)
            'swap_contract_address': coin['swap_contract_address'],
          if (coin['fallback_swap_contract'] != null)
            'fallback_swap_contract': coin['fallback_swap_contract'],
        });
        expect(
          activation['error_type'],
          isNull,
          reason: 'Arbitrum activation must succeed',
        );
        final response = await rpc('routed_swap::quote', {
          'from': 'ETH-ARB20',
          'to': 'USDC-ARB20',
          'amount': '0.05',
          'slippage': 0.005,
          'order': 'cheapest',
        }).timeout(const Duration(minutes: 2));
        expect(
          response['error_type'],
          isNull,
          reason: 'Signed browser proxy quote must succeed',
        );
        final route = (response['result']['routes'] as List).first as Map;
        expect(route['from']['coin'], 'ETH-ARB20');
        expect(route['to']['coin'], 'USDC-ARB20');
        expect(
          double.parse(route['to']['amount_min'] as String),
          greaterThan(0),
        );
        final fees = (route['fee_costs'] as List)
            .where((fee) => fee['name'] == 'LIFI Fixed Fee')
            .toList();
        expect(fees, hasLength(1));
        expect(fees.single['included'], isTrue);
        expect(double.parse(fees.single['amount'] as String), 0.001);
        binding.reportData = {
          'lifi_proxy_wasm': {
            'version': version['result'],
            'proxy': 'https://quicknode.gleec.com/lifi',
            'pair': ['ETH-ARB20', 'USDC-ARB20'],
            'amount': '0.05',
            'quoted_minimum_positive': true,
            'included_commission': '0.001',
            'passed': true,
            'scope': 'activation and exact quote only',
          },
        };
      });
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
