import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';
import 'package:web_dex/views/common/wallet_access/security_key/security_key_prompt_host.dart';

import '../../../support/legal_onboarding_harness.dart';

class _Behind {
  int taps = 0;
}

Future<SecurityKeyPrompts> _pumpHost(
  WidgetTester tester, [
  _Behind? behind,
]) async {
  final prompts = SecurityKeyPrompts();
  await LegalFormHarness().pump(
    tester,
    SecurityKeyPromptHost(
      prompts: prompts,
      child: Center(
        child: ElevatedButton(
          key: const Key('behind'),
          onPressed: () => behind?.taps++,
          child: const Text('behind'),
        ),
      ),
    ),
    size: const Size(800, 1000),
    scrollable: false,
    contentWidth: null,
    disableAnimations: true,
  );
  return prompts;
}

Future<void> _type(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('security-key-pin')), pin);
  await tester.tap(find.byKey(const Key('security-key-pin-submit')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('security-key-pin')),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('security-key sheet', () {
    testWidgets('takes the PIN over the app and hands it on once', (
      tester,
    ) async {
      final behind = _Behind();
      final prompts = await _pumpHost(tester, behind);
      Uint8List? sent;
      var answered = false;
      prompts.askPin(product: 'Maker Key').then((pin) {
        answered = true;
        sent = pin;
      });
      await tester.pumpAndSettle();
      expect(find.text('Maker Key'), findsOneWidget);

      await tester.tap(find.byKey(const Key('behind')), warnIfMissed: false);
      expect(behind.taps, 0, reason: 'the app is out of reach');

      await _type(tester, '12');
      expect(find.byKey(const Key('security-key-pin-problem')), findsOneWidget);
      expect(answered, isFalse, reason: 'a short PIN never reaches the key');

      await _type(tester, '1234');
      expect(answered, isTrue);
      expect(utf8.decode(sent!), '1234');
      expect(_fieldText(tester), isEmpty);
    });

    testWidgets('warns before the last try', (tester) async {
      final prompts = await _pumpHost(tester);
      prompts.askPin(retriesLeft: 1, wrongPin: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('security-key-pin-wrong')), findsOneWidget);
      expect(
        find.byKey(const Key('security-key-pin-last-try')),
        findsOneWidget,
      );

      prompts.askPin(retriesLeft: 3);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('security-key-pin-tries')), findsOneWidget);
      expect(find.byKey(const Key('security-key-pin-wrong')), findsNothing);
    });

    testWidgets('Escape cancels the step on screen', (tester) async {
      final prompts = await _pumpHost(tester);
      var cancelled = 0;
      prompts.cancellations.listen((_) => cancelled++);
      prompts.show(const SecurityKeyPrompt(SecurityKeyStage.touch));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('security-key-sheet')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('a passkey that cannot unlock is not offered', (tester) async {
      final prompts = await _pumpHost(tester);
      int? chosen;
      prompts
          .chooseAccount(const [
            SecurityKeyAccount(usable: true, name: 'Wallet · 0123abcd'),
            SecurityKeyAccount(usable: false, name: 'Other · 4567cdef'),
          ])
          .then((index) => chosen = index);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('security-key-account-1')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      await tester.tap(find.byKey(const Key('security-key-account-0')));
      await tester.pumpAndSettle();
      expect(chosen, 0);
    });

    testWidgets('a missed touch can be tried again', (tester) async {
      final prompts = await _pumpHost(tester);
      bool? again;
      prompts.askRetry().then((retry) => again = retry);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('security-key-primary')));
      await tester.pumpAndSettle();
      expect(again, isTrue);
    });

    testWidgets('closing the request removes the sheet', (tester) async {
      final prompts = await _pumpHost(tester);
      expect(prompts.hasHost, isTrue);
      prompts.show(const SecurityKeyPrompt(SecurityKeyStage.insert));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('security-key-cancel')), findsOneWidget);

      prompts.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('security-key-sheet')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(prompts.hasHost, isFalse);
    });
  });
}
