import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';

Future<void> logOut(WidgetTester tester) async {
  final Finder settingsMenu = find.byKey(const Key('main-menu-settings'));
  final Finder logOutButton = find.byKey(const Key('settings-logout-button'));
  final Finder confirmLogoutButton = find.byKey(
    const Key('popup-confirm-logout-button'),
  );

  final auth = tester.element(settingsMenu).read<AuthBloc>();
  await tester.tap(settingsMenu);
  await tester.pumpAndSettle();
  await tester.tap(logOutButton);
  await tester.pumpAndSettle();
  await tester.tap(confirmLogoutButton);
  // Engine shutdown is asynchronous and can outlast the dialog animation.
  // Do not start the next import while the old authenticated header is mounted.
  final elapsed = Stopwatch()..start();
  while ((auth.state.isSignedIn || auth.state.isLoading) &&
      auth.state.authError == null &&
      elapsed.elapsed < const Duration(seconds: 60)) {
    // Browser storage and the lock overlay complete through scheduled frames.
    // Keep driving the app while awaiting durable sign-out, as a real user does.
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(auth.state.authError, isNull, reason: 'Durable sign-out must succeed');
  expect(auth.state.isLoading, isFalse);
  expect(auth.state.currentUser, isNull);
  await tester.pumpAndSettle();
}
