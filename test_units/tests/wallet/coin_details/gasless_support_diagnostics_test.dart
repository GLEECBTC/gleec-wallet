// test_units is this repository's test root, but analyzer's visibleForTesting
// path heuristic only recognizes a directory named exactly `test`.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

const _hostKey = Key('gasless-support-diagnostics-test-host');

void main() {
  group('GasFree support diagnostics', () {
    Future<void> pumpHost(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              key: _hostKey,
              builder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    BuildContext hostContext(WidgetTester tester) =>
        tester.element(find.byKey(_hostKey));

    testWidgets('clipboard success is reported to callers', (tester) async {
      await pumpHost(tester);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      var clipboardCalls = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls++;
          return null;
        }
        return null;
      });

      expect(await copyToClipBoard(hostContext(tester), 'diagnostics'), isTrue);
      expect(clipboardCalls, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('clipboard failure prevents support launch', (tester) async {
      await pumpHost(tester);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard-unavailable');
        }
        return null;
      });

      final copied = await copyToClipBoard(hostContext(tester), 'diagnostics');
      final canOpenSupport = await copyGaslessSupportDiagnosticsForLaunch(
        hostContext(tester),
        'diagnostics',
        copyDiagnostics: (_, _) async => copied,
      );

      expect(copied, isFalse);
      expect(canOpenSupport, isFalse);
      await tester.pump();
      expect(find.text('Failed to copy to clipboard'), findsOneWidget);
    });

    testWidgets('unmount after copy prevents support launch', (tester) async {
      await pumpHost(tester);
      final copyStarted = Completer<void>();
      final copyResult = Completer<bool>();

      final canOpenSupport = copyGaslessSupportDiagnosticsForLaunch(
        hostContext(tester),
        'diagnostics',
        copyDiagnostics: (_, _) {
          copyStarted.complete();
          return copyResult.future;
        },
      );
      await copyStarted.future;
      await tester.pumpWidget(const SizedBox.shrink());
      copyResult.complete(true);

      expect(await canOpenSupport, isFalse);
    });
  });
}
