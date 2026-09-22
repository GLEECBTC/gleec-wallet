// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:feedback/feedback.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/services/feedback/custom_feedback_form.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../helpers/accept_alpha_warning.dart';

Future<void> testFeedbackForm(WidgetTester tester) async {
  await goto.settingsPage(tester);
  await tester.pumpAndSettle();
  final feedbackMenu = find.byKey(const Key('settings-menu-item-feedback'));
  if (FeedbackService.create() == null) {
    expect(feedbackMenu, findsNothing);
    await pause(msg: 'END TEST FEEDBACK: unconfigured provider is hidden');
    return;
  }
  await tester.tapAndPump(feedbackMenu);
  await tester.pumpAndSettle();
  final feedbackForm = find.byType(CustomFeedbackForm);
  expect(feedbackForm, findsOneWidget);
  BetterFeedback.of(tester.element(feedbackForm)).hide();
  await pause(msg: 'END TEST FEEDBACK');
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Run feedback tests:', (WidgetTester tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    await acceptAlphaWarning(tester);
    print('ACCEPT ALPHA WARNING');
    await tester.pumpAndSettle();
    await testFeedbackForm(tester);

    print('END FEEDBACK FORM TESTS');
  }, semanticsEnabled: false);
}
