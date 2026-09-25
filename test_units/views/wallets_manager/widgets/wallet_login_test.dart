import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

/// These tests used to assert that [PasswordTextField] auto-submits when a
/// multi-character burst arrives. It no longer does, and these assert the
/// absence: the field submits only on an explicit user action, and it never
/// touches the system clipboard.
///
/// The removed heuristic auto-submitted 300ms after any >=3-character change,
/// and distinguished "autofill" from "human paste" by reading the clipboard -
/// so every fast-typing burst sampled whatever the user had last copied.
void main() {
  group('PasswordTextField', () {
    late TextEditingController controller;
    late bool submitCalled;
    late List<MethodCall> clipboardCalls;

    setUp(() {
      controller = TextEditingController();
      submitCalled = false;
      clipboardCalls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              clipboardCalls.add(call);
              return <String, dynamic>{'text': 'previously-copied-secret'};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      controller.dispose();
    });

    Future<void> pumpField(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordTextField(
            controller: controller,
            onFieldSubmitted: () => submitCalled = true,
          ),
        ),
      ),
    );

    testWidgets('does not auto-submit on a multi-character burst', (
      tester,
    ) async {
      await pumpField(tester);

      // What a password manager fill, or a fast typist, looks like.
      controller.text = 'mypassword123';
      await tester.pump(const Duration(seconds: 1));

      expect(submitCalled, isFalse);
    });

    testWidgets('never reads the system clipboard', (tester) async {
      await pumpField(tester);

      controller.text = 'mypassword123';
      await tester.pump(const Duration(seconds: 1));
      controller.text = 'mypassword123-and-more';
      await tester.pump(const Duration(seconds: 1));

      expect(clipboardCalls, isEmpty);
    });

    testWidgets('submits when the user completes the field', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'mypassword123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitCalled, isTrue);
    });

    testWidgets('does not submit while the user is still typing', (
      tester,
    ) async {
      await pumpField(tester);

      for (final value in ['m', 'my', 'myp', 'mypa']) {
        controller.text = value;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));

      expect(submitCalled, isFalse);
    });
  });
}
