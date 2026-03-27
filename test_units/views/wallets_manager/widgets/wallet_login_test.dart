import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

void main() {
  group('PasswordTextField Auto-Submit Tests', () {
    late TextEditingController controller;
    bool submitCalled = false;

    setUp(() {
      controller = TextEditingController();
      submitCalled = false;
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'should auto-submit when quick login is enabled and multi-character input detected',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PasswordTextField(
                controller: controller,
                onFieldSubmitted: () {
                  submitCalled = true;
                },
                isQuickLoginEnabled: true,
              ),
            ),
          ),
        );
        await tester.pump();
        // Avoid focused-field clipboard paste heuristic so the test does not depend
        // on platform clipboard async behavior.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        // Simulate password manager input (multi-character change)
        controller.text = 'mypassword123';

        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(submitCalled, true);
      },
    );

    testWidgets('should not auto-submit when quick login is disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordTextField(
              controller: controller,
              onFieldSubmitted: () {
                submitCalled = true;
              },
              isQuickLoginEnabled: false,
            ),
          ),
        ),
      );

      // Simulate password manager input
      controller.text = 'mypassword123';

      // Wait for potential auto-submit timer
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitCalled, false);
    });

    testWidgets('should not auto-submit for single character input', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordTextField(
              controller: controller,
              onFieldSubmitted: () {
                submitCalled = true;
              },
              isQuickLoginEnabled: true,
            ),
          ),
        ),
      );

      // Simulate typing one character at a time
      controller.text = 'm';
      await tester.pump(const Duration(milliseconds: 100));
      controller.text = 'my';
      await tester.pump(const Duration(milliseconds: 100));
      controller.text = 'myp';

      // Wait for potential auto-submit timer
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitCalled, false);
    });

    testWidgets(
      'should not auto-submit when field is empty after multi-character input',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PasswordTextField(
                controller: controller,
                onFieldSubmitted: () {
                  submitCalled = true;
                },
                isQuickLoginEnabled: true,
              ),
            ),
          ),
        );

        // Simulate password manager input then clearing
        controller.text = 'mypassword123';
        await tester.pump(const Duration(milliseconds: 100));
        controller.text = '';

        // Wait for the auto-submit timer period
        await tester.pump(const Duration(milliseconds: 400));

        expect(submitCalled, false);
      },
    );
  });
}
