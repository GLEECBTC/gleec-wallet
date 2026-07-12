import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';

void testTransactionEventPrivacy() {
  group('transaction analytics privacy', () {
    test('GasFree provider errors never include raw payload data', () {
      const secret = 'api_secret=super-sensitive';
      const address = 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird';
      final event = SendFailedEventData(
        asset: 'USDT-TRC20',
        network: 'trc20',
        failureReason:
            'Provider unavailable at https://example.test?$secret for $address',
        hdType: 'hdwallet',
      );

      final reason = event.parameters['failure_reason'] as String;
      expect(reason, 'reason:service_unavailable');
      expect(reason, isNot(contains(secret)));
      expect(reason, isNot(contains(address)));
    });

    test('response mismatches use a stable security category', () {
      final event = SendFailedEventData(
        asset: 'USDT-TRC20',
        network: 'trc20',
        failureReason: 'Receiver mismatch: TPrivateRecipientAddress',
        hdType: 'iguana',
      );

      expect(event.parameters['failure_reason'], 'reason:security_mismatch');
    });

    test('unclassified failures collapse to unknown', () {
      final event = SendFailedEventData(
        asset: 'USDT-TRC20',
        network: 'trc20',
        failureReason: 'opaque-upstream-body-with-user-data',
        hdType: 'iguana',
      );

      expect(event.parameters['failure_reason'], 'reason:unknown');
    });

    test('GasFree lifecycle analytics contains only allowlisted fields', () {
      const event = GaslessTransferAnalyticsEventData(
        stage: 'submitted unknown',
        code:
            'Provider unavailable for 12.5 at TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
        retryable: false,
      );

      expect(event.parameters, {
        'stage': 'submitted_unknown',
        'code': 'service_unavailable',
        'rail': 'tron_gasfree',
        'retryable': false,
      });
      expect(event.parameters.keys, isNot(contains('amount')));
      expect(event.parameters.keys, isNot(contains('asset')));
      expect(event.parameters.toString(), isNot(contains('12.5')));
      expect(event.parameters.toString(), isNot(contains('TLntW9')));
    });
  });
}
