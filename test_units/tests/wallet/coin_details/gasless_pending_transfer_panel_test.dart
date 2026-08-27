import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_pending_transfer_panel.dart';

void main() {
  testWidgets(
    'Use Standard remains available while trace reconciliation is running',
    (tester) async {
      var standardRequests = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GaslessPendingTransferPanel(
                title: 'Transfer still processing',
                description: 'The unresolved GasFree transfer stays locked.',
                continueLabel: 'Continue checking',
                standardLabel: 'Use Standard transfer',
                activityLabel: 'View activity',
                supportLabel: 'Support',
                traceLabel: 'Trace ID',
                traceId: 'trace-pending',
                isChecking: true,
                onContinueChecking: () {},
                onUseStandard: () => standardRequests += 1,
                onViewActivity: () {},
                onSupport: () {},
              ),
            ),
          ),
        ),
      );

      final standardButton = find.byKey(
        const Key('withdraw-gasless-use-standard'),
      );
      expect(standardButton, findsOneWidget);

      await tester.tap(standardButton);
      await tester.pump();

      expect(standardRequests, 1);
    },
  );
}
