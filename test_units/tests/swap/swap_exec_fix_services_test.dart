import 'package:flutter_test/flutter_test.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_src_sdk_fakes.dart' hide atomicSwapOf;

/// Covers which atomic swaps sign-in picks back up: every one that has not
/// finished, however it is going.
void main() {
  test('signing in follows swaps still refunding, and none that finished, '
      'whichever side the wallet took', () async {
    final sdk = SrcSdk();
    final dex = SrcDex();
    final mm2 = SrcMm2Api();
    final services = servicesOf(sdk, dex: dex, mm2: mm2);
    final at = DateTime.now().subtract(const Duration(hours: 1));
    const takerPaid = [
      'Started',
      'Negotiated',
      'TakerFeeSent',
      'MakerPaymentReceived',
      'TakerPaymentSent',
      'TakerPaymentWaitForSpendFailed',
    ];
    const makerPaid = [
      'Started',
      'Negotiated',
      'TakerFeeValidated',
      'MakerPaymentSent',
      'TakerPaymentValidateFailed',
    ];
    mm2.page = recentSwapsOf([
      atomicSwapOf('taker-refunding', [
        ...takerPaid,
        'TakerPaymentWaitRefundStarted',
      ], at: at),
      atomicSwapOf(
        'maker-refunding',
        [...makerPaid, 'MakerPaymentRefundStarted'],
        maker: true,
        at: at,
      ),
      atomicSwapOf('taker-refunded', [
        ...takerPaid,
        'TakerPaymentRefunded',
        'Finished',
      ], at: at),
      atomicSwapOf('failed', [
        'Started',
        'NegotiateFailed',
        'Finished',
      ], at: at),
    ]);

    sdk.auth.users.add(userOf('alice'));
    await pumpEventQueue();

    expect(dex.statusReads, ['taker-refunding', 'maker-refunding']);
    await services.dispose();
  });
}
