import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show GaslessTransferState;
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/bloc/withdraw_form/gasless_transfer_state.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_gate.dart';

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

    test('GasFree quote analytics contains only closed domain values', () {
      final event = GaslessTransferAnalyticsEventData.quoteFailure(
        const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.serviceUnavailable,
          retryable: false,
        ),
      );

      expect(event.parameters, {
        'stage': 'quote',
        'code': 'service_unavailable',
        'rail': 'tron_gasfree',
        'retryable': false,
      });
      expect(event.parameters.keys, isNot(contains('amount')));
      expect(event.parameters.keys, isNot(contains('asset')));
      expect(event.parameters.keys, isNot(contains('message')));
    });

    test('GasFree pending duration is coarse and clamps clock skew', () {
      final event = GaslessTransferAnalyticsEventData.pending(
        transferState: GaslessTransferState.submittedPending,
        pendingDuration: Duration(seconds: -1),
      );

      expect(event.parameters['stage'], 'submittedpending');
      expect(event.parameters['code'], 'transfer_pending');
      expect(event.parameters['pending_duration'], 'under_1m');
      expect(event.parameters.keys, isNot(contains('duration_ms')));
      expect(event.parameters.keys, isNot(contains('submitted_at')));
    });

    test('GasFree failure stage and code are derived from typed state', () {
      final event = GaslessTransferAnalyticsEventData.failed(
        transferState: GaslessTransferState.rejectedBeforeRelay,
        retryable: true,
      );

      expect(event.parameters, {
        'stage': 'rejectedbeforerelay',
        'code': 'rejected_before_relay',
        'rail': 'tron_gasfree',
        'retryable': true,
      });
    });

    test('GasFree receive analytics contains only closed domain values', () {
      const event = GaslessReceiveAnalyticsEventData(
        status: GaslessReceiveAnalyticsStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.providerTemporarilyUnavailable,
      );

      expect(event.parameters, {
        'status': 'temporarilyunavailable',
        'code': 'provider_temporarily_unavailable',
        'rail': 'tron_gasfree',
      });
      expect(event.parameters.keys, isNot(contains('address')));
      expect(event.parameters.keys, isNot(contains('amount')));
      expect(event.parameters.keys, isNot(contains('provider')));
    });
  });
}
